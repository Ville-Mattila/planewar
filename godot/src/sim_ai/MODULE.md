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
| Status | AI-03 (2026-10-14): `CommandSink`. AI-04 (2026-10-14): `AiState`, `AiBatch`, `AiBrain`, `AiDriver` scheduling. AI-09 (2026-10-14): `LandingPilot`, AiState landing fields. Brains follow. |

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

## Invariants

- Unbound, `CommandSink` refuses everything (base behaviour). Bound, every call forwards unchanged: it never decides validity.
- `drive` never writes a POSSESSED entity's slot (S11, enforced by `SimSink`).
- Hook bytes: `SimAiHook.serialize / deserialize` are the opaque S4 bytes appended to `SimWorld.serialize()`.

- Think when `(tick + stagger) % P == 0`, `stagger` = per-entity round-robin counter (serialized): each entity thinks exactly 30/P times per 30 ticks, phases equally loaded. `P` = 10 (online), 15 offline/Lite or cut-ladder rung 1.
- Wake: next `on_tick`, accepted at most once per 5 ticks per entity. Bots: `(tick + 4 * slot) % P == 0`, P = 90/30/30/30 by tier (R0 C2-13).
- Batches stay sorted by slot (order is a function of state); dead entities are dropped at their next think; POSSESSED ones are skipped.
- Perf (03 s4.2 AI row): scheduling only, 400 units, no-op brain: ~130 us/tick on the dev machine (`test_ai_driver_perf.gd`).
- R0 B.12 A-71: `SimWorld` forwards the previous tick's drained events to `SimAiHook.on_event` before `on_tick` (TA-57); `AiDriver.on_event` registers AI-driven entities on SPAWN (def -> class table) and unregisters on DEATH (AI-37); `register()` stays public for rigs. Periods come from `autopilots.json` / `bot_profiles.json` with AI-19.

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
`test_landing_pilot.gd`; scenarios `godot/test/sim/ai/test_sc_landing.gd` (SC-02..SC-08; `LandingScenario`, `LandingWorld`).
