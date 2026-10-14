# PLANEWAR - agent conventions

Godot 4.7.2 game: a Triplane Turmoil spiritual successor with spaceships on a 6 km-radius spherical moon, fused with a C&C-style base builder. No avatar: possess any unit or structure; everything returns to autopilot when released. 2-8 players with bots. Typed GDScript only. Stylized low-poly. v1.0 ships Windows (Steam, incl. Deck), Android (Google Play) and web.

## Where the plan lives (read sections, not documents)

| Doc | Use it for |
|---|---|
| `docs/00-master-plan.md` | orientation only (pitch, owner decisions, doc map, milestones, first waves, known issues). Task agents skip it unless a brief names it. |
| `docs/01-vision-and-core-decisions.md` | the spine: pillars, 14 ADRs (s7), budgets (s8), lanes and interfaces (s9), glossary (s10). Binding. |
| `docs/reviews/R0-resolution-register.md` | Part B = canonical contract tables (def fields, enums, deps, signatures). Overrides 02-08. |
| `docs/02` game design, `03` architecture, `04` net/backend, `05` AI, `06` platforms/input/UX, `07` art/audio/content, `08` feature ideas | the long-form acceptance your task's `docs` field points at |
| `docs/09-roadmap-and-backlog.md` + `docs/backlog/backlog.json` | milestones, waves, lane ownership (s3.3), every task |
| `docs/10-agent-coordination.md` | roles, tiers, task lifecycle, contract-change protocol, how waves run |
| `godot/src/<module>/MODULE.md` | your lane's contract: public API, invariants, tests, recipes. Read before touching the module. |

Default reading for a task: this file, your lane's `MODULE.md`, the sections in the task's `docs`, the acceptance of its dependencies. Nothing else unless blocked.

## Pointer key

`01` = `docs/01-vision-and-core-decisions.md`, `03` = `docs/03-technical-architecture.md`, `10` = `docs/10-agent-coordination.md`. A pointer `(01:588)` is file:line of the rule's source text in the current docs. ADR-14 is one paragraph at 01:588; each rule below cites it once.

## Binding rules, ADR-14 (01:586-588)

- **Lanes and contracts.** The repo is split into lanes = modules (01 s9). Every module has a `MODULE.md`: responsibility, allowed deps, public API with signatures, invariants, test entry points, suggested tier. A change to Public API or Invariants updates the contract tests first, in the same PR; `tools/gen_module_api.py --check` must pass; file <= 300 lines. (01:588)
- **`class_name` on every script, one public class per file, files <= 400 lines.** Exception: the three autoload scripts (`Log`, `ContentDB`, `App`) have no `class_name`, because Godot rejects a global class that shares an autoload's name; `check_deps.py` D7 must exempt the paths registered under `[autoload]`. (01:588; check_deps D7, 03:1240)
- **Autoloads:** exactly `App`, `ContentDB`, `Log`. No new autoloads without an ADR amendment. (01:588; D4, 03:1237)
- **Every sim-affecting constant lives in JSON.** Balance, caps, physics constants, tier values go in `godot/content/defs/*.json` with a schema in `tools/schemas/` and a `_doc` citation. (01:588, ADR-09 01:528)
- **Commit subjects start with the task id** (`TA-18: ...`). CI lint rejects anything else. (01:588)
- **Never read Triplane Turmoil source** or use its names (clean-room rule, R1 s1.4). (01:588)
- **Never file upstream Godot issues or PRs** (R2 s1.4). Write the finding in your PR/REPORT; a human files it. (01:588)
- **Never add dependencies outside the allowlist.** Addons: `gdUnit4` 6.2.x and `nakama` only (`godot/addons/`; D5, 03:1238). No SDKs or network calls the docs do not name; no ad or tracking SDKs in any v1.0 build. (01:588)
- **Layering:** the table in 01 s9.2 (01:689) is mirrored verbatim in `tools/deps.json`; dependencies point down only. The only cross-layer exception is the named list of `sim` public types that `input`, `ui`, `campaign`, `net` may reference. `sim`, `sim_ai`, `core` contain no Nodes or `await` (D2, 03:1235). `check_deps.py` D1-D10 (03:1228-1243) fails CI on a violation. (01:588)
- **CONTRACT-0 first.** The JSON schemas and `sim/MODULE.md` encoding R0 Part B are committed before any lane opens. Do not start lane work if CONTRACT-0 is not `done`. (01:588)
- **Tiers** (guidance): Fable = cross-module design and ADR amendments; Opus = sim, net, planet renderer, Commander bot and all reviews of those; Sonnet = features against a `MODULE.md`, UI, platform services, tools; Haiku = defs, schemas, docs, map recipes, test data, lint fixes, simple unit tests. (01:588)

## Other binding rules

- **Typed GDScript, warnings as errors** (ADR-01, 01:411). The warning set (`untyped_declaration`, `inferred_declaration`, `unsafe_*`, `return_value_discarded`, `missing_await`, `unused_*`, `shadowed_variable`, `integer_division`, `narrowing_conversion`) is level 2 in `project.godot` and stays there (D8, 03:1241). Use `var _r := fn()` or `-> void`; use `core/mathx.gd` `floori()`/`posmod()` so `@warning_ignore` never appears in `src/sim/**`.
- **No C#. No GDExtension in v1.** Native twins are a v1.1 decision behind the same GDScript interface.
- **Threads:** none, except `Thread` in `godot/src/app/offline_host.gd` inside a non-web branch (D3, 03:1236).
- **`PLANET_RADIUS` discipline:** 6,000 m lives once in `core/sphere.gd`. Never type `6000` or `8192` in `src/**`; derive from `Sphere.PLANET_RADIUS` (D6, 03:1239).
- **Float literals** in `src/sim/**` other than `0.0, 0.5, 1.0, 2.0, -1.0` are a warning for a reason: numbers belong in defs (03:1239).
- **Enumerations are append-only** with frozen ordinals (`Command.Kind`, `SimEvent.Kind`, `AlertKind`, `LandingGrade`, def enums; R0 B.3). Append at the end in `sim/MODULE.md`; never reorder, rename or delete.
- **Tests are part of done** (ADR-11, 01:551). Every public symbol you add or change has a gdUnit4 test in the layer ADR-11 names (`godot/test/unit|sim|net|soak|perf|golden/`).
- **Stay in your lane.** Write only `godot/src/<lane>/**`, `godot/test/**/<lane>/**` and your `MODULE.md` (shared-file table: 10 s4.3, 10:268). Anything else is a PR comment `needs <lane>: ...` or a follow-up task. Never edit `docs/backlog/backlog.json`.
- **If the acceptance cannot be met inside the contract, stop.** Write `BLOCKED: <reason>` in the PR body. Do not widen a contract, add an edge to `deps.json`, or amend an ADR yourself; that goes to the Architect and the owner (10 s4, 10:250).

## GDScript performance rules (03 s12.2, 03:1210-1222)

Enforced by review; mechanically by `check_deps.py` where possible. Applies to `src/sim/**`, `src/sim_ai/**` and any hot path.

1. Sim state in packed arrays; no per-entity objects on hot paths (no `RefCounted` per entity in `src/sim/`, except reused `ShipState` scratch). (03:1212)
2. No `Dictionary` or `Array` allocation inside per-entity loops; preallocate scratch arrays as members. (03:1213)
3. Use `Vector3` built-ins (`dot`, `cross`, `normalized`, `lerp`, `distance_squared_to`), not component math; read `PackedVector3Array[i]` into a local once per entity. (03:1214)
4. No `String`/`StringName` formatting or `Log` calls in hot loops; `Log.debug` is compiled out by `const DEBUG := false` in release. (03:1215)
5. No signals inside `src/sim/`; append to `Array[SimEvent]` and drain once. (03:1216)
6. `for i in n` is fine; do not store `range(n)`; iterate `PackedInt32Array` live lists directly. (03:1217)
7. Typed everything; `Variant` boxing costs 2-3x. (03:1218)
8. Prefer `static func` on `class_name` utilities for math. (03:1219)
9. Hot-path functions <= 40 lines. (03:1220)
10. Measure before cutting: every optimisation PR cites a `perf_tick.gd` delta. (03:1221)
11. Never mutate a packed array stored inside an `Array` or `Dictionary` (`dict[k].append(x)` edits a copy); keep them as typed members (R0 C1-19). (03:1222)

## Local environment

- Set `GODOT_BIN` to your Godot 4.7.2 console binary; the commands below use `$GODOT_BIN` (the gdUnit4 runner reads it too). Machine-specific paths live in the untracked `CLAUDE.local.md` of the main checkout (agent worktrees under `.claude/worktrees/` do not have it: read it from the main checkout two levels up). Always confirm `"$GODOT_BIN" --version` starts with `4.7.2`; an inherited shell `GODOT_BIN` may point at an older build.
- Shell is Git Bash (POSIX syntax, forward slashes). Python is 3.14.
- Export templates are not installed locally; exports run in CI only.
- Branch protection on `main` is not available on the current GitHub plan. "main is protected" is a process rule enforced by review until the owner upgrades: never push to `main`, never merge your own PR, PRs only.

## Running things headless

```sh
"$GODOT_BIN" --headless --path godot --import                      # once per fresh worktree; builds .godot/ cache
python tools/check_deps.py                                  # D1-D10, < 10 s
python tools/validate_content.py                            # schemas, dangling refs, docs/examples
"$GODOT_BIN" --headless --path godot -s tools/validate_scenes.gd   # every .tscn instantiates
godot/addons/gdUnit4/runtest.sh -a res://test/unit -c -rd reports   # exit 0 ok, 100 failures, 101 warnings
godot/addons/gdUnit4/runtest.sh -a res://test/unit/<lane>/test_x.gd  # one file
python tools/gen_module_api.py --check                      # MODULE.md vs code
```

Never run `"$GODOT_BIN" -d` (or any debug-enabled headless run) without `--remote-debug tcp://127.0.0.1:0`; otherwise a parse error drops into an interactive `debug>` prompt and your run hangs forever. The gdUnit4 runner does this for you. Screenshots need a windowed build under Xvfb + llvmpipe (CI does it nightly); attach a local screenshot to PRs that touch `presentation/` or `ui/`. Cap CI-fix loops at three rounds, then report.

## Picking up a task

1. You are launched with one id from `docs/backlog/backlog.json` (fields: `id, title, lane, tier, size_days, depends_on, milestone, acceptance, docs, status`). The brief you received is the 10 s3.1 template; if you have only an id, build that brief yourself from the JSON.
2. Confirm every `depends_on` is `done`; otherwise stop and report.
3. Work in your own git worktree on branch `task/<id>-<slug>` from `main`. Run the import once.
4. Read: this file, `godot/src/<lane>/MODULE.md`, the task's `docs` sections, the dependencies' acceptance. Then write tests, then code.
5. Definition of done (10 s3.3): acceptance demonstrated by named tests or a REPORT; `check_deps`, `validate_content`, `validate_scenes`, `gen_module_api --check` green; zero warnings; `MODULE.md` current; perf note for `sim/`, `net/`, `presentation/`; screenshot for `presentation/`, `ui/`; PR from the template titled `<id>: <title>` with an acceptance -> evidence table.
6. Reviews: Opus reviews `sim`, `net`, `presentation/planet`, `sim_ai` Commander/brains/steer and every contract file, whoever wrote it; Sonnet reviews the rest. Fix one root cause per round. A second failed round escalates the task one tier; that is the orchestrator's call, not yours.
7. Final message: <= 20 lines; what you built, test names, perf numbers, what you could not do, contract questions.

## Glossary discipline

Use 01 s10's words: Core, Outpost, Harvester, Dart, Hauler, Bomber, Siege Crawler, Rail Lance, possess/release, autopilot, Commander bot, Adjutant, Doctrine, tail-down landing, Chase/Tactical/Commander camera tiers, `SimView`, `Command`, `PilotInput`. No synonyms, no Triplane names.
