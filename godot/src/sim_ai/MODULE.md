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
| Status | AI-03 (2026-10-14): `CommandSink`. AI-04 (2026-10-14): `AiState`, `AiBatch`, `AiBrain`, `AiDriver` scheduling. Brains follow. |

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
class_name AiBatch extends RefCounted              # ids of one class sorted by slot + `due` scratch
func add(id: int) -> bool;  func remove(id: int) -> bool
class_name AiBrain extends RefCounted              # per-class brain; base is a no-op
func think_batch(ids: PackedInt32Array, n: int, view: SimView, st: AiState, sink: CommandSink, tick: int) -> void
func act_batch(ids: PackedInt32Array, view: SimView, st: AiState, sink: CommandSink) -> void
func think_bot(slot: int, tier: int, tick: int, view: SimView, sink: CommandSink) -> void
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
- Open: `SimAiHook.on_tick` carries no events, so the session must forward drained events to `AiDriver.on_event`; roster registration is called by spawn wiring (AI-05+).

## Test entry points

`godot/test/unit/sim_ai/test_command_sink.gd`, `test_ai_driver.gd`, `test_ai_driver_perf.gd` (fixtures `ai_test_kit.gd`).
