# PLANEWAR

Codename for an arcade spaceship dogfighter fused with a Command & Conquer-style base builder, fought across a 6 km-radius spherical moon. It is a spiritual successor to Triplane Turmoil (no shared code, assets or names). You have no avatar: you can possess any of your ships, turrets or factories, and everything returns to its autopilot when you let go. Matches have 2-8 players, with bots in every empty seat. Modes are Online PvP, Skirmish, Co-op vs AI and an eight-mission Campaign. The art is stylized low-poly, the engine is Godot 4.7.2, and all code is typed GDScript.

v1.0 targets Windows (Steam, including Steam Deck), Android (Google Play) and the web (itch.io and our own site). iOS, macOS, Linux native, Poki and CrazyGames follow in v1.1.

## Status

**Planning is complete (2026-10-10). The repository skeleton exists; game code does not yet.** The design, architecture, backlog (339 tasks) and agent operating manual are written and reconciled. Delivery week 1 starts on 2026-10-12 with milestone M0 (Foundations).

## Where to start

| You are | Read |
|---|---|
| The owner, or anyone new | [`docs/00-master-plan.md`](docs/00-master-plan.md): the pitch, owner decisions, document map, milestones, first waves, risks and open questions |
| Running agents | [`docs/10-agent-coordination.md`](docs/10-agent-coordination.md) section 5, then [`docs/backlog/backlog.json`](docs/backlog/backlog.json) |
| An agent working on a task | [`CLAUDE.md`](CLAUDE.md), your lane's `godot/src/<module>/MODULE.md`, and the doc sections your task names |
| Looking for a decision | [`docs/01-vision-and-core-decisions.md`](docs/01-vision-and-core-decisions.md) (ADRs, glossary) and [`docs/reviews/R0-resolution-register.md`](docs/reviews/R0-resolution-register.md) Part B (contract tables) |

## Running things headless

Run these from the repository root. These are the commands from `CLAUDE.md`, "Running things headless".

```sh

godot --headless --path godot --import                      # once per fresh worktree; builds .godot/ cache
python tools/check_deps.py                                  # D1-D10, < 10 s
python tools/validate_content.py                            # schemas, dangling refs, docs/examples
godot --headless --path godot -s tools/validate_scenes.gd   # every .tscn instantiates
GODOT_BIN=godot godot/addons/gdUnit4/runtest.sh -a res://test/unit -c -rd reports   # exit 0 ok, 100 failures, 101 warnings
GODOT_BIN=godot godot/addons/gdUnit4/runtest.sh -a res://test/unit/<lane>/test_x.gd  # one file
python tools/gen_module_api.py --check                      # MODULE.md vs code
```

Notes:

- **Godot binary.** The commands use `godot` on the PATH. If it is not on your PATH, set `GODOT_BIN` to the Godot 4.7.2 console build and use it in place of `godot` and in the `GODOT_BIN=...` prefix.
- **Fresh worktree.** Run the `--import` line once per fresh clone or worktree before anything else; it builds the `.godot/` cache.
- **Debug runs.** Never run `godot -d` without `--remote-debug tcp://127.0.0.1:0`, or a parse error waits forever at a `debug>` prompt. The gdUnit4 runner adds this flag for you.
- **Exit codes** of `runtest.sh`: 0 ok, 100 failures, 101 warnings.
- **Screenshots** need a windowed build under Xvfb (CI does this nightly).

## Lane map

The repository is split into lanes, one module per lane. Each lane has a `MODULE.md` contract in its directory (`godot/src/<module>/MODULE.md`). Dependencies point down only; `tools/check_deps.py` enforces this. Source: `docs/09-roadmap-and-backlog.md` section 3.3 and `docs/01-vision-and-core-decisions.md` section 9.2.

| Lane | Directory |
|---|---|
| core | `godot/src/core/` |
| content | `godot/src/content/`, `godot/content/defs/` |
| sim | `godot/src/sim/` |
| sim_ai | `godot/src/sim_ai/` |
| net | `godot/src/net/` |
| server | `godot/src/server/` |
| presentation | `godot/src/presentation/` |
| camera | `godot/src/camera/` |
| input | `godot/src/input/` |
| ui | `godot/src/ui/`, `godot/scenes/ui/`, `godot/content/ui/` |
| platform | `godot/src/platform/` |
| campaign | `godot/src/campaign/`, `godot/content/campaign/` |
| app | `godot/src/app/` |
| assets | `godot/assets/` (Git LFS) |
| maps | `godot/content/maps/` |
| tools | `tools/` |
| test | `godot/test/` |
| server-ops | `server-ops/` |
| ci | `.github/workflows/` |
| web | `web/` |
| docs / repo / pm | `docs/`, repository root |

An agent edits only its lane's directory, its `godot/test/<layer>/<lane>/` tests and its `MODULE.md`. Anything else is a separate task or a PR comment.

## Documentation

| Doc | Content |
|---|---|
| [`docs/00-master-plan.md`](docs/00-master-plan.md) | Pitch, owner decisions, document map, milestones, first waves, risks |
| [`docs/01-vision-and-core-decisions.md`](docs/01-vision-and-core-decisions.md) | Pillars, ADRs (section 7), budgets, lanes and interfaces, glossary |
| [`docs/02-game-design.md`](docs/02-game-design.md) | Game design |
| [`docs/03-technical-architecture.md`](docs/03-technical-architecture.md) | Technical architecture |
| [`docs/04-networking-and-backend.md`](docs/04-networking-and-backend.md) | Networking and backend |
| [`docs/05-ai-autonomy-and-control.md`](docs/05-ai-autonomy-and-control.md) | AI, autonomy and control |
| [`docs/06-platforms-input-ux.md`](docs/06-platforms-input-ux.md) | Platforms, input and UX |
| [`docs/07-art-audio-content.md`](docs/07-art-audio-content.md) | Art, audio and content |
| [`docs/08-feature-ideas.md`](docs/08-feature-ideas.md) | Feature ideas |
| [`docs/09-roadmap-and-backlog.md`](docs/09-roadmap-and-backlog.md) | Milestones, calendar, backlog, lane ownership |
| [`docs/10-agent-coordination.md`](docs/10-agent-coordination.md) | Roles, tiers, task lifecycle, definition of done |

Also:

- [`docs/backlog/backlog.json`](docs/backlog/backlog.json): every task (id, lane, tier, dependencies, milestone, acceptance).
- [`CLAUDE.md`](CLAUDE.md): conventions every agent reads first.
- [`.claude/agents/`](.claude/agents/): one subagent definition per role.

## Test site

A static test site built from `web/site/` is deployed by Vercel at **https://planewar-test.vercel.app**. Vercel redeploys it on every push to `main`.
