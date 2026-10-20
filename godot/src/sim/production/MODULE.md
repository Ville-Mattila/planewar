# sim/production - MODULE.md

Contract for `godot/src/sim/production/**`: the production queues of 02 s6.4 (TA-19; R0 C3-08; A-21 split of
`sim/MODULE.md`, invariants S12 and S13 live there). A change to "Public API" or "Invariants" is a contract change:
contract tests first, same PR (ADR-11); `tools/gen_module_api.py --check` must pass; <= 300 lines (ADR-14).

| Field | Value |
|---|---|
| Responsibility | One queue of at most `economy.queue_max` (5) items per Shipyard / Vehicle Bay, shared by the team; every item remembers its queuer. The head is paid when it starts, runs for `build_time_s / max(production_min_speed, power_ratio)` and spawns the unit for the queuer; a head over the unit cap blocks with `CAP_REACHED`. Cancel refunds `cancel_refund_assembly` of a paid head. GD-17 adds `LaunchBay` (rally points; a produced ship is parked DOCKED on top of its Shipyard and leaves `economy.launch_delay_s` (3 s) after completion) and `AutoReplenish` (per-player unit targets). Not here: landing on and servicing at pads (GD-15). |
| Lane owner tier | Sonnet against this file (Opus review) |
| May depend on | `core`, `content`, `sim` (incl. `sim/world/`; `sim/economy/` `Economy`) |
| Must never touch | Nodes, `net`, `presentation`, `ui`, `sim_ai`; no `await`, signals, `Thread`, autoloads, RNG |
| Autoloads used | None |
| Status | implemented (TA-19, 2026-10-14; GD-17 2026-10-20: launch delay, rally, auto-replenish); `EconomyHub` steps it, `LocalSimView.production_queue` / `production_progress01` read it |

## Public API

```gdscript
class_name Production extends RefCounted
const NO_ITEM: int;  const CAP_UNITS: int                                    # -1; 0 (CAP_REACHED `b`)
func _init(store: EntityStore, players: PlayerTable, defs: WorldDefs, rules: MatchRules, events: SimEvents, economy: Economy, applier: CommandApplier)
func queue_max() -> int;  func length(factory: int) -> int;  func queuer(factory: int, i: int) -> int   # factory = entity slot; queuer -1 when there is no item i
func queue_of(factory: int) -> PackedInt32Array;  func progress01(factory: int) -> float               # unit def_ids head first; head progress
func can_make(factory_def: int, unit_def: int) -> bool                       # the unit's `produced_at`
func is_factory(factory_def: int) -> bool                                    # (GD-17) some unit is produced at this structure def
var launch: LaunchBay;  var replenish: AutoReplenish                         # (GD-17) owned here, stepped by `step`, serialized after the queue arrays
func enqueue(factory: int, player: int, unit_def: int, count: int) -> bool;  func cancel(factory: int, i: int) -> void;  func forget(factory: int) -> void
func step(t: int, dt: float) -> void                                         # step 10
var q_def: PackedInt32Array;  var q_player: PackedByteArray;  var q_len: PackedByteArray;  var started: PackedByteArray;  var paid_ore: PackedInt32Array;  var paid_ice: PackedInt32Array
func write_state(buf: StreamPeerBuffer) -> void;  func read_state(buf: StreamPeerBuffer) -> bool   # S4
```

```gdscript
class_name LaunchBay extends RefCounted                                      # GD-17: rally points + the launch delay
func set_rally(factory: int, p: Vector3) -> void;  func has_rally(factory: int) -> bool;  func rally_of(factory: int) -> Vector3;  func pending() -> int
func forget(factory: int) -> void;  func dock(u: int, f: int, tick: int) -> void;  func send_ground(u: int, f: int, owner: int, tick: int) -> void
func step(t: int) -> void;  func write_state(buf: StreamPeerBuffer) -> void;  func read_state(buf: StreamPeerBuffer) -> bool
var rally: PackedVector3Array;  var rally_set: PackedByteArray;  var l_ship: PackedInt32Array;  var l_due: PackedInt32Array;  var l_pad: PackedInt32Array
class_name AutoReplenish extends RefCounted                                  # GD-17: TOGGLE_AUTO_REPLENISH targets
const SPAN: int;  const PAYLOAD_PAIR: int;  const PAYLOAD_PAIRS_MAX: int;  var target: PackedByteArray   # [player * SPAN + def_id]
func payload_ok(payload: PackedByteArray) -> bool;  func apply(player: int, payload: PackedByteArray) -> void;  func target_of(player: int, def_id: int) -> int
func step(t: int) -> void;  func write_state(buf: StreamPeerBuffer) -> void;  func read_state(buf: StreamPeerBuffer) -> bool
```

Queue items are `[factory_slot * queue_max + i]`; head progress is the factory's `timer_a` (seconds of work).

## Invariants

- P1 (S13) A queue never holds more than `queue_max` items: `enqueue` refuses a batch that would pass it, the validator rejects it with `REJECTED_CAP`, step 1 re-checks.
- P2 Cost is paid when an item starts (`Economy.try_pay`); until then the head waits with one WAITING_FOR_ORE / ICE / SPEND_LOCKED alert per wait. PRODUCE is rejected `REJECTED_LOCKED` while the early share lock would forbid the batch (R0 C3-08).
- P3 Speed is `max(production_min_speed, power_ratio(team))`; the unit appears when progress reaches `build_time_s` of the queuer's resolved def, owned by the queuer (doctrine and caps are theirs).
- P4 A head that would exceed `caps.units` for its queuer (at start or at completion) blocks the queue: one CAP_REACHED event (`a` = player, `b` = `CAP_UNITS` 0, team -1; 04 s3.6 cap kind) and one ALERT PRODUCTION_BLOCKED_CAP per block; nothing is paid while blocked at start.
- P5 (S12) Cancel rights follow the queuer: `queuer(factory, i)` is the owner, a teammate may cancel when that player is disconnected, eliminated or a bot. Cancelling item 0 after its start refunds `cancel_refund_assembly` of the payment; unpaid items refund nothing; the spent-Ore ledger falls with the refund.
- P6 A destroyed factory drops its queue without refund (`forget`, from `EconomyHub.on_death`) and its rally point.
- P7 A produced ship is parked DOCKED (`link` = the factory, nose along the factory `up`, zero velocity) just outside the factory's bounding sphere and leaves exactly `launch_delay_s` after completion: DOCKED cleared, velocity `launch_speed_mps` along the pad normal, one LAUNCHED event (`a` ship, `b` factory); a ship that dies while parked never launches.
- P8 Rally: SET_RALLY (the factory owner's own finished factory, finite non-zero position) stores a point; the produced unit then takes a standing `MOVE` to it issued by its owner (ground units at spawn, ships at launch), else it keeps AUTO.
- P9 Auto-replenish: every `auto_replenish_period_s` a player whose alive + queued count of a def is below the target gets one item appended to the least-loaded finished factory of the team that makes it (lowest slot on ties); nothing is appended into a full queue, at the unit cap or while the early share lock would forbid the cost. The roster of TOGGLE_AUTO_REPLENISH replaces the player's targets; at most 8 pairs.

## Data owned

Queue arrays per factory entity slot (main range); `LaunchBay` rally points per factory slot and the pending launches (compact list, dock order); `AutoReplenish.target` per player and unit def. Head progress in the entity store's `timer_a`.

## Events emitted / consumed

Emits CAP_REACHED, ALERT (WAITING_FOR_ORE, WAITING_FOR_ICE, SPEND_LOCKED, PRODUCTION_BLOCKED_CAP), LAUNCHED and, through `CommandApplier.spawn`, SPAWN. Consumes PRODUCE / CANCEL_PRODUCE / SET_RALLY / TOGGLE_AUTO_REPLENISH via `EconomyHub`.

## Performance budget

03 s4.2 row "economy" (0.8 ms p95): `step` returns at once when no item is queued, no launch is pending and no target is set; the replenish scan is O(units + structures) once per period (1 s) only while a target is set; otherwise O(structures) plus O(units) once per tick only while a head is starting or blocked.

## Test entry points

`godot/test/unit/sim/production/test_production.gd`: queue cap 5 (P1), payment at start and timing (P2, P3), power speed, CAP_REACHED (P4), S12 cancel rights and refunds (P5), the early share lock until 2:00. GD-17: `test_launch_bay.gd` (P7, P8, the 23 s Dart), `test_auto_replenish.gd` (P9), `test_team_spend_lock.gd` (4-player team lock).
