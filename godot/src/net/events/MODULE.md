# net/events - MODULE.md

Contract for `godot/src/net/events/**`: the EVENTS (0x87, channel 3) and PROJECTILE_BATCH (0x8F, channel 2) paths (NET-10;
04 s3.6, R0 C2-03, C2-35). R0 B.9 A-21 split: `net/MODULE.md` was at its 300-line cap, so this subsystem has its own file.
A change to "Public API" or "Invariants" is a contract change: contract tests first, same PR (ADR-11);
`tools/gen_module_api.py --check` must pass; <= 300 lines (ADR-14).

| Field | Value |
|---|---|
| Responsibility | Server: turn `SimWorld.drain_events() -> Array[SimEvent]` into per-client reliable EVENTS packets (scope, roster masking, splitting at 1,200 B / 255 events) and per-client PROJECTILE_BATCH packets (roster filter, one re-send). Client: decode both, dedupe shots, report flak bursts. Not here: sending (ServerSession), `ENTITY_META` (RosterSync), applying events to presentation (NetSimView, NET-17). |
| Lane owner tier | Sonnet against this file |
| May depend on | `core`, `content`; `net` (`Protocol`, `Codec`, `Roster`); named `sim` types `SimEvent` (A-27, R0 B.9) |
| Must never touch | Nodes, `await`, `Thread`; `Build` (not a named type; `Build.Reject` travels as an `int`); `server/`, `presentation`, `ui` |
| Autoloads used | None |
| Status | implemented (NET-10, 2026-10-14). The `SimEvent` field convention below is the router's input contract; the sim emits only some kinds today (POSSESSED, RELEASED, DEATH, SPAWN, ALERT, CAP_REACHED, CORE_EXPOSURE, CEILING_RELEASE); the rest follow their systems |

## Public API

```gdscript
class_name EventAudience extends RefCounted                    # one client's routing state; the caller drains outbox / shot_out
var roster: Roster; var team: int; var player: int; var possessed_slot: int; var unfiltered: bool; var cells: PackedByteArray
var outbox: Array[PackedByteArray]; var shot_out: Array[PackedByteArray]; var shots_last: Array[PackedByteArray]
func _init(r: Roster = null) -> void
func set_cells(ids: PackedInt32Array) -> void;  func sees_cell(cell: int) -> bool;  func clear_out() -> void
class_name WireEvent extends RefCounted                        # one decoded EVENTS entry
var kind: int; var tick: int; var v: PackedInt32Array; var count: int; var pos_q: int; var pos: Vector3
class_name EventCodec                                          # EVENTS (0x87): id, tick u32, count u8, events[] x (kind u8, size u8, payload)
const POS: int; const ROW: int; const KIND_COUNT: int; const HEADER_BYTES: int; const EVENT_HEADER_BYTES: int; const COUNT_MAX: int
const NONE_REF: int; const SCHEMA: PackedInt32Array            # SCHEMA: field widths per kind, stride ROW, 0 ends a row
static func is_valid_kind(kind: int) -> bool;  static func payload_bytes(kind: int) -> int;  static func field_count(kind: int) -> int
static func write_header(buf: PackedByteArray, tick: int) -> int
static func write_event(buf: PackedByteArray, at: int, kind: int, vals: PackedInt32Array, pos_q: int) -> int   # next offset or -1
static func decode(bytes: PackedByteArray, out: Array[WireEvent]) -> int                                       # count or -1; all-or-nothing
class_name EventRouter extends RefCounted                      # server: scope + roster masking + packing
enum Scope { ROSTER, TEAM, ALL, CELL, TEAM_ROSTER, LOCK, POSSESSOR, NEVER }
enum Src { ZERO, REF_A, REF_B, RAW_A, RAW_B, X0, X1, X2, X3, X4, VALUE, VALUE255, TEAM, POS, XU16, OWNER_A }
const SCOPES: PackedInt32Array; const SOURCES: PackedInt32Array
var packets_made: int; var events_sent: int; var events_dropped: int
func route(tick: int, events: Array[SimEvent], audiences: Array[EventAudience]) -> void
func route_shots(tick: int, shots: ShotBuffer, audiences: Array[EventAudience]) -> void
static func ref_of(id: int, aud: EventAudience) -> int         # roster index or NONE_REF (absent, stale generation)
class_name ShotBuffer extends RefCounted                       # one tick of straight-line shots as packed arrays; quantised direction
var tick: int; var count: int; var shooter: PackedInt32Array; var weapon_slot: PackedInt32Array; var seed_byte: PackedInt32Array
var yaw_q: PackedInt32Array; var pitch_q: PackedInt32Array; var fuse: PackedInt32Array
func clear(for_tick: int = 0) -> void
func add_q(who: int, slot: int, seed_value: int, yaw: int, pitch: int, fuse_ticks: int = -1) -> void
func add(who: int, slot: int, seed_value: int, boresight: Basis, dir: Vector3, fuse_ticks: int = -1) -> void
class_name ProjectileBatch                                     # PROJECTILE_BATCH: id, tick u32, count u8, items 6 B (+ fuse u8 = 7 B)
const HEADER_BYTES: int; const ITEM_BYTES: int; const ITEM_FUSE_BYTES: int; const DIR_STEP_RAD: float; const COUNT_MAX: int
static func quantize_yaw(boresight: Basis, dir: Vector3) -> int;  static func quantize_pitch(boresight: Basis, dir: Vector3) -> int
static func dequantize_dir(boresight: Basis, yaw: int, pitch: int) -> Vector3;  static func item_bytes(fuse_ticks: int) -> int
static func encode(tick: int, shots: ShotBuffer, refs: PackedInt32Array, from: int, to: int) -> PackedByteArray
static func decode(bytes: PackedByteArray, out: ShotBuffer) -> int                                              # count or -1
class_name ShotRouter extends RefCounted                       # per-client batches: roster filter, this tick + last tick's packets
func route(tick: int, shots: ShotBuffer, aud: EventAudience) -> void
class_name ShotTracker extends RefCounted                      # client: dedupe by (shooter, seed, tick), live shots, flak burst ticks
const KEY_KEEP_TICKS: int; const MAX_LIVE: int
var shooter: PackedInt32Array; var weapon_slot: PackedInt32Array; var seed_byte: PackedInt32Array; var yaw_q: PackedInt32Array
var pitch_q: PackedInt32Array; var spawn_tick: PackedInt32Array; var burst_tick: PackedInt32Array; var duplicates: int; var rejected: int
func count() -> int;  func accept(bytes: PackedByteArray, now_tick: int) -> int;  func take_due_bursts(now_tick: int, out: PackedInt32Array) -> void
func remove_hit(attacker_ref: int, seed_value: int) -> bool;  func expire(now_tick: int, max_age_ticks: int) -> void
```

## Wire layout

EVENTS: 04 s3.6 table (per-kind payload, scope). `kind u8, size u8` frame every event, `size` must equal the table's
payload size; kind 17 (MATCH_END, message 0x8E) and kinds >= 34 are invalid here. `roster` fields are roster indices
(`Roster` slot = `EntityId.slot`), `0xFFFF` = not in the client's roster. HIT damage is u16 (clamped). Packets are
split at 1,200 B or 255 events and keep sim order; channel 3 is reliable and ordered, so the client sees one stream.
PROJECTILE_BATCH: 04 s2.3 row; direction is yaw / pitch i8 in 0.5 degree steps around the weapon boresight
(x right, y up, z forward), +-63.5 degrees; `weapon_slot` bit7 = HAS_FUSE, fuse u8 in ticks (flak burst = spawn tick + fuse).

`SimEvent` input convention (what `EventRouter` reads; `needs sim` to confirm as each system emits its kinds):
`a`, `b` EntityIds (or small ints where the 04 payload is a player / def / order kind), `value` damage, ore, ratio
(0-1), progress or severity, `team` the scope team (-1 = all), `extra` bytes. Per kind: SPAWN a, b = def (owner from the
roster); DEATH a, b = killer, extra[0] = cause; HIT a = target, b = attacker, value = damage, extra[0] = part,
extra[1] = seed; BOMB_IMPACT a = owner, b = projectile def, pos; ALERT a = `AlertKind`, b = subject, pos, value = severity;
STRUCTURE_LOST a, b = killer, extra[0..1] = def u16 LE; BUILD_STARTED extra[0] = player; ORDER_FAILED / SERVICED /
HANDOVER / DEATH / RELEASED extra[0] = reason, what, to; LANDING a, b = pad, extra = grade, q, flags, v_vert, v_horiz;
LOW_POWER value = ratio, team; CORE_EXPOSURE team = -1 for all; CAP_REACHED a = player, b = cap, team = -1 (to that player);
LOCK_* a = shooter, b = target, team = shooter's team; CAPTURE_PROGRESS b = team, value = progress; others as the table.

## Invariants

- E1: an entity outside the client's roster (absent, or stale generation) is never named in any event for that client;
  its reference is 0xFFFF and a roster-scoped event about it is not sent (test_event_router.gd, 600 random events).
- E2: every kind 0-33 except MATCH_END round-trips through route -> decode; sizes equal the 04 s3.6 table (test_event_codec.gd).
- E3: `EventCodec.decode` and `ProjectileBatch.decode` validate the whole packet, return -1 on anything malformed, append nothing, never throw.
- E4: no EVENTS or PROJECTILE_BATCH packet exceeds 1,200 B; events keep sim order inside and across packets.
- E5: a shot batch is sent on its tick and once on the next; `ShotTracker` registers a (shooter, seed, tick) once; a flak shot is due at `tick + fuse`.
- E6: routing is a pure function of (events, audience): the same inputs give byte-identical packets.

## Data owned

None. Scope and source tables are `const` in `EventRouter`; payload widths in `EventCodec.SCHEMA`. No def files.

## Events emitted / consumed

Consumes every `SimEvent.Kind` 0-33 (MATCH_END is message 0x8E, written by ServerSession). Emits nothing.

## Performance budget

04 s4.6 bandwidth rows (events share the 24 KB/s typical, 30 KB/s cap with snapshots) and the 03 s4.2 "events + interest +
encode + replay" row (4.0 ms p95, 8 clients, R0 B.7). Routing is table driven, no per-event allocation beyond the finished
packets; measured numbers in the NET-10 PR perf note.

## Test entry points

`godot/test/unit/net/test_event_codec.gd` (E2, E3), `godot/test/unit/net/test_event_router.gd` (E1, E4, E6),
`godot/test/unit/net/test_projectile_batch.gd` (E3, E5), `godot/test/net/test_event_stream.gd` (reliable order and shot
re-send over a LocalTransport BAD preset). Helper: `godot/test/unit/net/event_rig.gd`.

## How to add X (recipes for the cheapest tier)

- **A SimEvent kind:** append to `sim/MODULE.md` Enumerations and `SimEvent.Kind`, `Protocol.EventKind`, a row in 04 s3.6, then one row each in `EventCodec.SCHEMA`, `EventRouter.SCOPES`, `EventRouter.SOURCES`, `KIND_COUNT`; protocol version bump (Architect).
- **A routing rule:** add a `Scope` value, handle it in `EventRouter._in_scope`, test in `test_event_router.gd`.

## Open items

- Wreck slots (1,280-1,535, 03 s3.1) were outside the 1,280-entry `Roster`: decided by R0 B.11 A-54, the roster has **1,536** entries (04 s3.1 patched); `Roster.CAPACITY` and its tests change in NET-50, after which WRECK_SPAWNED / WRECK_SALVAGED and wreck refs reach filtered clients.
- `needs sim:` confirm the `SimEvent` field convention above as combat, economy and docking emit their kinds (HIT, SERVICED, LANDING, STRUCTURE_LOST).
- `needs server:` call `EventRouter.route` / `route_shots` after `drain_events()`, send `outbox` on CH_EVENTS reliable and `shot_out` on CH_SNAPSHOT unreliable, then `clear_out()`; fill `EventAudience.cells` from Interest (NET-08).
- Client-side spawn of the presentation projectile from `ShotTracker` (Kinematics.step_projectile) is NET-17.
