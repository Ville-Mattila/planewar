# sim/steer - MODULE.md

Contract for `godot/src/sim/steer/**`: 05's pure steering controllers (05 s1.3, s5; R0 C2-04, B.9 A-21 split of `sim/MODULE.md`).
A change to "Public API" or "Invariants" is a contract change: contract tests first, same PR (ADR-11); `tools/gen_module_api.py
--check` must pass; <= 300 lines (ADR-14). `net` prediction substitutes `Assist` for the possessed unit, so every change here is
reviewed for both the `sim_ai` and the `net` lane.

| Field | Value |
|---|---|
| Responsibility | Pure functions of their arguments that turn state into controls or probes: `FlightController` (05 s5.2, guidance target -> `PilotInput`) with its `FlightGains`, `TerrainProbe` (05 s5.3, time to impact, worst clearance, lift) and `LandingController` (05 s5.5, tail-down L1-L6, aborts, go-around, bearing). `Assist` lands here with AI-08 / AI-10. |
| Lane owner tier | Opus reviews (05 lane writes it; Sonnet may implement against this file) |
| May depend on | `core`, `content`, `sim` (`Terrain`, `Kinematics`, `PilotInput`) |
| Must never touch | Nodes, `net`, `presentation`, `ui`, `sim_ai`; no `await`, signals, `Thread`, RNG, autoloads, member state (S8) |
| Autoloads used | None |
| Status | `TerrainProbe` (AI-07), `FlightController` + `FlightGains` (AI-05), `LandingController` + structs (AI-09, 2026-10-14); assist planned |

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

```gdscript
class_name LandingController extends RefCounted                              # 05 s5.5 (AI-09), static only
enum Phase { TRANSIT, APPROACH, HOLD, GO_AROUND, TRANSITION, HOVER, FLARE, DONE }   # L1 L2 L2b L3 L4 L5 L6; append-only
enum Abort { NONE, HORIZ_ERR, SINK, PAD_INVALID, PAD_BUSY, PAD_THREAT, TTI, GLIDE } # append-only (AiState bytes)
static func step(st: LandingState, ship: ShipSnapshot, pad: PadSnapshot, prm: LandingParams, g: FlightGains, out: PilotInput) -> int   # one tick
static func should_abort(st: LandingState, ship: ShipSnapshot, pad: PadSnapshot, prm: LandingParams) -> int   # Abort
static func go_around(st: LandingState, ship: ShipSnapshot, pad: PadSnapshot, reason: int) -> void
static func guidance(st: LandingState, ship: ShipSnapshot, pad: PadSnapshot, prm: LandingParams) -> Vector3   # L1-L3 v_cmd
static func thrust_law(phase: int, ship: ShipSnapshot, pad: PadSnapshot, prm: LandingParams, g: FlightGains, out: PilotInput) -> void   # L4-L6; Assist.auto_dock
static func thrust_vector(phase: int, ship: ShipSnapshot, pad: PadSnapshot, prm: LandingParams) -> Vector3   # the position law's T (m/s^2)
static func choose_bearing(terrain: Terrain, pad: PadSnapshot, ship: ShipSnapshot, threat: PackedFloat32Array, prm: LandingParams) -> Vector3

class_name LandingParams extends RefCounted                                  # 05 s5.5 parameter struct per autopilot profile, read-only
const KEYS: PackedStringArray                                                # required `landing` keys (below)
static func from_dict(landing: Dictionary, gravity_mps2: float) -> LandingParams   # null if a KEYS entry is missing / not a number
var gravity: float; var cruise_alt_agl_m: float; var gate_dist_m: float; var tan_glide: float; var glide_tol_m: float
var transition_dist_m: float; var approach_min_speed: float; var approach_lookahead_m: float; var tan_capture: float
var kp_alt: float; var vz_max: float; var turn_cmd_max: float; var hold_radius_m: float; var hold_agl_m: float; var hold_speed: float
var goaround_agl_m: float; var goaround_extend_m: float; var max_attempts: int; var kp_pos: float; var kd_pos: float; var kp_vz: float
var tan_tilt: float; var tan_transition_tilt: float; var cos_transition_nose: float; var transition_exit_hspeed: float
var transition_exit_dist_m: float; var transition_speed_cap: float; var hover_agl_m: float; var kp_floor: float; var tan_floor_tilt: float
var sink_gain: float; var sink_min: float; var sink_max: float; var flare_agl_m: float; var tan_flare_tilt: float; var touch_vz: float
var abort_horiz_err_m: float; var abort_horiz_agl_m: float; var abort_vz: float; var abort_vz_agl_m: float; var abort_tti_s: float
var bearing_count: int; var bearing_samples: int; var bearing_clear_m: float; var bearing_terrain_weight: float

class_name LandingState extends RefCounted                                   # per-landing memory; the caller keeps it per entity
var phase: int; var attempts: int; var abort_reason: int; var bearing: Vector3; var mark: Vector3; var ga_dir: Vector3; var integ: Vector2
func reset() -> void                                                         # L1, no bearing, no attempts, no abort
class_name ShipSnapshot extends RefCounted                                   # reused input scratch
var b: Basis; var p: Vector3; var v: Vector3; var a_thrust: float; var eff_fade_start: float; var bounding_radius: float
var v_cruise: float; var ground_h: float; var lift_mps: float; var tti_s: float
class_name PadSnapshot extends RefCounted                                    # reused input scratch
var p: Vector3; var n: Vector3; var radius_m: float; var valid: bool; var busy: bool; var threat: bool
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
kp_turn_thrust 2, brake_overspeed_mps 20. R0 B.12 A-67: the keys are in `autopilots.schema.json` (required inside a `flight` object) and 05 s4.4 / s5.2; AI-19 writes every `ap_*`. A-68: the `damping_only` dive figure in FC3 is the accepted acceptance for the A/B variant.

**TerrainProbe.** `p` is the sim position (planet centre origin), `v` the world velocity. The path is constant velocity in the tangent frame carried
along the great circle (ground speed `s`, angle `s t / |p|`), radius `|p| + v.n0 t - 0.5 g t^2`. The doc's signatures gain the
`terrain` argument because `Terrain` is an instance (03 s6.2), not a static sampler.

**Contract impact:** combined `probe()` call (05 s5.3 had three functions `time_to_impact` / `min_clearance` / `terrain_lift`, which would
cost 13-18 samples per think against the 6 budgeted); brains call `probe()` once per think. TTI is 05's linear refinement between
the first sample at or below 0 and the previous one; there is no t = 0 sample and no bisection.

**LandingController.** 05 s5.5's table, tail-down only (O-2). `step` runs every tick: abort rules, transitions, then the
output (L1-L3: `guidance` through `track_velocity`; L4-L6: `thrust_law`; DONE: zero axes and thrust). The caller owns pad
selection, the bearing (`choose_bearing` when TRANSIT is inside the gate with no bearing: TRANSIT -> APPROACH waits for it),
DONE (it sees DOCKED) and diverts (`abort_reason` PAD_INVALID, `attempts` > `max_attempts`). L2 flies to the gate fix until
established (approach side, within `approach_capture_deg` of the line, inbound), then pure pursuit on the glide slope with
05's speed schedule; L4 needs established + `|h - h(d)| <= glide_tol_m` at `transition_dist_m`, else a GLIDE go-around. L3
climbs to `goaround_agl_m` along the approach course, extends `goaround_extend_m`, counts an attempt, resets the bearing.
AI-09 additions to the 05 law: (1) the **height floor** (R0 B.12 A-70) in L4, and in L5 while outside the pad radius:
below `hover_agl_m` (pad plane or terrain) the vertical command climbs at `kp_floor` per m (never descends) and the tilt is
capped at `floor_tilt_deg`; (2) **vertical-first
allocation**: the horizontal demand gets at most `sqrt(a^2 - a_v^2)` of the thrust; (3) L4 -> L5 also needs the nose within
`transition_nose_deg` of the pad normal and the ship outside the L5 horizontal-abort envelope (offset + speed / kd_pos);
L5 sinks only as far as the ship is centred including its drift, and L5 -> L6 likewise. Velocity-phase commands turn at
most `turn_cmd_max_deg` off the track (bank-to-turn, no loops).

**Contract impact (AI-09):** 05's `step(phase, ship, pad, prm, out) -> Phase` takes the per-landing memory `LandingState`
(phase, attempts, bearing, go-around geometry, integrators) and the `FlightGains`; `choose_bearing` takes the `Terrain`
and a per-candidate threat penalty array (no `ThreatSampler` exists yet); `should_abort` takes `st`. **Needs content
(AI-19):** the `landing` block gains `cruise_alt_agl_m` (the profile's), `glide_tol_m` 25, `approach_min_speed_mps` 40,
`approach_lookahead_m` 400, `approach_capture_deg` 30, `kp_alt` 0.5, `vz_max_mps` 60, `turn_cmd_max_deg` 60,
`hold_radius_m` 400, `hold_agl_m` 150, `hold_speed_mps` 50, `goaround_agl_m` 200, `goaround_extend_m` 1500,
`transition_max_tilt_deg` 75 (A-34), `transition_nose_deg` 45, `transition_exit_hspeed_mps` 15, `transition_exit_dist_m` 30,
`transition_speed_cap_mps` 30, `kp_floor` 1, `floor_tilt_deg` 45, `sink_gain` 0.25, `sink_min_mps` 1.5,
`sink_max_mps` 6, `flare_tilt_deg` 10, `abort_horiz_agl_m` 15, `abort_vz_agl_m` 10, `abort_tti_s` 1, `bearing_count` 8,
`bearing_samples` 6, `bearing_clear_m` 60, `bearing_terrain_weight` 0.05 (fixture `test/sim/ai/ai09_params.json`).

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

- LC1: `LandingController` is static and reads only its arguments; it writes only `st` and `out` (`test_source_has_no_state`,
  `test_pure_and_deterministic`). FC2 holds for its output (it drives the stick through `FlightController`).
- LC2: every autopilot touchdown meets R0 B.5 with the thrust axis within 10 degrees of the pad normal (05 AI-09). From the
  TA-30 dock sets (normal and fast) every class lands 200/200 (Dart, Bomber) or 50/50 (Lancer, Scout, Hauler) with zero
  off-pad scrapes and zero aborts, under both lift models (`test_landing_dock_sets.gd`; the AI-05 spike law scraped in
  37/200 fast Dart runs). SC-02..SC-08 pass under `speed_scaled` (`test_sc_landing.gd`; SC-04 100/100, median 31 s).
- LC3: each 05 abort rule fires in exactly its phases (`test_abort_rules`, `test_tti_abort_only_when_the_impact_is_off_the_pad`);
  an abort always enters GO_AROUND; GO_AROUND and DONE never abort.
- LC4: L6 never commands the thrust axis past `flare_tilt_deg`; |T| never exceeds the thrust available along it; below
  `hover_agl_m` in L4 (and in L5 off the pad) the vertical command is a climb (`test_flare_*`, `test_vertical_first_*`,
  `test_floor_*`). A terrain contact in L4-L6 is a failed landing in every closed-loop test (A-70).

## Performance budget

05 s10 "act" row: one `track_velocity` or `track_thrust_vector` per AI ship per tick, no allocation (Vector3 / float locals,
writes into the caller's `PilotInput`); budget 6 us per ship. Measured by `test_perf_cost_per_call` (best of 6 batches, owner's
desktop, 4.7.2, shared with other jobs): track_velocity 5.7-7.8 us/call, track_thrust_vector 2.0-2.5 us/call. At the top of
that range the act row is over budget; the 05 s10 governor's rung 2 (act at 15 Hz for far ships) halves it. A Dart think in
`test_perf_think_and_act` (probe + test guidance) costs about 51 us against the 25 us row: the guidance, not this module.

05 s5.3 / s10 "terrain probe" row: **6 height samples per think** (`probe`, hit or clear, no extra samples; `test_probe_costs_exactly_the_probe_times`)
and 1 per `sample_clearance` at act (every 3rd tick), about 375 samples per tick at 400 AI ships. No allocation: the only write is to
the caller's `ProbeResult`.

`LandingController.step` per tick per landing ship (`test_perf_cost_per_call`, dev laptop, best of 6): 10.3 us in L1-L3
(guidance + `track_velocity`), 7.2 us in L4-L6, against the 6 us act row: a landing ship costs 1.2-1.7 rows (landing is
never degraded by the governor, 05 s10; RETURN ships are a small share of the 400). `choose_bearing` 32 us (8 x 6 height
samples), once per approach at think. No allocation (struct fields, Vector3 / float locals).

## Test entry points

`godot/test/unit/sim/steer/test_flight_controller.gd` (step response under both lift models, any-attitude recovery, hover,
interface, purity, perf); `godot/test/sim/ai/test_auto_dock_landing.gd` (TA-30 spike landing numbers);
`godot/test/sim/ai/test_sc_terrain_flight.gd` (SC-09, SC-10 on cradle); `godot/test/unit/sim/steer/test_terrain_probe.gd`
(closed forms on flat and sloped synthetic terrain, ridge, cradle crater rims against an independent Quaternion path, lift,
cost, purity); `godot/test/unit/sim/steer/test_landing_controller.gd` (transitions, aborts, bearing, L4-L6 law, purity,
perf); `godot/test/sim/ai/test_landing_dock_sets.gd` (L4-L6 from the TA-30 dock sets, every class, both lift models);
`godot/test/sim/ai/test_sc_landing.gd` (SC-02..SC-08 through `LandingPilot` on `LandingWorld`).

## How to add X (recipes for the cheapest tier)

- **A probe time:** edit `probe_times_s` in the autopilots def; nothing here changes.
- **A new controller:** `static func` only, take a state struct and an output `PilotInput`; add a purity test like `test_source_has_no_state`.

## Open items

- `ProbeParams.lift_max_frac` / `lift_min_time_s` are in `autopilots.schema.json` (optional); AI-19 writes them (0.6, 0.5) into every `ap_*` (R0 B.12 A-67).
- Landing under the `damping_only` A/B lift model: the L4-L6 law lands every dock set, but the full L1-L6 scenarios crash
  in L2 (thrustless descent while decelerating: `track_velocity` cuts thrust on overspeed, and under damping_only thrust
  is the lift). Reported, not asserted, like AI-05's SC-09 / SC-10 (A-68); a FlightController / gain item for AI-06.
- The structure bounding-sphere probe of 05 s5.4 and the 1.0 s re-sample at act (PULL_UP) are `sim_ai` callers of `TerrainProbe`.
- A-69 (05 s5.3 erratum): lift callers use the drop-free clearance `c_k + 0.5 g t_k^2` and add the lift to the current radial speed; TTI / PULL_UP keep the ballistic probe. `probe()` is unchanged; AI-13 owns the brain side. `LandingPilot` (AI-09) already does both.
- A-70 (05 s5.5 erratum): implemented by AI-09 (`LandingController.thrust_vector`, floor = `landing.hover_agl_m`; LC2); `Assist.auto_dock()` (AI-10) inherits it.
