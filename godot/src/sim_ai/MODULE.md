# sim_ai - MODULE.md

Contract for `godot/src/sim_ai/**` (05; AI-32). Allowed deps: `core`, `content`, `sim` (`tools/deps.json`). No Nodes, `await`,
signals, `Thread`, autoloads. Randomness only through `Rng.fork(&"ai")`. Reads the world only through `SimView` (vision rules),
writes only through `CommandSinkBase`.

| Field | Value |
|---|---|
| Responsibility | Autopilots, the Commander bot and the Adjutant, run inside the sim tick at R0 B.5 step 3 via `SimAiHook`. |
| Lane owner tier | Opus (Commander / brains); Sonnet for recipes against this file |
| May depend on | `core`, `content`, `sim` |
| Must never touch | Nodes, `net`, `presentation`, `ui`; no `await`, signals, `Thread`, autoloads |
| Autoloads used | None |
| Status | AI-03 (2026-10-14): `CommandSink`. AI-04 (2026-10-14): `AiState`, `AiBatch`, `AiBrain`, `AiDriver` scheduling. AI-09 (2026-10-14): `LandingPilot`, AiState landing fields. AI-12 (2026-10-14): target choice points (`TargetParams`, `TargetContext`, `TowerEnvelope`, `TargetChooser`). AI-08 (2026-10-14): `Overlays` SAFETY / RECOVER_CEILING, `OverlayParams`, the driver's release-edge check. AI-11 (2026-10-20): `Separation`, `Formation`, `FormationParams`, `EscortPilot`, AiState FORMAT 4 (`form_slot`, `form_state`, `form_order`, `sep_age`, `sep_push`). AI-13 (2026-10-21): `DartBrain` (+ `DartModes`, `DartCombat`, `AttackRun`, `DartParams`), `Guidance`, `TeamPicture`, AiState FORMAT 5, the A-89 budget OR in `Overlays.run_safety`. Other brains follow. |

## Public API

```gdscript
class_name CommandSink extends CommandSinkBase     # AI-03: the handle brains take; forwards to the sim's SimSink and counts
func bind(inner: CommandSinkBase) -> void;  func is_bound() -> bool;  func reset_counters() -> void   # AiDriver binds it each on_tick
func submit(cmd: Command) -> CommandResult         # via SimSink: validated, rate-limited, applied in step 1 of the next tick
func drive(id: int, input: PilotInput) -> bool     # false if POSSESSED or dead (S11), slot untouched
func end_overlay(id: int) -> void                  # TA-59: AiDriver calls it when an overlay ends; clears the replicated overlay byte
func set_ai_tag(id: int, tag: int) -> void         # replicated ai_tag u8 (05 s6.1); read back as SimView.ai_tag
func pathing() -> Pathing                          # inner's Pathing; null when unbound
var submits: int; var drives: int; var drives_refused: int; var tags: int   # counters for AiDriver.stats()
```

```gdscript
class_name AiState extends RefCounted              # AI-04: SoA by entity slot (05 s4.3) + scheduling arrays cls/eid/stagger/last_wake/wake_pending
func _init(slots: int = EntityStore.SLOT_COUNT) -> void;  func ensure_capacity(slots: int) -> void;  func clear_slot(s: int) -> void
func set_mode(id: int, m: int, tick: int) -> void;  func registered_count() -> int
func serialize() -> PackedByteArray;  func deserialize(bytes: PackedByteArray) -> bool   # only registered slots, ascending
# AI-09 (FORMAT 2): land_phase / land_attempts / land_abort / land_flags (u8), land_bearing / land_mark / land_ga_dir (Vector3),
# integ (Vector2), ground_h / lift (f32) per slot; pad_claim by pad slot, written after the records (non-zero, ascending)
const LAND_BUSY: int; const LAND_THREAT: int; const LAND_FOREIGN: int       # land_flags bits, refreshed at think
# AI-08 (FORMAT 3): overlay / ov_flags (u8) per slot after fire_mask; the overlays use `integ`
# AI-11 (FORMAT 4): form_slot / form_state / sep_age (u8) per slot after ov_flags, form_order (i32) after last_wake, sep_push (Vector3) after land_ga_dir; NO_SLOT = 255; form_slot k + ROSTER_WIDTH = overflow escort; sep_age = Separation.AGE_* flags
const NO_SLOT: int; const ROSTER_WIDTH: int      # form_roster (by escortee slot * ROSTER_WIDTH + class slot -> escort EntityId) is derived: rebuilt by deserialize, not in the bytes
const OV_PULL_UP: int; const OV_RTB_SENT: int; const OV_POSSESSED: int      # ov_flags bits
# AI-13 (FORMAT 5): sub / passes / prev_mode / wp / bflags (u8) after land_flags, seen_tick / mark_tick / burst_tick / order_tick (i32) after form_order, home / goal (Vector3) after sep_push, hp_mark / clear_m / aim_err (f32) after lift
var target_count: PackedByteArray                  # AI-13: by slot, registered slots whose target is it (derived: rebuilt by deserialize, not in the bytes)
var rtb_floor: PackedFloat32Array                  # AI-13 (FORMAT 5, after aim_err): the cached RTB fuel floor, 0 = unset
func set_target(s: int, t: int) -> void            # AI-13: the one writer of `target` (keeps target_count)
class_name AiBatch extends RefCounted              # ids of one class sorted by slot + `due` scratch
func add(id: int) -> bool;  func remove(id: int) -> bool
class_name AiBrain extends RefCounted              # per-class brain; base is a no-op
func think_batch(ids: PackedInt32Array, n: int, view: SimView, st: AiState, sink: CommandSink, tick: int) -> void
func act_batch(ids: PackedInt32Array, view: SimView, st: AiState, sink: CommandSink) -> void
func think_bot(slot: int, tier: int, tick: int, view: SimView, sink: CommandSink) -> void
func bind_rng(rng: Rng) -> void                    # AI-13: AiDriver binds its Rng.fork(&"ai") stream on set_brain and after deserialize
class_name LandingPilot extends RefCounted         # AI-09: RETURN landing of one ship class over LandingController (05 s5.5)
const RTB_KEYS: PackedStringArray;  const DOCKED: int
var def: ShipDef; var prm: LandingParams; var gains: FlightGains; var probe_params: ProbeParams; var terrain: Terrain
var pad_radius_by_def: PackedFloat32Array
func _init(ship_def: ShipDef, common: FlightCommonDef, rules: RulesDef, flight_gains: FlightGains, landing: LandingParams, probe: ProbeParams, rtb: Dictionary, t: Terrain, pad_radius: PackedFloat32Array) -> void
func needs_rtb(id: int, view: SimView) -> bool     # 05 s6 RTB rule: fuel floor with the distance term, hull
func fuel_floor(id: int, view: SimView) -> float;  func hp_floor() -> float   # AI-13: needs_rtb's two terms (a brain caches the floor)
func begin(id: int, pad: int, st: AiState) -> void # RETURN start or divert: L1 TRANSIT on `pad`
func phase(id: int, st: AiState) -> int
func think(id: int, view: SimView, st: AiState) -> void      # pad validity / divert, one probe, busy / threat flags, bearing, claim
func act(id: int, view: SimView, st: AiState, out: PilotInput) -> int   # LandingController.step into `out`; the brain drives it
func select_pad(id: int, view: SimView, exclude: int, st: AiState) -> int   # 05 s5.5 score, fuel rejection, nearest fallback
class_name AiClassTable extends RefCounted          # AI-37: def id -> class batch; ships then ground units in def order, NONE (255) for the rest
const NONE: int
static func from_content(c: ContentSet) -> PackedByteArray;  static func class_of(table: PackedByteArray, def_id: int) -> int
class_name AiDriver extends SimAiHook              # AI-04
func _init(rng: Rng = null, think_period_ticks: int = 10, cut_period_ticks: int = 15, bot_periods: PackedInt32Array = PackedInt32Array([90, 30, 30, 30])) -> void
func think_period() -> int;  func set_offline_profile(lite: bool) -> void;  func set_cut_rung1(on: bool) -> void;  func ai_rng() -> Rng
func set_brain(cls: int, brain: AiBrain, bot: bool = false) -> void;  func register(id: int, cls: int) -> bool;  func unregister(id: int) -> bool
func wake(id: int, tick: int) -> bool;  func on_event(ev: SimEvent) -> void          # SPAWN registers by def class (AI-37, A-71); HIT wakes; DEATH unregisters and wakes hunters
func set_class_table(table: PackedByteArray) -> void                         # AI-37: def id -> class byte (AiClassTable); empty: SPAWN registers nothing
func schedule_bot(slot: int, tier: int) -> void;  func unschedule_bot(slot: int) -> void;  func bot_due(slot: int, tier: int, tick: int) -> bool
func on_tick(tick: int, view: SimView, sink: CommandSinkBase) -> void;  func serialize() -> PackedByteArray;  func deserialize(bytes: PackedByteArray) -> void
func stats() -> Dictionary;  func reset_stats() -> void                     # stats: + "overlay_ticks" (AI-08)
func set_overlay_params(cls: int, p: OverlayParams) -> void;  func set_terrain(t: Terrain) -> void   # AI-08: per-class overlays; the map's Terrain (default flat datum)
```

```gdscript
class_name FormationParams extends RefCounted      # AI-11: separation + formation numbers (05 s5.4, s5.6) and the SL-2 wing slots, read-only
const SEP_KEYS: PackedStringArray;  const FORM_KEYS: PackedStringArray       # required keys of the `separation` / `formation` blocks
var sep_radius_m: float; var sep_gain: float; var sep_push_mps: float; var query_radius_m: float                 # 05 s5.4: 60, 1.0, 20; query <= Spatial.ring2_m (187.9 m)
var look_s: float; var look_miss_m: float; var look_lag_s: float; var look_eff: float; var look_min_s: float; var look_max_mps: float; var look_brake: float   # AI-11 look-ahead
var class_slots: PackedVector3Array; var wing_slots: PackedVector3Array      # (right, forward, up) m; class: tangent frame of the escortee, wing: leader body frame
var k_form: float; var speed_cap_mult: float; var engage_radius_m: float; var rejoin_radius_m: float; var break_utility: float; var max_break_frac: float; var min_heading_speed: float
var wing_tolerance_m: float; var focus_timeout_s: float; var focus_leash_m: float; var break_radius_m: float; var break_s: float; var ceiling_m: float   # wing.json + rules.ceiling_soft_m
static func from_dict(sep: Dictionary, form: Dictionary, wing: WingDef, ceiling_soft_m: float, engage_m: float, ring2_m: float = INF) -> FormationParams   # null on a missing key / bad slot table (1..ROSTER_WIDTH); query_radius_m clamped to Spatial.ring2_m; wing may be null
func slot_count(wing: bool) -> int
class_name Separation extends RefCounted           # AI-11: 05 s5.4 friendly separation, static only
static func push(id: int, p: Vector3, v: Vector3, team: int, view: SimView, prm: FormationParams) -> Vector3   # velocity to add to the guidance command; one ids_near
const AGE_FRESH: int; const AGE_CLOSING: int                               # sep_age bits: the last think refreshed; that refresh found a closing pair
static func needs_refresh(age: int) -> bool                                 # false only right after a refresh that found no closing pair
static func term(s: int, id: int, p: Vector3, v: Vector3, team: int, view: SimView, prm: FormationParams, st: AiState) -> Vector3   # the one refresh / hold policy: push into st.sep_push[s] or hold it once
class_name Formation extends RefCounted            # AI-11: 05 s5.6 slot geometry, static only
static func slot_world(lp: Vector3, lv: Vector3, lb: Basis, idx: int, wing: bool, prm: FormationParams) -> Vector3   # lb = SimView.basis(leader); clamped to the soft ceiling
static func v_cmd(p: Vector3, slot_pos: Vector3, lv: Vector3, cruise: float, prm: FormationParams) -> Vector3       # lv + k_form (slot - p), capped at cruise x speed_cap_mult
static func max_breakers(count: int, prm: FormationParams) -> int;  static func may_break(slot: int, count: int, prm: FormationParams) -> bool
static func free_slot(used: int, limit: int) -> int                        # lowest clear bit below limit, else AiState.NO_SLOT
class_name EscortPilot extends RefCounted          # AI-11: ESCORT of one ship class (05 s3.1, s5.6), the Dart / Lancer brains call it for an ESCORT head
enum Outcome { FORMING, ENGAGING, LOST }
const FORM: int; const ENGAGE: int; const SPENT: int; const DOCKED: int      # form_state values (SPENT: a FOCUS / BREAK timed out, FORM until the order is re-issued)
var def: ShipDef; var prm: FormationParams; var gains: FlightGains
func _init(ship_def: ShipDef, params: FormationParams, flight_gains: FlightGains) -> void
func think(id: int, view: SimView, st: AiState, tick: int, threat: int = 0, utility: float = 0.0) -> Outcome   # writes guidance_vel / guidance_point / target; LOST: brain fails the order to AUTO
func act(id: int, view: SimView, st: AiState, out: PilotInput) -> bool    # track_velocity on guidance_vel; false while ENGAGE or without an escortee
func release(id: int, st: AiState) -> void;  func slot_error(id: int, view: SimView, st: AiState) -> float
```

```gdscript
class_name AiTag                                   # AI-13 (R0 B.17 A-94): enum holder, `enum Tag` (Enumerations below)
class_name DartBrain extends AiBrain               # AI-13: 05 s6.2 Dart; AiState.mode = its AiTag.Tag, also written as the ai_tag
const B_RTB_SENT: int; const B_RUN_DONE: int; const DOCKED_STATE: int; const SEP_PHASES: int
var prm: DartParams; var gains: FlightGains; var probe_params: ProbeParams; var terrain: Terrain; var modes: DartModes; var stats_pull_ups: int
var stats_longest_pull_up: int; var stats_thinks: int; var stats_refreshes: int; var stats_shape_loss: int; var stats_checks: int; var stats_check_loss: int   # deterministic perf counters
static func from_content(c: ContentSet, ap: Dictionary, def: ShipDef, t: Terrain, ring2_m: float = INF) -> DartBrain   # null on a missing key; FlightCommonDef from c (A-90)
func think_one(id: int, view: SimView, st: AiState, sink: CommandSink, tick: int) -> void   # one think (rigs, perf)
class_name DartModes extends RefCounted            # AI-13: the per-order thinks (RETURN, ESCORT, ATTACK, MOVE, PATROL / HOLD / GUARD / AUTO) and the choice point
const B_RUN_DONE: int
var prm: DartParams; var terrain: Terrain; var landing: LandingPilot; var escort: EscortPilot; var run: AttackRun; var combat: DartCombat; var targets: TargetParams; var stats_choices: int; var picture: TeamPicture
func _init(params: DartParams, t: Terrain, lp: LandingPilot, ep: EscortPilot, ar: AttackRun, dc: DartCombat, tp: TargetParams) -> void
static func patrol_point(home: Vector3, k: int, n: int, radius: float) -> Vector3;  static func is_combat(m: int) -> bool
func choice_due(s: int, tick: int) -> bool         # the think phase of the choice point (every choice_period_thinks, staggered by slot)
func think_return(id: int, s: int, m: int, head: OrderSpec, view: SimView, st: AiState, tick: int) -> int
func think_escort(id: int, s: int, m: int, head: OrderSpec, view: SimView, st: AiState, tick: int) -> int
func think_attack(id: int, s: int, m: int, head: OrderSpec, view: SimView, st: AiState, tick: int) -> int
func think_move(id: int, s: int, head: OrderSpec, view: SimView, st: AiState) -> int
func think_patrol(id: int, s: int, m: int, head: OrderSpec, kind: int, view: SimView, st: AiState, tick: int) -> int
class_name DartCombat extends RefCounted           # AI-13: INTERCEPT / ENGAGE (straight-line gun, R0 C1-03) / EXTEND / EVADE
const F_BOOST: int; const F_FLIP: int
var prm: DartParams; var gains: FlightGains; var rng: Rng; var stats_draws: int
func _init(params: DartParams, flight_gains: FlightGains) -> void
func think(id: int, mode: int, view: SimView, st: AiState, tick: int) -> int
func act_engage(id: int, view: SimView, st: AiState, out: PilotInput, p: Vector3, v: Vector3, b: Basis, tick: int) -> void   # the act's own reads passed in
static func aim_offset(dir: Vector3, err: Vector2, up: Vector3) -> Vector3   # the burst's small aim error applied to `dir` (no rotation per tick)
static func gauss2(r: Rng) -> Vector2              # two standard normals (Box-Muller), the per-burst aim error
class_name AttackRun extends RefCounted            # AI-13: the 05 s6.3 sub-machine R1-R5 (Dart; Lancer / Bomber with AI-14)
enum Step { NONE, ROUTE, RUN_IN, RELEASE, EGRESS, REATTACK, DONE };  enum Band { LOW, DECK, HIGH }
const F_ABORTED: int; const F_RELEASING: int; const F_DIVING: int; const F_BOOST: int; const F_FLIP: int   # bflags bits
var prm: DartParams; var terrain: Terrain; var dart_dive: bool
func _init(params: DartParams, t: Terrain) -> void
static func step_of(st: AiState, s: int) -> int;  static func band_of(st: AiState, s: int) -> int
func begin(id: int, view: SimView, st: AiState, aim: Vector3, tick: int) -> void;  func think(id: int, target: int, view: SimView, st: AiState, tick: int) -> int
func act(id: int, view: SimView, st: AiState, out: PilotInput) -> void   # R3 sight + stick (FIRE2), egress BOOST / FLIP
class_name DartParams extends RefCounted           # AI-13: the brain's numbers from ap_dart + ship / rules / order_rules / weapon / tower defs
const KEYS: PackedStringArray; const GUN_KEYS: PackedStringArray; const BOMB_KEYS: PackedStringArray; const EVADE_KEYS: PackedStringArray; const GUIDE_KEYS: PackedStringArray
const INTERCEPT_KEYS: PackedStringArray; const RUN_KEYS: PackedStringArray; const LAUNCH_KEYS: PackedStringArray; const RTB_KEYS: PackedStringArray; const ORDER_KEYS: PackedStringArray
const THREAT_NONE: int; const THREAT_GUN: int; const THREAT_FLAK: int; const THREAT_MISSILE: int
var tick_hz: int; var think_ticks: int; var cruise_speed: float; var boost_speed: float; var dt: float; var gravity: float; var cruise_agl: float; var deck_agl: float; var max_alt: float
var patrol_radius: float; var intercept_radius: float; var clear_tti: float; var pull_up_tti: float; var fire_range: float; var fire_cone_k: float; var burst_ticks: int; var cycle_ticks: int
var aim_error_rad: float; var slug_speed: float; var aoa_comp_max: float; var dive_rad: float; var release_tol: float; var pullout_margin_s: float; var hp_drop: float; var evade_ticks: int
var evade_turn_rad: float; var kp_alt: float; var vz_max: float; var wp_radius: float; var check_ticks: int; var sample_s: float; var pull_up_hold_ticks: int; var launch_tilt_rad: float; var deck_speed: float
var aoa_comp_cos: float; var vision_period: int
var boost_close: float; var lost_ticks: int; var engage_extra: float; var engage_margin: float; var overshoot: float; var extend_ticks: int; var choice_period: int; var patrol_points: int
var patrol_switch: float; var hp_window_ticks: int; var standoff: float; var break_ttc: float; var ip_dist: float; var ip_arrive: float; var band_low: float; var band_high: float
var continue_rad: float; var egress_turn_rad: float; var egress_ticks: int; var abort_hp01: float; var max_passes: int; var predict_dt: float; var predict_steps: int; var dive_release_frac: float
var pitch_over_agl: float; var launch_climb_agl: float; var launch_max_speed: float; var arrival: float; var move_agl: float; var patrol_engage: float; var hold_orbit: float
var guard_orbit: float; var guard_engage: float; var loiter_alt: float; var ghost_ticks: int; var bomb_def: ProjectileDef; var bomb_damage: float; var bomb_interval: float; var rules: RulesDef
var threat_kind: PackedByteArray; var threat_range: PackedFloat32Array; var threat_scan: float; var hp_by_def: PackedFloat32Array; var rtb_ammo: int
static func from_content(ap: Dictionary, def: ShipDef, c: ContentSet) -> DartParams;  func ticks(s: float) -> int;  static func block(d: Dictionary, k: String) -> Dictionary
class_name Guidance extends RefCounted             # AI-13: shaping shared by brains and overlays (05 s5.3; A-69, A-89), static
static func band_vz(agl: float, band_agl: float, alt: float, max_alt: float, kp: float, vz_max: float) -> float
static func level(dir_h: Vector3, speed: float, vz: float, u: float, up: Vector3) -> Vector3
static func lifted(v_cmd: Vector3, vel: Vector3, up: Vector3, lift: float) -> Vector3;  static func cleared(v_cmd: Vector3, vel: Vector3, up: Vector3, need: float) -> Vector3
static func floored(v_cmd: Vector3, up: Vector3, agl: float, floor_agl: float, kp: float, vz_max: float) -> Vector3
static func sink_limited(v_cmd: Vector3, b: Basis, up: Vector3, g: FlightGains, room: float) -> Vector3   # at most one pull_up_loss
static func drop_free_clearance(r: ProbeResult, gravity: float) -> float;  static func budget_low(visible: float, b: Basis, v: Vector3, up: Vector3, g: FlightGains) -> bool
static func pull_up_due(terrain: Terrain, b: Basis, p: Vector3, v: Vector3, up: Vector3, g: FlightGains, sample_s: float, visible: float) -> bool
static func toward(p: Vector3, to: Vector3, up: Vector3) -> Vector3;  static func ground_dist(a: Vector3, b: Vector3) -> float
class_name TeamPicture extends RefCounted          # AI-13: per team, the visible enemy ships of the Vision epoch (built once, shared by its choice points)
var builds: int; var period: int
func epoch(team: int, tick: int) -> int;  func reset() -> void
func enemies(view: SimView, team: int, tick: int) -> PackedInt32Array;  func near(view: SimView, team: int, tick: int, origin: Vector3, radius: float) -> int;  func near_ids() -> PackedInt32Array
```

```gdscript
class_name OverlayParams extends RefCounted        # AI-08: per-class overlay numbers from the autopilot def (05 s2.4, s4.4), read-only
const KEYS: PackedStringArray                      # safety_clear/min_hold/max_hold/force_rtb_fuel01, recover_ceiling_gamma_deg / _exit_alt_m
var bridge: BridgeParams; var ground: bool; var clear_tti_s: float; var min_hold_ticks: int; var max_hold_ticks: int
var force_rtb_fuel01: float; var rc_gamma_rad: float; var rc_exit_alt_m: float; var ceiling_hard_m: float; var v_cruise: float
static func for_ship(ap: Dictionary, def: ShipDef, rules: RulesDef, tick_hz: int, flight_common: FlightCommonDef) -> OverlayParams   # null on a missing key; R0 B.15 A-90
static func for_ground(ap: Dictionary, rules: RulesDef, tick_hz: int) -> OverlayParams              # safety_min_hold_s only
class_name Overlays extends RefCounted             # AI-08: 05 s2.4 overlays executed in step 3, static
const NONE: int; const SAFETY: int; const RECOVER_CEILING: int   # = ControlMachine.Overlay ordinals
static func enter(id: int, v: SimView, st: AiState, p: OverlayParams, tick: int) -> void   # release edge: RECOVER_CEILING at >= ceiling_hard_m, else SAFETY
static func clear(st: AiState, s: int) -> void
static func run(id: int, v: SimView, st: AiState, p: OverlayParams, terrain: Terrain, sink: CommandSink, tick: int, probe: ProbeResult, out: PilotInput) -> bool   # true: ended
static func run_safety(id: int, v: SimView, st: AiState, p: OverlayParams, terrain: Terrain, sink: CommandSink, tick: int, probe: ProbeResult, out: PilotInput) -> bool
static func run_recover_ceiling(id: int, v: SimView, st: AiState, p: OverlayParams, terrain: Terrain, sink: CommandSink, probe: ProbeResult, out: PilotInput) -> bool
static func run_ground_safety(id: int, st: AiState, p: OverlayParams, sink: CommandSink, tick: int, out: PilotInput) -> bool
class_name TargetParams extends RefCounted         # AI-12: choice-point constants from an autopilots.json entry (05 s6.2, s6.8)
static func from_dict(d: Dictionary) -> TargetParams   # null unless target_weights, target_dist_falloff_m, target_under_tower_penalty, switch_margin
func bind(entity_index: Dictionary) -> void;  func weight(def_id: int, loaded: bool) -> float   # class name -> def id; `hauler_loaded` pseudo class
static func num(d: Dictionary, key: String, fallback: float) -> float;  static func as_num(v: Variant, fallback: float) -> float   # typed JSON readers
static func dict_of(d: Dictionary, key: String) -> Dictionary;  static func entity_def(entity_index: Dictionary, name: StringName) -> int
var max_candidates: int   # default 8: cost bound of a choice point
var switch_margin: float; var tower_switch_margin: float; var rank_weights: PackedFloat32Array   # + the 05 inline multipliers (optional keys)
class_name TowerEnvelope extends RefCounted        # AI-12: one tower def's envelope + priority, built from the towers.json `tower` block (C2-15)
static func from_block(block: Dictionary, entity_index: Dictionary, params: TargetParams) -> TowerEnvelope
func in_envelope(h_rel: float, agl: float) -> bool;  func kind_ok(def_id: int) -> bool;  func base_weight(def_id: int, loaded: bool) -> float
func eligible(p_tower: Vector3, p_t: Vector3, def_id: int, range_m: float, terrain_h: float) -> bool
class_name TargetContext extends RefCounted        # AI-12: per-team preallocated facts (attacked_until / targeted_by by slot, enemy tower list, score scratch)
func mark_attacker(id: int, tick: int, window_ticks: int) -> void;  func attacked_recently(id: int, tick: int) -> bool;  func add_targeter(id: int) -> void;  func remove_targeter(id: int) -> void
func add_tower(pos: Vector3, range_m: float, env: TowerEnvelope) -> bool;  func clear_towers() -> void;  func under_tower(p_t: Vector3, def_id: int, terrain_h: float) -> bool
class_name TargetChooser extends RefCounted        # AI-12: static choice points with hysteresis
static func score_ship(w: float, dist: float, hp01: float, attacked: bool, under_tower: bool, targeters: int, p: TargetParams) -> float
static func score_tower(base: float, attacking: bool, hp01: float, towers_on_it: int, guard_attacker: bool, slew_s: float, p: TargetParams) -> float
static func pick(ids: PackedInt32Array, scores: PackedFloat32Array, n: int, current: int, margin: float) -> int
static func choose_ship(view: SimView, team: int, cand: PackedInt32Array, n: int, origin: Vector3, radius: float, current: int, tick: int, ctx: TargetContext, p: TargetParams, out: PackedInt32Array) -> int
static func choose_tower(view: SimView, team: int, tower_pos: Vector3, aim: Vector3, env: TowerEnvelope, range_m: float, cand: PackedInt32Array, n: int, current: int, tick: int, ctx: TargetContext, p: TargetParams, guarded: int, out: PackedInt32Array) -> int
```

**Overlays (AI-08).** `ControlMachine` sets the store's overlay on release; `SimView` does not expose it, so `AiDriver`
sees the release itself: the control state of an entity marked possessed (or in an overlay) is read every tick, of the
others on their think phase (1/P per tick) or at once through `on_event(POSSESSED)`; the first tick a marked live entity
is not POSSESSED, `Overlays.enter` starts RECOVER_CEILING (at or above `ceiling_hard_m`, the C11 case) or SAFETY. Per
tick, after the class's `act_batch` (so the overlay's `drive` wins): SAFETY holds the release velocity shaped by the A-69 lift
(`integ`, pitch seeded with `Assist.trim_lead`), PULL_UP (`Assist.pull_up`) from TTI < `safety_pull_up_tti_s` until TTI >= `safety_clear_tti_s`,
one RETURN request (FLAG_PREPEND) below `safety_force_rtb_fuel01`, ends at TTI >= clear and >= min hold, or at max hold
unless pulling up. RECOVER_CEILING: heading kept, `recover_ceiling_gamma_deg` path at `v_cruise` + lift, the SAFETY
checks, ends at <= `recover_ceiling_exit_alt_m`. A ship DOCKED / LANDED ends its overlay at once (05 s2.5). Ground SAFETY: BRAKE for `safety_min_hold_s`. An entity in an overlay
does not think; at the end it is woken. LINK_BRIDGE is `Assist.link_bridge` in `SimWorld` step 4 (sim/steer).

## Enumerations (append-only; ordinals frozen; R0 B.3)

- `AiTag.Tag` (`sim_ai/ai_tag.gd`; R0 B.17 A-94; the replicated `ai_tag` u8, 05 s6.1): 0 NONE, 1 LAUNCH, 2 PATROL, 3 INTERCEPT, 4 ENGAGE, 5 EXTEND, 6 EVADE, 7 BOMB, 8 RETURN, 9 DOCKED, 10 PULL_UP, 11 MOVE, 12 HOLD, 13 GUARD, 14 ESCORT, 15 LOITER, 16 FLEE, 17 SEARCH, 18 FERRY_PICK, 19 LOAD, 20 FERRY_DROP, 21 TOW, 22 CAPTURE, 23 PICK_FIELD, 24 TO_FIELD, 25 MINE, 26 TO_REFINERY, 27 QUEUE, 28 UNLOAD, 29 SIEGE, 30 RELOCATE, 31 TRACK, 32 OFFLINE, 33 IDLE (0-15 the Dart, AI-13; 16-33 reserved for AI-14 / AI-16 / AI-17 / AI-18; a new word is appended at the end).

## Invariants

- Unbound, `CommandSink` refuses everything (base behaviour). Bound, every call forwards unchanged: it never decides validity.
- `drive` never writes a POSSESSED entity's slot (S11, enforced by `SimSink`).
- Hook bytes: `SimAiHook.serialize / deserialize` are the opaque S4 bytes appended to `SimWorld.serialize()`.

- Think when `(tick + stagger) % P == 0`, `stagger` = per-entity round-robin counter (serialized): each entity thinks exactly 30/P times per 30 ticks, phases equally loaded. `P` = 10 (online), 15 offline/Lite or cut-ladder rung 1.
- Wake: next `on_tick`, accepted at most once per 5 ticks per entity. Bots: `(tick + 4 * slot) % P == 0`, P = 90/30/30/30 by tier (R0 C2-13).
- Batches stay sorted by slot (order is a function of state); dead entities are dropped at their next think; POSSESSED ones are skipped.
- Perf (03 s4.2 AI row): scheduling only, 400 units, no-op brain: ~130 us/tick on the dev machine (`test_ai_driver_perf.gd`).
- R0 B.12 A-71: `SimWorld` forwards the previous tick's drained events to `SimAiHook.on_event` before `on_tick` (TA-57); `AiDriver.on_event` registers AI-driven entities on SPAWN (def -> class table) and unregisters on DEATH (AI-37); `register()` stays public for rigs. Periods come from `autopilots.json` / `bot_profiles.json` with AI-19.
- OV1: an overlay starts on the tick of the release (no latency) for an entity the driver knew to be possessed; overlays run every tick, after the class's act; an entity in an overlay never thinks and is woken when it ends; possession drops it (`test_overlays.gd`, SC-11).
- OV2: SAFETY never ends during a PULL_UP; it ends at TTI >= `safety_clear_tti_s` after `safety_min_hold_s`, else at `safety_max_hold_s` (SC-11: overlay ends with TTI >= 4 s).
- OV3: one RETURN request per overlay at most, none when fuel is above the threshold or the head is already RETURN (SC-12).
- OV4: overlay state (`overlay`, `ov_flags`, `integ`, `overlay_since`, `guidance_vel`, `tti`) is in the S4 bytes; restore + continue is byte-identical (`test_overlays_deterministic_and_s4`).
- Perf (AI-08, `test_overlays_perf.gd`, best of 6): release-edge check +0.17 us per registered unit per tick (+69 us at 400); one overlay tick (`Overlays.run`: 6 height samples + `track_velocity`) 10-12 us, against the 05 s10 act row's 6 us per ship: overlays run on released ships only (a handful per tick), never on the roster.
- The def -> class table (`set_class_table`, AI-37) is session configuration, not part of the S4 bytes: a restored session calls `set_class_table(AiClassTable.from_content(...))` again before the next tick.
- Resolved by TA-59: the SAFETY RETURN (FLAG_PREPEND) goes through `SimSink.submit` as a system order (issuer -1, no rate token); `SimView.overlay(id)` and `CommandSinkBase.end_overlay(id)` clear the replicated overlay byte when SAFETY / RECOVER_CEILING ends (`AiDriver` calls it).
- Open (needs content, AI-19): `autopilots.json` with the `safety_*`, probe and `flight` keys and the AI-08 additions `recover_ceiling_gamma_deg` (-20) and `recover_ceiling_exit_alt_m` (1400) in the schema; the session builds `OverlayParams` per class and calls `set_terrain(world.terrain())`.
- TC1: choice points read only `SimView` candidates that are alive, enemy and `visible_to(team, id)`; ties go to the earlier candidate; a new choice must exceed `switch_margin` (tower: `tower_switch_margin`) times the current's score, a current no longer a candidate is dropped (`test_target_chooser.gd`). No envelope or priority literal in `sim_ai/`: both come from `towers.json` via `TowerEnvelope`.
- TC2: cost is bounded by `TargetParams.max_candidates` (8): one cheap pass keeps the best N by `w / (1 + dist / falloff)` (insertion into the caller's `out`), then only those are fully scored; `out` and `ctx.scores` must hold N (asserted). 05 s10 think row = 25 us for 6 probes + 1 neighbour query + 1 choice point; measured `choose_ship` N=8 ~43 us with a typed-array fake view (3x CI tolerance bound 75 us), n=64 ~207 us (`test_cost_of_one_choice_point_at_the_budget_row`): over the row on this desktop debug build, so brains call it at most every other think or with a pre-filtered N <= 4 until the Architect revisits the row. The modifiers can reorder candidates the pre-score ranks 9th or lower; accepted.
- TC3: `ctx.targeted_by` counts the chooser itself when it holds `current`; the chooser subtracts it, so focus fire counts the other ships only.
- Resolved by AI-13 (R0 B.15 A-89): `Overlays.run_safety` starts PULL_UP at TTI < `safety_pull_up_tti_s` OR when the visible clearance (AGL, one height sample, or the probe's worst drop-free clearance) is below `FlightController.pull_up_loss` (`test_safety_overlay_ors_the_pull_up_budget_into_its_trigger`; SC-11 on cradle).
- Open (AI-12): optional `autopilots` keys read by `TargetParams` (`attacked_mult`, `low_hp_mult`, `focus_mult`, `tower_*`, `guard_mult`, `tower_rank_weights`) **need content** in `autopilots.schema.json`; they default to the 05 literals (`TargetParams` constants and `DEFAULT_RANK_WEIGHTS`; flagged, not yet read from a def). The bomb-prediction step and horizon for `Ballistics.predict_impact` are brain parameters from the same def.

- Landing (AI-09): a pad is busy for a ship when another ship occupies it, is first in `pad_queue`, or holds a live claim
  (`pad_claim`: alive, `aux_id` = the pad, phase not HOLD / GO_AROUND); a ship claims at think once inside the gate on a
  free pad and releases on HOLD, GO_AROUND, divert and dock. Pad geometry is cached per pad id (derived, not S4 bytes).
  Pad selection scans `SimView.structures()` once per RETURN start or divert (05 s10: the only roster scan here);
  `w_hangar` and `risk01` are neutral until the threat map lands. The threat flag is any enemy projectile within
  `threat_radius_m` of the pad (bombs / rockets are not distinguishable through SimView yet). **Needs content (AI-19):**
  the `rtb` block gains `hold_fuel_reserve_s` 25, `pad_eta_scale_s` 60, `pad_queue_s` 15, `pad_w_one_queued` 0.6,
  `pad_w_more_queued` 0.3, `threat_radius_m` 300 (05 s5.5 numbers; fixture `test/sim/ai/ai09_params.json`).
- Perf (05 s10, `test_think_and_act_cost`, dev laptop, `LandingWorld` view): think 14.6 us (25 us row), act 14.3 us per
  landing ship (6 us row; 10 us of it is `LandingController.step`, see `sim/steer/MODULE.md`).

- Formation (AI-11, 05 s5.4 / s5.6; `test_formation.gd`, `test_escort_pilot.gd`, `test_sc39_escort_formation.gd`, `test_swarm_separation.gd`): F1 slot offsets are (right, forward, up) in the escortee's tangent frame (class) or body frame (SL-2 wing, `escort_slot >= 0`, `wing.json` back / right / up converted on load); `v_cmd = v_leader + k_form (slot - p)`, capped at cruise x 1.1; a slot above `rules.ceiling_soft_m` is pulled down to it. F2 a class slot is assigned once per order (lowest free index of the escortee's roster row `form_roster`, entries validated against `aux_id` / `form_slot` / liveness on use; no spatial query), kept in `form_slot`, dropped by `release`; with every class slot held, a further escort is an overflow escort: it doubles up on slot `EntityId.slot(id) % n`, stored as that + `ROSTER_WIDTH` outside the roster (the roster names holders only, so restore rebuilds the same rows), keeps it when a holder leaves and never breaks out (the break share counts holders); the brain must call `release` whenever it stops routing a ship to `EscortPilot` (an order replaced without a LOST think), else the stale holder keeps its slot while its `aux_id` is unchanged; at most `max_break_frac` of the escorts (at least one, the higher slots) leave formation, FORM breaks only for utility > `break_utility` within `engage_radius_m` of the escortee, rejoins when the threat is gone or beyond `rejoin_radius_m`; FOCUS / BREAK use the `wing.json` leash and time limits and, once timed out, stay `SPENT` until the order is re-issued (`form_order` = issue_tick). F3 `think` writes `guidance_vel` (formation + separation) and, while ENGAGING, `target`; the brain flies the attack and applies terrain shaping (05 s5.3) to `guidance_vel` before `act`. F4 `Separation`: the 05 s5.4 proximity ring plus an AI-11 look-ahead (below); friendly ships only, enemies never; SC-39 (Bomber MOVE 5 km, 2 Dart ESCORT): in slot 88-96 % of the run, no DEATH, smallest gap 8.7 m (join-up).
- Separation look-ahead (AI-11; 05 s5.4 as amended by R0 B.14 A-84; the doc formula alone cannot meet the acceptance): the ring (60 m, 20 m/s) gives a head-on pair 0.3 s and an overtaker no sideways push; flight-model measurements (Dart / Lancer / Bomber step response to a 30 degree heading command: ~1 s lag, then 0.7-1.0 m of lateral offset per m/s of push per second) make the ring too late. For each friendly neighbour closing within `look_s` (4 s; a slow closer is judged at the horizon) whose predicted miss is under `look_miss_m` (80 m): push sideways (horizontal part of the miss vector, else `up x v_rel`, opposite for the two ships) at `deficit / (look_eff max(t - look_lag_s, look_min_s))` m/s, at most `look_max_mps`; only the most urgent neighbour counts (sums cancel in a clump); a ship catching up on a neighbour ahead also sheds `look_brake` x the closing speed x urgency.
- Separation refresh (AI-11 round 3, `Separation.term`, the one policy EscortPilot and `SwarmWorld` call): a think holds the cached term only right after a refresh that found no closing pair (a friendly in the query approaching at >= 1 m/s); otherwise it refreshes. Flags in `sep_age` (AGE_FRESH, AGE_CLOSING), FORMAT 4 unchanged. Measured on `SwarmWorld` (12 mixed ships, fair starts, query 180 m), 300 seeds: 4 collide (every-think baseline 4; holding only when the look-ahead term is zero also 4, but on other seeds incl. seed 6 of the CI 50; the unconditional every-second-think hold was 11); stress (same destinations) 19 of 300 (every think 21; look-ahead-zero rule 14); CI: 50 seeds zero collisions, stress 30 seeds better than without separation; without separation 30 of 50 seeds collide. SC-39 refresh share 0.74-0.81 of the FORMING thinks (wing 0.64).
- Perf (AI-11, `test_escort_perf.gd`; 05 s10 think row 25 us, act row 6 us; dev machine, 4 escorts + 12 friendly Darts within 300 m + 240 far Darts over many cells, best of 6 batches of 1000 per-call timings): query radius `query_radius_m` 180 m <= `Spatial.ring2_m` (187.9 m), the ring path; group count and slot assignment read the roster row, no spatial query. Held think ~8 us, refresh think ~38 us. The formation spawns in one tick (parallel flight). Quiet case (refresh share 0.50) mean 23.2-23.5 us, median 29, p95 39; threat-gate case (share 0.50) mean 28.2-28.3; closing-neighbour case (a friendly head-on 150 m ahead: refresh every think) mean 38-39, p95 39-41; act 7.1. A flown formation (SC-39, share ~0.78) costs about 30 us per think: the row is met by the steady case only; a brain that also probes and chooses targets budgets the refresh think against its own row. CI bound: row x `CI_FACTOR` 2 on the per-call mean (05 s10 rows are per-tick sums, so a mean is the comparison; 05 s11.1 keeps p95 assertions for the pinned runner; R0 A-62: no row moves before it is measured); the closing case x 2 more (transient).
- Open (needs sim, R0 B.14 A-85 -> TA-60): the ORDER wire payload (`CommandPayload.read_order`, 04 s2.5) carries no `escort_slot` / `escort_mode` / `focus`, so SL-2 orders cannot reach the queue by `Command` yet; `EscortPilot` reads them from `SimView.order_head`, tests inject through `OrderQueue.push` (`FormationKit.escort_order`).
- Open (needs content, R0 B.14 A-86 -> AI-19): `engage_radius_m` comes from `order_rules.json` `escort_engage_radius_m` (OrderRulesDef), not the `formation` block; `autopilots.json` `separation` block gains `push_mps`, `lookahead_s`, `lookahead_miss_m`, `lookahead_lag_s`, `lookahead_eff`, `lookahead_min_s`, `lookahead_max_mps`, `lookahead_brake`, `query_radius_m`, and a `formation` block with `FormationParams.FORM_KEYS` (fixture `test/sim/ai/ai11_params.json` carries the 05 values until then).

- Dart (AI-13, 05 s6.2-6.3; `test_dart_brain.gd`, `test_sc_dart.gd` SC-01 / SC-28 / SC-29, `test_sc_dart_terrain.gd` SC-09 / SC-10 / SC-11 on cradle): DB1 the mode is an `AiTag.Tag` and is the `ai_tag` (set on change and the tick PULL_UP starts); per-entity state is AiState only (FORMAT 5), `TeamPicture` / `TargetContext` are scratch, `target_count` is derived; restore + continue is byte-identical with the driver configured before `deserialize`, so its rebind loop is exercised (`test_dart_brain_is_deterministic_and_restores_s4`, three Darts on one Bomber, counts compared). DB2 one TerrainProbe pass per think (6 samples); TTI / PULL_UP keep the ballistic probe; the climb command is A-69 over every sample: `v_cmd.radial >= v_r + climb_need` (`Guidance.cleared`, signed), then the deck floor, the sink limit (one `pull_up_loss`; the sink scaled by room / loss) and no climb at `max_alt_m`. DB3 PULL_UP starts at act every `pull_up_check_ticks` (staggered by slot) on the 1.0 s re-sample < 0 OR the A-89 budget (one `pull_up_loss` while sinking; no conservative pre-bound exists: the loss is INF where the chosen elevation has no climb and is not monotone, a (speed, sink) grid bound was undercut by random states), and at think on TTI < `safety_pull_up_tti_s`; it ends (R0 B.17 A-92) at the first think with TTI >= `safety_clear_tti_s`, `pull_up_min_hold_s` held and `climb_need_mps` <= 0, then `prev_mode`; no max hold in v1 (`stats_longest_pull_up` reported); the SAFETY overlay keeps its 05 s2.4 exit. DB4 vision only: choice points take `TeamPicture`, rebuilt once per team per Vision epoch (team t's bits change only in its own pass, so the cache equals the live set every tick: `test_team_picture_is_built_once_per_vision_epoch_and_stays_exact`); an ATTACK on a never-seen entity flies no run; an invisible target's last seen position is `goal`, lost after `lost_s`. DB5 the choice point runs every `choice_period_thinks` (6th) think; the separation term refreshes every `SEP_PHASES` (3rd) think, never on a choice think, and every think while a pair closes (AI-11's rule); engaged, a target chased out of the radius is kept until lost. DB6 ENGAGE steers the nose onto the erroneous lead (`aoa_comp_max_deg`); outside fire range on the think's cached lead (`aim_lead`), inside it on the per-tick lead; `standoff_m` (200) and the ram break-off `break_ttc_s` (2.0) are the 05 s6.2 ENGAGE append of R0 B.17 A-93 (keys in `intercept`). DB7 Deck legs fly at `deck_speed_mps` (160, SC-09's speed). DB8 a run done with no bombs prepends a system RETURN; the RTB rule (every think; the fuel floor cached in `rtb_floor` at the choice period) prepends one per head; no pad: LOITER over home.
- Measured (dev laptop): SC-01 airborne 1.27 s, AGL 150-302 m, <= 1,307 m from the pad; SC-28 10 / 10 kills, Bomber first 10 / 10; SC-29 Deck, 100 % of 18 s in Flak range below 150 m AGL; SC-09 min clearance 30 / 24 m, SC-10 trench 100 % low, rille legs no contact; SC-11 cradle pull-up +0 ticks; 0 unrecoverable states in every tick checked while sinking (265 / 502 / 61 / 139 / 141 / 41).
- Perf (`test_dart_perf.gd`, guards row x CI_FACTOR 2 only; counters asserted: choice share 1/6, refresh share <= 0.5, <= 1 `pull_up_loss` per shaped think and per act check, 1 picture per team per epoch). Dev laptop, host scale 1.00: quiet think 41 / median 36 / p95 72 us; engaged think 56 / 41 / 83; act patrol 8.5, act engage in fire range 18.4 us; TeamPicture 221 us for 261 ships = 295 us per tick at 8 teams (cap 450). Engaged think components: hold 29, separation refresh think 68, choice think 73 (choose_engaged 33, combat.think 8.5); act engage: act_engage 8.9 (track_velocity 3.2, lead 1.6) + act_batch reads and the check 5-6. **BLOCKED (perf, A-62):** the engaged think and the engaged act are over row x 2 after every lever of the review; contract question in PR #87. `_send_rtb` allocates an OrderSpec and a Command per send (rare).
- Open (needs sim): order completion (05 C4) is not wired, so a finished ATTACK stays the head (`B_RUN_DONE`: AUTO patrol under it) and a MOVE orbits its point; Docking (GD-15) is not built, so DOCKED waits; `Spatial.ids_near` beyond `ring2_m` is O(touched cells), and `TeamPicture` still walks `ships()` once per team per Vision epoch: a per-team visible-enemy list from Vision would make choice points O(candidates); a world saved during a gun fight did not always round-trip byte-exactly (the diff sits in the ProjectileStore section; seen with three AI Darts firing, not with a possessed one: `test_dart_brain.gd` saves before the first slug). Open (needs content, AI-19): the AI-13 keys of `ai13_autopilots.json` (`guidance`, `intercept`, `attack_run` blocks, `gun.aoa_comp_max_deg`, `evade.heading_change_deg`, `rtb.ammo`). Open (threat map, s7.4): the IP bearing is the direct one, the Autocannon "stay > 450 m" rule and the `attacked` factor (HIT feed) are not applied; rail towers do not set a band.

## Test entry points

`godot/test/unit/sim_ai/test_command_sink.gd`, `test_ai_driver.gd`, `test_ai_driver_perf.gd` (fixtures `ai_test_kit.gd`),
`test_landing_pilot.gd`; scenarios `godot/test/sim/ai/test_sc_landing.gd` (SC-02..SC-08; `LandingScenario`, `LandingWorld`); `test_target_chooser.gd`;
`test_overlays.gd`, `test_overlays_perf.gd` (AI-08); `godot/test/sim/ai/test_sc_overlays.gd` (SC-11, SC-12, SC-22, SC-23,
SC-25, determinism and S4; fixtures `overlay_kit.gd`, `ai08_autopilots.json`).
`test_formation.gd`, `test_escort_pilot.gd`, `test_escort_perf.gd` (AI-11; fixtures `godot/test/sim/ai/formation_kit.gd`, `swarm_world.gd`, `ai11_params.json`); `godot/test/sim/ai/test_sc39_escort_formation.gd` (SC-39), `test_swarm_separation.gd` (50-seed swarm).
`test_dart_brain.gd`, `test_dart_perf.gd` (AI-13; fixtures `godot/test/sim/ai/dart_kit.gd`, `ai13_autopilots.json`); scenarios `godot/test/sim/ai/test_sc_dart.gd` (SC-01, SC-28, SC-29), `test_sc_dart_terrain.gd` (SC-09, SC-10, SC-11 on cradle, the dive bound).
