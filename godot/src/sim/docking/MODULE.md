# sim/docking - MODULE.md

Contract for `godot/src/sim/docking/**`: landing on a pad, pad queues and the resupply service (GD-15; 03 s6.4, 02 s2.2,
s2.3, s17.1; R0 B.5 landing rule, C3-13; A-21 split of `sim/MODULE.md`). A change to "Public API" or "Invariants" is a
contract change: contract tests first, same PR (ADR-11); `tools/gen_module_api.py --check` must pass; <= 300 lines (ADR-14).

| Field | Value |
|---|---|
| Responsibility | Turning step 8's PAD contacts into landings (pad-free rule, hull damage of the damage band, crash, docked pose, grade inputs: manual / hot / dead stick, LANDING then DOCKED), the per-pad queue of waiting ships, the three parallel service timers with their Ice / Ore costs and pauses, SERVICED, releasing a ship whose pad is gone. Not here: the landing volume and band (`Collision`), the grade formula and per-ship log (`sim/scoring/`), points (GD-27), the Shipyard launch (`LaunchBay`), the docked launch of a service pad (contract question CQ-1), auto-dock steering (`Assist.auto_dock`, AI-10 / NET-18 wire it and call `PilotTrack.note_assist`). |
| Lane owner tier | Opus (sim lane); Sonnet against this file with an Opus review |
| May depend on | `core`, `content`, `sim` (incl. `sim/world/` `WorldDefs`, `SimEvents`, `PlayerTable`, `InputSlots`, `PadQueries`, `StateIO`, `CommandApplier`; `sim/combat/` `DamageSink`; `sim/economy/` `Economy`; `sim/scoring/`; `sim/control/` `ControlMachine` enums; `sim/orders/` `OrderSpec`) |
| Must never touch | Nodes, `net`, `presentation`, `ui`, `sim_ai`; no `await`, signals, `Thread`, autoloads, RNG |
| Autoloads used | None |
| Status | implemented (GD-15, 2026-10-23); composed by `EconomyHub` (`docking`), driven by `SimWorld`: `track` step 4, `land` end of step 9, `step` step 10 after Production. State in the economy section (format 13) |

## Public API

Lane-internal: other lanes read docking through `SimView` (`dock_state`, `service_state`, `service_progress`, `pad_queue`,
`pad_occupant`, `landing_grade_last`) and the LANDING / DOCKED / SERVICED / ALERT events.

```gdscript
class_name Docking extends RefCounted                                        # EconomyHub.docking
var queue: PadQueue; var service: PadService; var landings: LandingLog; var grade: LandingGrade; var pilots: PilotTrack; var touchdown: Touchdown
func _init(store: EntityStore, players: PlayerTable, defs: WorldDefs, economy: Economy, events: SimEvents, applier: CommandApplier, hz: int) -> void
func track(inputs: InputSlots) -> void                                       # step 4, after AssistStep
func land(t: int, collision: Collision) -> void                              # end of step 9 (after Combat, before the deferred deaths)
func step(_t: int, dt: float) -> void                                        # step 10 after Production: release, service pass, queue
func service_progress(id: int) -> Vector3;  func pad_queue(pad: int) -> PackedInt32Array;  func landing_grade_last(id: int) -> int   # SimView bodies
func write_state(buf: StreamPeerBuffer) -> void;  func read_state(buf: StreamPeerBuffer) -> bool

class_name Touchdown extends RefCounted                                      # D1-D5
var landed: int                                                              # landings resolved by the last `land` (perf counter, not state)
func _init(store: EntityStore, defs: WorldDefs, events: SimEvents, sink: DamageSink, queue: PadQueue, service: PadService, landings: LandingLog, grade: LandingGrade, pilots: PilotTrack, hz: int) -> void
func land(t: int, collision: Collision) -> void

class_name PadQueue extends RefCounted                                       # 03 s3.2 `pad_queues`, D6
const PER_PAD: int                                                           # 8 waiting ships per pad
var q_pad: PackedInt32Array; var q_ship: PackedInt32Array                    # pairs in arrival order (saved)
func _init() -> void
func of(pad: int) -> PackedInt32Array;  func head(pad: int) -> int;  func count(pad: int) -> int;  func pad_of(ship: int) -> int
func update(wish_ship: PackedInt32Array, wish_pad: PackedInt32Array, n: int) -> void
func remove(ship: int) -> void
func write_state(buf: StreamPeerBuffer) -> void;  func read_state(buf: StreamPeerBuffer) -> bool

class_name PadService extends RefCounted                                     # D7-D10
const BIT_FUEL: int; const BIT_AMMO: int; const BIT_REPAIR: int; const BIT_WAIT_ICE: int; const BIT_WAIT_ORE: int; const BIT_FAST: int; const BIT_DONE: int
var svc_gen: PackedInt32Array; var svc_bits: PackedByteArray                 # per main-range slot: the stay's generation and BIT_* (saved)
var serviced: int                                                            # ships given service in the last pass (perf counter, not state)
func _init(store: EntityStore, defs: WorldDefs, economy: Economy, events: SimEvents, landings: LandingLog, grade: LandingGrade) -> void
func begin(s: int) -> void                                                   # a new stay (landing, or the first pass that meets the docked ship)
func open() -> void;  func close() -> void;  func serve(s: int, pad: int, dt: float) -> void   # one pass: open, serve each, close
func progress(s: int) -> Vector3                                             # (fuel01, rearm line, hp01)
func write_state(buf: StreamPeerBuffer) -> void;  func read_state(buf: StreamPeerBuffer) -> bool

class_name PilotTrack extends RefCounted                                     # D3 manual flag; per player slot
var h_id: PackedInt32Array; var h_has: PackedByteArray; var h_pos: PackedVector3Array   # saved
var dock_held: PackedByteArray                                               # DOCK held this tick (step 4; derived, not saved)
func _init(store: EntityStore, players: PlayerTable) -> void
func track(inputs: InputSlots) -> void;  func note_assist(s: int) -> void
func manual(id: int, pad_pos: Vector3, pad_up: Vector3, window_m: float) -> bool
func write_state(buf: StreamPeerBuffer) -> void;  func read_state(buf: StreamPeerBuffer) -> bool
```

Constants: `flight_common` (landing_safe_* / landing_damage_* bands via `Collision`, `auto_dock_radius_m` as the queue
radius), `scoring.json` `landing` (+ `landing_grade.manual_window_m`), `ships.json` (`fuel_s`, `refuel_ice`,
`refuel_time_s`, `rearm_time_s`, `repair_time_s`, `primary` / `secondary`, `hp`), `weapons.json` `rearm_ice`,
`economy.json` `repair_ore_per_hp`, `structures.json` `pad_radius_m` / `pads`. Slots in the API are entity slots.

## Invariants

- D1 Landing (03 s6.4, A-31). Every tick, each PAD contact of step 8 (contact order = ascending ship slot) whose ship is
  standing (not killed in step 9) and not DOCKED is judged. The pad must be a live, finished (`F_BUILDING` clear) service
  pad (`pad_radius_m` > 0 with `pads` > 0; never a `launch_pad` structure) with no ship docked on it and either no queue
  or this ship at its head; otherwise the ship holds and nothing happens, unless its band is DESTROY (then it crashes:
  the band is physics, not permission). Two arrivals on one free pad in one tick: the first in contact order lands.
- D2 Grade inputs from the contact: v_vert = max(post-move descent, the tick's terrain hit_normal_speed) (Collision, GD-15:
  Kinematics' push-out zeroes the normal speed), v_horiz, tilt (thrust axis to the pad normal), offset (pad frame).
  Hot = an enemy-team ship within `hot_radius_m` of the pad or the ship hit within `hot_window_s` (`last_damage_tick` > 0).
  Dead stick = fuel01 < `dead_stick_fuel01` at touchdown.
- D3 Manual (05 s5.5, 02 s17.1). A landing is manual iff the ship is POSSESSED and the tracking player's last non-human tick
  (the tick before the possession; every tick with an overlay on the possessed ship, i.e. LINK_BRIDGE; every
  `note_assist`) is absent or farther than `manual_window_m` (150 m) horizontally from the pad. A possession that began
  while DOCKED has no autopilot approach. An unpossessed (autopilot) landing is never manual (grade AUTO).
- D4 Outcome, in this order: DAMAGE band -> `DamageSink.damage(hp_max * max(ratio_vert, ratio_hor, ratio_tilt))`, each
  ratio = clamp((x - safe) / (damage - safe)) (HIT); a hull emptied -> CRASH. DESTROY band -> `DamageSink.destroy`
  (deferred death at the end of this step 9, DEATH the same tick). `LandingLog.record`, then LANDING (a ship, b pad,
  value q, pos the ship, team the ship's; extra = [grade, round(q x 255), flags bit0 manual / bit1 hot / bit2 dead stick,
  v_vert and v_horiz in 0.1 m/s clamped 0..255]); then, unless CRASH: DOCKED | LANDED, `vel` and `rates` 0, `pos` =
  pad.pos + pad.up x radius (A-82 socket), fwd = pad.up (nose up), body up = its old up in the pad plane, `link` = pad,
  the queue entry dropped, a new service stay, DOCKED (a ship, b pad).
- D5 No grade without content: a ContentSet without a usable `scoring` block lands nothing (`grade.n_vert` = 0).
- D6 Queue (03 s3.2, s6.4). A ship wants a pad when its head order is RETURN (`order_kind`) or its pilot holds DOCK
  (`PilotTrack.dock_held`). It waits for the nearest live pad of its team that is busy (a ship served on it this tick) or
  already queued, whose centre is within `auto_dock_radius_m` of the ship (3-D; ships farther from the moon's centre than
  the highest such pad + the radius are skipped). Entries keep their arrival order while they still wait for the same
  pad; new waiters are appended in ascending ship slot, at most `PER_PAD` per pad; a ship that docks, dies, loses the wish
  or leaves the radius drops out. Updated once per step 10; read by `Touchdown` (head) and `SimView.pad_queue`.
- D7 Service (02 s2.3) runs in step 10 for every DOCKED ship whose `link` is a live finished service pad; three
  independent timers (refuel, rearm, repair; PadService header for the laws). Whole-refuel cost `ceil(refuel_ice x
  fuel_missing01)` Ice, whole-repair cost `ceil(hp_missing x repair_ore_per_hp)` Ore (E7's telescoping rule), rearm
  `rearm_ice` per secondary round (gun rounds free). Time scales with what is missing; a full service from empty takes
  max(refuel_time_s, rearm_time_s, repair_time_s x missing share) (test_service table).
- D8 Repair bonus: a stay that starts after a FAIR / CLEAN / ACE landing (`LandingLog`) repairs in `repair_time_s x
  repair_time_mult` (0.9).
- D9 Pause: a timer whose tick cost the team pool cannot pay does not advance (no partial spend, `try_spend`); ALERT
  WAITING_FOR_ICE / WAITING_FOR_ORE (a kind, b ship, pos pad, team the ship's, extra[0] its owner) once per pause start.
  SERVICED (a ship, b pad, extra[0] = given bits fuel 1 / ammo 2 / repair 4) once per stay when all three are full.
- D10 A DOCKED ship whose `link` names a pad that is no longer alive is released in step 10 (DOCKED / LANDED cleared, `link` 0, no event;
  Kinematics moves it from the next step); one with `link` 0 is left alone. A ship on a `launch_pad` structure (Shipyard) is never served.
- D11 S4: queue, service records, landing log and pilot track are saved (economy section, format 13); a world reloaded
  mid-service continues byte-identically, events included (test_docking_s4). `dock_held` and the perf counters are
  derived, not state. `read_state` refuses malformed sizes, zero or duplicate queue entries, slots outside the main range.
- D12 Allocation: none per entity per tick (scratch arrays are members; the service pass writes the store arrays through
  local handles, one copy-on-write per pass); `pad_queue` and LANDING / SERVICED `extra` allocate (list getter, events).

## Data owned

`PadQueue` (pairs), `PadService` per-slot stay records, `PilotTrack` per player slot; `LandingLog` (sim/scoring) is
created here. A docked ship's `EntityStore.timer_a` holds its rearm line (0..1; structures use it for build progress). Step scratch (docked list, wishes, candidate pads with per-slot marks) is not state.

## Events emitted / consumed

Emits LANDING (29), DOCKED (4), SERVICED (5), ALERT (WAITING_FOR_ICE 22, WAITING_FOR_ORE 23) and, through `DamageSink`,
HIT (landing damage). Consumes Collision's PAD contacts (step 8), Kinematics' terrain reports (via Collision).

## Performance budget

03 s4.2 row 10 (0.8 ms p95; SL-1 grade < 0.05 ms reserved) and row 9 for the landings. `test_docking_perf.gd` (PerfGate,
hard counters): one pass over the ships (~0.06 us per ship), ~2.5 us per ship in service, the queue O(wishes x same-team
busy or queued pads) after the altitude filter; a landing costs one O(ships) hot scan (~30 us at 688 ships). Numbers and
the `perf_tick.gd --full` delta in the GD-15 PR perf note.

## Test entry points

`godot/test/unit/sim/docking/test_touchdown.gd` (D1-D5), `test_pad_queue.gd` (D6), `test_service.gd` (D7-D10, the
02 s2.3 table for every ship), `test_docking_s4.gd` (D11, format 13 refusal), `test_docking_perf.gd` (D12, row 10 / 9),
helper `docking_test_kit.gd`; the SimView contract (`godot/test/unit/sim/contract/`) pins `service_progress`, `pad_queue`
and `landing_grade_last`; `godot/test/unit/sim/test_collision.gd` (D2 impact speed).

## How to add X

- **A service kind:** a timer in `PadService.serve` with its own BIT_*, a def field per ship (ADR-09), a row in the
  test_service table and a bit in SERVICED `extra[0]` (04 s3.6 `what`).
- **An assist that counts against manual (auto-dock wiring, AI-10 / NET-18):** call `Docking.pilots.note_assist(slot)` on
  every tick the assist substitutes the possessed ship's input.

## Open items (contract questions raised by GD-15)

- CQ-1 Docked launch from a service pad: 05 s2.5 "thrust >= 0.5 held for 0.3 s launches" and 02 s2.3 "an AUTO ship
  waits until fuel >= 50 %" have no def fields in R0 Part B (`launch_thrust_min`, `launch_hold_s`, `auto_launch_fuel01`),
  and the LAUNCHED of a ship still inside its pad volume would land it again next tick (needs a rule). Until ratified, a
  ship landed on a service pad stays DOCKED (no LAUNCHED from service pads; LaunchBay's Shipyard launch is unchanged).
- CQ-2 The crash pad damage (02 s2.2 "the pad takes 100 damage") has no def field; not applied.
- CQ-3 (needs net) LANDING flags bit2 = dead stick (04 s3.6 names bit0 manual, bit1 hot; the byte is unchanged in size).
