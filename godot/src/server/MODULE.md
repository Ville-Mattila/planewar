# server - MODULE.md

Contract for `godot/src/server/**`, v0.1 (NET-14 `ClientLink`). Source of truth: 04 s2.2, s7, s8, s11 and R0 C2-12 / C2-27.
NET-38 writes the final contract and NET-15 adds `ServerSession`; both append to this file. A change to "Public API" or
"Invariants" is a contract change: contract tests first, same PR (ADR-11); `tools/gen_module_api.py --check` must pass; <= 300 lines.

| Field | Value |
|---|---|
| Responsibility | The authoritative match process: per-client links (handshake, state machine, queues, rate limits, strikes), later `ServerSession`, `ProtocolValidator`, `MatchConfig`, FleetAgent. It owns no sim rules: game legality stays in `SimWorld.apply_command`. |
| Lane owner tier | Sonnet for links and validators; Opus for `ServerSession.tick()` and handoff flows (NET-15, NET-19) |
| May depend on | `core`, `content`, `sim`, `sim_ai`, `net`, `platform` (`tools/deps.json`) |
| Must never touch | `presentation`, `ui`, `input`, `camera`, `app`; Nodes in link code; `await`; `Thread` (web is single-threaded, 03 s11) |
| Autoloads used | None in link code (`Log` allowed elsewhere, never per packet) |
| Status | `ClientLink`, `TokenBucket`, `LinkLimits`, `HelloMsg` implemented (NET-14); everything else planned |

## Public API

```gdscript
class_name TokenBucket extends RefCounted             # server/token_bucket.gd: 04 s11.4 bucket on integer ms
var rate_per_s: float; var burst: float
func _init(p_rate_per_s: float, p_burst: float, now_ms: int) -> void   # starts full
func take(now_ms: int, cost: float = 1.0) -> bool
func available(now_ms: int) -> float

class_name LinkLimits extends RefCounted              # server/link_limits.gd: 04 s2.2 / s11.3 / s11.4 numbers
const CHANNEL_CAP: PackedInt32Array                   # [1024, 64, 2048, 2048] inbound hard caps per channel
var hello_timeout_ms: int; var load_timeout_ms: int; var close_delay_ms: int      # 5000, 60000 (match_rules.json), 500
var packets_per_s: float; var packet_burst: float; var bytes_per_s: float; var byte_burst: float   # 120, 120, 8192, 8192
var command_per_s: float; var command_burst: float    # 10, 30 (rules.json)
var chat_per_s: float; var chat_burst: float; var ping_per_s: float; var ping_burst: float   # 2, 5, 1, 3
var keyframe_interval_ms: int; var strike_limit: int; var strike_window_ms: int; var kick_ban_ms: int   # 5000, 20, 60000, 60000
var input_queue_max: int; var control_queue_max: int  # 16, 32
static func channel_cap(channel: int) -> int
static func from_defs(rules: RulesDef, match_rules: MatchRulesDef) -> LinkLimits

class_name HelloMsg extends RefCounted                # server/hello_msg.gd: one parsed HELLO (0x01)
var version: int; var content_hash: PackedByteArray; var token: PackedByteArray; var build: int
var platform: int; var input_class: int; var role: int; var session_id: int; var secret: PackedByteArray
static func decode(b: PackedByteArray) -> HelloMsg    # null on any malformation

class_name ClientLink extends RefCounted              # server/client_link.gd: one connected client (04 s7, s11)
enum State { PRE_HELLO, LOADING, LOADED, PLAYING, CLOSING, CLOSED }
enum Verdict { QUEUED, DROPPED_CHANNEL, DROPPED_SIZE, DROPPED_RATE, DROPPED_STATE, MALFORMED, VIOLATION }
enum CloseReason { NONE, HELLO_TIMEOUT, LOAD_TIMEOUT, REFUSED, KICKED, TRANSPORT }
const KICK_TEXT: String
var conn: int; var transport: Transport; var limits: LinkLimits; var state: State; var close_reason: CloseReason
var slot: int; var team: int; var session_id: int; var direct_view: bool; var strikes: int
var hello: HelloMsg; var expected_map_hash: PackedByteArray; var loaded_map_hash: PackedByteArray
var connected_ms: int; var welcomed_ms: int; var close_at_ms: int; var last_seq: int; var taken_seqs: PackedInt32Array
var dropped_rate: int; var dropped_size: int; var dropped_channel: int; var dropped_state: int; var malformed: int; var packets_in: int
func _init(p_conn: int, p_transport: Transport, p_limits: LinkLimits, now_ms: int) -> void
func on_packet(channel: int, bytes: PackedByteArray, now_ms: int) -> Verdict   # transport entry; never throws
func take_commands() -> Array[Command];  func take_control() -> Array[PackedByteArray];  func take_inputs() -> Array[PackedByteArray]
func accept(w: WelcomeInfo, now_ms: int) -> bool      # sends WELCOME, PRE_HELLO -> LOADING
func refuse(reason: int, server_version: int, text: String, now_ms: int) -> void   # REFUSE, close after close_delay_ms
func start_playing() -> void                          # LOADED -> PLAYING
func send_command_result(seq: int, code: int, detail: int) -> void
func add_strike(n: int, now_ms: int) -> void;  func strikes_recent(now_ms: int) -> int
func update(now_ms: int) -> void                      # HELLO / LOADED timeouts and the delayed close
func on_transport_closed() -> void;  func is_closed() -> bool
```

## Invariants

1. I1: `on_packet` never throws and never touches the sim; every packet that fails a gate is dropped and counted, never
   half-parsed (04 s7, s11.4). Gate order: channel and channel hard cap, packet bucket, byte bucket, message id, catalogue
   size, state, handler.
2. I2: a reserved or server-bound id, a short or malformed HELLO / LOADED / COMMAND is a strike; rate drops, wrong channel,
   oversize, wrong state and duplicate or stale `seq` are not (04 s11.3 V-ANY, s11.4).
3. I3: HELLO must arrive within `hello_timeout_ms` (5 s) of connect, LOADED within `load_timeout_ms` (60 s,
   `match_rules.json`) of WELCOME; the link closes through `Transport.close` and reports `HELLO_TIMEOUT` / `LOAD_TIMEOUT` (04 s2.2).
4. I4: `refuse` sends REFUSE then closes `close_delay_ms` (500 ms) later; a CLOSING or CLOSED link ignores all packets.
5. I5: COMMAND uses the `rules.json` bucket (10/s, burst 30): excess answers `COMMAND_RESULT REJECTED_RATE` with the seq and
   is not struck. CHAT 2/s burst 5, QUICK_PING 1/s burst 3, REQUEST_KEYFRAME 1 per 5 s, packets 120/s, bytes 8 KB/s.
6. I6: `strike_limit` (20) strikes inside `strike_window_ms` (60 s) send `ADMIN_NOTICE(KICK)` and close; the 60 s
   `REFUSE(RATE_LIMIT)` ban and the `/report` are ServerSession's.
7. I7: time is caller-supplied integer milliseconds; the link reads no clock, so it replays identically under `LocalTransport`.
8. I8: a command taken from the link carries `player = slot`; `taken_seqs[i]` is the wire seq of the i-th command of the latest `take_commands`.
9. I9: a LOADED whose hash differs from `expected_map_hash` is a strike and leaves the link in LOADING.

## Data owned

Per-link token buckets, the 60 s strike journal, and the command / control / input queues (bounded: `control_queue_max`
newest-dropped, `input_queue_max` oldest-dropped; commands are bounded by the command bucket). Reads `rules.json`
(`command_rate_per_s`, `command_burst`) and `match_rules.json` (`load_timeout_s`) only through `LinkLimits.from_defs`.
The other limits are transport policy (not sim state) with 04 citations in `link_limits.gd`.

## Events emitted / consumed

None (no signals; ServerSession polls `state`). Consumes `Transport.packet` through `ServerSession._on_packet` -> `on_packet`.

## Performance budget

Not on a sim hot path. `on_packet` is O(1) per packet (a few bucket takes, one id lookup) plus one decode for COMMAND;
8 links x 120 packets/s is < 1,000 calls/s. `strikes_recent` is O(strikes in window <= 20).

## Test entry points

`godot/test/net/server/test_client_link.gd` (handshake, timeouts, queues, strikes, `HelloMsg`, `LinkLimits`),
`godot/test/net/server/test_link_rates.gd` (every 04 s11.4 rate row), `godot/test/net/server/test_token_bucket.gd`.

## How to add X (recipes for the cheapest tier)

A new rate row: add the `var` to `LinkLimits` with its 04 citation, add a `TokenBucket` to `ClientLink._init`, take from it in
`_route`, and add a positive and a negative case to `test_link_rates.gd`.
