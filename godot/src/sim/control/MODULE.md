# sim/control - MODULE.md

Contract for `godot/src/sim/control/**`: 05's control-state machine (05 s2; AI-02; R0 C2-08, B.3; R0 B.10 A-44, A-45).
R0 B.9 A-21 split of `sim/MODULE.md`, whose Enumerations keep the frozen ordinals (control state, overlay, `ReleaseReason`).
A change to "Public API" or "Invariants" is a contract change: contract tests first, same PR (ADR-11); `tools/gen_module_api.py
--check` must pass; <= 300 lines (ADR-14).

| Field | Value |
|---|---|
| Responsibility | Every control transition of 05 s2.3 (C1-C18): POSSESS / RELEASE / REQUEST_POSSESS / HANDOVER, ORDER intake into the standing or pending queue, head completion and failure, the resume rule of a release, the silent-pilot rule (C13 / C14), ceiling release, invalidation, admin release, disconnect, death and match end; their guards (`CommandResult` codes of C6r and 04 V-REQ) and events. Sets overlays; does not execute them (`sim_ai` runs SAFETY / RECOVER_CEILING, `Assist.link_bridge` runs LINK_BRIDGE). Does not judge order completion (brains / AI-15 call `complete_head` / `fail_head`), does not own the queues' storage (`sim/orders/`) or the transport timeout (net, via `SimWorld.remove_player`). |
| Lane owner tier | Opus (05 lane writes it, Opus reviews) |
| May depend on | `core`, `content`, `sim` (incl. `sim/orders/`, `sim/world/` `PlayerTable`, `InputSlots`, `SimEvents`, `StateIO`) |
| Must never touch | Nodes, `net`, `presentation`, `ui`, `sim_ai`; no `await`, signals, `Thread`, autoloads (D2, D3) |
| Autoloads used | None |
| Status | implemented (AI-02, 2026-10-14); replaces TA-18's interim stand-ins in `CommandApplier` |

## Public API

`SimWorld` composes one `ControlMachine`; other lanes see its effects through `SimView` (`control_state`, `possessor`), the
events and `SimWorld.admin_release`. Lane-internal otherwise (not in `tools/deps.json` named types).

```gdscript
class_name ControlMachine extends RefCounted                                 # 05 s2; one per SimWorld
enum State { AUTO, ORDERED, POSSESSED }                                      # `control_state` u8 (R0 B.3)
enum Overlay { NONE, SAFETY, RECOVER_CEILING, LINK_BRIDGE }                  # `overlay` u8 (R0 B.3)
enum ReleaseReason { PLAYER, DEATH, CEILING, HANDOVER, DISCONNECT, MATCH, INVALID, ADMIN }   # R0 B.3; 04's RELEASED uses it unchanged
enum OrderFail { INVALID_TARGET, UNREACHABLE, STUCK, OVERRIDDEN, INVALID_ON_RESUME, NO_PAD, NO_AMMO }   # ORDER_FAILED reason, R0 B.3 order
const DECAY_TICKS: int                                                       # 10 = net InputBuffer.DECAY_TICKS (A-45)
const DECAY_FACTOR: float; const KEEP_BUTTONS: int                           # 0.5 per silent tick; BOOST | BRAKE held (A-44)
const REQUEST_TTL_S: int; const ECHO_WINDOW_S: int; const UPLINK_MARGIN_M: int   # 10 s, 10 s, 50 m (needs content)
var orders: ControlOrders
func _init(store: EntityStore, queue: OrderQueue, players: PlayerTable, inputs: InputSlots, events: SimEvents, ceiling_hard_m: float, tick_hz: int) -> void
func check_possess(p: int, t: int, claimed: bool) -> int                     # C6 / C6r, CommandResult.Code; pure
func check_release(p: int, t: int) -> int;  func check_request(cmd: Command) -> int   # C9; C8 / C10 (V-REQ); pure
func spectator(p: int) -> bool                                               # open slot, or team lost its last Core
func request_from(id: int) -> int;  func silent_ticks(p: int) -> int;  func last_input_tick(p: int) -> int
func apply(cmd: Command) -> void                                             # step 1: POSSESS, RELEASE, REQUEST_POSSESS, HANDOVER
func possess(p: int, s: int) -> void;  func release_player(p: int, reason: int) -> void   # C6; C9 / C11 / C12 / C15 / C16 / C18
func step_releases() -> void;  func admin_release(p: int) -> void            # step 1: C12 disconnect, C18 ADMIN (queued)
func release_all(reason: int) -> void;  func release_team(t: int) -> void    # C16 match end; C16 team lost its last Core
func note_input(p: int) -> void;  func step_inputs(tick: int) -> void        # PILOT_INPUT stored; step 2 C13 / C14
func control_check() -> void                                                 # step 3 start: C11, C18 INVALID, C17
func on_death(s: int) -> void                                                # step 9: C15
func write_state(buf: StreamPeerBuffer) -> void;  func read_state(buf: StreamPeerBuffer) -> bool

class_name ControlOrders extends RefCounted                                  # C1-C5, C7, the C9 resume rule
var queue: OrderQueue; var rules: OrderRules                                 # rules null: every order valid on resume
func _init(store: EntityStore, q: OrderQueue, players: PlayerTable, events: SimEvents, tick_hz: int) -> void
func room(s: int, flags: int) -> bool                                        # C3 guard (REJECTED_CAP when false)
func order(spec: OrderSpec, ids: PackedInt32Array) -> void                   # C1 / C2 (+ OVERRIDDEN echo) / C3 / C7
func complete_head(s: int) -> bool;  func fail_head(s: int, reason: int) -> bool   # C4 ORDER_DONE; C5 ORDER_FAILED
func resume(s: int) -> void;  func valid(s: int, spec: OrderSpec) -> bool    # C9: pending wins if any valid; INVALID_ON_RESUME drops
```

## Invariants

- CM1: `State`, `Overlay` and `ReleaseReason` ordinals equal sim/MODULE.md Enumerations (test_enums.gd); `ReleaseReason` is exactly R0 B.3's eight names; `OrderFail` follows the R0 B.3 ORDER_FAILED reason list. Append-only.
- CM2: Guards are pure and run twice (intake and step 1); a rejected command changes nothing. C6r order: DEAD, NOT_OWNER, NOT_POSSESSABLE (def or BUILDING), ALREADY_POSSESSED (possessor or same-intake claim), NO_RIGHTS (spectator), UPLINK (radius >= planet + `ceiling_hard_m` - 50). V-REQ failures are NO_RIGHTS; a HANDOVER from a non-pilot is NOT_OWNER; wrong payload size is MALFORMED.
- CM3: An entity has at most one possessor and a player at most one entity: `store.possessor[s] == p` iff `players.possessed[p] == id(s)`.
- CM4: Every release emits exactly one RELEASED (a = entity, b = old pilot, extra[0] = reason; HANDOVER adds extra[1] = new pilot) before any ORDER_FAILED of its resume; CEILING adds CEILING_RELEASE; C10 emits RELEASED, HANDOVER (b = new pilot, extra[0] = old), POSSESSED in that order.
- CM5: After a release the state is ORDERED iff the standing queue is non-empty (MATCH clears both queues: AUTO); overlay SAFETY (RECOVER_CEILING for CEILING, NONE for DEATH and for structures).
- CM6: Silent pilot (C13): silent ticks 1..DECAY_TICKS reuse the last input with pitch / yaw / roll x 0.5 per tick, thrust held, buttons & (BOOST | BRAKE); tick DECAY_TICKS + 1 sets LINK_BRIDGE and emits one ALERT(LINK_WEAK); the entity stays POSSESSED until C12. The possession tick itself is not silent. A fresh input clears LINK_BRIDGE (C14).
- CM7: Hand-over (C10) never replays the old pilot's input: both player slots and the entity slot start neutral, LINK_BRIDGE holds until the new pilot's first input, and no LINK_WEAK follows.
- CM8: No mutation outside `SimWorld.step()`: `admin_release` and `note_input` only set flags consumed in the next step (S1). Per-tick work loops over the 8 player slots only; nothing allocates per tick.
- CM9: `write_state` / `read_state` carry requests, silence counters, fresh-input and admin flags and lost teams, so `deserialize(serialize())` continues byte-identically (S4).

## Data owned

Per main-range slot: `_request_from` (u8, NONE_U8), `_request_tick`. Per player: `_last_input`, `_silent`, `_fresh`, `_admin`.
Per team: `_team_out`. It writes `EntityStore.control_state`, `possessor`, `overlay` (+ DIRTY_CONTROL), `PlayerTable.possessed`,
the player and entity input slots, and the `orders` side table through `OrderQueue`. Defs read: `rules.ceiling_hard_m`, `tick_hz`, `order_rules`.

## Events emitted / consumed

Emits POSSESSED, RELEASED (`ReleaseReason` in extra[0]), CEILING_RELEASE, HANDOVER, POSSESS_REQUESTED (b = requester, extra[0] =
pilot), ORDER_DONE (value = order kind), ORDER_FAILED (b = issuer, extra = [OrderFail, by]), ALERT PENDING_ORDER / HANDOVER_REQUEST /
LINK_WEAK (b = entity, extra[0] = the pilot slot the alert is for). Consumes POSSESS, RELEASE, REQUEST_POSSESS, HANDOVER, ORDER, PILOT_INPUT.

## Performance budget

03 s4.2 rows 1-2 (commands + inputs, 0.4 ms) and the control check inside row 3: `step_releases` + `step_inputs` + `control_check`
measure 15.5 µs per tick with 8 possessed ships (20,000-tick loop, owner's machine, 2026-10-14); `perf_tick.gd --full` row
`commands_inputs` p95 0.022 ms. Command application is O(ids) per ORDER and O(queue <= 8) per release.

## Test entry points

`godot/test/unit/sim/control/test_control_machine.gd` (one test per row C1-C18), `godot/test/unit/sim/control/test_control_rules.gd`
(C6r and V-REQ codes, every `ReleaseReason`, hand-over without replay, autopilot resume, determinism, S4), `godot/test/unit/sim/test_enums.gd`
(CM1), `godot/test/sim/test_tick_scenario.gd` (100-tick event sequence incl. LINK_WEAK).

## How to add X (recipes for the cheapest tier)

- **A release reason:** append to `ReleaseReason` here and in sim/MODULE.md Enumerations (R0 B.3 change first), pick its overlay in
  `_release_overlay`, add a row to `test_each_release_reason_reaches_a_released_event`.
- **A rejection rule:** add it to the guard in 05 C6r order, with a code from `CommandResult.Code`, and a line in `test_c6r_every_rejection_code`.

## Open items

- `needs content:` `rules.json` fields for the 10 s request TTL, the 10 s OVERRIDDEN echo window and the 50 m uplink margin (ADR-09).
- Callers still to land: AI-15 / brains call `ControlOrders.complete_head` / `fail_head` (C4, C5); Economy / GD-20 calls
  `release_team` when a team loses its last Core (C16); NET-19 maps `RELEASED` / `HANDOVER` to 04 messages and decides whether the
  server feeds `InputBuffer`'s decayed inputs or lets the sim's C13 run (both use 10 ticks); AI-08 executes the overlays.
- The PilotInput RELEASE bit (04 s5.4 "INPUT with RELEASE bit") is not acted on by the sim; the client turns it into `Command.release`.
- Bots are not refused POSSESS by the sim (05 s1 decision 11 is a `sim_ai` rule); a spectator is an open slot or a lost team.
