# net/commands - MODULE.md

Contract for `godot/src/net/commands/**`: the COMMAND (0x03, channel 0) payload and envelope codecs (NET-04; 04 s2.5,
R0 C2-06, B.14 A-85). `net/MODULE.md` is at its 300-line cap, so this subsystem has its own file (as `net/events`).
A change to "Public API", "Wire layout" or "Invariants" is a contract change: contract tests first, same PR (ADR-11);
`tools/gen_module_api.py --check` must pass; <= 300 lines (ADR-14).

| Field | Value |
|---|---|
| Responsibility | Map the sim form of `Command.payload` to the 04 s2.5 wire payload and back for all 16 `Command.Kind`s, and build / parse the COMMAND message. Shape checks only; legality (rights, ownership, counts such as `queue_max`, order rules, `escort_slot` range) is the sim validator's. Not here: sending, rate limits, strikes (server `ClientLink`, NET-14), V-ORD class rules (NET-16). |
| Lane owner tier | Sonnet against this file |
| May depend on | `core`, `content`; `net` (`Protocol`, `Codec`); named `sim` type `Command` (A-27) |
| Must never touch | Nodes, `await`, `Thread`; other `sim` types (the constants it needs are copied and pinned by tests); `server/`, `presentation`, `ui` |
| Autoloads used | None |
| Status | implemented (NET-04). |

## Public API

```gdscript
class_name CommandCodec                               # net/commands/command_codec.gd; all static
const HEADER_BYTES: int; const MESSAGE_MAX_BYTES: int; const KIND_COUNT: int; const ORDER_HEADER_BYTES: int   # 14, 270, 16, 9
const ORDER_MAX_IDS: int; const ORDER_MAX_POINTS: int; const ESCORT_TRAILER_BYTES: int                        # 32, 16, 6
static func encode_payload(cmd: Command, out: PackedByteArray) -> bool   # sim form -> wire; false (out empty) for PILOT_INPUT, malformed or oversize payloads, non-finite or out-of-band points
static func decode_payload(kind: int, target: int, wire: PackedByteArray) -> Command   # wire -> sim form (player -1, tick 0); null when malformed
static func encode_message(seq: int, tick: int, cmd: Command) -> PackedByteArray   # empty when not encodable
static func decode_message(bytes: PackedByteArray) -> Command   # tick = the sender stamp; null when malformed
static func seq_of(bytes: PackedByteArray) -> int       # -1 when too short
static func order_wire_size(count: int, point_count: int, is_escort: bool) -> int
static func order_fits(count: int, point_count: int, is_escort: bool) -> bool   # legal counts and <= 256 B
```

## Wire layout

Message: id u8, seq u16, tick u32, kind u8, target u32, len u16, payload (<= 256 B; 270 B total, `Protocol.CATALOGUE`).
Payload per kind: the sim form (`sim/command.gd`, `CommandPayload`) with positions as vec3q (`Codec`, 8 B) instead of f64 x 3;
every other byte is identical. ORDER: u8 kind (0-11), flags, haul_mode (0-2), count (1-32), u32 ids[count], u32 target,
u8 point_count (0-16), vec3q points, and for ESCORT only the trailer u8 escort_mode (0-2), u8 escort_slot (0xFF = -1), u32 focus.
The ORDER header is 9 bytes: a 32-id ORDER carries at most 14 points (249 B) and a 32-id ESCORT is 143 B (R0 B.16 A-91; `test_order_constants_match_sim_and_15_points_refused` pins `ORDER_HEADER_BYTES` to `OrderSpec.WIRE_HEADER_BYTES`). BUILD 7 B (rotation 0-3),
PRODUCE 3, SET_RALLY 8 (vec3q), TOGGLE_AUTO_REPLENISH u8 enabled (0-1) + 0-8 x (u16 def, u8 count), SET_ADJUTANT 3
(enabled any byte, profile 0-2), CANCEL_PRODUCE / HANDOVER 1, CANCEL_BUILD / POSSESS / RELEASE / REQUEST_POSSESS /
SURRENDER 0, DEBUG_SPAWN 76 and DEBUG_SET 9 (sim form verbatim). PILOT_INPUT is never a COMMAND.

## Invariants

- C1: decoders never throw; any malformed input (size, count, enum range, invalid cell, point outside the codable band, trailer on a non-ESCORT order, ESCORT without trailer) returns null, never a partial command.
- C2: every non-null decode re-encodes, and the re-encoding decodes to an equal command (positions within one quantum, or the neighbour cell on a cell border).
- C3: decoded positions meet `Codec` bounds (N7): < 0.05 m per point for -500 m .. ceiling.
- C4: for kinds without positions the wire bytes equal the sim builder bytes (`Command.*`, `CommandPayload.*`).

## Performance budget

Not a per-tick path: <= 10 commands/s per client (04 s2.3). Measured (`test/perf/test_command_codec_perf.gd`, dev box): ORDER 32 ids x 14 points
249 B encode 25 us / decode 21 us; ORDER MOVE 3 us; ESCORT 32 ids 3 / 4 us; SET_RALLY 2.4 / 2.7 us; PRODUCE, SET_ADJUTANT, TOGGLE x8 1-2 us.

## Test entry points

`test/unit/net/test_command_codec.gd` (all kinds, sim-builder cross-check, ESCORT trailer, boundary, raw-position bound, per-kind mutation sweep, random bytes); `test/perf/test_command_codec_perf.gd`. NET-23 adds the 100,000-mutation fuzz.

## How to add X

**A Command kind.** Architect: append the ordinal (sim and `Protocol.CommandKind`), add the layout to 04 s2.5, then `_shape_ok` here (or a converter if it carries positions) and a row in `_valid_commands()` in the test.
