# net/replay - MODULE.md

Contract for `godot/src/net/replay/**`: the `.pwr` replay file (NET-25; 04 s13.1-s13.2, 01 ADR-10, R0 C1-02, C2-25).
`net/MODULE.md` is at its 300-line cap, so this subsystem has its own file (R0 B.9 A-21 precedent).
A change to "Public API", "Wire layout" or "Invariants" is a contract change: contract tests first, same PR (ADR-11);
`tools/gen_module_api.py --check` must pass; <= 300 lines (ADR-14).

| Field | Value |
|---|---|
| Responsibility | Server and offline host: write a replay as a pseudo-client whose interest set is everything, reading the `SnapshotCodec` shared per-tick cache (nothing is re-quantised), plus the unfiltered event stream, chat and input summaries, as one streaming gzip with an index and footer. Client: open a file (or recover a truncated one), apply frames to a replicated state, seek by keyframe, play frames into a `ClientSession` as a `Transport`. Redact names, user ids and chat text in place. Offline file listing and the 20-file cap. Not here: Nakama `replay_url` (NET-42), the Replays screen (UX), `ClientSession` / `NetSimView` (NET-17), choosing when to start or stop a writer (ServerSession NET-15, offline host). |
| Lane owner tier | Opus (writer, reader); Sonnet for `tools/replay_inspect.py` |
| May depend on | `core`, `content`; `net` (`Codec`, `DeadReckon`, `Protocol`, `Roster`, `RosterCodec`, `SnapshotCodec`, `SnapshotDecoder`, `BaselineStore`, `BaselineFrame`, `PilotWire`, `Transport`), `net/events` (`EventRouter`, `EventAudience`, `EventCodec`, `WireEvent`); named `sim` type `SimEvent` |
| Must never touch | Nodes, `await`, `Thread`, `WorkerThreadPool` (web is single-threaded); `FileAccess.open_compressed` (not gzip: Godot's own container); `server/`, `platform/` (web saves go through 06's `Saves.try_*`, the caller passes the resolved path) |
| Autoloads used | None |
| Status | implemented (NET-25, 2026-10-14). Not in the file: PROJECTILE_BATCH shots (see Open items) |

## Public API

```gdscript
class_name ReplayFormat                                          # constants + gzip helpers
const MAGIC: PackedByteArray; const END_MAGIC: PackedByteArray; const FRAME_HEADER_BYTES: int; const FOOTER_BYTES: int
const HASH_BYTES: int; const ID_BYTES: int; const SNAPSHOT_EVERY: int; const KEYFRAME_TICKS: int; const CHUNK_ENTITIES: int
const INPUT_SUMMARY_TICKS: int; const INPUT_ENTRY_BYTES: int; const REPLAY_TEAM: int; const FILE_CAP: int; const FLUSH_BYTES: int
enum FrameType { KEYFRAME = 1, DELTA = 2, EVENTS = 3, CHAT = 4, INPUT_SUMMARY = 5 }                       # append-only
enum Status { OK, RECOVERED, BAD_MAGIC, UNSUPPORTED_VERSION, CORRUPT, IO_ERROR }                           # append-only
static func read_str8(buf: PackedByteArray, at: int, out: PackedStringArray) -> int                       # end offset or -1; text in out[0]
static func gzip(raw: PackedByteArray) -> PackedByteArray;  static func gunzip(data: PackedByteArray, ok: PackedByteArray) -> PackedByteArray
static func drain(gz: StreamPeerGZIP) -> PackedByteArray

class_name ReplayHeader extends RefCounted                       # the HEADER block; parse() fills every field
var protocol_version: int; var content_hash: PackedByteArray; var map_hash: PackedByteArray; var map_id: String; var match_id: PackedByteArray
var config: PackedByteArray; var seed_value: int; var started_unix: int; var tick_rate: int; var slot: PackedInt32Array; var team: PackedInt32Array
var kind: PackedInt32Array; var doctrine: PackedInt32Array; var input_class: PackedInt32Array; var user_id: Array[PackedByteArray]
var player_name: PackedStringArray; var length: int; var uid_at: PackedInt32Array; var name_at: PackedInt32Array
func add_player(slot_id: int, team_id: int, kind_id: int, doctrine_id: int, input_class_id: int, uid: PackedByteArray, display_name: String) -> void
func player_count() -> int;  func to_bytes() -> PackedByteArray;  func parse(buf: PackedByteArray) -> int   # ReplayFormat.Status

class_name ReplayWriter extends RefCounted                       # server / offline host; one writer per match
var frames_written: int; var keyframes: int; var raw_bytes: int; var bytes_out: int; var deferred: int; var last_error: int
var meta_us: int; var encode_us: int; var io_us: int                                                          # cumulative, perf notes
func open_file(path: String, header: ReplayHeader) -> int       # streams to path + ".part"; Error
func open_memory(header: ReplayHeader) -> int
func record_tick(codec: SnapshotCodec, tick: int, slots: PackedInt32Array, roster: Roster, events: Array[SimEvent]) -> void   # after prepare_tick(tick)
func record_chat(tick: int, msg_id: int, sender: int, scope: int, text: String) -> void
func record_input_summary(tick: int, player_slots: PackedInt32Array, entities: PackedInt32Array, inputs: PackedByteArray) -> void
func finish(result_hash: PackedByteArray, ended_tick: int) -> PackedByteArray   # INDEX + FOOTER; file mode renames .part, returns empty

class_name ReplayReader extends RefCounted                       # open, apply, seek
const NO_FRAME: int
var header: ReplayHeader; var roster: Roster; var decoder: SnapshotDecoder; var status: int; var tick: int; var frame_type: int
var result_hash: PackedByteArray; var ended_tick: int; var has_footer: bool; var index_tick: PackedInt32Array; var index_offset: PackedInt32Array
var packets: Array[PackedByteArray]; var events: Array[WireEvent]; var chat_id: PackedInt64Array; var chat_sender: PackedInt32Array
var chat_scope: PackedInt32Array; var chat_text: PackedStringArray; var input_slot: PackedInt32Array; var input_entity: PackedInt32Array; var input_bytes: PackedByteArray
func _init(gravity_mps2: float = 0.0, tick_hz: int = 30) -> void   # set decoder.gravity_def[def_id] = 1 for gravity-bearing defs
func open(path: String) -> int;  func open_bytes(file: PackedByteArray) -> int;  func open_raw(raw: PackedByteArray, cut: bool = false) -> int
func rewind() -> void;  func frames_begin() -> int;  func frames_end() -> int;  func at_end() -> bool;  func peek_tick() -> int
func next_frame(apply: bool = true) -> int                       # frame type, NO_FRAME at the end or on a bad frame (status CORRUPT)
func seek(target: int) -> bool;  func seek_keyframe(target: int) -> int;  func current() -> BaselineFrame
func position_of(slot: int) -> Vector3                           # baseline entry dead-reckoned to the last frame's tick

class_name ReplayRedactor                                        # same-length redaction, offsets unchanged
static func redact_raw(raw: PackedByteArray, names: bool = true, chat: bool = true, user_ids: bool = true) -> PackedByteArray   # empty if unreadable
static func redact_file(path: String, names: bool = true, chat: bool = true, user_ids: bool = true) -> int                      # Error

class_name ReplayTransport extends Transport                     # kind() == &"replay", conn 1
signal keyframe_started(tick: int);  signal finished
const CONN: int; var speed: float; var paused: bool; var playhead: float; var packets_sent: int
func _init(reader: ReplayReader) -> void;  func seek(target: int) -> int   # keyframe tick restarted from, or -1
func kind() -> StringName;  func poll() -> void;  func close(_conn: int, _reason: int) -> void   # Transport overrides; poll() advances the playhead

class_name ReplayStore                                           # offline files, R0 C2-25
static func file_name(started_unix: int, mode: String, map_id: String) -> String       # <unix>_<mode>_<map>.pwr
static func list(dir: String) -> PackedStringArray;  static func prune(dir: String, keep: int = ReplayFormat.FILE_CAP) -> int
static func make_room(dir: String) -> int                        # leaves room for one new file under the cap
```

Changed in `net` for this module (listed in `net/MODULE.md`): `SnapshotCodec.append_frame` (bool; encode() continues the
frame already begun for the tick, so a frame can hold more than 4 packets), `SnapshotDecoder.forget_tick(tick)` and
`SnapshotDecoder.reset()`.

## Wire layout

04 s13.1 is the source. One gzip stream (a real `.gz`: Python `gzip` opens it), little-endian:

```
HEADER   "PWR1", protocol_version u16, content_hash 32, map_hash 32, map_id str8, match_id 16, config bytes16 (u16 length),
         seed u64, started_unix u32, tick_rate u8, player_count u8, players[] x (slot, team, kind, doctrine, input_class u8,
         user_id 16, name str8), header_len u32 (whole header incl. this field)
FRAME    type u8, tick u32, len u32, payload      (KEYFRAME 1, DELTA 2, EVENTS 3, CHAT 4, INPUT_SUMMARY 5)
INDEX    count u32, (tick u32, byte_offset u32) x count     offsets are in the INFLATED stream, of each KEYFRAME frame header
FOOTER   index_offset u32, result_hash 32, ended_tick u32, "PWRE"
```

KEYFRAME / DELTA / EVENTS payload = a packet container: `count u16`, then `len u16 + wire message` per packet. The messages
are the live ones: ENTITY_META (0x88), ROSTER_REMOVE (0x90), SNAPSHOT (0x84) and EVENTS (0x87), exactly as 04 s3 lays them out.
CHAT: `msg_id u64, sender u8, scope u8, text str16 (u16 length)`. INPUT_SUMMARY: `count u8`, then `slot u8, entity u32, 30 x 8 B
PilotWire` per player (anti-cheat and kill-cam; never replayed into the sim, ADR-10).

Decisions where 04 s13.1 was open: (1) the snapshot is encoded by `SnapshotCodec.encode` for a pseudo-client of team 15
(`REPLAY_TEAM`, owns nothing, so no `ai_tag` bytes) with every live slot in section A; a frame is chunks of 128 slots, each
chunk 1-4 SNAPSHOT packets whose first packet has index 0, so a frame is any number of packets (a chunk with no record is
dropped). (2) A KEYFRAME is a frame with baseline 0 (every record FULL) preceded by ENTITY_META for the whole roster; the reader
clears its roster and baselines on it. (3) A DELTA is against the previous written frame (`baseline_tick` in the packets), which
is lossless, so the reader never acks. (4) Dead reckoning: an entity that moves as predicted writes no record, so a reader
gets its position with `ReplayReader.position_of`, which is the live `DeadReckon` arithmetic. (5) A tick with nothing to
write writes no frame and is not a baseline; the next frame is against the last written one.

## Invariants

- R1: the file is exactly gzip(HEADER FRAME* INDEX FOOTER); frames are in non-decreasing tick order; every KEYFRAME is in INDEX
  at its frame-header offset; a KEYFRAME needs no earlier frame (`test_replay.gd` index seek, 5 random targets, forward and back).
- R2: reading a written file reproduces the live quantised state: at every written tick `position_of` is within 0.5 m of the
  live position, hp and flags equal (`test_round_trip_two_minutes`, 3,600 ticks, bombs included).
- R3: `ReplayReader` never throws or stalls on any byte string: a truncated or footer-less file opens as RECOVERED with every
  complete frame; a bad frame ends the read with CORRUPT (`test_truncated_*`, `test_mutated_file_never_throws`, 1,500 mutations;
  Python: `tools/tests/test_replay_inspect.py`).
- R4: redaction changes only user-id bytes, name bytes and chat text bytes, to zero / '*' of the same length; the result opens
  OK with the same index and frames (`test_redaction_in_place_keeps_file_valid`).
- R5: writing is deterministic: the same inputs give byte-identical files (`test_determinism`).
- R6: `tools/replay_inspect.py` decodes the committed fixture to the same quantised state as the GDScript reader
  (`test_replay_fixture.gd` and `test_replay_inspect.py` pin one JSON).
- R7: the writer allocates nothing per entity; chunk lists, packets and frame bytes are the only per-frame allocations. It reads
  the shared cache; it never calls `prepare_tick`.
- R8: no Node, no thread; the writer holds only the flush window (64 KB) plus one frame in memory. The reader holds the whole
  inflated stream.

## Data owned

None. Cadence constants (`SNAPSHOT_EVERY` 3 = 10 Hz, `KEYFRAME_TICKS` 300 = 10 s) are file-format constants of 04 s13.1, not
sim values.

## Performance budget

03 s4.2 row 12 "events + interest + encode + replay" (4.0 ms p95, 8 clients, R0 B.7); bandwidth/disk 04 s13.1 (about 25 KB/s
compressed, <= 20 MB per 30 min, ADR-10). Measured numbers: the NET-25 PR perf note (`test/perf/bench_replay.gd`,
`BENCH_REPLAY`, canonical scene, reported against A-62).

## Test entry points

`godot/test/net/test_replay.gd` (R1-R5, ReplayTransport, ReplayStore), `godot/test/net/test_replay_fixture.gd` (R6),
`tools/tests/test_replay_inspect.py` (R3, R4, R6 in Python); helper `godot/test/net/replay_rig.gd`; perf
`godot/test/perf/bench_replay.gd`. Regenerate the fixture with `PW_UPDATE_FIXTURES=1` and commit both files.

## How to add X (recipes for the cheapest tier)

- **A frame type:** append to `ReplayFormat.FrameType` (never reorder), handle it in `ReplayReader._parse` and
  `tools/replay_inspect.py`; readers of older files ignore nothing: an unknown type ends the read (CORRUPT), so a new type is a
  `PROTOCOL_VERSION` bump (Architect).
- **Start a replay (server):** `ReplayWriter.new().open_file("/var/lib/planewar/replays/<match_id>.pwr", header)`; each tick after
  `codec.prepare_tick(frame)`: `record_tick(codec, tick, interest.all_ids, roster, events)`; on ENDED `finish(result_hash, tick)`.
- **Offline:** `ReplayStore.make_room(dir)`, `open_file(dir.path_join(ReplayStore.file_name(unix, mode, map_id)), header)`.
- **Play:** `ReplayReader` -> `ReplayTransport` -> `ClientSession`; on `keyframe_started` the client resets its baselines.

## Open items

- PROJECTILE_BATCH shots are not recorded (04 s13.1 lists no frame type for them): a replay shows hits, deaths and bombs
  (events) but not straight-line shots. Append `FrameType.PROJECTILES = 6` when the presentation needs them (Architect).
- Size: on the synthetic canonical scene (940 entities, all movers circling) the file is ~34 KB/s gzip, 61 MB per 30 min, over
  the 20 MB target (ratio 1.3; random orientation and position residuals do not compress). The 04 s13.1 fallback (5 Hz for
  tier-C-class entities) is not implemented; `perf/replay_size` on a real recorded match decides (follow-up).
- `needs server:` call the writer from `ServerSession` (NET-15); `needs sim:` `SimEvent` convention as in `net/events/MODULE.md`.
- `needs ClientSession (NET-17):` reset baselines on `keyframe_started`; accept `ReplayTransport` in place of a network transport.
