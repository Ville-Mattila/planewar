# sim/world - MODULE.md

Contract for `godot/src/sim/world/**`: the helpers of the tick driver `SimWorld` (TA-18; 03 s3.5, s4.1, s4.4; R0 B.5).
R0 B.9 A-21 split: `SimWorld` and every type other lanes may name stay in `sim/MODULE.md`; this subsystem holds the
lane-internal classes `SimWorld` composes. A change to "Public API" or "Invariants" is a contract change: contract tests
first, same PR (ADR-11); `tools/gen_module_api.py --check` must pass; <= 300 lines (ADR-14).

| Field | Value |
|---|---|
| Responsibility | Step 1 command intake and application (validation S10 / S12, the pending queue; control transitions are `sim/control/`'s), step 5 ship motion, step 6 projectile motion, the per-row profiler, the player / team side tables, input slots, match clock, events array, injected defs, state bytes for S4. Not a public surface: other lanes reach all of it through `SimWorld`, `SimView` and `CommandSinkBase` (sim/MODULE.md). |
| Lane owner tier | Opus (sim lane); Sonnet for recipes against this file |
| May depend on | `core`, `content`, `sim` (R0 B.4: inside the sim module) |
| Must never touch | Nodes, `net`, `presentation`, `ui`, `sim_ai`; no `await`, signals, `Thread`, autoloads (D2, D3) |
| Autoloads used | None |
| Status | implemented (TA-18, 2026-10-14). AI-02 (2026-10-14) moved the control transitions and ORDER intake to `ControlMachine` (`sim/control/MODULE.md`); the S4 byte format is interim until TA-21 |

## Public API

Lane-internal: named by `sim/` code and sim tests only (never in `tools/deps.json` named types). `ProjectileMotion` is
lane-internal by decision (TA-18 / TA-43 follow-up): clients and `sim_ai` call `Kinematics.step_projectile` directly.

```gdscript
class_name CommandIntake extends RefCounted                                  # the pending queue (<= 256 / tick) + the one entry of apply_command and SimSink.submit
var pending: Array[Command];  var economy: EconomyHub                        # (TA-19) BUILD / CANCEL_BUILD / PRODUCE / CANCEL_PRODUCE are routed to it in step 1
func submit(cmd: Command) -> CommandResult;  func apply_all(tick: int) -> void
func submit_system(cmd: Command) -> CommandResult                           # (TA-59) SimSink's path for ORDER + FLAG_PREPEND: queued with target SYSTEM (-1), player kept, issuer -1; survives S4
func write_state(buf: StreamPeerBuffer) -> void;  func read_state(buf: StreamPeerBuffer) -> bool
class_name PoseReader extends RefCounted                                      # (TA-59, A-73) LocalSimView.read_poses body
static func read(store: EntityStore, proj: ProjectileStore, ids: PackedInt32Array, pos: PackedVector3Array, rot: PackedVector4Array) -> int
class_name CommandValidator extends RefCounted                               # S10 rate + state rules, S12
const RATE_PER_S: int; const BURST: int; const QUEUE_MAX: int;  var order_rules: OrderRules
var build: Build; var production: Production; var last_reject: int   # (TA-19) set by EconomyHub: BUILD -> can_place (REJECTED_PLACEMENT + reject), PRODUCE -> team factory, queue room, REJECTED_LOCKED, S12 by queuer
func validate(cmd: Command, tick: int, ended: bool, queued: int) -> CommandResult   # rate (bucket charged), phase, then check()
func validate_system(cmd: Command, ended: bool, queued: int) -> CommandResult        # (TA-59) system ORDER (target SYSTEM): phase, queue bound, active issuer slot, no token; check() then allows RETURN on own-team units only
func check(cmd: Command) -> int                                              # pure state rules; CommandResult.Code; re-run in step 1
func begin_tick() -> void;  func write_state(buf: StreamPeerBuffer) -> void;  func read_state(buf: StreamPeerBuffer) -> bool
class_name CommandApplier extends RefCounted                                 # step 1: control kinds and ORDER to ControlMachine, the rest here
const DEATH_CAUSE_DEBUG: int;  var dying: PackedInt32Array
func store_pilot(cmd: Command) -> void;  func apply(cmd: Command, tick: int) -> void   # store_pilot also flags the input fresh (05 C13)
func order_move(s: int, issuer: int, point: Vector3, tick: int) -> void       # (GD-17) rally: a standing MOVE for entity slot `s` through ControlOrders
func kill(s: int) -> void;  func resolve_deaths(tick: int) -> void          # resolve_deaths: ControlMachine.on_death (C15), then DEATH
func spawn(def_id: int, owner: int, team: int, p: Vector3, v: Vector3, fwd_in: Vector3, tick: int) -> int   # slot or -1; SPAWN event
class_name CommandPayload                                                    # sim form of Command.payload (04 s2.5 order; f64 positions / pilot axes)
const ORDER_MAX_IDS: int; const ORDER_MAX_POINTS: int; const PILOT_BYTES: int; const DEBUG_SPAWN_BYTES: int; const DEBUG_SET_BYTES: int
const SET_HP: int; const SET_FUEL: int; const SET_KILL: int
static func read_order(cmd: Command, spec: OrderSpec, ids: PackedInt32Array) -> bool;  static func read_pilot(cmd: Command, out: PilotInput) -> bool
static func u8_at(cmd: Command, off: int) -> int;  static func u16_at(cmd: Command, off: int) -> int;  static func u32_at(cmd: Command, off: int) -> int
static func v3_at(b: PackedByteArray, off: int) -> Vector3
static func cancel_build(player: int, structure: int) -> Command;  static func cancel_produce(player: int, factory: int, queue_index: int) -> Command
static func handover(player: int, id: int, to_slot: int) -> Command;  static func simple(player: int, kind: Command.Kind, target: int) -> Command
static func debug_spawn(player: int, def_id: int, owner: int, team: int, p: Vector3, v: Vector3, fwd: Vector3) -> Command
static func debug_set(player: int, target: int, field: int, value: float) -> Command
class_name ShipMotion extends RefCounted                                     # step 5 ships: step_ship with one ShipState scratch, DOCKED skipped (A-41)
func step(t: int, dt: float) -> void                                         # terrain contacts -> Collision.report_terrain(slot, tick, hit_normal_speed)
class_name ProjectileMotion extends RefCounted                               # step 6: straight inline, else step_projectile(out = one reused scratch)
func step(tick: int, dt: float) -> void                                      # guided re-aim within turn_rate_dps; ttl expiry frees
class_name TickProfiler extends RefCounted                                   # 03 s4.4 rows, ms; row 0 is ServerSession's, 8b inside ROW_COLLISION
const ROWS: int; const ROW_TRANSPORT: int; const ROW_COMMANDS: int; const ROW_AI: int; const ROW_PATHING: int; const ROW_KINEMATICS: int
const ROW_PROJECTILES: int; const ROW_SPATIAL: int; const ROW_COLLISION: int; const ROW_TERRAIN_8B: int; const ROW_COMBAT: int
const ROW_ECONOMY: int; const ROW_VISION: int; const ROW_EVENTS: int; const ROW_TOTAL: int;  var enabled: bool; var rows: PackedFloat32Array
func begin() -> void;  func lap(row: int) -> void;  func finish() -> void
class_name PlayerTable extends RefCounted                                    # 03 s3.2 PlayerState / TeamState side tables
const SLOTS: int; const TEAMS: int
func is_active(slot: int) -> bool;  func cancel_delegable(slot: int) -> bool   # S12: disconnected, eliminated or a bot
func members(t: int, out: PackedInt32Array) -> void;  func write_state(buf: StreamPeerBuffer) -> void;  func read_state(buf: StreamPeerBuffer) -> bool
class_name InputSlots extends RefCounted                                     # per-entity (main range) and per-player PilotInput slots, f64 axes
const ENTITY_SLOTS: int
func set_entity(slot: int, input: PilotInput) -> void;  func read_entity(slot: int, out: PilotInput) -> void;  func clear_entity(slot: int) -> void
func set_player(player: int, input: PilotInput) -> void;  func clear_player(player: int) -> void;  func copy_player_to_entity(player: int, slot: int) -> void
func write_state(buf: StreamPeerBuffer) -> void;  func read_state(buf: StreamPeerBuffer) -> bool
class_name MatchState extends RefCounted                                     # tick, exposure / end ticks, winner; shared by world, intake, view
var tick: int; var exposure_tick: int; var ended_tick: int; var winner_team: int
func ended() -> bool;  func write_state(buf: StreamPeerBuffer) -> void;  func read_state(buf: StreamPeerBuffer) -> bool
class_name SimEvents extends RefCounted                                      # the event array; emit stamps `tick` (S5); drain(keep) queues the batch for the hook (`pending`, A-71); forward(hook) delivers it once at step 3; write_pending / read_pending (saved, format 9)
var list: Array[SimEvent]; var pending: Array[SimEvent]; var tick: int
func emit(kind: SimEvent.Kind, a: int, b: int, at: Vector3, value: float, team: int, reason: int = -1) -> SimEvent;  func drain(keep: bool = false) -> Array[SimEvent]
func forward(hook: SimAiHook) -> void;  func write_pending(buf: StreamPeerBuffer) -> void;  func read_pending(buf: StreamPeerBuffer) -> bool
class_name WorldDefs extends RefCounted                                      # injected ContentSet + ResolvedDefs per player slot + flat tables
const NEUTRAL: int;  var content: ContentSet; var rules: RulesDef; var common: FlightCommonDef; var economy: EconomyDef; var base: ResolvedDefs
var projectile_radius: PackedFloat32Array; var pad_radius_by_def: PackedFloat32Array; var bomb_mult_by_def: PackedFloat32Array; var fuse_delay_s: PackedFloat32Array; var unsupplied_rate_mult: float; var vision_hz: int; const DEFAULT_VISION_HZ: int; var straight: PackedByteArray; var turn_rad_per_s: PackedFloat32Array
var ship_table: Array[ShipDef]; var ship_count: int
func resolve(slot: int, doctrine: StringName) -> bool;  func resolved(owner: int) -> ResolvedDefs;  func ship(owner: int, def_id: int) -> ShipDef
func entity_kind(def_id: int) -> int;  func hp_max(owner: int, def_id: int) -> float;  func cost(owner: int, def_id: int) -> Vector2i
func possessable(def_id: int) -> bool;  func radius_of(def_id: int) -> float;  static func build_cell_m() -> float
class_name TeamStats                                                         # LocalSimView's team aggregates, O(structures), never on the tick path
static func stockpile_cap(store: EntityStore, defs: WorldDefs, team: int) -> Vector2i;  static func power_balance(store: EntityStore, defs: WorldDefs, team: int) -> Vector2
static func tech_available(store: EntityStore, defs: WorldDefs, team: int, def_id: int) -> bool;  static func has_structure(store: EntityStore, team: int, def_id: int) -> bool
static func count_owned(store: EntityStore, player: int, live: PackedInt32Array) -> int;  static func fill_player(v: PlayerStateView, pl: PlayerTable, slot: int) -> void
class_name EconomyHub extends RefCounted                                     # (TA-19) composes Build, Economy, Construction, Production; routes their commands, deaths and step 10
var build: Build; var economy: Economy; var construction: Construction; var production: Production
static func handles(kind: Command.Kind) -> bool;  func apply(cmd: Command) -> void;  func begin_tick(t: int) -> void;  func step(t: int, dt: float) -> void;  func on_death(s: int) -> void
func spawn_start_kit(slot: int, centre: Vector3, toward: Vector3, tick: int) -> bool;  func write_state(buf: StreamPeerBuffer) -> void;  func read_state(buf: StreamPeerBuffer) -> bool
class_name StateIO                                                           # S4 bytes: named properties via put_var / get_var, type-checked
static func put_props(buf: StreamPeerBuffer, o: Object, names: PackedStringArray) -> void;  static func get_props(buf: StreamPeerBuffer, o: Object, names: PackedStringArray) -> bool
static func size_of(v: Variant) -> int;  static func sizes_ok(o: Object, names: PackedStringArray, n: int) -> bool;  static func ints_in(v: PackedInt32Array, count: int, lo: int, hi: int) -> bool   # (TA-21) range checks of restored state
```

## Invariants

- W1: `CommandValidator.check` is pure; `CommandApplier.apply` re-runs it, so a command that turned invalid after `validate` (a second POSSESS of the same entity, a dead target) has no effect (S10). Same-tick POSSESS claims are rejected at `validate` already.
- W2: the token bucket holds `BURST * tick_hz` units, refills `RATE_PER_S` per tick and charges `tick_hz` per command: integer arithmetic, so the rate is exact and deterministic. PILOT_INPUT is exempt.
- W3: `SimEvents.emit` stamps the tick `SimWorld.step()` set before step 1; nothing outside `step()` emits (S5).
- W4: `ShipMotion` and `ProjectileMotion` allocate nothing per entity: one `ShipState`, one `PilotInput`, one `ProjectileState` scratch; each SoA array is copied at most once per tick (copy-on-write of the local handle).
- W5: every class holding state has `write_state` / `read_state`; `SimWorld.serialize` writes them in a fixed order and `deserialize(serialize())` reproduces each byte for byte (S4).
- W6: Control state, overlay and `ReleaseReason` are `ControlMachine`'s enums (AI-02, sim/control/MODULE.md CM1); nothing here redefines them.
- W7: `EconomyHub` owns no state of its own; `on_death` runs for every dying structure before the deferred free (footprint, site, queue), so a freed slot never keeps a footprint or a queue.

## Data owned

`PlayerTable` (players, team pools), `InputSlots`, `MatchState`, the token buckets and same-intake POSSESS claims, the pending command queue, the deferred death list (empty between ticks), the profiler rows, the event list. Nothing on disk.

## Events emitted / consumed

`CommandApplier`: SPAWN, DEATH, CAP_REACHED (debug spawn over the cap); `EconomyHub` (with `Construction`, `Economy`, `Production`): BUILD_STARTED, BUILD_DONE, STRUCTURE_LOST, LOW_POWER, CAP_REACHED (a production head over the unit cap), ALERT (BUILD_DONE, STORAGE_FULL, LOW_POWER, WAITING_FOR_ORE / ICE, SPEND_LOCKED, PRODUCTION_BLOCKED_CAP); the control events (POSSESSED, RELEASED, ...) are `ControlMachine`'s (sim/control/MODULE.md). `SimWorld` step 10: CORE_EXPOSURE, MATCH_END. Consumes every `Command.Kind`.

## Performance budget

03 s4.2 rows 1-2 (0.4 ms), 5 (3.0 ms), 6 (2.5 ms) at 1,200 entities + 2,000 projectiles; measured by `perf_tick.gd --full` (PERF_ROW lines).

## Test entry points

`godot/test/unit/sim/test_command_validator.gd` (S10, S12, W1, W2), `godot/test/unit/sim/build/test_construction.gd` (EconomyHub routing, W5 for the economy section), `godot/test/unit/sim/test_sim_world.gd` (W3, steps 5, 6, 9, 10),
`godot/test/unit/sim/test_serialize.gd` (W5), `godot/test/unit/sim/test_enums.gd` (W6), `godot/test/unit/sim/test_command_payload.gd`, `godot/test/sim/test_tick_scenario.gd`, `godot/test/perf/perf_tick.gd`.

## How to add X (recipes for the cheapest tier)

- **A command kind's application:** add its branch to `CommandApplier.apply` (or hand it to its system), its state rule to `CommandValidator.check`, a validator test row and a scenario step.
- **A profiler row user:** call `_profiler.lap(TickProfiler.ROW_x)` right after the step in `SimWorld.step()`; never time inside a hot loop.

## Open items

- Def fields exist since R0 B.11 A-51 (`rules.json` `command_rate_per_s` / `command_burst`, `shooter_grace_ticks`, `cut_ladder` rungs 1-6 and 8; `match_rules.json` `arc_open_divisor` / `arc_expand_divisor`; the uplink margin, request TTL and echo window are `ControlMachine`'s, `sim/control/MODULE.md`). **TA-49** (landed) reads them: `CommandValidator._init`, `MatchRules.from_defs` / `adopt_match_def` (also on deserialize), `ControlMachine.configure`, `SimWorld` (`collision.shooter_grace_ticks`), `Pathing.from_rules`; `CommandValidator.RATE_PER_S` / `BURST`, `MatchRules._ARC_*_DIV` and `Collision.shooter_grace_ticks`'s caller value stay as documented defaults (A-43 pattern, no symbol removed). `set_budget_profile` applies rung 3 (`ProjectileStore.live_cap`) and exposes rung 8 as `SimWorld.path_expansions_per_tick()`, which TA-50 assigns to `Pathing.expansions_per_tick` once Pathing is wired; rungs 1 / 2 / 4 / 5 / 6 apply when their systems land (AI-04, TA-37, Collision tier-A sets, Economy caps).
- Interim, replaced by their owners: ORDER ghost-age / visibility checks (AI-15); DEBUG deaths (DEATH cause; step-9 damage landed with GD-08 and weapon fire with GD-36, `sim/combat/MODULE.md`; `CommandApplier.spawn` loads the doctrine-resolved ammo / bombs / rockets / tower pool); SURRENDER is validated and accepted but applied by GD-20. BUILD, PRODUCE, CANCEL_*, SET_RALLY (GD-17: payload 3 x f64, a finished factory of the issuer's team, A-81) and TOGGLE_AUTO_REPLENISH (GD-17: `u8 enabled`, then up to 8 pairs of `u16 def, u8 count`) go to `EconomyHub`.
- TA-21 compacts the S4 format (live slots only, ~150 KB at 1,200 entities) into `sim/serialize.gd`; today every slot is written (486 KB at 1,200 entities + 2,000 projectiles; serialize 2.2 ms, deserialize 35 ms incl. map load).
- Assist substitution (step 4) is empty until AI-10; rows 8b, 11 and 12 read 0. Step 3b runs `Pathing.advance()` (TA-50); the S4 bytes carry `Pathing.write_state` after the orders.
