# sim/steer - MODULE.md

Contract for `godot/src/sim/steer/**`: 05's pure steering controllers (05 s1.3, s5; R0 C2-04, B.9 A-21 split of `sim/MODULE.md`).
A change to "Public API" or "Invariants" is a contract change: contract tests first, same PR (ADR-11); `tools/gen_module_api.py
--check` must pass; <= 300 lines (ADR-14). `net` prediction substitutes `Assist` for the possessed unit, so every change here is
reviewed for both the `sim_ai` and the `net` lane.

| Field | Value |
|---|---|
| Responsibility | Pure functions of their arguments that turn state into controls or probes: `FlightController` (05 s5.2, guidance target -> `PilotInput`) with its `FlightGains`, `TerrainProbe` (05 s5.3, time to impact, worst clearance, lift), `LandingController` (05 s5.5, tail-down L1-L6, aborts, go-around, bearing) and `Assist` (R0 B.5 step 4 substitution: `link_bridge`, AI-08; driven by `AssistStep`) with its `BridgeParams`. `Assist.auto_dock` (AI-10): the possessed ship's DOCK-held landing law. |
| Lane owner tier | Opus reviews (05 lane writes it; Sonnet may implement against this file) |
| May depend on | `core`, `content`, `sim` (`Terrain`, `Kinematics`, `PilotInput`) |
| Must never touch | Nodes, `net`, `presentation`, `ui`, `sim_ai`; no `await`, signals, `Thread`, RNG, autoloads, member state (S8) |
| Autoloads used | None |
| Status | `TerrainProbe` (AI-07), `FlightController` + `FlightGains` (AI-05), `LandingController` + structs (AI-09, 2026-10-14); `AimSolver` + `Ballistics` (AI-12, 2026-10-14); `Assist.link_bridge` + `BridgeParams` + `AssistStep` (AI-08, 2026-10-14); `Assist.auto_dock` (AI-10) |

## Public API

```gdscript
class_name FlightGains extends RefCounted                                    # 05 s5.2 parameter struct per (autopilot profile, ship class), read-only
const KEYS: PackedStringArray                                                # required `flight` keys (below)
var dt: float; var pitch_rate: float; var yaw_rate: float; var roll_rate: float; var rate_accel: float   # tick, ShipDef caps (rad/s, rad/s^2)
var kp_path: float; var ki_path: float; var integ_max: float; var integ_band: float; var lead_max: float  # path loop (rad)
var kp_att: float; var kp_yaw: float; var kp_roll: float; var kp_bank: float; var bank_threshold: float; var bank_max: float
var t_trim: float; var kp_speed: float; var ki_speed: float; var kp_turn_thrust: float; var brake_overspeed: float
var ship: ShipDef; var rules: RulesDef; var common: FlightCommonDef; var stop_angle: float; var lead_best: PackedFloat32Array; var lead_du: float; var lead_de: float; var lift_best: PackedFloat32Array   # AI-38
const LEAD_TABLE_SIZE: int; const LEAD_ERR_SIZE: int; const LEAD_SEARCH_STEPS: int   # lead_best [speed][path error] resolution
static func from_dict(flight: Dictionary, def: ShipDef, tick_hz: int, rules_def: RulesDef, flight_common: FlightCommonDef) -> FlightGains   # null: key / def missing

class_name FlightController extends RefCounted                               # 05 s5.2, static only
static func track_velocity(b: Basis, v: Vector3, v_cmd: Vector3, up_local: Vector3, g: FlightGains, integ: Vector2, out: PilotInput) -> Vector2
static func track_thrust_vector(b: Basis, t_dir: Vector3, t_mag01: float, up_local: Vector3, g: FlightGains, out: PilotInput) -> void
static func shape_rate(e: float, kp: float, accel: float) -> float           # stop-in-time rate: sign(e) min(kp |e|, sqrt(2 accel |e|))
static func weight_support_throttle(b: Basis, v: Vector3, up_local: Vector3, g: FlightGains) -> float   # AI-38 throttle floor
static func lead_cap(u: float, err: float, e_s: float, g: FlightGains) -> float   # best_lead, opening to lead_max with overspeed
static func best_lead(u: float, err: float, g: FlightGains) -> float; static func lift_best(u: float, g: FlightGains) -> float   # table lookups
static func turn_accel(u: float, alpha: float, err: float, g: FlightGains) -> float   # thrust + lift along the chord to the command
static func pull_up(b: Basis, v: Vector3, up_local: Vector3, g: FlightGains, out: PilotInput) -> void   # best-climb PULL_UP; axes + thrust
static func pull_up_loss(b: Basis, v: Vector3, up_local: Vector3, g: FlightGains) -> float   # height lost before PULL_UP arrests the sink
static func pull_up_plane(b: Basis, v: Vector3, up_local: Vector3) -> Vector3   # unit horizontal of the pull-up plane
static func pull_up_elevation(v: Vector3, h: Vector3, up_local: Vector3, th0: float, g: FlightGains) -> float   # Newton step to the best climb
static func climb_accel(v: Vector3, h: Vector3, up_local: Vector3, theta: float, g: FlightGains) -> float   # radial accel at elevation theta

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
static func drop_free_lift(r: ProbeResult, probe_params: ProbeParams, h_req: float, speed: float) -> float   # (AI-08) R0 B.12 A-69 lift from a filled result

class_name BridgeParams extends RefCounted                                   # AI-08: LINK_BRIDGE / SAFETY law parameters per ship class, read-only
const KEYS: PackedStringArray                                                # required top-level autopilot keys (+ the `flight` block)
var gains: FlightGains; var probe: ProbeParams; var pull_up_tti_s: float     # safety_pull_up_tti_s (05 s2.4: 2.0 s)
var ship: ShipDef; var rules: RulesDef                                       # base class def + world rules: the trim feed-forward's lift law
static func from_autopilot(ap: Dictionary, def: ShipDef, rules_def: RulesDef, tick_hz: int, flight_common: FlightCommonDef) -> BridgeParams
static func table(content: ContentSet, rules_def: RulesDef, tick_hz: int) -> Array[BridgeParams]   # by local ship index; null: no autopilot def
static func autopilot_raw(content: ContentSet, id: StringName) -> Dictionary # AutopilotDef.raw of `id`, {} when absent

class_name Assist extends RefCounted                                         # R0 B.5 step 4 substitution, static only; SimWorld and net Prediction
static func link_bridge(b: Basis, p: Vector3, v: Vector3, terrain: Terrain, bp: BridgeParams, probe: ProbeResult, out: PilotInput) -> void
static func auto_dock(st: LandingState, ship: ShipSnapshot, pad: PadSnapshot, prm: LandingParams, g: FlightGains, radius_m: float, latch_mult: float, inp: PilotInput) -> bool   # true = assist overwrote inp
static func link_bridge_ground(out: PilotInput) -> void                      # ground unit: stop (thrust 0, no BRAKE: no reverse)
static func pull_up(b: Basis, v: Vector3, up_local: Vector3, g: FlightGains, out: PilotInput) -> void   # buttons 0 + FlightController.pull_up (AI-38)
static func hold_velocity(b: Basis, v: Vector3, lift_mps: float, up_local: Vector3, g: FlightGains, lead: float, out: PilotInput) -> void   # v_cmd = v + up * lift, pitch integrator = lead
static func trim_lead(v: Vector3, up_local: Vector3, bp: BridgeParams) -> float   # steady nose lead: sin = g_perp / (u k_up_effective), <= integ_max

class_name AssistStep extends RefCounted                                     # SimWorld step 4 driver, static only (A-73: SimWorld composes)
static func run(store: EntityStore, players: PlayerTable, inputs: InputSlots, terrain: Terrain, bridge: Array[BridgeParams], probe: ProbeResult, scratch: PilotInput) -> void

class_name AimSolver extends RefCounted                                      # AI-12, 05 s6.2/s6.8, R0 C1-03: straight-line intercept, static only
static func intercept_time(r: Vector3, u: Vector3, speed: float) -> float    # |r + u t| = speed t, r = p_t - p_s, u = v_t - v_s; INF if none
static func lead_point(p_s: Vector3, v_s: Vector3, p_t: Vector3, v_t: Vector3, speed: float) -> Vector3
static func aim_dir(p_s: Vector3, v_s: Vector3, p_t: Vector3, v_t: Vector3, speed: float) -> Vector3   # ZERO if none
static func fuse_time(r: Vector3, u: Vector3, speed: float, delay_s: float, arm_s: float, lifetime_s: float) -> float   # flak timed fuse
static func in_fire_cone(nose: Vector3, aim: Vector3, cone_k: float, target_radius: float, dist: float) -> bool

class_name Ballistics extends RefCounted                                     # AI-12, 05 s6.3.1: bombs and siege shells only, static only
static func predict_impact(p: Vector3, v: Vector3, def: ProjectileDef, rules: RulesDef, terrain: Terrain, dt: float, dt_far: float, near_m: float, max_steps: int, st: ProjectileState) -> Vector4   # st = caller scratch; xyz, w = flight time; NO_IMPACT
static func flat_impact(p: Vector3, v: Vector3, def: ProjectileDef, rules: RulesDef, ground_alt_m: float) -> Vector4   # closed form, local flat
static func shift_impact(cached: Vector4, p0: Vector3, v0: Vector3, p: Vector3, v: Vector3, def: ProjectileDef, rules: RulesDef, ground_alt_m: float) -> Vector4
static func has_impact(r: Vector4) -> bool
```

```gdscript
class_name LandingController extends RefCounted                              # 05 s5.5 (AI-09), static only
enum Phase { TRANSIT, APPROACH, HOLD, GO_AROUND, TRANSITION, HOVER, FLARE, DONE }   # L1 L2 L2b L3 L4 L5 L6; append-only
enum Abort { NONE, HORIZ_ERR, SINK, PAD_INVALID, PAD_BUSY, PAD_THREAT, TTI, GLIDE } # append-only (AiState bytes)
static func step(st: LandingState, ship: ShipSnapshot, pad: PadSnapshot, prm: LandingParams, g: FlightGains, out: PilotInput) -> int   # one tick
static func step_assist(st: LandingState, ship: ShipSnapshot, pad: PadSnapshot, prm: LandingParams, g: FlightGains, out: PilotInput) -> int   # L4-L6 only: no abort rules, no L1-L3 (Assist.auto_dock)
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
var assist_off: bool; var assist_near: bool                                  # AI-10: auto-dock gave up (until DOCK released); acted within auto_dock_radius_m = AUTO landing
func release() -> void                                                       # DOCK released: L1, assist re-armed, assist_near kept
func reset() -> void                                                         # L1, no bearing, no attempts, no abort
class_name ShipSnapshot extends RefCounted                                   # reused input scratch
var b: Basis; var p: Vector3; var v: Vector3; var a_thrust: float; var eff_fade_start: float; var bounding_radius: float
var v_cruise: float; var ground_h: float; var lift_mps: float; var tti_s: float
class_name PadSnapshot extends RefCounted                                    # reused input scratch
var p: Vector3; var n: Vector3; var radius_m: float; var valid: bool; var busy: bool; var threat: bool
```
**Assist (AI-08).** `link_bridge` is LINK_BRIDGE (05 C10 hand-over until the new pilot's first input, C13 from the 11th
silent tick, A-44 / A-45; R0 C2-08): one `TerrainProbe.probe` pass with h_req = `required_clearance(|v|)` into the caller's
`probe` scratch, then `pull_up` when TTI < `pull_up_tti_s`, else `hold_velocity(v, drop_free_lift, trim_lead)`. Stateless
(no hysteresis): the probe runs every tick. **Contract impact:** 05 s2.4 says "hold velocity"; a stateless hold with zero
integrators carries no angle-of-attack trim and sags under gravity (a 15 s cradle stall hit terrain in 7-14 % of starts
per class, still 1 % with the A-69 lift alone), so the hold gets the 05 s5.3 / A-69 lift (v_cmd.radial = v_r + lift) and
the steady nose lead fed forward from the lift law (`trim_lead`, no new def key): 0 contacts (`test_long_bridge_*`).
`TerrainProbe.drop_free_lift` (append) is A-69 for every lift caller; the worst sample is the ballistic one (`probe`
unchanged). `SimWorld` step 4 calls `AssistStep.run` (one line, A-73): every possessed entity under LINK_BRIDGE, ships
with a `BridgeParams` entry (not DOCKED / LANDED) fly `link_bridge`, ground units get `link_bridge_ground`, structures keep
the decayed input. PULL_UP is the AI-38 best-climb law (05's nose-to-up killed the speed_scaled lift). `BridgeParams` comes from the
class's autopilot def; **needs content (AI-19):** `autopilots.json` with the `flight`, probe and `safety_*` keys (fixture
`test/sim/ai/ai08_autopilots.json`); until then every table entry is null and step 4 leaves the decayed input in place.

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
and the `FlightGains`; `choose_bearing` takes the `Terrain` and a per-candidate threat penalty array. The `landing` block
keys are `LandingParams.KEYS` (anchors in the fixture `test/sim/ai/ai09_params.json`; AI-19 writes them).

**AI-38 (05 s5.2 / s5.3 amended; A-68: one law, the lift model read from `Kinematics`, no def key).** `track_velocity`:
throttle >= `weight_support_throttle` (the gravity the best wing lift at that speed cannot carry; faded out over
`integ_band` below the path; the throttle integrator holds while it flies); nose lead <= `lead_cap` (`best_lead`, ~40
degrees for a cruising Dart under speed_scaled, opening to `lead_max` with overspeed: braking needs the bigger lead).
`pull_up` (via `Assist.pull_up`): nose to the best-climb elevation of the lift law, wings level, thrust above the horizon
only. `pull_up_loss` is the pull-up budget callers compare with their clearance (AI-06 rig; brains AI-13). Evidence:
`godot/test/tuning/README.md`.

## Invariants

- AS1: `Assist` is static and reads only its arguments (S8): no member or static `var`, RNG, clock, Node or autoload; the
  only writes are `out` and the `probe` scratch, so `net` Prediction reproduces the server's step 4 bit for bit
  (`test_source_has_no_state`, `test_pure_and_deterministic`, `test_sc25_input_starvation_bridge`).
- AS2: `link_bridge` clears every button (FIRE, FLIP, DOCK, RELEASE, BOOST; BRAKE only as `track_velocity` sets it); a
  pull-up writes thrust 1 with the nose above the horizon, 0 below it (AI-38; `test_pulls_up_below_the_threshold`).
- AS3: On cradle, every ship class under the bridge alone has no terrain contact for 2 s (the 10-tick A-45 window and on)
  from 100 random starts at 150-600 m AGL, 0-30 degree dives, v_cruise, and for 15 s from 0-10 degree descents
  (`test_bridge_window_no_terrain_contact_on_cradle`, `test_long_bridge_no_terrain_contact_on_cradle`).
- FC1: `FlightController` is static and reads only its arguments: no member or static `var`, no RNG, clock, Node or autoload
  (S8, 03 s5.6). Identical arguments give identical outputs; 3,000 closed-loop ticks of two ships replay bit-identically
  (`test_pure_and_deterministic`, `test_source_has_no_state`).
- FC2: outputs stay in the `PilotInput` ranges and are scaled by the ship's own rate caps, so an autopilot has exactly a
  human's agility (P1); only the axes and the BRAKE bit are written (`test_only_axes_and_brake_bit_are_written`).
- FC3: (05 s5.2 acceptance) from trimmed flight at v_cruise a 30 degree heading or 15 degree climb / dive step converges within
  5 degrees in <= 2.0 s with < 15 % overshoot for all five ship classes under `speed_scaled`; under `damping_only` turns and
  climbs do, 15 degree dives take <= 2.6 s with < 20 % overshoot (thrust-limited; `test_step_response_*`,
  `test_damping_only_dive_is_thrust_limited`); any attitude recovers to the command within 15 s.
- FC5 (AI-38): floor = lift law, never undercut on a level command; `best_lead` / PULL_UP within 2 / 3 degrees of brute force;
  `pull_up_loss` bounds the height lost (`test_flight_controller_lift.gd`).
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
- AS1: `AimSolver` solves the straight-line equation exactly (05 wrote two fixed-point iterations; the closed form is their limit); the shooter velocity is carried, no gravity term. Slugs stepped by `Kinematics.step_projectile` hit co-altitude targets at 200/400/650/800 m and random moving shooter/target pairs within 5 cm (`test_aim_solver.gd`); the converged time agrees with `ui/hud/lead_solver.gd` within 1 %. Cross-lane: the HUD pip is mirrored, not shared (ui is not allowed to reference `sim/steer`); the Architect may point `LeadSolver` at `AimSolver` later.
- BA1: `predict_impact` uses the sim's own `Kinematics.step_projectile` and the Collision ground test (altitude < height + radius), allocates nothing (the caller passes the `ProjectileState` scratch) and takes `dt` (fine) and `dt_far` (used while clearance > `near_m`; a coarse step that would cross the ground is retried fine). Fine only (`dt_far` = `dt` = 2 sim ticks): within 2 m of the stepped sim for drops of 50-800 m (accepted 3 m), measured 88-109 us for a 300 m fall (the ~60-step cost 05 s6.3.1 assumed). Far mode (`dt_far` 0.133 s, `near_m` 150): 5.2 m worst error at 800 m / 250 m/s, 105-128 us for an 11 s fall, for run-in planning; R3 RELEASE uses fine. 05 s6.3.1's 0.1 s x 60 steps gives 3.9 m at 800 m and cannot reach an 11 s fall; a velocity offset that cancels the coarse bias for flat gravity was tried and fails once transport matters. `shift_impact` keeps the cached impact current within 5 m over a 10-tick gap; the plain closed form alone is hundreds of metres off over a long fall (6 km moon curvature). Terrain cost: one `Terrain.height_at` per step (a bomb is nearly always inside the relief band, so the sim's prefilter would not pay).

## Performance budget

AI-08 (`test_overlays_perf.gd`, best of 6, owner's desktop): `Assist.link_bridge` 6.9-7.9 us/call (6 height samples +
`track_velocity`); step 4 runs it at most once per player slot (<= 8 per tick, <= 65 us), outside the AI hook's budget row.

05 s10 "act" row: one `track_velocity` or `track_thrust_vector` per AI ship per tick, no allocation (Vector3 / float locals,
writes into the caller's `PilotInput`); budget 6 us per ship. Measured by `test_perf_cost_per_call` (best of 6 batches, owner's
desktop, 4.7.2, shared with other jobs): track_velocity 5.7-7.8 us/call, track_thrust_vector 2.0-2.5 us/call. AI-38: floor +
lead cap 1.2 us (track_velocity 6.9 us); `pull_up` 7.5 us, `pull_up_loss` 7.2 us (pull-ups only); lead table built once per class. At the top of
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
`godot/test/sim/ai/test_sc_terrain_flight.gd` (SC-09, SC-10 on cradle); `godot/test/unit/sim/steer/test_aim_solver.gd`, `test_ballistics.gd`, `test_terrain_probe.gd`
(closed forms on flat and sloped synthetic terrain, ridge, cradle crater rims against an independent Quaternion path, lift,
cost, purity); `godot/test/unit/sim/steer/test_landing_controller.gd` (transitions, aborts, bearing, L4-L6 law, purity,
perf); `godot/test/sim/ai/test_landing_dock_sets.gd` (L4-L6 from the TA-30 dock sets, every class, both lift models);
`godot/test/sim/ai/test_sc_landing.gd` (SC-02..SC-08 through `LandingPilot` on `LandingWorld`);
`godot/test/unit/sim/steer/test_assist.gd` (AS1-AS3, BridgeParams parse); `godot/test/sim/ai/test_sc_overlays.gd` (SC-22, SC-25
through `SimWorld` step 4).

## How to add X (recipes for the cheapest tier)

- **A probe time:** edit `probe_times_s` in the autopilots def; nothing here changes.
- **A new controller:** `static func` only, take a state struct and an output `PilotInput`; add a purity test like `test_source_has_no_state`.
## Open items

- `ProbeParams.lift_max_frac` / `lift_min_time_s` are in `autopilots.schema.json` (optional); AI-19 writes them (0.6, 0.5) into every `ap_*` (R0 B.12 A-67).
- Landing under `damping_only`: L1-L6 docks 200/200 with the AI-06 recommended set (AI-19 adopts it); at the AI-05 anchors it still crashes (lead_max 80).
- The structure bounding-sphere probe of 05 s5.4 and the 1.0 s re-sample at act (PULL_UP) are `sim_ai` callers of `TerrainProbe`.
- A-69 (05 s5.3 erratum): lift callers use the drop-free clearance `c_k + 0.5 g t_k^2` and add the lift to the current radial speed; TTI / PULL_UP keep the ballistic probe. `probe()` is unchanged; AI-13 owns the brain side. `LandingPilot` (AI-09) already does both.
- A-70 (05 s5.5 erratum): implemented by AI-09 (`LandingController.thrust_vector`, floor = `landing.hover_agl_m`; LC2); `Assist.auto_dock()` (AI-10) inherits it.

**Assist.auto_dock (AI-10).** `inp` is the possessed ship's input (human, or the net-predicted copy). The caller keeps one `LandingState`
per possessed ship and at possession **passes the autopilot's own state** (copied from AiState: phase, attempts, bearing, integ) when
the ship was landing: a ship possessed in L5/L6 continues in that phase (05:237, SC-16); with no landing in progress (any phase before
L4, or a fresh state) the assist cold-starts in L4 TRANSITION. With DOCK held, a valid free pad, the ship above the pad plane and its
horizontal distance in the pad frame <= `radius_m` (`flight_common.auto_dock_radius_m`, A-33) it overwrites thrust / pitch / yaw / roll
/ BRAKE via `LandingController.step_assist` (BOOST and FLIP cleared, other buttons kept); once in L4-L6 it holds out to
`radius_m * latch_mult` (A-34, x5); L4 is limited to `transition_max_tilt_deg` (75 degrees) while braking. DOCK released or out of
the latch: `st.release()`. The pad lost or taken sets `st.assist_off` until DOCK is released. No abort for horizontal error, sink or
TTI (a human has no go-around). `LandingState.assist_near` is set by every acting tick within `radius_m` of the pad and survives
`release()`: the sim reads it at the LANDING event (set = grade AUTO, unset = manual) and then calls `reset()`. Fill the snapshots with
`tti_s` INF and `pad.threat` false. Wiring into `AssistStep`, `LANDING_ASSIST` and the grade itself wait for GD-15 and NET-18.
