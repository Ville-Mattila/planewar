# R0 amendments 23: `flee_radius_m`, `quiet_s`, `follow` and `harvest` are required on `ap_harvester`; `follow` becomes required on `ap_crawler` in AI-18's PR (AI-47 PR #168, contract question from its Opus review)

| Field | Value |
|---|---|
| **Register id** | R0 Part B, subsection B.29 (append-only): A-144, A-145 added 2026-11-16. The B.1 `autopilots.json` sentence gains one clause. No ADR is amended; no enumeration, signature, `deps.json` edge, wire layout, autoload, addon or thread change; `PROTOCOL_VERSION` and `SimSerialize.FORMAT` unchanged. |
| **Status** | Decided by the Architect 2026-11-16; the OWNER items below carry their default until the owner rules. |
| **Date** | 2026-11-16 |
| **Raised by** | AI-47 (PR #168), Opus review verdict "escalate (Architect)": the PR adds required def fields and labels them "Contract impact: append". |
| **Decided by** | Architect (Fable), 10 s4.1 ("a new required def field" is a Change: the Architect proposes, the owner approves) and 10 s4.3 (`tools/schemas/*.schema.json`: "Architect for required fields"). |
| **Size** (10 s4.1) | Two register rows, one B.1 clause, one new task (AI-48), two acceptance appends. The Architect edits no `godot/src/**`, no `godot/test/**`, no schema, no `MODULE.md`. |

Reading order: the B.29 rows in `docs/reviews/R0-resolution-register.md` are the binding text; this file is the why.

## A-144 (AI-47) the four `ap_harvester` keys are required

**Evidence.**

1. **The consumer has no defaults.** `sim_ai/brains/MODULE.md` HV5 (AI-16, PR #162, Opus-reviewed): "keys all required, no defaults"; `HarvesterParams` rejects a def that lacks one. A schema that leaves them optional accepts a def the brain refuses, so `validate_content` would pass content that fails at load.
2. **Precedent.** B.14 A-86 (`separation` / `formation`) and B.17 A-93 (`guidance` / `intercept` / `attack_run` on `ap_dart`, landed by AI-19, PR #158) ratified brain blocks as required on the class that reads them, optional elsewhere, every key required when present. This is the same shape.
3. **No number changes.** The review diffed all 21 block keys plus `flee_radius_m` 600 and `quiet_s` 15 against `godot/test/sim/ai/ai16_autopilots.json`: values and JSON types are identical, and the AI-16 suites pass on the shipped def (PR #168: 272 unit and 115 sim cases, CI 19 / 19). The values trace to AI-16 (05 s5.7, 05 s6.6).
4. **No other consumer is affected.** Only the `ap_harvester` anyOf branch gains requirements; the shipped def and the canonical fixture already satisfy it in the PR.

**Decision (OWNER, default applied as A-93 was).** Required on `ap_harvester`: `flee_radius_m`, `quiet_s`, `follow` (11 keys), `harvest` (10 keys); every key required when a block is present; `additionalProperties: false` on both blocks. Optional on every other `ap_*`, A-145 excepted. The values are data and the content lane tunes them without a ruling.

**What PR #168 changes before merge** (author; no value or brain test changes):

1. PR body: "Contract impact: change (R0 B.29 A-144)", not "append".
2. `tools/schemas/autopilots.schema.json` `autopilot` `$comment`: it says the class keys `flee_radius_m`, `tow_scan_m`, `tow_enemy_clear_m`, `quiet_s` are optional. Reword: `flee_radius_m`, `quiet_s`, `follow` and `harvest` are required on `ap_harvester` (R0 B.29 A-144) and optional elsewhere.
3. `ap_harvester` `_doc` (shipped def and canonical fixture): cite `sim_ai/brains/MODULE.md` HV5 and R0 B.29 A-144 instead of the fixture path, which AI-48 deletes.
4. One committed negative case in `tools/tests/test_validate_content.py` (the form of the existing `ap_dart` `flight/kp_path` case): an `ap_harvester` without `follow` fails validation. The PR's negative checks were run from a scratch script; a required field needs a test that stays (10 s4.1 "test diff").

**Not required: a commit split.** 10 s4.1 asks for the contract test in an earlier commit; PRs to `main` are squash-merged, so the order does not survive, and the test diff is in the same PR. A fixup commit on the branch is enough.

## A-145 (AI-47 review) `ap_crawler` carries `follow`, required, added by AI-18

HV5 and 05 s5.7 give the Siege Crawler the same ground follower as the Harvester; `ap_crawler` today has the B.1 required keys only and nothing reads a `follow` block on it. The block is required for the same reason as A-144 (the follower has no defaults), and it lands with its reader: a required block with no consumer is untested data.

**Decision.** AI-18 adds `follow` to the `ap_crawler` schema branch as required (the same `$defs.follow`, the same 11 keys, none added or dropped), together with the shipped def, the canonical fixture and one negative case, in its own PR flagged "Contract impact: change (R0 B.29 A-145)". No second Architect round. Starting values are `ap_harvester`'s; AI-18 tunes them and says so in `_doc`.

**Limits.** Only `follow` is ratified. Any other new `ap_crawler` key or block is either optional with a default (an append) or returns as a contract question with its key list (the A-93 path: fixture first, ruling, then content). `harvest`, `flee_radius_m` and `quiet_s` are not `ap_crawler` keys.

## The dead fixture (no register row; a task)

`godot/test/sim/ai/ai16_autopilots.json` has no loader after PR #168. `godot/src/sim_ai/brains/MODULE.md` (lines 17, 227, 233) and `godot/src/sim_ai/MODULE.md` (line 282) still name it and D10 fails if a named file is missing, so AI-47 (content lane) rightly left it. **AI-48** (sim_ai) removes the references and the file.

## Backlog patch (proposed; the owner approves, the orchestrator lands it; `backlog.json` is not edited here)

```json
{
  "new": [
    {"id": "AI-48", "title": "sim_ai: delete the dead fixture ai16_autopilots.json and its MODULE.md references (R0 B.29 A-144)", "lane": "sim_ai", "tier": "Haiku", "size_days": 0.1, "depends_on": ["AI-47"], "milestone": "M3", "acceptance": "godot/test/sim/ai/ai16_autopilots.json deleted; godot/src/sim_ai/brains/MODULE.md (status row, HV5, test entry points) and godot/src/sim_ai/MODULE.md no longer name it; HV5 reads as a description of the shipped ap_harvester keys (required, R0 B.29 A-144) and no longer as a content note for AI-19; ai16_kit.gd has no AUTOPILOTS const or comment naming the fixture; grep finds no ai16_autopilots under godot/ or tools/; check_deps (D10), gen_module_api --check, validate_content and the sim_ai unit and sim suites green; no Public API or behaviour change", "docs": ["docs/reviews/R0-amendments-23.md", "godot/src/sim_ai/brains/MODULE.md"]}
  ],
  "acceptance_append": {
    "AI-47": "; R0 B.29 A-144: the four ap_harvester keys are required (a Change, not an append); the schema $comment says so, the ap_harvester _doc cites brains/MODULE.md HV5 instead of the fixture, and test_validate_content.py has a negative case (ap_harvester without follow fails)",
    "AI-18": "; R0 B.29 A-145: ap_crawler carries a required follow block (the 11 keys of $defs.follow) in the schema, the shipped def and the canonical fixture, with one negative case in test_validate_content.py, all in this PR flagged 'Contract impact: change (R0 B.29 A-145)'; any other new ap_crawler key is optional with a default or a contract question"
  },
  "note": {
    "AI-47": "Ruling R0-amendments-23 (B.29 A-144, A-145): required confirmed; no commit split; fixture removal is AI-48.",
    "AI-18": "AI-18 edits tools/schemas/autopilots.schema.json and autopilots.json for the follow block only, under A-145 (10 s4.3: Architect for required fields; defs: fields its task adds)."
  }
}
```

## Not ruled here

- `tow_scan_m` and `tow_enemy_clear_m` (the Hauler's keys in the same `$comment`) stay optional; no brain requires them today.
- AI-18 is tiered Haiku in `backlog.json` for a brain; CLAUDE.md's tier guidance puts brains at Opus. A re-tier is the orchestrator's call at launch, not part of this ruling.

## Decisions for the owner

1. A-144: `flee_radius_m`, `quiet_s`, `follow`, `harvest` required on `ap_harvester`. Recommendation: approve (the brain has no defaults; A-86 / A-93 precedent; no value changes). Default if silent: applied; PR #168 merges after the four author fixes above.
2. A-145: AI-18 adds `follow` as required on `ap_crawler` in its own PR, no second ruling. Alternative: a separate content task before AI-18 (a required block with no reader). Recommendation: AI-18. Default: AI-18.
3. AI-48 (sim_ai, Haiku, 0.1 d, M3) deletes the dead fixture. Alternative: fold it into AI-18 (same lane, same files; saves a PR but leaves the fixture until AI-18 runs). Recommendation: AI-48 now. Default: AI-48 as written.
4. No commit split on PR #168 (squash merge). Alternative: enforce 10 s4.1's "earlier commit" literally. Recommendation: no split. Default: no split.
