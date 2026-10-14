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

class_name ProbeResult extends RefCounted                                    # preallocated by the brain, overwritten by probe()
var tti_s: float; var min_clearance_m: float; var worst_t_s: float           # INF when clear; worst (lowest) sample
var worst_dir: Vector3; var lift_mps: float                                  # unit direction of the worst sample; extra climb along local up

class_name TerrainProbe extends RefCounted                                   # 05 s5.3, static only
static func probe(terrain: Terrain, p: Vector3, v: Vector3, probe_params: ProbeParams, h_req: float, out: ProbeResult) -> void   # ONE pass, 6 samples
static func sample_clearance(terrain: Terrain, p: Vector3, v: Vector3, gravity: float, t: float) -> float   # 1 sample: the 1.0 s act-time re-check
```

`p` is the sim position (planet centre origin), `v` the world velocity. The path is constant velocity in the tangent frame carried
along the great circle (ground speed `s`, angle `s t / |p|`), radius `|p| + v.n0 t - 0.5 g t^2`. The doc's signatures gain the
`terrain` argument because `Terrain` is an instance (03 s6.2), not a static sampler.

**Contract impact:** combined `probe()` call (05 s5.3 had three functions `time_to_impact` / `min_clearance` / `terrain_lift`, which would
cost 13-18 samples per think against the 6 budgeted); brains call `probe()` once per think. TTI is 05's linear refinement between
the first sample at or below 0 and the previous one; there is no t = 0 sample and no bisection.

## Invariants

- ST1: Every function is `static` and reads only its arguments; no member `var`, no RNG, no clock, no allocation (Vector3 and float
  locals only). Identical inputs give identical outputs on every peer (S8, S9; `test_pure_and_deterministic`, `test_source_has_no_state`).
- ST2: `tti_s` is the first crossing found at sample resolution: INF when no probe sample is <= 0 (a dip narrower than the sample
  spacing is missed by design, 05 s5.3; `test_dip_between_samples_is_missed_by_design`), linear between the bracketing samples
  otherwise. Error vs the true first crossing: < 0.1 s on analytic flat, sloped and ridge cases (`test_flat_*`,
  `test_sloped_terrain_matches_quadratic`, `test_ridge_tti_against_dense_reference`); measured <= 0.5 s (one probe interval) when
  grazing the rough cradle crater rims at 300 m/s, 8 m AGL (`test_cradle_tti_matches_dense_reference_and_lift_clears`). Kept linear
  (zero extra samples); the Architect may revisit. A path already under the surface at sample 0 gives a value in [0, t_0].
- ST3: `lift_mps` is >= 0, 0 when the worst clearance is >= `h_req`, and <= `lift_max_frac * |v|`.
- ST4: A vertical or stationary ship stays over one point (no NaN from a zero ground speed).

## Performance budget

05 s5.3 / s10 "terrain probe" row: **6 height samples per think** (`probe`, hit or clear, no extra samples; `test_probe_costs_exactly_the_probe_times`)
and 1 per `sample_clearance` at act (every 3rd tick), about 375 samples per tick at 400 AI ships. No allocation: the only write is to
the caller's `ProbeResult`.

## Test entry points

`godot/test/unit/sim/steer/test_terrain_probe.gd` (closed forms on flat and sloped synthetic terrain, ridge, cradle crater rims
against an independent Quaternion path, lift, cost, purity). SC-09 / SC-10 move to AI-05's acceptance (they need FlightController).

## How to add X (recipes for the cheapest tier)

- **A probe time:** edit `probe_times_s` in the autopilots def; nothing here changes.
- **A new controller:** `static func` only, take a state struct and an output `PilotInput`; add a purity test like `test_source_has_no_state`.

## Open items

- `ProbeParams.lift_max_frac` / `lift_min_time_s` are in `autopilots.schema.json` (optional); **needs content:** the `autopilots` def file does not exist yet and must carry them (0.6, 0.5).
- The structure bounding-sphere probe of 05 s5.4 and the 1.0 s re-sample at act (PULL_UP) are `sim_ai` callers of `TerrainProbe`.
