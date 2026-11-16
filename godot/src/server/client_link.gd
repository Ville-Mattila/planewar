class_name ClientLink extends RefCounted
## One connected client as the server sees it (04 s7, s11): handshake state machine, per-link queues, token-bucket
## rate limits and strikes. `on_packet` is the only entry from a transport's `packet` signal and does only gating,
## parsing and queuing (04 s7): it never touches the sim. Time is caller-supplied integer milliseconds, so every
## timeout and bucket is deterministic under LocalTransport. Verifying the join token, choosing slot / team and
## sending MATCH_STATE are ServerSession's (NET-15); this class owns what a link can do on its own.

enum State { PRE_HELLO, LOADING, LOADED, PLAYING, CLOSING, CLOSED }
enum Verdict { QUEUED, DROPPED_CHANNEL, DROPPED_SIZE, DROPPED_RATE, DROPPED_STATE, MALFORMED, VIOLATION }
enum CloseReason { NONE, HELLO_TIMEOUT, LOAD_TIMEOUT, REFUSED, KICKED, TRANSPORT }

const KICK_TEXT: String = "protocol abuse"

var conn: int
var transport: Transport
var limits: LinkLimits
var state: State = State.PRE_HELLO
var close_reason: CloseReason = CloseReason.NONE
var slot: int = Protocol.SLOT_SPECTATOR
var team: int = 0
var session_id: int = 0
var direct_view: bool = false          ## offline local link: reads LocalSimView, no snapshots (04 s7.1)
var strikes: int = 0                   ## lifetime total; the kick rule uses the 60 s window
var hello: HelloMsg = null
var expected_map_hash: PackedByteArray = PackedByteArray()
var loaded_map_hash: PackedByteArray = PackedByteArray()
var connected_ms: int
var welcomed_ms: int = 0
var close_at_ms: int = 0
var last_seq: int = -1
var taken_seqs: PackedInt32Array = PackedInt32Array()   ## wire seq of each command the latest `take_commands` returned
var dropped_rate: int = 0
var dropped_size: int = 0
var dropped_channel: int = 0
var dropped_state: int = 0
var dropped_queue: int = 0             ## evicted or refused because a bounded queue was full
var malformed: int = 0
var packets_in: int = 0

var _packets: TokenBucket
var _bytes: TokenBucket
var _commands: TokenBucket
var _chat: TokenBucket
var _pings: TokenBucket
var _keyframes: TokenBucket
var _strike_times: PackedInt64Array = PackedInt64Array()
var _cmd_queue: Array[Command] = []
var _cmd_seqs: PackedInt32Array = PackedInt32Array()
var _control: Array[PackedByteArray] = []
var _inputs: Array[PackedByteArray] = []


func _init(p_conn: int, p_transport: Transport, p_limits: LinkLimits, now_ms: int) -> void:
	conn = p_conn
	transport = p_transport
	limits = p_limits
	connected_ms = now_ms
	_packets = TokenBucket.new(limits.packets_per_s, limits.packet_burst, now_ms)
	_bytes = TokenBucket.new(limits.bytes_per_s, limits.byte_burst, now_ms)
	_commands = TokenBucket.new(limits.command_per_s, limits.command_burst, now_ms)
	_chat = TokenBucket.new(limits.chat_per_s, limits.chat_burst, now_ms)
	_pings = TokenBucket.new(limits.ping_per_s, limits.ping_burst, now_ms)
	# REQUEST_KEYFRAME: one per interval, no burst.
	_keyframes = TokenBucket.new(1000.0 / float(limits.keyframe_interval_ms), 1.0, now_ms)


# region ingress

## Gates, parses and queues one inbound packet (04 s7). Order: channel and hard size cap, packet and byte buckets,
## message id (reserved / server-bound ids are a violation: strike), channel and catalogue size, state, then the
## per-id handler. Never throws; a packet that fails any gate is dropped and counted.
func on_packet(channel: int, bytes: PackedByteArray, now_ms: int) -> Verdict:
	packets_in += 1
	if state >= State.CLOSING:
		return Verdict.DROPPED_STATE
	if channel < 0 or channel >= Protocol.CHANNEL_COUNT or bytes.is_empty():
		dropped_channel += 1
		return Verdict.DROPPED_CHANNEL
	if bytes.size() > LinkLimits.channel_cap(channel):
		dropped_size += 1
		return Verdict.DROPPED_SIZE
	if not _packets.take(now_ms) or not _bytes.take(now_ms, float(bytes.size())):
		dropped_rate += 1
		return Verdict.DROPPED_RATE
	var id: int = bytes[0]
	if not Protocol.is_known(id) or not Protocol.is_client_to_server(id):
		return _violation(now_ms)
	if not Protocol.channel_allows(channel, id):
		dropped_channel += 1
		return Verdict.DROPPED_CHANNEL
	if bytes.size() > Protocol.max_bytes(id):
		dropped_size += 1
		return Verdict.DROPPED_SIZE
	if state == State.PRE_HELLO and id != Protocol.HELLO:
		dropped_state += 1
		return Verdict.DROPPED_STATE
	return _route(id, bytes, now_ms)


func _route(id: int, bytes: PackedByteArray, now_ms: int) -> Verdict:
	match id:
		Protocol.HELLO:
			return _on_hello(bytes, now_ms)
		Protocol.LOADED:
			return _on_loaded(bytes, now_ms)
		Protocol.COMMAND:
			return _on_command(bytes, now_ms)
		Protocol.CHAT:
			return _queue_control(bytes) if _chat.take(now_ms) else _rate_drop()
		Protocol.QUICK_PING:
			return _queue_control(bytes) if _pings.take(now_ms) else _rate_drop()
		Protocol.REQUEST_KEYFRAME:
			return _queue_control(bytes) if _keyframes.take(now_ms) else _rate_drop()
		Protocol.INPUT, Protocol.SNAPSHOT_ACK, Protocol.PING:
			return _queue_input(bytes)
		_:
			return _queue_control(bytes)


func _on_hello(bytes: PackedByteArray, now_ms: int) -> Verdict:
	if state != State.PRE_HELLO or hello != null:
		dropped_state += 1
		return Verdict.DROPPED_STATE
	var m: HelloMsg = HelloMsg.decode(bytes)
	if m == null:
		return _malformed(now_ms)
	hello = m
	return Verdict.QUEUED


func _on_loaded(bytes: PackedByteArray, now_ms: int) -> Verdict:
	if state != State.LOADING:
		dropped_state += 1
		return Verdict.DROPPED_STATE
	if bytes.size() != 1 + Protocol.HASH_BYTES:
		return _malformed(now_ms)
	var h: PackedByteArray = bytes.slice(1)
	if not expected_map_hash.is_empty() and h != expected_map_hash:
		return _malformed(now_ms)          # wrong map pack: strike, stay LOADING until the timeout
	loaded_map_hash = h
	state = State.LOADED
	return Verdict.QUEUED


func _on_command(bytes: PackedByteArray, now_ms: int) -> Verdict:
	var seq: int = CommandCodec.seq_of(bytes)
	if not _commands.take(now_ms):
		send_command_result(maxi(seq, 0), Protocol.ResultCode.REJECTED_RATE, 0)
		return _rate_drop()
	var cmd: Command = CommandCodec.decode_message(bytes)
	if cmd == null:
		send_command_result(maxi(seq, 0), Protocol.ResultCode.REJECTED_MALFORMED, 0)
		return _malformed(now_ms)
	var ahead: int = (seq - last_seq) & 0xFFFF
	if last_seq >= 0 and (ahead == 0 or ahead > 0x7FFF):
		return Verdict.DROPPED_STATE       # duplicate or stale seq: dropped silently, never struck (04 s11.3 V-ANY)
	last_seq = seq
	cmd.player = slot
	_cmd_queue.append(cmd)
	var _p: bool = _cmd_seqs.push_back(seq)
	return Verdict.QUEUED


func _queue_control(bytes: PackedByteArray) -> Verdict:
	if _control.size() >= limits.control_queue_max:
		dropped_queue += 1
		return Verdict.DROPPED_RATE
	_control.append(bytes)
	return Verdict.QUEUED


func _queue_input(bytes: PackedByteArray) -> Verdict:
	if _inputs.size() >= limits.input_queue_max:
		_inputs.pop_front()
		dropped_queue += 1
	_inputs.append(bytes)
	return Verdict.QUEUED


func _rate_drop() -> Verdict:
	dropped_rate += 1
	return Verdict.DROPPED_RATE


func _malformed(now_ms: int) -> Verdict:
	malformed += 1
	add_strike(1, now_ms)
	return Verdict.MALFORMED


func _violation(now_ms: int) -> Verdict:
	add_strike(1, now_ms)
	return Verdict.VIOLATION

# endregion

# region queues (drained by ServerSession.tick, 04 s7 step 2-3)

## Commands parsed since the last call, in arrival order; their wire seqs are in `taken_seqs` (same index).
func take_commands() -> Array[Command]:
	var out: Array[Command] = _cmd_queue
	taken_seqs = _cmd_seqs
	_cmd_queue = []
	_cmd_seqs = PackedInt32Array()
	return out


## Control packets (LEAVE, DOCTRINE_PICK, CHAT, QUICK_PING, INTEREST_HINT, REQUEST_KEYFRAME, SPECTATE_FOLLOW) since the last call.
func take_control() -> Array[PackedByteArray]:
	var out: Array[PackedByteArray] = _control
	_control = []
	return out


## Channel-1 packets (INPUT, SNAPSHOT_ACK, PING) since the last call.
func take_inputs() -> Array[PackedByteArray]:
	var out: Array[PackedByteArray] = _inputs
	_inputs = []
	return out

# endregion

# region handshake and lifecycle (04 s2.2)

## Sends WELCOME and enters LOADING; the LOADED timeout starts now. False (and nothing sent) unless a valid HELLO is
## pending in PRE_HELLO and `w` encodes.
func accept(w: WelcomeInfo, now_ms: int) -> bool:
	if state != State.PRE_HELLO or hello == null:
		return false
	var b: PackedByteArray = SessionCodec.encode_welcome(w)
	if b.is_empty():
		return false
	slot = w.slot
	team = w.team
	session_id = w.session_id
	expected_map_hash = w.map_hash
	welcomed_ms = now_ms
	state = State.LOADING
	transport.send(conn, Protocol.CH_CONTROL, b, true)
	return true


## REFUSE then close after `close_delay_ms` (04 s2.2). Valid in any live state.
func refuse(reason: int, server_version: int, text: String, now_ms: int) -> void:
	if state >= State.CLOSING:
		return
	transport.send(conn, Protocol.CH_CONTROL, SessionCodec.encode_refuse(reason, server_version, text), true)
	_begin_close(CloseReason.REFUSED, now_ms)


## LOADED -> PLAYING once ServerSession has sent the keyframe.
func start_playing() -> void:
	if state == State.LOADED:
		state = State.PLAYING


func send_command_result(seq: int, code: int, detail: int) -> void:
	var b: PackedByteArray = PackedByteArray([Protocol.COMMAND_RESULT, 0, 0, code & 0xFF, detail & 0xFF])
	b.encode_u16(1, seq & 0xFFFF)
	transport.send(conn, Protocol.CH_CONTROL, b, true)


## Adds `n` strikes at `now_ms`; reaching `strike_limit` inside `strike_window_ms` kicks the link (ADMIN_NOTICE KICK,
## close after `close_delay_ms`). The ban on reconnect (`kick_ban_ms`) is ServerSession's.
func add_strike(n: int, now_ms: int) -> void:
	strikes += n
	for _k: int in n:
		var _p: bool = _strike_times.push_back(now_ms)
	if strikes_recent(now_ms) >= limits.strike_limit and state < State.CLOSING:
		var t: PackedByteArray = KICK_TEXT.to_utf8_buffer()
		var b: PackedByteArray = PackedByteArray([Protocol.ADMIN_NOTICE, Protocol.AdminNotice.KICK, t.size()])
		b.append_array(t)
		transport.send(conn, Protocol.CH_CONTROL, b, true)
		_begin_close(CloseReason.KICKED, now_ms)


func strikes_recent(now_ms: int) -> int:
	var keep: PackedInt64Array = PackedInt64Array()
	for t: int in _strike_times:
		if now_ms - t < limits.strike_window_ms:
			var _p: bool = keep.push_back(t)
	_strike_times = keep
	return keep.size()


## Timers (call at 1 Hz or faster): HELLO timeout, LOADED timeout, and the delayed close after REFUSE / KICK.
func update(now_ms: int) -> void:
	if state == State.PRE_HELLO and now_ms - connected_ms >= limits.hello_timeout_ms:
		_close_now(CloseReason.HELLO_TIMEOUT)
	elif state == State.LOADING and now_ms - welcomed_ms >= limits.load_timeout_ms:
		_close_now(CloseReason.LOAD_TIMEOUT)
	elif state == State.CLOSING and now_ms >= close_at_ms:
		_close_now(close_reason)


## The transport reported the connection gone.
func on_transport_closed() -> void:
	if state != State.CLOSED:
		if close_reason == CloseReason.NONE:
			close_reason = CloseReason.TRANSPORT
		state = State.CLOSED


func is_closed() -> bool:
	return state == State.CLOSED


func _begin_close(reason: CloseReason, now_ms: int) -> void:
	state = State.CLOSING
	close_reason = reason
	close_at_ms = now_ms + limits.close_delay_ms


func _close_now(reason: CloseReason) -> void:
	close_reason = reason
	state = State.CLOSED
	transport.close(conn, Transport.DisconnectReason.LOCAL_CLOSE)

# endregion
