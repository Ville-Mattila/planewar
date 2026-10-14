# sim/steer - MODULE.md

Contract for `godot/src/sim/steer/**`: 05's pure steering controllers (05 s1.3, s5; R0 C2-04, B.9 A-21 split of `sim/MODULE.md`).
A change to "Public API" or "Invariants" is a contract change: contract tests first, same PR (ADR-11); `tools/gen_module_api.py
--check` must pass; <= 300 lines (ADR-14). `net` prediction substitutes `Assist` for the possessed unit, so every change here is
reviewed for both the `sim_ai` and the `net` lane.

| Field | Value |
|---|---|
| Responsibility | Pure functions of their arguments that turn state into controls or probes: today `TerrainProbe` (05 s5.3, time to impact, worst clearance, lift). `FlightController`, `LandingController`, `Assist` land here with AI-05, AI-09 and AI-08. |
| Lane owner tier | Opus reviews (05 lane writes it; Sonnet may implement against this file) |
| May depend on | `core`, `content`, `sim` (`Terrain`, `Kinematics`, `PilotInput`) |
| Must never touch | Nodes, `net`, `presentation`, `ui`, `sim_ai`; no `await`, signals, `Thread`, RNG, autoloads, member state (S8) |
| Autoloads used | None |
| Status | `TerrainProbe` implemented (AI-07, 2026-10-14); other controllers planned |

## Public API

```gdscript
class_name ProbeParams extends RefCounted                                    # 05 s5.3 parameter struct, one per autopilot profile, read-only
var min_clearance_m: float; var clearance_per_mps: float                     # autopilots def (Dart): 25, 0.25
var probe_times_s: PackedFloat32Array                                        # autopilots def: 0.5 1 1.5 2 3 4, ascending
var gravity: float                                                           # rules.gravity
var lift_max_frac: float; var lift_min_time_s: float                         # lift cap 0.6 * |v|; sample-time floor 0.5 s
static func make(min_clearance: float, per_mps: float, times: PackedFloat32Array, g: float, lift_frac: float, lift_min_time: float) -> ProbeParams
func required_clearance(speed: float) -> float                               # min_clearance_m + clearance_per_mps * speed

class_name TerrainProbe extends RefCounted                                   # 05 s5.3, static only
const REFINE_STEPS: int                                                      # 5 bisection steps on a hit
static func time_to_impact(terrain: Terrain, p: Vector3, v: Vector3, probe: ProbeParams) -> float   # s; 0 if under surface; INF if clear
static func min_clearance(terrain: Terrain, p: Vector3, v: Vector3, probe: ProbeParams) -> Vector2  # (clearance m, time s) of worst sample
static func terrain_lift(terrain: Terrain, p: Vector3, v: Vector3, probe: ProbeParams, h_req: float) -> float   # m/s extra climb along local up
```

`p` is the sim position (planet centre origin), `v` the world velocity. The path is constant velocity in the tangent frame carried
along the great circle (ground speed `s`, angle `s t / |p|`), radius `|p| + v.n0 t - 0.5 g t^2`. The doc's signatures gain the
`terrain` argument because `Terrain` is an instance (03 s6.2), not a static sampler.

## Invariants

- ST1: Every function is `static` and reads only its arguments; no member `var`, no RNG, no clock, no allocation (Vector3 and float
  locals only). Identical inputs give identical outputs on every peer (S8, S9; `test_pure_and_deterministic`, `test_source_has_no_state`).
- ST2: `time_to_impact` is 0 when clearance at t = 0 is <= 0, INF when no probe sample is <= 0, otherwise within 0.1 s of the true
  first crossing in the sampled interval (`test_flat_*`, `test_sloped_terrain_matches_quadratic`, `test_ridge_tti_against_dense_reference`).
- ST3: `terrain_lift` is >= 0, 0 when the worst clearance is >= `h_req`, and <= `lift_max_frac * |v|`.
- ST4: A vertical or stationary ship stays over one point (no NaN from a zero ground speed).

## Performance budget

05 s10 / s5.3: 6 height samples per call, +1 (t = 0) and +5 (bisection) only inside `time_to_impact` on a hit; at think only
(05 s5.3 budgets about 375 samples per tick at 400 AI ships). Each `Terrain.height_at` is one
bilinear lookup over `PackedByteArray.decode_u16`.

## Test entry points

`godot/test/unit/sim/steer/test_terrain_probe.gd` (closed forms on flat and sloped synthetic terrain, ridge, cradle crater rims
against an independent Quaternion path, lift, purity). SC-09 / SC-10 need FlightController (AI-05) and the brains and are owned
by those tasks.

## How to add X (recipes for the cheapest tier)

- **A probe time:** edit `probe_times_s` in the autopilots def; nothing here changes.
- **A new controller:** `static func` only, take a state struct and an output `PilotInput`; add a purity test like `test_source_has_no_state`.

## Open items

- SC-09 / SC-10 (AI-07 acceptance text) cannot run before `FlightController` (AI-05) and the Dart brain exist; they are tracked there.
- The structure bounding-sphere probe of 05 s5.4 and the 1.0 s re-sample at act (PULL_UP) are `sim_ai` callers of `TerrainProbe`.
