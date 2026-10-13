# 10 - Agent coordination: the operating manual

| Field | Value |
|---|---|
| **Status** | v1.0, 2026-10-10, written by the engineering-manager agent (Fable 5.1) against 01 v1.1, 03 stage 3, 09 and `docs/backlog/backlog.json` (339 tasks). |
| **Audience** | The owner (one human) and every Claude Code session that works on this repository. |
| **Binding inputs** | 01 ADR-11 (tests), ADR-12 (CI), ADR-14 (agent conventions), 01 s9 (lanes), 03 s12.4 (`check_deps.py`), 03 s15 (MODULE.md), 09 s3.3 (lane ownership), 09 s4.2 (cost), 09 Appendix A (`backlog.json`). Where this document and those disagree, those win and this document is patched. |
| **Companion files created with this document** | `CLAUDE.md` (repo root; the short form every agent reads), `.claude/agents/*.md` (12 subagent definitions, one per role). |

**The one-paragraph version.** The owner runs the project from Claude Code. A cheap *orchestrator* session reads `backlog.json`, finds the tasks whose dependencies are `done`, and launches one subagent per task in its own git worktree, using the task's `tier` as the agent's model. Each agent reads `CLAUDE.md`, its lane's `MODULE.md` and the doc sections its task names, writes code and tests inside its lane's directory, and opens a PR that references the task id. An Opus reviewer reads every PR into `sim`, `net`, `presentation/planet` and `sim_ai` Commander code; a Sonnet reviewer reads the rest. CI (ADR-12) is the gate nobody argues with. Contracts (`MODULE.md`, schemas, enums, ADRs) change only through the Architect and then the owner. The owner personally checks what no agent can: game feel, art, store and legal.

---

## 1. Roles

### 1.1 Role catalogue

| Role | Who / model | What it does | Never does |
|---|---|---|---|
| **Owner** | Human (Ville) | Approves waves, merges PRs to `main`, decides ADR amendments, signs off spikes (HUM-12), runs playtests (QA-02/03/04), art sign-off (HUM-09), store/legal (HUM-02/05/10/13). Standing duty from 09 s5: 1-2 h/day of PR review in M2-M3, weekly balance-band review from M3. | Writes code under time pressure that an agent could write; merges red CI. |
| **Orchestrator** | Sonnet 5.5 session (the owner's interactive Claude Code session, or a Workflow script run from it). Opus 5.5 only when the wave needs judgement (re-planning a failed wave, triaging flaky CI). | Per wave: computes the ready set from `backlog.json`, confirms it with the owner, spawns one agent per task with the task's tier, tracks PRs, launches reviewers, updates `backlog.json` status, writes the wave log (`docs/waves/<date>-<milestone>.<wave>.md`). | Writes product code; changes a task's tier or acceptance; merges. |
| **Architect** | Fable 5.1 (`.claude/agents/architect.md`) | PM-01, PM-02, PM-03 (the only three Fable tasks in the backlog); ADR amendment proposals; `MODULE.md` contract changes that cross lanes; re-sizing and re-tiering after a spike; resolving a contradiction between two docs. Reads the whole doc set when it must. | Implements features; reviews ordinary PRs; is launched for anything a `MODULE.md` already answers. |
| **Lane engineer** | Opus 5.5 or Sonnet 5.5 per the lane table (1.3) | Implements one backlog task inside one lane: code, tests, `MODULE.md` update, perf note, PR. One agent per task per worktree. | Edits another lane's files (files a PR comment or a follow-up task instead); changes enums or signatures without a contract-change PR (Section 4). |
| **Reviewer** | Opus 5.5 (`code-reviewer.md`) for `sim`, `net`, `presentation/planet`, `sim_ai` Commander/brains, `core/sphere.gd`, anything touching `MODULE.md`, schemas or `deps.json`; Sonnet 5.5 (same agent file, `model` overridden) for everything else | Reads the diff, the task's acceptance, the tests and CI output; posts a verdict with a checklist (Section 3.6); re-reviews after fixes. | Rewrites the PR itself (it requests changes); approves without running or reading the tests. |
| **Content author** | Haiku 5.5 (`content-author.md`) | Def JSON, map recipes, mission JSON, locale strings, SFX recipes, fixtures, `_doc` citations; every edit validated by `tools/validate_content.py`, `moonbake validate`, `check_locale.py`. Batched (Section 7.3). | Changes a schema; invents a number not present in 02/05/07 or a tuning decision not signed by Opus/owner. |
| **Test author** | Haiku 5.5 (`test-author.md`) | Unit tests from a `MODULE.md` signature list, scenario JSON for `test/sim/`, golden-scene lists, negative fixtures, soak configs. | Weakens an assertion to make a test pass; tests private symbols. |
| **QA / playtest analyst** | Sonnet 5.5 (`playtest-analyst.md`) | Turns soak output (`balance_report.py`), playtest telemetry (02 s18.4) and tester notes into a ranked issue list with repro steps, files them as backlog tasks (status `todo`, tier proposed), drafts the playtest report skeleton the owner finishes. | Decides balance changes (that is GD-34/QA-09, Opus, owner-approved); runs the playtest (owner). |

### 1.2 What "orchestrator" means in practice

The orchestrator is not a long-lived daemon. It is whichever Claude Code session the owner is sitting in when a wave starts. It uses the Workflow tool (Section 5.4) or, for a small wave, plain `Agent` calls with `.claude/agents` types. It keeps the owner in the loop at three points: before launching (the ready list), after PRs exist (the review summary), and after merges (the status update). Sonnet 5.5 is the right tier because every decision it makes is a lookup in `backlog.json` or a CI result; the moment a decision needs judgement (a spike failed, two PRs conflict in intent, a reviewer and author disagree twice) it hands off to the owner or launches the Architect.

### 1.3 RACI per lane

R = responsible (writes it), A = accountable (reviews and signs the PR; the owner is always the final merger and is omitted), C = consulted (must be asked before a change that touches its contract), I = informed (gets a PR comment or a wave-log line). Lanes follow 09 s3.3; the agent names are `.claude/agents/*.md`.

| Lane (directory) | R (build) | A (review) | C | I |
|---|---|---|---|---|
| `core` (`godot/src/core/`) | sim-engineer (Opus) for `sphere.gd`, `mathx.gd`; test-author/content-author (Haiku) for utilities | code-reviewer (Opus) | architect for any new public symbol (every module depends on core) | all lanes |
| `content` (`godot/src/content/`, `godot/content/defs/`, `tools/schemas/`) | feature-engineer (Sonnet) for `ContentDB`/loaders; content-author (Haiku) for defs | code-reviewer (Sonnet); Opus when a schema changes | sim-engineer (defs feed `sim`), architect for schema field additions | ui, sim_ai, campaign |
| `sim` (`godot/src/sim/`) | sim-engineer (Opus); feature-engineer (Sonnet) only for tasks 09 s2.2 lowered with an Opus review (GD-08, GD-12, GD-15, NET-25 etc.) | code-reviewer (Opus), always | architect for `MODULE.md` Public API / Invariants / enum appends; net-engineer for anything serialised | sim_ai, net, ui, presentation |
| `sim_ai` (`godot/src/sim_ai/`, `godot/src/sim/steer/`) | ai-engineer (Opus) for Commander, brains, `sim/steer/` controllers; feature-engineer (Sonnet) for autopilot behaviours against `sim_ai/MODULE.md` | code-reviewer (Opus) for Commander/brains/steer; Sonnet for overlays and debug data | sim-engineer (`SimAiHook`, `CommandSink`), net-engineer (`Assist` is used by prediction) | content (books), test |
| `net` (`godot/src/net/`) | net-engineer (Opus) | code-reviewer (Opus), always | sim-engineer (`SimView`, `Command`, enums), architect for protocol version bumps | server, ui, app |
| `server` (`godot/src/server/`) | feature-engineer (Sonnet) | code-reviewer (Opus) | net-engineer, tools-engineer (server-ops) | platform |
| `presentation/planet` (`godot/src/presentation/planet/`) | planet-renderer-engineer (Opus) | code-reviewer (Opus) | architect (tier values in `quality_tiers.json` are a contract) | camera, ui, tools (baker) |
| `presentation` other (views, VFX, audio emitters, pools) | feature-engineer (Sonnet) | code-reviewer (Sonnet); Opus when pools or interpolation change | planet-renderer-engineer (budgets), sim-engineer (`SimEvent` kinds) | ui, camera |
| `camera` | feature-engineer (Sonnet); planet-renderer-engineer (Opus) for UX-02, UX-11 | code-reviewer (Sonnet; Opus for UX-02/UX-11) | presentation (ViewState) | ui, input |
| `input` | feature-engineer / ui-engineer (Sonnet) | code-reviewer (Sonnet) | sim-engineer (`PilotInput` is the only `sim` type input may see) | ui, net (prediction consumes `PilotInput`) |
| `ui` (`godot/src/ui/`, `godot/scenes/ui/`, `godot/content/ui/`) | ui-engineer (Sonnet); content-author (Haiku) for screens from a spec | code-reviewer (Sonnet) | input, camera, net (`ClientSession` command API) | platform, campaign |
| `platform` | feature-engineer (Sonnet) | code-reviewer (Sonnet; Opus for deletion cascade and entitlements) | tools-engineer (server-ops: Nakama modules) | ui, app |
| `campaign` (`godot/src/campaign/`, `godot/content/campaign/`) | feature-engineer (Sonnet) runtime; content-author (Haiku) missions | code-reviewer (Sonnet) | sim-engineer (`CommandSinkBase`), ui-engineer (briefing widgets) | content/locale |
| `app` | feature-engineer (Sonnet); planet-renderer-engineer or sim-engineer (Opus) for TA-41 | code-reviewer (Opus for `offline_host.gd` and `match_controller.gd`; Sonnet otherwise) | net-engineer, architect (the only `Thread` allowlist) | every lane |
| `assets` (`godot/assets/`, LFS) | content-author (Haiku) props from recipes; feature-engineer (Sonnet) for Blender recipes; Opus for style frames (ART-01, ART-06) | code-reviewer (Sonnet) + `validate_glb.py` | owner (HUM-09 style sign-off), presentation | ui |
| `maps` (`godot/content/maps/`) | feature-engineer (Sonnet) recipes; content-author (Haiku) variants | code-reviewer (Sonnet) + `moonbake validate` | sim-engineer (slot layout), content (resources block) | sim_ai (Commander opening books) |
| `tools` (`tools/`) | tools-engineer (Sonnet); content-author (Haiku) fixtures | code-reviewer (Sonnet); Opus for `check_deps.py` rule changes | architect (`deps.json`, `d6_allow.txt` are contracts) | all lanes |
| `test` (`godot/test/`) | test-author (Haiku) scenarios/unit; tools-engineer (Sonnet) harnesses, soak, perf | code-reviewer (Sonnet); Opus for perf harness changes | the lane under test | all |
| `server-ops` (`server-ops/`) | tools-engineer (Sonnet) | code-reviewer (Sonnet; Opus for NET-31, OPS-06) | net-engineer, platform | owner (cost lines) |
| `ci` (`.github/workflows/`) | tools-engineer (Sonnet) | code-reviewer (Sonnet; Opus signs the soak result of TA-03) | architect (gates are ADR-11/12) | all |
| `web` (`web/`) | ui-engineer (Sonnet) | code-reviewer (Sonnet) | platform, ci (size gate) | owner (hosting) |
| `docs`, `repo`, `pm` | content-author (Haiku) docs; architect (Fable) PM-* | owner | architect | all |

Two rules the table encodes: **(a)** an Opus review is mandatory wherever an Opus build tier appears, regardless of who wrote the PR (01 ADR-14, 09 s3.3); **(b)** a C-column lane is consulted *before* the change, as a comment on the task's PR or as a contract-change PR (Section 4), never discovered at review.

---

## 2. Model-tier policy

### 2.1 Decision rules

Apply the first rule that matches. The `tier` field in `backlog.json` already encodes the answer for every task; these rules exist for new tasks, sub-tasks and escalations.

| # | If the task... | Tier | Backlog examples |
|---|---|---|---|
| T1 | changes an ADR, a cross-module contract, lane ownership or the plan itself; or must weigh trade-offs across three or more docs | **Fable** | PM-01 replan after the spike wave; PM-02 scope gate; PM-03 v1.1 plan. Nothing else. |
| T2 | is a P0 spike with a REPORT.md, or sits on a 03 s4.2 hot path (`sim` tick, kinematics, entity store, collision, vision, pathing, codec, interest, prediction, planet mesher), or is Commander-bot/brain logic, or defines a `MODULE.md` from scratch | **Opus** | CONTRACT-0, TA-11 entity store, TA-18 tick driver, TA-22 S-SIM-1, TA-25 S-WORLD-1, TA-30 S-FLIGHT-1, NET-08 interest, NET-18 prediction, AI-13/AI-22 Commander, TA-23 planet quadtree, TA-41 S-WEB-2, GD-34/QA-09 balance passes, QA-08 perf hardening |
| T3 | implements a feature or service against an existing `MODULE.md` or a fully specified doc section with numeric acceptance (UI screens, platform services, tools, server-ops, autopilot behaviours, event routing, harnesses) | **Sonnet** | GD-08 damage rules (every rule a one-line formula), NET-10 EventRouter, AI-11 formation, AI-12 targeting, UX-06 touch controls, UX-16 HUD math, ART-28 cradle recipe, GD-29 mission schema, TA-03 CI skeleton, TA-27 `gen_module_api.py`, ART-04 Blender library |
| T4 | produces data that a validator checks mechanically (defs, schemas with fixtures, map recipe variants, mission JSON, locale, SFX recipes, test vectors), a straightforward unit test from a listed signature, a doc page from a template, or a lint fix with a known rule | **Haiku** | GD-01 schema fixtures, TA-05 core utilities (PCG32 against a reference sequence), TA-10 `rules.json` seed, AI-32 debug overlay data + `sim_ai/MODULE.md`, TEST-01 `validate_scenes.gd`, REPO-01/04/05/06, DOC-01 README, QA-01 device matrix, ART-37 map fixtures |
| T5 | is a review | Opus for T2 lanes and any contract file; Sonnet otherwise (Section 2.3) | - |
| T6 | is orchestration (reading `backlog.json`, spawning, status updates) | Sonnet | - |

Tie-breakers: a task is Opus if a wrong answer would cost a milestone or would be invisible to tests (determinism, float precision, hot-path allocations, protocol compatibility). A task is Haiku only if a validator or a reference value exists that fails on a wrong answer; otherwise it is Sonnet. "Looks like architecture" is not a reason for Fable: 09 s4.2 is explicit that everything that looked like architecture in the seeds is already decided in 01 and R0 and is implementation against a contract.

### 2.2 Escalation

- **Two failures escalate one tier.** A Haiku or Sonnet task whose PR fails review twice, or whose agent reports "cannot satisfy acceptance" twice, is relaunched one tier up with the two failed attempts' review comments in the brief. The orchestrator records `"escalated_from": "<tier>"` in the wave log and the Architect, at the next PM task, decides whether `backlog.json` is re-tiered permanently.
- **Opus failing twice** is not escalated to Fable; it is a signal that the contract or the acceptance is wrong. The orchestrator stops the task, files an "ADR amendment request" or a contract question (Section 4) and the Architect answers it.
- **Failure means** red CI the agent could not fix inside its own lane, a reviewer verdict of "request changes" on the same root cause twice, or an agent that ends without a PR. A flaky CI job (Section 5.6) is not a failure.
- **De-escalation** happens only through the Architect at PM-01/02/03 (re-size and re-tier), never ad hoc.

### 2.3 Mandatory review pairings

| PR touches | Author tier | Reviewer | Notes |
|---|---|---|---|
| `godot/src/sim/**`, `godot/src/net/**`, `godot/src/presentation/planet/**`, `sim_ai` Commander/brains/`sim/steer/`, `core/sphere.gd`, `core/mathx.gd` | any | **Opus** | Includes the 09 s2.2 lowered tasks (GD-08, GD-12, GD-15, NET-05, NET-25, AI-10, UX-07, ART-13, FEAT-21): Sonnet writes, Opus reviews. Budget 0.15 Opus days per Sonnet day in these lanes. |
| any `MODULE.md`, `tools/schemas/*.schema.json`, `tools/deps.json`, `tools/d6_allow.txt`, `project.godot`, `export_presets.cfg`, `.github/workflows/*`, `docs/adr/*` | any | **Opus**, then **owner** | Contract files (Section 4). |
| `godot/src/app/offline_host.gd`, `match_controller.gd`, `platform` deletion and entitlements, `server-ops` NET-31/OPS-06 | Sonnet | **Opus** | Threading allowlist, compliance, money. |
| other `godot/src/**`, `tools/`, `server-ops/`, `web/` | Sonnet | **Sonnet** reviewer (not the author's session) | Opus on request when the author flags uncertainty. |
| `godot/content/**`, `godot/test/**` scenarios, `docs/**`, fixtures | Haiku | **Sonnet** reviewer; validator output attached | Batched content PRs get one review per batch. |
| spike REPORT.md | Opus | **owner** (HUM-12) within 2 working days | The Architect reads them all at PM-01. |

A reviewer never reviews its own author session's PR. When the owner wants a second opinion on a `sim`/`net` PR, launch a second Opus reviewer with a different lens (correctness vs determinism vs perf), not a Fable.

---

## 3. Task lifecycle

```
todo --(orchestrator launches)--> in_progress --(PR opened, CI green)--> review
review --(approved + owner merge)--> done
review --(changes requested)--> in_progress     (same agent, same worktree)
in_progress/review --(2 failures)--> escalate (Section 2.2)   |  --(owner)--> dropped
```

`backlog.json` is the single source of truth for status. Nothing else (no spreadsheet, no issue tracker in v1) carries task state; GitHub PRs carry the conversation.

### 3.1 The brief (copy-pasteable)

The orchestrator fills this from `backlog.json` and hands it to the agent as its first message. Fields in angle brackets come from the task object; nothing else is added unless the owner says so.

```markdown
# Task <id>: <title>

**Lane:** <lane>  -  **Tier:** <tier>  -  **Size:** <size_days> agent-days  -  **Milestone:** <milestone>

## Read first (and nothing else by default)
1. `CLAUDE.md` (repo root)
2. `godot/src/<lane>/MODULE.md` (if the lane has one; otherwise the contract named in 09 s3.3 for this lane)
3. These doc sections, in this order: <docs[]  e.g. "03 s4.1", "R0 B.5", "03 TA-18">
4. The acceptance of your dependencies, for the interfaces you consume: <depends_on[] with their one-line acceptance>

## Acceptance (verbatim from backlog.json)
<acceptance>

## Allowed paths
- Write: `godot/src/<lane>/**`, `godot/test/<layer>/<lane>/**`, `godot/src/<lane>/MODULE.md`
- Plus, for this task only: <extra paths the orchestrator grants, e.g. a def file or a schema; empty by default>
- Read anything. Do not edit any other path; file a PR comment "needs <lane>: <what>" instead.

## Worktree and branch
- Worktree: `../Planewar-wt/<id>` on branch `task/<id>-<slug>` from `main` at <sha>.
- Commit messages start with `<id>: `.

## Definition of done (all required)
- [ ] Tests for every public symbol you added or changed exist under `godot/test/` and pass headless.
- [ ] `tools/check_deps.py` passes (D1-D10); `tools/validate_content.py` passes if you touched JSON.
- [ ] `godot --headless --path godot --import` then the gdUnit4 run is green with the ADR-01 warning set at Error.
- [ ] `MODULE.md` of your lane updated if a public symbol, invariant, event or test entry point changed; `tools/gen_module_api.py --check` passes.
- [ ] Perf note in the PR for any change under `sim/`, `net/`, `presentation/`: `perf_tick.gd` or the relevant benchmark delta, or "not on a hot path: <why>".
- [ ] Screenshot attached if `presentation/` or `ui/` changed (ADR-11 consequence).
- [ ] PR opened with the template, title `<id>: <title>`, body lists each acceptance line with how it is demonstrated.

## Constraints you may not negotiate
ADR-14 (CLAUDE.md restates them). Enumerations are append-only. `PLANET_RADIUS` is read from `Sphere`, never typed. No new autoloads, addons, threads, C#, GDExtension. If the acceptance cannot be met inside the contract, stop and write `BLOCKED: <reason>` in the PR body; do not widen the contract yourself.

## Report back (final message, <= 20 lines)
What you built, test names, perf numbers, anything you could not do, and any contract question for the Architect.
```

### 3.2 Branches and worktrees

- One task = one worktree = one branch. Worktrees live beside the repo, never inside it: `../Planewar-wt/<id>/` (so Godot's `.godot/` import cache is per worktree and agents never share it).
- Branch name `task/<id>-<slug>`; slug is lowercase, hyphenated, <= 40 chars, from the title. Examples: `task/TA-18-sim-world-tick-driver`, `task/GD-08-damage-rules`, `task/ART-28-cradle-recipe`.
- Spikes use `spike/<id>-<name>` and may stay unmerged; their REPORT.md is copied to `docs/spikes/<id>-REPORT.md` on `main` by a follow-up Haiku task.
- Contract changes use `contract/<lane>-<short>` (Section 4).
- Create: `git worktree add ../Planewar-wt/<id> -b task/<id>-<slug> main`. Remove after merge: `git worktree remove ../Planewar-wt/<id>` and `git branch -d`. The orchestrator does both; agents do neither.
- Each worktree runs `godot --headless --path godot --import` once before tests (CI does the same). Expect 1-3 minutes; the `.godot/` directory is git-ignored.
- `main` is protected (REPO-01): PR only, green CI required, one approval required, linear history (squash merge).

### 3.3 Definition of done

A task is `done` when every line below is true. Reviewers check the list; the orchestrator refuses to set `done` without a merged PR.

1. **Acceptance demonstrated.** Every clause of the task's `acceptance` maps to a named test, a CI job output, or a REPORT.md section, and the PR body says which.
2. **Tests part of the change.** New or changed public symbols have tests in the layer ADR-11 names; a task that changes a `MODULE.md` contract updated the contract tests *first* (ADR-11 agent rule).
3. **`check_deps.py` green** (D1-D10), **`validate_content.py` green**, **`validate_scenes.gd` green**, **`gen_module_api.py --check` green** (TA-27 onward).
4. **Warnings as errors.** The ADR-01 warning set stays at level 2 in `project.godot` (D8) and the headless run has zero warnings. `@warning_ignore` appears nowhere in `src/sim/**` (03 s1.1 house style: `mathx.gd` helpers).
5. **`MODULE.md` current**: Public API, Invariants, Events, Performance budget, Test entry points reflect the merged code; file <= 300 lines.
6. **Perf note** present for `sim/`, `net/`, `presentation/`: a measured delta from `perf_tick.gd` / codec bytes / chunk build time, or an explicit "not on a hot path" with the reason. 03 s12.2 rule 10: every optimisation PR cites a delta.
7. **Screenshot** attached for `presentation/` or `ui/` changes (local render; goldens run nightly).
8. **CI green** on the PR: import, deps, content, scenes, unit/sim/net, exports, 10-minute soak, 25 % A/B. Flaky retries are allowed only per Section 5.6.
9. **Reviewed by the pairing tier** (Section 2.3), approved, and merged by the owner (or auto-merge the owner enabled for that lane).
10. **`backlog.json` status = done** in the same merge or the orchestrator's follow-up commit, with `"pr": <number>` and `"merged": "<date>"` added to the task object (fields are additive; `backlog_report.py` ignores unknown keys).

### 3.4 PR template (`.github/PULL_REQUEST_TEMPLATE.md`, created by REPO-06)

```markdown
## <id>: <title>

**Lane:** <lane>  **Tier:** <tier>  **Reviewer tier required:** Opus | Sonnet
**Docs read:** <list>

### Acceptance -> evidence
| Acceptance clause | Demonstrated by |
|---|---|
| <clause 1> | `godot/test/unit/<lane>/test_x.gd::test_y` |
| <clause 2> | CI job `soak_pr` output line "...") |

### Contract impact
- [ ] No change to any MODULE.md Public API / Invariants, schema, enum, deps.json, ADR
- [ ] Contract change included: contract tests updated first in commit <sha>; Architect ack: <link or "pending">

### Checks run locally
- [ ] `godot --headless --path godot --import`
- [ ] `tools/check_deps.py`  - [ ] `tools/validate_content.py`  - [ ] `gen_module_api.py --check`
- [ ] gdUnit4: `<n>` tests, 0 failures, 0 warnings

### Perf note (required for sim/, net/, presentation/)
<benchmark, before -> after, or "not on a hot path: ...">

### Screenshot (required for presentation/, ui/)
<image or "n/a">

### Not done / questions for the Architect
<empty or list>
```

The commit-message lint (REPO-06) rejects any commit whose first line does not start with an id present in `backlog.json`; `CONTRACT-<lane>-<n>` ids are registered by the Architect when a contract PR opens (Section 4).

### 3.5 Review checklist (what the reviewer actually does)

1. Read the task in `backlog.json` and the doc sections it names. Reviewers read contracts and acceptance, not the author's transcript (09 s4.2 token hygiene).
2. Read the diff once end to end. Flag any file outside the lane's allowed paths (Section 4.3) before anything else; that is an automatic "request changes".
3. Open every new or changed test; check that it would fail if the feature were removed (no tautologies, no asserting on the thing just set).
4. Check the `MODULE.md` diff against the code diff: every new public symbol is listed, nothing listed is missing, no enum reordered.
5. For Opus lanes: determinism (no `Dictionary` iteration order, no `randf()` outside `Rng`, no float accumulation across ticks without a reason), allocations in per-entity loops (03 s12.2), packed-array copy-on-write trap (rule 11), `PLANET_RADIUS` discipline (D6), signals in sim (D2).
6. For `net`: every new field is quantised per 04 s3 and round-trips in a codec test; no packet can exceed 1,200 B; a fuzzed packet never throws.
7. For `ui`/`input`: Steam Deck 9 px text, controller navigation, touch control count (<= 7 on the right half), locale keys not literals.
8. For content: `_doc` citation per value, schema valid, numbers traceable to 02/05/07 or to a signed balance pass.
9. Read the CI logs for the soak and A/B steps, not only the green tick.
10. Verdict: **Approve** / **Request changes (root cause: ...)** / **Escalate to Architect (contract question: ...)**. One root cause per round; list every instance of it. Nits are allowed but labelled "nit:" and never block.

### 3.6 Merge policy

- Squash merge, PR title becomes the commit subject (so the id lint holds on `main`).
- Owner merges. From M2 on, the owner may enable auto-merge for Haiku content PRs after the Sonnet review approves and CI is green; never for Opus lanes or contract files.
- Merge order inside a wave follows the dependency graph; the orchestrator rebases a waiting PR onto `main` after each merge and re-runs CI (`git rebase main` in the worktree, force-push with lease).
- A PR open more than 5 working days without activity is closed by the orchestrator and the task returns to `todo` with a note; the worktree is removed.
- Red `main` is a stop-the-line event: no new launches until green (revert first, fix second).

### 3.7 How `backlog.json` is updated

- Only the orchestrator (and the Architect in PM tasks) writes `backlog.json`. Agents never touch it; the brief says so.
- Transitions: `todo -> in_progress` at launch (commit `WAVE: start <ids>` on `main`, or kept in the orchestrator's working tree until the wave closes, owner's choice); `in_progress -> review` when the PR is opened and CI is green; `review -> done` on merge; `-> dropped` only by the owner with a reason string in `"dropped_reason"`.
- Additive fields the orchestrator may write: `pr`, `branch`, `started`, `merged`, `escalated_from`, `attempts`, `wave`. Fields it may never change: `id`, `tier`, `size_days`, `depends_on`, `milestone`, `acceptance`, `docs` (those are the Architect's at PM-01/02/03).
- New tasks (bugs from playtests, sub-tasks from QA-06) are appended by the playtest analyst or the orchestrator with `status: todo`, a proposed `tier`, the `lane`, and `depends_on`; the Architect confirms tier and milestone at the next weekly review (Section 6.3). Ids for new tasks: `BUG-<n>`, `SUB-<parent>-<n>`.
- `tools/backlog_report.py` (REPO-05) prints the ready set; its output is the wave proposal (Section 5.1). 09 s2.3 stays a rendered copy of the JSON and is regenerated, never hand-edited.

---

## 4. Contract-change protocol

A **contract** is anything another lane compiles or validates against: `godot/src/<module>/MODULE.md` (Public API, Invariants, Events, Test entry points; `godot/src/sim/<subsystem>/MODULE.md` for `sim/steer/`, `sim/orders/`, `sim/control/`, `sim/scoring/` once they exist, R0 B.9 A-21), `tools/schemas/*.schema.json`, the append-only enumerations (R0 B.3, the `sim/MODULE.md` "Enumerations" block, whose bullet format `test_protocol.gd` parses), `tools/deps.json`, `tools/d6_allow.txt`, `project.godot`, `export_presets.cfg`, `.github/workflows/*`, `godot/content/defs/*.json` field *sets* (not values), and every ADR in 01 and `docs/adr/`.

### 4.1 Three sizes of change

| Size | Examples | Who may do it | Path |
|---|---|---|---|
| **Append** | a new `SimEvent.Kind` at the end; a new optional def field with a default; a new public function on an existing class; a new test entry point; a new D6 allow entry with reason | The lane engineer, inside its task PR, **if** the task's `docs` or acceptance call for it | Contract tests updated first (same PR, earlier commit); `MODULE.md` edited; PR flagged "Contract impact: append"; Opus review; the orchestrator posts a one-line notice in the wave log so consuming lanes rebase. |
| **Change** | a signature change; a new required def field; a new allowed dependency edge in `deps.json`; a new `Thread`/autoload/addon allowlist entry; an invariant weakened; a tier-value table changed | **Architect** (Fable) proposes; **owner** approves | Agent files a contract question in its PR body (`BLOCKED:` or "Not done / questions"). Orchestrator launches the Architect with the question; the Architect opens `contract/<lane>-<short>` with the `MODULE.md` diff, the test diff, a migration note per consuming lane, and if an ADR is touched a `docs/adr/ADR-<nn>-amendment-<n>.md` from the REPO-05 template. Owner approves; the orchestrator rebases affected worktrees. |
| **Reorder / delete / rename** | anything that changes an existing enum ordinal, removes a public symbol, renames a def field, moves `PLANET_RADIUS` | **Forbidden** in v1. | Add the new thing, deprecate the old in `MODULE.md` "Open items", delete at a major version only, by ADR. `gen_module_api.py --check` and the schema diff in CI fail on a removed symbol. |

### 4.2 ADR amendments

- Any agent may *request* one: a section "ADR amendment request" in its PR body or spike REPORT.md with: the ADR, the sentence that blocks, the evidence (test or measurement), the proposed wording, who is affected. It never changes 01 itself.
- The Architect turns requests into `docs/adr/ADR-<nn>-amendment-<n>.md` (template from REPO-05: context, decision, consequences, register id, affected `MODULE.md`s and tasks), batches them for the owner, and after approval patches 01's amendment log and the affected docs in one PR.
- The owner's decision is recorded on the amendment file and in 01's log before any lane acts on it. Spike fallbacks already written in the owning doc (09 s6) are *not* amendments; they are data changes a Haiku task applies.

### 4.3 Lane-owned paths and the shared-files list

Default rule (09 s3.3): a task may edit only its lane's directory, `godot/test/<layer>/<lane>/`, and its `MODULE.md`. CODEOWNERS (REPO-01) mirrors this table so GitHub requests the right review. Everything below is **shared**: the named role edits it, everyone else files a request.

| Shared file / path | Who may edit | How others request |
|---|---|---|
| `godot/project.godot`, `export_presets.cfg`, `.godot-version` | tools-engineer (ci tasks) with Opus review; Architect for warning/autoload keys | PR comment "needs ci:" |
| `tools/deps.json`, `tools/d6_allow.txt`, `tools/check_deps.py` rules | Architect (edges, allowlists); tools-engineer (implementation) | contract question |
| `tools/schemas/*.schema.json` | content lane (feature-engineer) for appends; Architect for required fields | "Contract impact: append" or contract question |
| `godot/src/sim/MODULE.md` enum block | sim-engineer appends (declaration, register bullet and GDScript enum in one PR); nobody reorders | "Contract impact: append" |
| `godot/content/defs/*.json` | content-author (values, batched); sim-engineer only for fields its task adds | content task |
| `godot/content/maps/*/recipe.json` | maps lane | "needs maps:" |
| `godot/content/locale/*.json` | content-author; ui-engineer may add keys with English text in its PR (a Haiku task fills other locales) | - |
| `godot/scenes/app/*.tscn`, `godot/src/app/**` | app lane (feature-engineer) | "needs app:" (mode wiring, settings keys) |
| `.github/workflows/*.yml` | ci lane | "needs ci:" |
| `CLAUDE.md`, `.claude/agents/*`, `docs/10-agent-coordination.md` | Architect or owner | PR comment |
| `docs/backlog/backlog.json`, `docs/09-roadmap-and-backlog.md` s2.3 | orchestrator (status), Architect (everything else) | never edited by task agents |
| `docs/01..08` | Architect (amendments) ; content-author for Haiku doc patches named in a task (e.g. GD-34's 02 revision under Opus direction) | ADR amendment request |
| `godot/test/soak/configs/*.json`, `balance_bands.json` | test lane; GD-34/QA-09 (Opus) for bands | - |
| `README.md`, `docs/compliance/**`, `docs/waves/**` | docs lane; platform lane for compliance; orchestrator for waves | - |

Conflict avoidance in a wave: the orchestrator launches at most one task per lane per wave (09 s2.1 convention); two tasks that must share a lane run back to back in the same worktree sequence. A task whose lane string is `a+b` (e.g. `sim+tools`, `net+server`) owns both directories for its duration and no other task in the wave may be launched in either.

---

## 5. Running a wave (owner's step-by-step in Claude Code)

### 5.1 Pick the wave

1. Pull `main`, make sure CI is green. If red, Section 3.6 last bullet.
2. Run `python tools/backlog_report.py --ready` (REPO-05). Until it exists, the one-liner below does the same (run from the repo root; it is what the workflow script in 5.4 does internally):
   ```
   python -I -c "import json;d=json.load(open('docs/backlog/backlog.json',encoding='utf-8'));done={t['id'] for t in d if t['status']=='done'};print('\n'.join(f\"{t['id']:12} {t['tier']:7} {t['lane']:20} {t['size_days']:>4} {t['title'][:70]}\" for t in d if t['status']=='todo' and all(x in done for x in t['depends_on'])))"
   ```
3. Cut the list to what you can review: 09 s1.3 says 3 agents in M0, 2 in M1, 6 (max 8) in M2-M3, 3 in M4, 2-3 later. Prefer critical-path tasks (09 s3.1) and the lowest-tier ready tasks that unblock the most.
4. Enforce one task per lane. If two ready tasks share a lane, the second waits or is chained after the first in the same worktree.
5. `Owner` tier tasks are yours; do them or note the date you will.
6. Write the wave file `docs/waves/<yyyy-mm-dd>-<M>.<n>.md`: the list, the SHA of `main`, the agent count. This is the commit `WAVE: start <ids>` that also flips statuses to `in_progress`.

### 5.2 Spawn the agents

Two ways; both use `.claude/agents/*.md`, whose `model:` field is the tier.

**Interactive (small wave, <= 3 tasks).** In your Claude Code session: "Launch `sim-engineer` for TA-18 in a worktree; brief from backlog.json" and the session fills the Section 3.1 brief and calls the Agent tool with `subagent_type: sim-engineer`, `isolation: worktree`. Repeat per task. Ask the session to report when each PR exists.

**Scripted (M2-M3 waves).** Run the Workflow in 5.4 with `args: {ids: [...], main_sha: "..."}`. It builds briefs, launches each task with the agent type that matches its lane and the model that matches its tier, waits for PRs, then launches a reviewer per PR with the pairing tier. It returns a table you paste into the wave file.

Role selection from `lane` (the script's `AGENT_FOR_LANE` map; override per task in `args` when needed):

| lane prefix | agent | default model (from task.tier) |
|---|---|---|
| `sim`, `sim/*`, `core` (math) | sim-engineer | opus (or sonnet when the task tier is Sonnet; still Opus review) |
| `sim_ai`, `sim/steer` | ai-engineer | opus / sonnet |
| `net` | net-engineer | opus |
| `presentation/planet`, `TA-23..26`, `TA-31` | planet-renderer-engineer | opus |
| `server`, `presentation` (non-planet), `camera`, `input`, `platform`, `campaign`, `app`, `maps` | feature-engineer | sonnet |
| `ui`, `ui/*`, `web`, `ui assets` | ui-engineer | sonnet |
| `tools`, `ci`, `server-ops`, `test` harnesses, `repo` | tools-engineer | sonnet |
| `content`, `content/*`, `assets` props, `docs`, `audio` recipes, `locale` | content-author | haiku |
| `test` scenarios/unit, fixtures | test-author | haiku |
| `spikes` | the lane engineer of the spike's subject | opus |
| `pm` | architect | fable |

The task's `tier` always wins over the table's default model; the table only picks the *persona*.

### 5.3 Verify results

For each PR the wave produced:

1. Open the PR. The body must have the acceptance -> evidence table filled. Empty rows = send back without review.
2. Check CI: all jobs green, soak slope line printed, A/B delta < 25 %. Read the exports step for the web size figure if `presentation/` or `assets/` changed.
3. Read the reviewer's verdict (the script posts it as a PR comment and returns it). "Approve" with an Opus reviewer on an Opus lane and green CI: merge. "Request changes": the script already relaunched the author once; if it is the second round, Section 2.2.
4. Spot-check one thing yourself per PR: pick one acceptance clause and run its test locally (`addons/gdUnit4/runtest.sh -a res://test/unit/<lane>/test_x.gd` in the worktree), or open the screenshot. Thirty seconds per PR keeps reviewers honest.
5. Merge in dependency order; the script (or you) rebases the next PR and waits for CI.
6. After the last merge: `python tools/backlog_report.py` and commit the status changes with `WAVE: close <ids>`; append the actual agent-days and token spend to the wave file (Section 7).

### 5.4 Example workflow script outline (ready to adapt)

Run from the owner's Claude Code session via the Workflow tool. Plain JavaScript; `agent()` spawns subagents using the `.claude/agents` types. Adapt `MODEL` to the model aliases installed in your Claude Code (`fable`, `opus`, `sonnet`, `haiku` are what the agent files use), and replace the `gh` invocations with your repo's names. The script does not read files itself; it asks one Haiku agent to read `backlog.json` and return the ready set as structured data.

```javascript
export const meta = {
  name: 'planewar-wave',
  description: 'Launch ready backlog tasks as tiered agents in worktrees, then review each PR',
  whenToUse: 'Owner starts a wave from docs/backlog/backlog.json',
  phases: [
    { title: 'Select', detail: 'read backlog.json, compute ready set, one task per lane' },
    { title: 'Build',  detail: 'one agent per task, model = task.tier, git worktree' },
    { title: 'Review', detail: 'pairing-tier reviewer per PR; one fix round' },
    { title: 'Report', detail: 'wave table + backlog status patch' },
  ],
}

// ---- configuration ---------------------------------------------------------
const MODEL = { Fable: 'fable', Opus: 'opus', Sonnet: 'sonnet', Haiku: 'haiku' }
const OPUS_REVIEW_LANES = /^(sim|net|presentation\/planet|core)(\b|\/)|sim_ai|sim\/steer|spikes/
const AGENT_FOR_LANE = [
  [/^spikes|^pm$/,                      null],                 // decided per task below
  [/^sim_ai|sim\/steer/,                'ai-engineer'],
  [/^sim(\b|\/)|^core$/,                'sim-engineer'],
  [/^net(\b|\+)/,                       'net-engineer'],
  [/presentation\/planet/,              'planet-renderer-engineer'],
  [/^ui|^web|ui assets/,                'ui-engineer'],
  [/^tools|^ci|^server-ops|^repo/,      'tools-engineer'],
  [/^test/,                             'test-author'],
  [/^content|^assets|^docs|^audio|locale/, 'content-author'],
  [/.*/,                                'feature-engineer'],
]
const pickAgent = (t) => {
  if (t.lane === 'pm') return 'architect'
  if (t.lane.startsWith('spikes')) return t.id.startsWith('NET') ? 'net-engineer'
    : t.id === 'TA-25' ? 'planet-renderer-engineer' : 'sim-engineer'
  if (t.tier === 'Haiku' && /^test/.test(t.lane)) return 'test-author'
  if (t.tier === 'Haiku') return 'content-author'
  return AGENT_FOR_LANE.find(([re]) => re.test(t.lane))[1]
}
const reviewerModel = (t) => (OPUS_REVIEW_LANES.test(t.lane) || t.tier === 'Opus') ? 'opus' : 'sonnet'
const MAX_PARALLEL = (args && args.maxAgents) || 6         // 09 s1.3 capacity per milestone
const MAIN_SHA = args && args.main_sha                      // passed in by the owner
const ONLY = (args && args.ids) || null                     // optional explicit task list

// ---- phase 1: select -------------------------------------------------------
phase('Select')
const READY_SCHEMA = { type: 'object', required: ['tasks'], properties: { tasks: { type: 'array', items: {
  type: 'object', required: ['id','title','lane','tier','size_days','depends_on','milestone','acceptance','docs'],
  properties: { id:{type:'string'}, title:{type:'string'}, lane:{type:'string'}, tier:{type:'string'},
    size_days:{type:'number'}, depends_on:{type:'array',items:{type:'string'}}, milestone:{type:'string'},
    acceptance:{type:'string'}, docs:{type:'array',items:{type:'string'}}, dep_acceptance:{type:'array',items:{type:'string'}} } } } } }
const ready = await agent(
  `Read docs/backlog/backlog.json. Return every task with status "todo" whose depends_on are all status "done"` +
  (ONLY ? ` and whose id is in ${JSON.stringify(ONLY)}` : '') +
  `, excluding tier "Owner". For each, include dep_acceptance: the one-line acceptance of each dependency. ` +
  `Keep at most one task per lane (prefer the lowest milestone, then the longest critical chain). Return JSON only.`,
  { schema: READY_SCHEMA, model: 'haiku', effort: 'low', label: 'ready set' })
let tasks = (ready && ready.tasks) || []
if (tasks.length > MAX_PARALLEL) { log(`dropping ${tasks.length - MAX_PARALLEL} ready tasks beyond capacity ${MAX_PARALLEL}`); tasks = tasks.slice(0, MAX_PARALLEL) }
log(`wave: ${tasks.map(t => `${t.id}(${t.tier})`).join(', ')}`)
if (!tasks.length) return { wave: [], note: 'nothing ready' }

// ---- brief (Section 3.1) ---------------------------------------------------
const slug = (s) => s.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/(^-|-$)/g, '').slice(0, 40)
const brief = (t) => `# Task ${t.id}: ${t.title}
**Lane:** ${t.lane}  -  **Tier:** ${t.tier}  -  **Size:** ${t.size_days} agent-days  -  **Milestone:** ${t.milestone}
## Read first (and nothing else by default)
1. CLAUDE.md  2. godot/src/${t.lane.split(/[+\/]/)[0]}/MODULE.md if it exists  3. Doc sections: ${t.docs.join('; ')}
4. Dependencies' acceptance: ${(t.dep_acceptance || []).join(' | ')}
## Acceptance (verbatim)
${t.acceptance}
## Allowed paths
Write only godot/src/${t.lane.split(/[+\/]/).join('/**, godot/src/')}/**, godot/test/**/${t.lane.split(/[+\/]/)[0]}/**, and that lane's MODULE.md. Read anything. Never edit docs/backlog/backlog.json.
## Branch
You are in a fresh git worktree. Create and use branch task/${t.id}-${slug(t.title)} from main (${MAIN_SHA || 'current'}). Commit subjects start with "${t.id}: ".
## Definition of done
Tests for every public symbol; godot --headless --path godot --import; tools/check_deps.py; tools/validate_content.py if JSON touched; gdUnit4 green with zero warnings; MODULE.md updated and tools/gen_module_api.py --check green; perf note for sim/net/presentation; screenshot for presentation/ui; PR opened with the repo template, title "${t.id}: ${t.title}" (use: gh pr create --fill --title ...).
## Non-negotiable
ADR-14 as restated in CLAUDE.md. Enumerations append-only. Never type 6000; use Sphere.PLANET_RADIUS. If acceptance cannot be met inside the contract, stop and write BLOCKED: <reason> in the PR body.
## Return
JSON only: {pr_url, branch, tests_added:[...], perf_note, blocked:boolean, blocked_reason, contract_questions:[...]}`

const BUILD_SCHEMA = { type: 'object', required: ['pr_url','branch','blocked'], properties: {
  pr_url:{type:'string'}, branch:{type:'string'}, tests_added:{type:'array',items:{type:'string'}},
  perf_note:{type:'string'}, blocked:{type:'boolean'}, blocked_reason:{type:'string'}, contract_questions:{type:'array',items:{type:'string'}} } }
const REVIEW_SCHEMA = { type: 'object', required: ['verdict','root_cause','checklist_failed'], properties: {
  verdict:{type:'string', enum:['approve','request_changes','escalate']}, root_cause:{type:'string'},
  checklist_failed:{type:'array',items:{type:'string'}}, comment_url:{type:'string'} } }

// ---- phases 2-3: build -> review -> one fix round (pipeline: no barrier) ----
const results = await pipeline(tasks,
  (t) => agent(brief(t), { phase: 'Build', label: `${t.id} build`, agentType: pickAgent(t),
                           model: MODEL[t.tier], isolation: 'worktree', schema: BUILD_SCHEMA }),
  async (built, t) => {
    if (!built || built.blocked) return { t, built, review: null }
    const review = await agent(
      `Review PR ${built.pr_url} for task ${t.id} (${t.title}). Acceptance: ${t.acceptance}. Docs: ${t.docs.join('; ')}. ` +
      `Follow the review checklist in docs/10-agent-coordination.md s3.5 and the reviewer rules in your agent file. ` +
      `Post your verdict as a PR comment with gh, then return JSON {verdict, root_cause, checklist_failed, comment_url}.`,
      { phase: 'Review', label: `${t.id} review`, agentType: 'code-reviewer', model: reviewerModel(t), schema: REVIEW_SCHEMA })
    return { t, built, review }
  },
  async (r, t) => {
    if (!r.review || r.review.verdict !== 'request_changes') return r
    // one fix round by the same persona at the same tier; a second failure escalates (Section 2.2) -- that is the owner's call, not the script's
    const fixed = await agent(
      `Continue task ${t.id} on branch ${r.built.branch} (check out the branch in this worktree). A reviewer requested changes: ${r.review.root_cause}. ` +
      `Failed checklist items: ${r.review.checklist_failed.join('; ')}. Fix the root cause, keep the contract, update tests, push, and return the same JSON as before.`,
      { phase: 'Build', label: `${t.id} fix`, agentType: pickAgent(t), model: MODEL[t.tier], isolation: 'worktree', schema: BUILD_SCHEMA })
    const review2 = fixed && !fixed.blocked ? await agent(
      `Re-review PR ${fixed.pr_url} after fixes for ${r.review.root_cause}. Same checklist; return the same JSON.`,
      { phase: 'Review', label: `${t.id} re-review`, agentType: 'code-reviewer', model: reviewerModel(t), schema: REVIEW_SCHEMA }) : null
    return { t, built: fixed || r.built, review: review2, attempts: 2 }
  })

// ---- phase 4: report -------------------------------------------------------
phase('Report')
const rows = results.filter(Boolean).map(({ t, built, review, attempts }) => ({
  id: t.id, tier: t.tier, lane: t.lane, pr: built && built.pr_url, blocked: !!(built && built.blocked),
  verdict: review ? review.verdict : (built && built.blocked ? 'blocked' : 'no-review'),
  attempts: attempts || 1, next_status: review && review.verdict === 'approve' ? 'review (merge me)' : 'in_progress',
  questions: (built && built.contract_questions) || [] }))
log(`approve: ${rows.filter(r => r.verdict === 'approve').length}, changes: ${rows.filter(r => r.verdict === 'request_changes').length}, blocked/escalate: ${rows.filter(r => r.blocked || r.verdict === 'escalate').length}`)
return { main_sha: MAIN_SHA, wave: rows }
```

What the owner does with the return value: paste the table into the wave file, merge the `approve` rows in dependency order, launch the Architect for any `contract_questions` or `escalate`, and apply Section 2.2 to rows with `attempts: 2` and a non-approve verdict. A follow-up Haiku agent (or the session itself) patches `backlog.json` statuses from the table; the script never writes the file.

Variants worth keeping as separate saved workflows: `planewar-content-batch` (one Haiku agent per def file with a single Sonnet review at the end, Section 7.3), `planewar-spike` (one Opus agent, no review stage, returns the REPORT.md path), `planewar-replan` (Architect only, reads every REPORT.md, returns the backlog patch for the owner).

### 5.5 Handling failures

| Symptom | Action |
|---|---|
| Agent returns `blocked: true` | Read the reason. Contract problem -> launch Architect (Section 4). Missing dependency the graph missed -> add the edge to `backlog.json` (Architect confirms later) and return the task to `todo`. Acceptance wrong -> Architect. |
| Agent ends with no PR and no `blocked` | Relaunch once with the same brief plus "Your previous attempt ended without a PR; the worktree is at `<path>`; inspect `git status` and continue." Counts as attempt 1 of 2. |
| Reviewer `request_changes` twice on the same root cause | Section 2.2: escalate one tier (Haiku -> Sonnet -> Opus). Opus twice -> Architect. |
| PR edits files outside the lane | Reviewer rejects automatically. Author splits: the in-lane part stays; the out-of-lane part becomes a "needs <lane>:" comment and, if real, a `SUB-<id>-<n>` task for that lane. |
| Two PRs in one wave conflict on `main` | Should not happen (one lane per wave). If it does, merge the critical-path one, rebase the other in its worktree (`git rebase main`), rerun CI; if the rebase needs judgement, the author agent does it with a short brief. |
| Agent asks a question mid-task | Workflow agents cannot ask; they must decide or `BLOCKED`. Interactive subagents may ask; answer only from the docs, and if the docs are silent, that is a contract question (Section 4). |
| Agent proposes reading Triplane source, filing a Godot issue, adding an addon | Refuse; it is in ADR-14 and `CLAUDE.md`. Note it in the wave log; a pattern of such proposals is a brief-quality problem, not an agent problem. |

### 5.6 Flaky CI

- **Definition.** A job that fails and passes on rerun with no code change. Only the soak, A/B perf, export-download and golden jobs are allowed to be flaky; a flaky unit/sim/net test is a bug.
- **Policy.** One rerun of the failed job is allowed per PR by the orchestrator (`gh run rerun --failed`). A second failure is treated as real. The rerun and its outcome are written in the PR as a comment "CI rerun: <job>, <reason suspected>".
- **A/B perf noise.** The same-job base-vs-head A/B fails above +25 % (03 s1.4). Base-vs-base noise was measured in S-CI-1; if a PR fails A/B with no hot-path change, rerun once; if it fails again, the perf note in the PR must explain or the PR waits for the pinned runner's nightly number (TA-42).
- **Golden screenshots** differ per Mesa version. A golden failure after a runner image change is fixed by a Haiku task regenerating goldens (keyed by driver string), never by widening tolerance in a feature PR.
- **Tracking.** `docs/waves/flaky.md` gets one line per rerun (date, job, PR). Three reruns of the same job in two weeks create a `SUB-TA-03-<n>` task for the ci lane at Sonnet tier.
- **Flaky unit test** (fails/passes without change): quarantine is not allowed; the owning lane fixes it in the same PR or the PR is not merged. Determinism is a pillar of the sim (ADR-06); a flaky sim test is a sim bug.

---

## 6. Spikes, playtests, cadence, and what only the owner can check

### 6.1 Spikes as decision gates

A spike (01 Appendix A, 03 s14, 09 s6) is an Opus task whose deliverable is a `REPORT.md`, not merged production code. Rules:

1. **Branch `spike/<id>`**, may contain throwaway code; only `tools/`, `test/perf/` harness pieces and data files it produces are merged (via a follow-up task the REPORT names).
2. **REPORT.md** follows `docs/templates/REPORT.md` (REPO-05): scope, harness, measurements (tables, raw numbers attached under `docs/spikes/<id>/`), pass/fail per criterion, the fallback taken or recommended (from the owning doc's fail path), and "plan changes requested" as ids.
3. **Owner reads within 2 working days** (HUM-12) and writes the gate decision on the REPORT (pass / pass with fallback X / fail -> PM decision). No lane that the spike "Blocks" (01 App. A column) is launched before that line exists.
4. **Fallbacks are data** (09 s6 standing rule): a Haiku task applies `rules.json` / `match_rules.json` / `modes.json` / `quality_tiers.json` changes; a code split is never a fallback.
5. **PM-01** (after S-FLIGHT-1, S-SIM-1, S-WORLD-1, S-NAV-1, S-WEB-1) and **PM-02** (after S-WEB-2 and playtest 1) are the two Fable moments: the Architect reads every REPORT, converts every open fail path into tasks or amendments, re-sizes M3+ and hands the owner a backlog patch to approve.
6. Order is fixed by 01 Appendix A: S-CI-1, then CONTRACT-0, then **S-FLIGHT-1 before any downstream lane opens**, then S-SIM-1 and S-WORLD-1 in parallel, then S-NAV-1, S-WEB-1, S-WEB-2, S-NET-1, S-BACKEND-1.

### 6.2 Playtest loop

| Step | Who | Output |
|---|---|---|
| Recruit and schedule (3 novices for S-FLIGHT-1 at week 4; 4 for S-UX-1; 6-10 for QA-02; 8 incl. 2 browsers for QA-03; 20+ for QA-04) | Owner (HUM-07) | dates in the wave file |
| Build the test build and the protocol (GD-35 telemetry, 02 s18.4 metrics, tester questionnaire) | tools-engineer / test lane | a tagged build and `docs/playtests/<n>/protocol.md` |
| Run the session, take notes, collect telemetry | Owner | raw notes + telemetry export |
| Analyse: rank issues, compute pad time / possession uplift / landing success / "feels like a plane" median, compare to bands | playtest-analyst (Sonnet) | `docs/playtests/<n>/analysis.md` + `BUG-*` tasks appended to `backlog.json` (status `todo`, tier proposed) |
| Decide: what is balance (GD-34/QA-09, Opus), what is UX (06 lane tasks), what is a pillar question (owner) | Owner + Architect at the weekly review | tiers and milestones confirmed; tasks enter the next wave |
| Verify: the next playtest or the weekly soak shows the metric moved | playtest-analyst | one line per fixed issue in the next analysis |

Soak output (nightly `balance_report.py`, GD-25) feeds the same loop weekly without humans: out-of-band metrics become `BUG-*` tasks proposed by the analyst, decided at the weekly review.

### 6.3 Weekly cadence (owner, about 3-4 hours plus merges)

| Day | Activity | Tool / output |
|---|---|---|
| Monday | **Wave open.** Ready set, capacity check, launch (Section 5.1-5.2). Read Friday's nightly: soak, perf history, goldens. | wave file, `WAVE: start` commit |
| Daily (M2-M3: 1-2 h) | Merge approved PRs in dependency order; answer `BLOCKED` and contract questions (route to Architect); spot-check one test per PR. | PR merges, Architect launches |
| Wednesday | **Mid-wave check.** Any agent silent > 1 day or any PR red > 1 day: Section 5.5. Rebase waiting PRs. | PR comments |
| Thursday | **Review and plan.** Weekly balance-band review from M3 (bands file vs nightly); triage `BUG-*`/`SUB-*` proposals (tier, milestone); approve any pending ADR amendments; owner tasks due next week. | `backlog.json` patch (Architect or orchestrator), amendment approvals |
| Friday | **Wave close.** `WAVE: close`, actual agent-days and tokens into the wave file, flaky log, worktrees removed; pick the next ready set so Monday starts fast. | wave file closed |
| Every 2 weeks | Re-read 09 s1.1 milestone exit criteria for the current milestone; re-check calendar slip against the three critical chains (09 s1.2). | one paragraph in the wave file |
| Per spike | Gate read within 2 working days (HUM-12). | REPORT decision line |

### 6.4 What the owner must personally check (no agent sign-off counts)

- **Game feel.** S-FLIGHT-1 tester session in person; every build that changes `kinematics.gd`, `sim/steer/`, camera constants or assist profiles gets ten minutes of the owner's own flying before merge (the reviewer checks numbers; only a human checks "feels like a plane"). Tail-down landings, boost, the Chase camera on the pole, the auto-dock hand-over.
- **Art.** Style frames (ART-01, ART-06) and the Dart/Core sign-off (HUM-09) in rendered form on the actual devices (HUM-06), including the nose-up landing pose. Golden screenshots catch regressions, not taste.
- **Readability on devices.** Steam Deck at 1280x800 and the Android-mid phone: 9 px text, control counts, icon band distance. Once per milestone, before the playtest.
- **Audio.** The licensed music (HUM-08) and the mix on a phone speaker and on headphones; no AI-generated audio enters the repo (ADR-13 / 07).
- **Store, legal, money.** Every account, fee, contract, policy, questionnaire and submission (HUM-02/03/05/10/13/18); the IAP catalogue; the data-safety answers in `docs/compliance/` before any store upload. Agents draft; the owner signs and submits.
- **Fiction and names.** Campaign fiction, faction and title names (HUM-02, HUM-17), the clean-room rule (no Triplane names).
- **Spend.** The monthly token and infrastructure figures (Section 7) against 09 s4.
- **Anything an agent presents as "confirmed by the user" or "approved earlier".** Approval exists only in the amendment files, the REPORT decision lines and the wave files; an agent quoting approval from elsewhere is wrong by definition.

---

## 7. Cost control

### 7.1 Token budget guidance per tier

Relative list prices (09 s4.2, cached 2026-10-06, input/output per million tokens): Haiku 5.5 $0.10/$0.50, Sonnet 5.5 $2/$10, Opus 5.5 $4/$20, Fable 5.1 $10/$50. Planning figures per task, to be replaced by measured numbers from the wave files after M0:

| Tier | Typical task | Planning budget per task (input + output) | Watch for |
|---|---|---|---|
| Haiku | a def file, a fixture set, 3-6 unit tests, a README | 0.3-1 M tokens | reading more than `CLAUDE.md` + `MODULE.md` + one doc section; retries from a vague brief (fix the brief, not the model) |
| Sonnet | a class with tests, a UI screen, a tool | 2-6 M tokens | re-reading whole docs (brief must name sections); long CI-fix loops (cap at 3 CI rounds, then stop and report) |
| Opus | a hot-path subsystem, a spike with REPORT | 8-25 M tokens; spikes up to 40 M | exploring alternatives the docs already rejected; rewriting Sonnet-tier scaffolding itself instead of delegating (an Opus agent may launch a Haiku helper for fixtures) |
| Fable | PM-01/02/03, an ADR amendment set | 10-30 M tokens, 3 times in v1.0 | being launched at all for anything a `MODULE.md` answers |
| Reviews | per PR | Sonnet 0.5-1.5 M; Opus 1-3 M | reviewers reading transcripts instead of diffs and tests |

Rules of thumb that follow from 09 s4.2: token cost of v1.0 is roughly 1 Haiku : 110 Sonnet : 75 Opus : 4 Fable, so the lever is **keeping Sonnet tasks small and contract-bound** (fewer retries), then **keeping Opus review rounds to one**. Shaving Haiku saves nothing.

Mechanics:
- Every brief names doc *sections*, never documents; `CLAUDE.md` tells agents to read nothing else by default.
- Agents cap CI-fix loops at three rounds, then report. Each extra round is a full context re-read.
- Reviewers get the diff, the acceptance, the tests and the CI log; they never get the author's transcript.
- Spikes end with a REPORT the owner reads once; nobody re-derives a spike result from its transcript.
- The orchestrator records tokens per agent from the Workflow journal in the wave file; after M0 these replace the planning column above.
- Prompt caching: keep `CLAUDE.md` and each `MODULE.md` stable within a wave (edits invalidate the cached prefix for every agent in the lane); batch contract edits to the wave boundary.

### 7.2 When not to use Fable

- Never for implementation, review of ordinary PRs, debugging, test writing, or "let's think about the architecture of X" when X has a `MODULE.md`.
- Never for a single-lane question; that is the lane's Opus engineer reading its own contract.
- Never as an escalation target from Opus; an Opus double failure is a contract problem, and the Architect is launched with *that* framing (the question), not with the task.
- Yes for: PM-01, PM-02, PM-03; an ADR amendment that moves a number other docs depend on; a contradiction between two docs that both claim 01; re-tiering the backlog after measured token data; redesigning this document.
- Budget: 2.5 Fable agent-days in v1.0 (09 s4.1). If the wave files show Fable use above one launch per month outside PM tasks, something upstream (contracts, briefs) is broken and that is what gets fixed.

### 7.3 Batching Haiku content work

Batch when: ten or more def/fixture/mission/locale/SFX-recipe edits share a validator and a doc section (GD-01's 15 schemas, ART-37's 11 fixtures, GD-32's mission strings, UX-30's locale, QA-07's reserve, a GD-34/QA-09 retune after Opus decides the numbers).

How:
- One worktree, one branch `task/<id>-batch`, one PR, one Sonnet review at the end; inside it, one Haiku agent per file or per 3-5 small files (parallel, `pipeline`), each running the validator before returning.
- The brief for each Haiku agent contains the exact doc table or the Opus decision list for its files; never "tune X".
- The batch PR's acceptance -> evidence table lists the validator run and the spot-value tests (03 s9.4 schema discipline).
- Do **not** batch across validators (defs with locale) or across lanes; do not batch anything that changes a schema (that is a contract append by the content lane at Sonnet).
- Retunes: Opus (GD-34) writes `docs/balance/<date>-decisions.md` with the exact new values and reasons; a Haiku batch applies them; the nightly soak verifies; nothing is retuned by Haiku on its own judgement.

### 7.4 Infrastructure and runner cost

Not token cost but owned by the same cadence: the pinned perf runner and game host (HUM-04, about EUR 60/month per 04 s12.4), CI minutes (keep PR pipeline <= 15 min; exports to nightly if it grows), LFS quota (HUM-01, ~2 GB), reference devices (HUM-06, one-off). Reviewed monthly in the Friday wave file.

---

## Appendix A. File map created or expected by this document

| Path | Created by | Purpose |
|---|---|---|
| `CLAUDE.md` | this document's companion (REPO-02 refines) | the short conventions every agent reads first |
| `.claude/agents/architect.md`, `sim-engineer.md`, `net-engineer.md`, `ai-engineer.md`, `planet-renderer-engineer.md`, `feature-engineer.md`, `ui-engineer.md`, `tools-engineer.md`, `content-author.md`, `test-author.md`, `code-reviewer.md`, `playtest-analyst.md` | companion (REPO-03 adds settings and hooks) | one subagent per role, `model` = tier |
| `.claude/settings.json` | REPO-03 | permissions; PostToolUse hook running `check_deps.py` / `validate_content.py` on edited files |
| `.github/PULL_REQUEST_TEMPLATE.md`, commit-id lint | REPO-06 | Section 3.4 |
| `CODEOWNERS` | REPO-01 | Section 4.3 table |
| `docs/templates/MODULE.md.template`, `REPORT.md`, `docs/adr/` template | 03 s15.1, REPO-05 | contracts and gates |
| `tools/backlog_report.py` | REPO-05 | ready set, per-milestone totals |
| `docs/waves/<date>-<M>.<n>.md`, `docs/waves/flaky.md` | orchestrator | the audit trail of every wave |
| `docs/playtests/<n>/`, `docs/spikes/<id>-REPORT.md`, `docs/balance/<date>-decisions.md` | playtest-analyst, spike agents, GD-34/QA-09 | Section 6 |

## Appendix B. First two weeks, concretely

- **Day 1 (owner):** HUM-01 (repo, Actions, LFS, secret store), HUM-06 order devices, HUM-04 start the VPS/host purchase. `git init` is REPO-01 (Haiku) once the GitHub repo exists; copy `CLAUDE.md`, `.claude/agents/` and `docs/` in as the first commit.
- **Day 2 wave (3 agents, interactive):** REPO-01 [Haiku, repo]; then TA-01 [Sonnet, app: `project.godot` per 03 s1.1], DOC-01 + REPO-04 + REPO-05 [Haiku, docs], REPO-02 [Sonnet, repo: refine `CLAUDE.md`], ART-02 [Sonnet, tools].
- **Day 4:** TA-05 [Haiku, core utilities], TA-02 [Sonnet, tools: `check_deps.py`], REPO-03 [Sonnet, `.claude/settings.json` + hook].
- **Week 2:** TA-03 S-CI-1 [Sonnet, Opus signs the soak] is the gate; nothing else matters until it is green. Then REPO-06, CONTRACT-0 [Opus], TEST-01, ART-32; then GD-01, TA-07; then TA-10, TA-08.
- **Week 3-4 (M1):** GD-02/03/05 defs [Haiku], TA-04 sphere math [Opus], TA-06 core MODULE.md, TA-12 kinematics [Opus], then TA-30 S-FLIGHT-1 [Opus] with the three novices (HUM-07). Owner flies it. Nothing downstream opens before the gate line is written on its REPORT.

## Revision log

| Date | Change | Why |
|---|---|---|
| 2026-10-10 | Editorial sweep (editor-in-chief): `CLAUDE.md` gains a pointer row for `docs/00-master-plan.md` (orientation only; task agents do not read it by default). 09/`backlog.json` REPO-02, REPO-03 and DOC-01 retitled as refinements of the companion files this document created (see 09 revision log). | `00-master-plan.md` became the entry point; the backlog titles predated the companion files. |
| 2026-10-13 | s4 and s4.3: subsystem `MODULE.md` files under `godot/src/sim/<subsystem>/` are contracts once they exist; the `sim/MODULE.md` enumeration block's bullet format is a parsed contract (`test_protocol.gd`). | `sim/MODULE.md` reached the 300-line cap at 299 lines (R0 B.9 A-21, `docs/reviews/R0-amendments-02.md`). |
