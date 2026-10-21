# net/keyframe - MODULE.md

Contract for `godot/src/net/keyframe/**`: the KEYFRAME (0x86, channel 3) message, the stale-ack / join / request policy that
decides when one is sent, and the rolling tier-C refresh (NET-07; 04 s3.1, s3.4, s4.3, R0 C1-15, B.10 A-36, A-37, A-40).
`net/MODULE.md` is at its 300-line cap, so this subsystem has its own file (as `net/events`, `net/commands`).
A change to "Public API", "Wire layout" or "Invariants" is a contract change: contract tests first, same PR (ADR-11);
`tools/gen_module_api.py --check` must pass; <= 300 lines (ADR-14).

| Field | Value |
|---|---|
| Responsibility | Server: build a KEYFRAME (every record a FULL, against nothing) for a client and reset that client's `BaselineStore` mirror to it; decide when one is due (join / reconnect, `REQUEST_KEYFRAME`, ack older than 32 ticks); pick the per-tick rolling-refresh FULLs of the client's C set. Client: validate and apply a KEYFRAME to a `SnapshotDecoder`. Not here: sending, `ENTITY_META` / `TEAM_DETAIL(FULL)` / `POSSESS_ACK` after it (ServerSession NET-15, reconnect NET-20), choosing the C set (`Interest`, NET-08), strike accounting for rate-limited requests (ClientLink NET-14). |
| Lane owner tier | Sonnet against this file; Opus reviews |
| May depend on | `core`, `content`; `net` (`Protocol`, `Codec`, `Roster`, `SnapshotCodec`, `SnapshotDecoder`, `BaselineStore`, `BaselineFrame`) |
| Must never touch | Nodes, `await`, `Thread`, `WorkerThreadPool`; `sim` types; `server/`, `presentation`, `ui` |
| Autoloads used | None |
| Status | implemented (NET-07). |

## Public API

```gdscript
class_name KeyframeCodec extends RefCounted           # net/keyframe/keyframe_codec.gd; scratch arrays sized once (1,536 entries)
const HEADER_BYTES: int; const COUNT_MAX: int; const OFF_SEQ: int; const OFF_TICK: int; const OFF_SCOPE: int; const OFF_COUNT: int   # 10 1536 1 3 7 8
enum Status { OK, MALFORMED, STALE, MISSING_ROSTER }
var seq: int; var tick: int; var scope: int; var count: int; var malformed: int; var missing: PackedInt32Array
func encode(codec: SnapshotCodec, store: BaselineStore, at_tick: int, keyframe_seq: int, key_scope: int, indices: PackedInt32Array) -> PackedByteArray   # empty when prepare_tick(at_tick) was not run, scope or seq invalid; resets `store`, mirror frame at_tick = the records
func decode(bytes: PackedByteArray, dec: SnapshotDecoder) -> int   # validate the whole message, then apply; anything but OK changes nothing (N10 shape)
func forget() -> void                              # reconnect: the next keyframe_seq is accepted whatever the last one was
func reencode() -> PackedByteArray                    # bytes of the last OK decode, rebuilt from its raw fields (invariant K3)
static func seq_of(bytes: PackedByteArray) -> int;  static func tick_of(bytes: PackedByteArray) -> int;  static func scope_of(bytes: PackedByteArray) -> int   # -1 when too short
static func size_for(records: int, own_records: int, escapes: int) -> int   # header + records x 19 + own + 2 per escape

class_name KeyframePolicy extends RefCounted          # net/keyframe/keyframe_policy.gd; one per client, server side
const STALE_TICKS: int; const REQUEST_MIN_TICKS: int; const NONE: int   # 33 (older than DEPTH 32); 150 (5 s); -1
var seq: int; var anchor_tick: int; var sent_all: int; var sent_repair: int; var sent_stale: int; var sent_requested: int; var refused: int
func start(tick: int) -> void                         # join / reconnect: a KEYFRAME(ALL) is due on the next poll
func request(reason: int, tick: int) -> bool          # REQUEST_KEYFRAME(Protocol.KeyframeRequest); false when rate limited (one per 5 s) or not started
func poll(store: BaselineStore, tick: int) -> int     # NONE or Protocol.KeyframeScope due this tick; consumes it and advances `seq`

class_name RollingRefresh extends RefCounted          # net/keyframe/rolling_refresh.gd; one per client (04 s4.3, R0 C1-15)
const PERIOD_TICKS: int; const MIN_REFRESH_TICKS: int  # 300 (every C entity within 300 ticks); 150 (5 s)
var picked: int; var skipped: int
static func per_tick(c_count: int) -> int             # ceil(c_count / 300)
func pick(c: PackedInt32Array, tick: int, out: PackedInt32Array) -> int   # `c` ascending roster indices; fills `out` (cleared), returns its size
func note_full(indices: PackedInt32Array, tick: int) -> void   # FULLs sent by other means (a keyframe) count as refreshed
func reset() -> void
```

`SnapshotDecoder.accept_keyframe(tick: int) -> BaselineFrame` (listed in net/MODULE.md) is the one decoder entry the codec uses: it
forgets every frame and packet receipt, begins the frame of `tick` against nothing and makes `tick` the newest and complete (acked) tick.

## Wire layout

KEYFRAME (04 s2.3 0x86): id u8, keyframe_seq u16, tick u32, scope u8 (`Protocol.KeyframeScope`: ALL 0, ROSTER_REPAIR 1), count u16,
then `count` records in ascending roster index; <= 65,535 B (Protocol.MAX_RELIABLE_BYTES); 1,536 records are <= 30,720 B.
A record is the SNAPSHOT FULL record (04 s3.5): gap (u8 1-254 from the previous record, the first record's gap is its index, 0 only
for index 0; else 0xFF + u16 index) then 0xFF, vec3q 8, quat_s3 4, vel 3, hp 1, flags 1, ai_tag 1 for an entry of the client's own
team = 19 B (+1). Canonical gaps only (an escape where a u8 gap fits is MALFORMED). All FULLs: the keyframe has no baseline.
ENTITY_META for every record's index is sent before the KEYFRAME on channel 3 (ordered); the doc's sequence diagram lists it after,
so `decode` returns MISSING_ROSTER with `missing` filled when an index has no roster entry and the caller holds the message
(RosterSync semantics). ROSTER_REPAIR has the same layout; the server sends it for `REQUEST_KEYFRAME(ROSTER_GAP)` with the repaired
roster's META first and no `TEAM_DETAIL(FULL)` after; the client treats both scopes identically (full baseline reset).

Order at the server: `poll` returns a scope -> META for the indices -> `encode` (store reset, mirror frame = keyframe) -> send on
channel 3 -> no SNAPSHOT to that client in that tick (the KEYFRAME carries the tick's state) -> `RollingRefresh.note_full`.
Until the client acks (its `complete_tick` is the keyframe tick), `base_for` is 0 and SNAPSHOTs are FULL-against-nothing, as at join.

Rolling refresh: each tick `pick` chooses `ceil(C_count / 300)` entries of the client's C set (`InterestClient.c_set`, ascending
index), round-robin by roster index (a cursor survives set changes), skipping an entity refreshed < 150 ticks ago (only possible
when C_count < 150; a skipped entry still uses its slot); the result is `SnapshotCodec.encode(..., refresh)`: FULLs in section C.

## Invariants

- K1: no periodic keyframe: `poll` returns a scope only for join / reconnect (`start`), an accepted request, or a stale ack. Stale =
  `tick - acked_tick >= 33` while the last keyframe has been acked (`acked_tick >= anchor_tick`): a client that never acks its keyframe
  is not sent another (the channel is reliable); exactly one keyframe per stale episode.
- K2: `decode` is total: never throws or reads past the end; validates header, count, gaps (strictly ascending, canonical), mask byte 0xFF,
  valid vec3q cell, exact length, roster membership, then applies; anything but OK changes nothing (the decoder's frames, receipts and
  `store` stay as they were). A `keyframe_seq` not newer (u16 wrap) than the last applied one is STALE.
- K3: every OK decode re-encodes to the identical bytes (`reencode`), and decoding those leaves `same_state` frames.
- K4: after `encode` + `decode` the server mirror frame and the client frame are `same_state`; a SNAPSHOT delta against any later acked
  tick decodes with identical baselines (N9).
- K5: `RollingRefresh`: every C entity present throughout is picked at least once in any 300 consecutive ticks; at most `per_tick(n)`
  per tick; refresh bytes at 700 C entities (3 FULL per tick) <= 1.8 KB/s (04 s4.3, R0 C1-15).
- K6: no allocation per entity in `encode` / `decode` / `pick` (scratch preallocated).

## Performance budget

Bandwidth: 04 s4.3 / s4.6 rolling-refresh row (3 FULLs per tick at 700 C, ~1.7 KB/s; <= 1.8 KB/s asserted). A keyframe is one reliable
message per join / reconnect / stale ack (22.8 KB at 1,200 entities), outside the 30 KB/s unreliable budget. CPU: part of the 03 s4.2
"events + interest + encode + replay" row; `pick` is O(log n + k). Measured figures: `test/perf/test_keyframe_perf.gd` (PerfGate).

## Test entry points

`test/unit/net/test_keyframe_codec.gd` (layout, sizes, scopes, malformed table, mutation sweep with re-encode, random bytes, STALE seq),
`test/unit/net/test_keyframe_policy.gd` (33-tick gap exactly once, 32 none, no periodic, request rate limit, unacked keyframe),
`test/unit/net/test_rolling_refresh.gd` (per_tick, coverage within 300 ticks, skip rule, cursor), `test/net/test_keyframe_link.gd`
(server + client over `LocalTransport` with loss: stale-ack reset, refresh bytes at 700 C), `test/perf/test_keyframe_perf.gd`.

## How to add X

A scope: append to `Protocol.KeyframeScope` (append-only; Architect), extend `decode`'s range check and `test_keyframe_codec.gd`.
