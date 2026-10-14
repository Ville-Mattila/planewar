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
| Status | AI-03 (2026-10-14): `CommandSink`. AI-04 (2026-10-14): `AiState`, `AiBatch`, `AiBrain`, `AiDriver` scheduling. AI-09 (2026-10-14): `LandingPilot`, AiState landing fields. AI-12 (2026-10-14): target choice points (`TargetParams`, `TargetContext`, `TowerEnvelope`, `TargetChooser`). Brains follow. |

## Public API

```gdscript
class_name CommandSink extends CommandSinkBase     # AI-03: the handle brains take; forwards to the sim's SimSink and counts
func bind(inner: CommandSinkBase) -> void;  func is_bound() -> bool;  func reset_counters() -> void   # AiDriver binds it each on_tick
func submit(cmd: Command) -> CommandResult         # via SimSink: validated, rate-limited, applied in step 1 of the next tick
func drive(id: int, input: PilotInput) -> bool     # false if POSSESSED or dead (S11), slot untouched
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
class_name AiBatch extends RefCounted              # ids of one class sorted by slot + `due` scratch
func add(id: int) -> bool;  func remove(id: int) -> bool
class_name AiBrain extends RefCounted              # per-class brain; base is a no-op
func think_batch(ids: PackedInt32Array, n: int, view: SimView, st: AiState, sink: CommandSink, tick: int) -> void
func act_batch(ids: PackedInt32Array, view: SimView, st: AiState, sink: CommandSink) -> void
func think_bot(slot: int, tier: int, tick: int, view: SimView, sink: CommandSink) -> void
class_name LandingPilot extends RefCounted         # AI-09: RETURN landing of one ship class over LandingController (05 s5.5)
const RTB_KEYS: PackedStringArray;  const DOCKED: int
var def: ShipDef; var prm: LandingParams; var gains: FlightGains; var probe_params: ProbeParams; var terrain: Terrain
var pad_radius_by_def: PackedFloat32Array
func _init(ship_def: ShipDef, common: FlightCommonDef, rules: RulesDef, flight_gains: FlightGains, landing: LandingParams, probe: ProbeParams, rtb: Dictionary, t: Terrain, pad_radius: PackedFloat32Array) -> void
func needs_rtb(id: int, view: SimView) -> bool     # 05 s6 RTB rule: fuel floor with the distance term, hull
func begin(id: int, pad: int, st: AiState) -> void # RETURN start or divert: L1 TRANSIT on `pad`
func phase(id: int, st: AiState) -> int
func think(id: int, view: SimView, st: AiState) -> void      # pad validity / divert, one probe, busy / threat flags, bearing, claim
func act(id: int, view: SimView, st: AiState, out: PilotInput) -> int   # LandingController.step into `out`; the brain drives it
func select_pad(id: int, view: SimView, exclude: int, st: AiState) -> int   # 05 s5.5 score, fuel rejection, nearest fallback
class_name AiDriver extends SimAiHook              # AI-04
func _init(rng: Rng = null, think_period_ticks: int = 10, cut_period_ticks: int = 15, bot_periods: PackedInt32Array = PackedInt32Array([90, 30, 30, 30])) -> void
func think_period() -> int;  func set_offline_profile(lite: bool) -> void;  func set_cut_rung1(on: bool) -> void;  func ai_rng() -> Rng
func set_brain(cls: int, brain: AiBrain, bot: bool = false) -> void;  func register(id: int, cls: int) -> bool;  func unregister(id: int) -> bool
func wake(id: int, tick: int) -> bool;  func on_event(ev: SimEvent) -> void          # HIT wakes; DEATH unregisters and wakes hunters
func schedule_bot(slot: int, tier: int) -> void;  func unschedule_bot(slot: int) -> void;  func bot_due(slot: int, tier: int, tick: int) -> bool
func on_tick(tick: int, view: SimView, sink: CommandSinkBase) -> void;  func serialize() -> PackedByteArray;  func deserialize(bytes: PackedByteArray) -> void
func stats() -> Dictionary;  func reset_stats() -> void
```

```gdscript
class_name TargetParams extends RefCounted         # AI-12: choice-point constants from an autopilots.json entry (05 s6.2, s6.8)
static func from_dict(d: Dictionary) -> TargetParams   # null unless target_weights, target_dist_falloff_m, target_under_tower_penalty, switch_margin
func bind(entity_index: Dictionary) -> void;  func weight(def_id: int, loaded: bool) -> float   # class name -> def id; `hauler_loaded` pseudo class
static func num(d: Dictionary, key: String, fallback: float) -> float;  static func as_num(v: Variant, fallback: float) -> float   # typed JSON readers
static func dict_of(d: Dictionary, key: String) -> Dictionary;  static func entity_def(entity_index: Dictionary, name: StringName) -> int
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

## Invariants

- Unbound, `CommandSink` refuses everything (base behaviour). Bound, every call forwards unchanged: it never decides validity.
- `drive` never writes a POSSESSED entity's slot (S11, enforced by `SimSink`).
- Hook bytes: `SimAiHook.serialize / deserialize` are the opaque S4 bytes appended to `SimWorld.serialize()`.

- Think when `(tick + stagger) % P == 0`, `stagger` = per-entity round-robin counter (serialized): each entity thinks exactly 30/P times per 30 ticks, phases equally loaded. `P` = 10 (online), 15 offline/Lite or cut-ladder rung 1.
- Wake: next `on_tick`, accepted at most once per 5 ticks per entity. Bots: `(tick + 4 * slot) % P == 0`, P = 90/30/30/30 by tier (R0 C2-13).
- Batches stay sorted by slot (order is a function of state); dead entities are dropped at their next think; POSSESSED ones are skipped.
- Perf (03 s4.2 AI row): scheduling only, 400 units, no-op brain: ~130 us/tick on the dev machine (`test_ai_driver_perf.gd`).
- R0 B.12 A-71: `SimWorld` forwards the previous tick's drained events to `SimAiHook.on_event` before `on_tick` (TA-57); `AiDriver.on_event` registers AI-driven entities on SPAWN (def -> class table) and unregisters on DEATH (AI-37); `register()` stays public for rigs. Periods come from `autopilots.json` / `bot_profiles.json` with AI-19.
- TC1: choice points read only `SimView` candidates that are alive, enemy and `visible_to(team, id)`; ties go to the earlier candidate; a new choice must exceed `switch_margin` (tower: `tower_switch_margin`) times the current's score, a current no longer a candidate is dropped (`test_target_chooser.gd`). No envelope or priority literal in `sim_ai/`: both come from `towers.json` via `TowerEnvelope`.
- TC2: cost, 05 s10 think row (25 us per think incl. 1 choice point): `choose_ship` over 24 candidates ~106 us against a Dictionary-backed test view (the view dominates; per candidate 6 `SimView` reads, no allocation). Brains pre-filter with `ids_near` masks to <= 8 candidates.
- Open (AI-12): optional `autopilots` keys read by `TargetParams` (`attacked_mult`, `low_hp_mult`, `focus_mult`, `tower_*`, `guard_mult`, `tower_rank_weights`) **need content** in `autopilots.schema.json`; they default to the 05 literals. The bomb-prediction step and horizon for `Ballistics.predict_impact` are brain parameters from the same def.

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

## Test entry points

`godot/test/unit/sim_ai/test_command_sink.gd`, `test_ai_driver.gd`, `test_ai_driver_perf.gd` (fixtures `ai_test_kit.gd`),
`test_landing_pilot.gd`; scenarios `godot/test/sim/ai/test_sc_landing.gd` (SC-02..SC-08; `LandingScenario`, `LandingWorld`); `test_target_chooser.gd`.
