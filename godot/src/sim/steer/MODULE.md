# sim/steer - MODULE.md

Contract for `godot/src/sim/steer/**`: 05's pure steering controllers (05 s1.3, s5; R0 C2-04, B.9 A-21 split of `sim/MODULE.md`).
A change to "Public API" or "Invariants" is a contract change: contract tests first, same PR (ADR-11); `tools/gen_module_api.py
--check` must pass; <= 300 lines (ADR-14). `net` prediction substitutes `Assist` for the possessed unit, so every change here is
reviewed for both the `sim_ai` and the `net` lane.

| Field | Value |
|---|---|
| Responsibility | Pure functions of their arguments that turn state into controls or probes: `FlightController` (05 s5.2, guidance target -> `PilotInput`) with its `FlightGains`, and `TerrainProbe` (05 s5.3, time to impact, worst clearance, lift). `LandingController` and `Assist` land here with AI-09 and AI-08 / AI-10. |
| Lane owner tier | Opus reviews (05 lane writes it; Sonnet may implement against this file) |
| May depend on | `core`, `content`, `sim` (`Terrain`, `Kinematics`, `PilotInput`) |
| Must never touch | Nodes, `net`, `presentation`, `ui`, `sim_ai`; no `await`, signals, `Thread`, RNG, autoloads, member state (S8) |
| Autoloads used | None |
| Status | `TerrainProbe` (AI-07, 2026-10-14), `FlightController` + `FlightGains` (AI-05, 2026-10-14); landing and assist planned |

## Public API

```gdscript
class_name FlightGains extends RefCounted                                    # 05 s5.2 parameter struct per (autopilot profile, ship class), read-only
const KEYS: PackedStringArray                                                # required `flight` keys (below)
var dt: float; var pitch_rate: float; var yaw_rate: float; var roll_rate: float; var rate_accel: float   # tick, ShipDef caps (rad/s, rad/s^2)
var kp_path: float; var ki_path: float; var integ_max: float; var integ_band: float; var lead_max: float  # path loop (rad)
var kp_att: float; var kp_yaw: float; var kp_roll: float; var kp_bank: float; var bank_threshold: float; var bank_max: float
var t_trim: float; var kp_speed: float; var ki_speed: float; var kp_turn_thrust: float; var brake_overspeed: float
static func from_dict(flight: Dictionary, def: ShipDef, tick_hz: int) -> FlightGains   # null if a KEYS entry is missing / not a number

class_name FlightController extends RefCounted                               # 05 s5.2, static only
static func track_velocity(b: Basis, v: Vector3, v_cmd: Vector3, up_local: Vector3, g: FlightGains, integ: Vector2, out: PilotInput) -> Vector2
static func track_thrust_vector(b: Basis, t_dir: Vector3, t_mag01: float, up_local: Vector3, g: FlightGains, out: PilotInput) -> void
static func shape_rate(e: float, kp: float, accel: float) -> float           # stop-in-time rate: sign(e) min(kp |e|, sqrt(2 accel |e|))

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

**FlightController.** `b` is the basis as `SimView.basis(id)` returns it (x right, y up, z = -forward), `v` the world velocity,
`up_local` the unit radial; no body rates are needed (SimView has none). `track_velocity` points the nose at the velocity
direction rotated toward `v_cmd` by `kp_path` x the path error, plus the pitch integrator (a nose lead along the local vertical
that carries the steady angle of attack; input clamped to `integ_band`, frozen while the lead is at `lead_max`); it banks by
`kp_bank` x (heading error - `bank_threshold`) up to `bank_max` and sets the throttle so the speed loop acts along the path:
`(t_trim + kp_speed e + I) / max(cos AoA, 0.5) + kp_turn_thrust x path error`. `integ` = (pitch, throttle) integrators: the
caller stores the returned value per entity and resets it to zero on a mode change. `track_thrust_vector` points the thrust
axis at `t_dir` (roll rate to zero) with throttle `t_mag01 x max(fwd . t_dir, 0)`. Writes: thrust, pitch, yaw, roll and the
BRAKE bit (set on overspeed by `track_velocity`, cleared by `track_thrust_vector`); FIRE, BOOST, FLIP, DOCK bits are the caller's.

**Contract impact (AI-05):** the 05 s4.4 `flight` block gains `integ_max_rad`, `integ_band_deg`, `lead_max_deg`, `kp_att`,
`kp_bank`, `bank_max_deg`, `t_trim`, `kp_turn_thrust` (05 had `t_trim` 0.5 and the +-0.5 clamp in prose); `kp_path` is the nose
lead per radian of path error and `kp_yaw` the yaw pointing gain; `k_guidance` is not read here. Tuned values (fixture
`test/sim/ai/ai05_params.json`): kp_path 4, ki_path 0.3, integ_max_rad 0.8, integ_band_deg 6, lead_max_deg 80, kp_att 6,
kp_yaw 6, kp_roll 3, kp_bank 1, bank_threshold_deg 10, bank_max_deg 60, t_trim 0.5, kp_speed 0.05, ki_speed 0.005,
kp_turn_thrust 2, brake_overspeed_mps 20. **Needs content:** these keys in `autopilots.schema.json` and every `ap_*` (AI-19).

**TerrainProbe.** `p` is the sim position (planet centre origin), `v` the world velocity. The path is constant velocity in the tangent frame carried
along the great circle (ground speed `s`, angle `s t / |p|`), radius `|p| + v.n0 t - 0.5 g t^2`. The doc's signatures gain the
`terrain` argument because `Terrain` is an instance (03 s6.2), not a static sampler.

**Contract impact:** combined `probe()` call (05 s5.3 had three functions `time_to_impact` / `min_clearance` / `terrain_lift`, which would
cost 13-18 samples per think against the 6 budgeted); brains call `probe()` once per think. TTI is 05's linear refinement between
the first sample at or below 0 and the previous one; there is no t = 0 sample and no bisection.

## Invariants

- FC1: `FlightController` is static and reads only its arguments: no member or static `var`, no RNG, clock, Node or autoload
  (S8, 03 s5.6). Identical arguments give identical outputs; 3,000 closed-loop ticks of two ships replay bit-identically
  (`test_pure_and_deterministic`, `test_source_has_no_state`).
- FC2: outputs stay in the `PilotInput` ranges and are scaled by the ship's own rate caps, so an autopilot has exactly a
  human's agility (P1); only the axes and the BRAKE bit are written (`test_only_axes_and_brake_bit_are_written`).
- FC3: (05 s5.2 acceptance) from trimmed flight at v_cruise a 30 degree heading or 15 degree climb / dive step converges within
  5 degrees in <= 2.0 s with < 15 % overshoot for all five ship classes under `speed_scaled`; under `damping_only` turns and
  climbs do, 15 degree dives take <= 2.6 s with < 20 % overshoot (thrust-limited; `test_step_response_*`,
  `test_damping_only_dive_is_thrust_limited`); any attitude recovers to the command within 15 s.
- FC4: `track_thrust_vector` holds a tail-down hover for every class, Bomber (a_thrust 14) included; the TA-30 L4-L6 law
  flown through it lands 200/200 Dart and 200/200 Bomber from the spike's dock and fast-dock sets inside R0 B.5
  (`test_auto_dock_landing.gd`).
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

05 s10 "act" row: one `track_velocity` or `track_thrust_vector` per AI ship per tick, no allocation (Vector3 / float locals,
writes into the caller's `PilotInput`); budget 6 us per ship. Measured by `test_perf_cost_per_call` (best of 6 batches, owner's
desktop, 4.7.2, shared with other jobs): track_velocity 5.7-7.8 us/call, track_thrust_vector 2.0-2.5 us/call. At the top of
that range the act row is over budget; the 05 s10 governor's rung 2 (act at 15 Hz for far ships) halves it. A Dart think in
`test_perf_think_and_act` (probe + test guidance) costs about 51 us against the 25 us row: the guidance, not this module.

05 s5.3 / s10 "terrain probe" row: **6 height samples per think** (`probe`, hit or clear, no extra samples; `test_probe_costs_exactly_the_probe_times`)
and 1 per `sample_clearance` at act (every 3rd tick), about 375 samples per tick at 400 AI ships. No allocation: the only write is to
the caller's `ProbeResult`.

## Test entry points

`godot/test/unit/sim/steer/test_flight_controller.gd` (step response under both lift models, any-attitude recovery, hover,
interface, purity, perf); `godot/test/sim/ai/test_auto_dock_landing.gd` (TA-30 spike landing numbers);
`godot/test/sim/ai/test_sc_terrain_flight.gd` (SC-09, SC-10 on cradle); `godot/test/unit/sim/steer/test_terrain_probe.gd`
(closed forms on flat and sloped synthetic terrain, ridge, cradle crater rims against an independent Quaternion path, lift,
cost, purity).

## How to add X (recipes for the cheapest tier)

- **A probe time:** edit `probe_times_s` in the autopilots def; nothing here changes.
- **A new controller:** `static func` only, take a state struct and an output `PilotInput`; add a purity test like `test_source_has_no_state`.

## Open items

- `ProbeParams.lift_max_frac` / `lift_min_time_s` are in `autopilots.schema.json` (optional); **needs content:** the `autopilots` def file does not exist yet and must carry them (0.6, 0.5).
- The structure bounding-sphere probe of 05 s5.4 and the 1.0 s re-sample at act (PULL_UP) are `sim_ai` callers of `TerrainProbe`.
