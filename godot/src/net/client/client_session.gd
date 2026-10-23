class_name ClientSession extends RefCounted
## The client half of the match plane (01 s9.4, 04 s2.2, s5): one per match, on any Transport (LocalTransport,
## ENet, WebSocket, ReplayTransport). State machine CONNECTING -> LOADING (WELCOME) -> PLAYING (LOADED sent
## and a world state decoded: the join KEYFRAME or a FULL snapshot) -> ENDED (MATCH_END, REFUSE, `leave`); a transport loss in LOADING / PLAYING is RECONNECTING
## (the retry loop is NET-20). `tick()` (30 Hz, single-threaded, web-safe) polls the transport, routes every packet
## through the total decoders (catalogue channel check first, 04 s11.4: a wrong-channel, unknown or oversize message
## is dropped and counted), advances the clock (ClientClock: drift estimator, time dilation), sends SNAPSHOT_ACK for
## complete ticks only (10 Hz, R0 B.10 A-36), PING (1 Hz) and RosterSync's REQUEST_KEYFRAME, then samples
## NetSimView at the render tick. Prediction / INPUT are NET-18: `set_pilot_input` stores the input for it.

enum State { CONNECTING, LOADING, PLAYING, RECONNECTING, ENDED }

signal state_changed(state: int)

const ACK_EVERY_TICKS: int = 3              ## SNAPSHOT_ACK 10/s when not possessing (04 s2.3)
const PING_EVERY_TICKS: int = 30            ## PING 1/s

var state: int = State.CONNECTING
var local_player: int = 0
var team: int = 0
var phase: int = Protocol.SessionPhase.LOBBY
var welcome: WelcomeInfo = WelcomeInfo.new()
var clock: ClientClock = ClientClock.new()
var roster_sync: RosterSync = RosterSync.new()
var decoder: SnapshotDecoder
var keyframes: KeyframeCodec = KeyframeCodec.new()
var refuse_reason: int = -1
var end_reason: int = -1
var events: Array[WireEvent] = []           ## decoded this tick (cleared at the start of tick())
var pilot_input: PilotInput = null          ## the latest local input (Prediction, NET-18)
var ticks: int = 0
var last_tick_us: int = 0
## counters
var packets_in: int = 0
var dropped: int = 0                        ## wrong channel, unknown / reserved id, oversize, wrong state
var malformed: int = 0                      ## a decoder rejected the bytes
var snapshots_ok: int = 0
var held: int = 0
var keyframes_applied: int = 0
var acks_sent: int = 0
var last_ack: int = 0
var _transport: Transport
var _server_conn: int = 1                          # the server's conn id on this endpoint (LocalTransport.CLIENT_CONN)
var _view: NetSimView
var _hello: PackedByteArray = PackedByteArray()
var _loaded: bool = false
var _cmd_seq: int = 0
var _clock_src: LocalClock = null
var _held_kf: PackedByteArray = PackedByteArray()
var _team_wire: TeamStateWire = TeamStateWire.new()
var _scratch: PackedInt64Array = PackedInt64Array()
var _ready_ticks: PackedInt32Array = PackedInt32Array()
var _ready_bytes: Array[PackedByteArray] = []


func _init(transport: Transport, player: int) -> void:
	_transport = transport
	local_player = player
	decoder = SnapshotDecoder.new(0.0, 30, 0, roster_sync.roster)
	_view = NetSimView.new(roster_sync.roster, decoder)
	_view.slot_id = player
	if transport is LocalTransport:
		_clock_src = (transport as LocalTransport).clock
	var _a: int = transport.connected.connect(_on_connected)
	var _b: int = transport.disconnected.connect(_on_disconnected)
	var _c: int = transport.packet.connect(_on_packet)


## Content defs (gravity, tick rate, radii) and the loaded map's terrain.
func configure(content: ContentSet, terrain: Terrain) -> void:
	configure_defs(NetDefs.new(content), terrain)


## configure with prepared tables (tests, replays with a recorded content set).
func configure_defs(defs: NetDefs, terrain: Terrain) -> void:
	_view.bind(defs, terrain)
	clock = ClientClock.new(defs.tick_hz)


## HELLO to send on connect (or now, when the transport is already connected). Empty bytes on bad arguments.
func hello(content_hash: PackedByteArray, join_token: PackedByteArray, platform: int, input_class: int, role: int) -> bool:
	_hello = SessionCodec.encode_hello(content_hash, join_token, 0, platform, input_class, role)
	return not _hello.is_empty()


## The map pack is loaded and verified: LOADED (once, in LOADING).
func mark_loaded(map_hash: PackedByteArray) -> void:
	if state != State.LOADING or _loaded:
		return
	var b: PackedByteArray = SessionCodec.encode_loaded(map_hash)
	if not b.is_empty():
		_loaded = true
		_send(Protocol.CH_CONTROL, b)


func view() -> NetSimView:
	return _view


func render_tick() -> float:
	return clock.render_tick()


## The tick the client acknowledges: the newest complete one (R0 B.10 A-36).
func ack_tick() -> int:
	return decoder.store.complete_tick


func send_command(cmd: Command) -> void:
	if state == State.ENDED or cmd == null:
		return
	var b: PackedByteArray = CommandCodec.encode_message(_cmd_seq & 0xFFFF, maxi(floori(clock.clock), 0), cmd)
	if not b.is_empty():
		_cmd_seq += 1
		_send(Protocol.CH_CONTROL, b)


func set_pilot_input(input: PilotInput) -> void:
	pilot_input = input


func leave() -> void:
	_set_state(State.ENDED)


func tick() -> void:
	var t0: int = Time.get_ticks_usec()
	events.clear()
	_transport.poll()
	var now: float = now_ms()
	clock.advance(now)
	_replay_held()
	if state == State.LOADING and _loaded and decoder.store.newest_tick > 0:
		_set_state(State.PLAYING)
	if state == State.LOADING or state == State.PLAYING:
		var rq: PackedByteArray = roster_sync.poll(_now_tick())
		if not rq.is_empty():
			_send(Protocol.CH_CONTROL, rq)
		if ticks % ACK_EVERY_TICKS == 0 and decoder.store.complete_tick > 0:
			last_ack = decoder.store.complete_tick
			acks_sent += 1
			_send(Protocol.CH_INPUT, SessionCodec.encode_snapshot_ack(last_ack, keyframes.seq))
		if ticks % PING_EVERY_TICKS == 0:
			_send(Protocol.CH_INPUT, SessionCodec.encode_ping(int(now) & 0xFFFFFFFF))
	_view.sample(clock.render_tick())
	ticks += 1
	last_tick_us = Time.get_ticks_usec() - t0


## Local milliseconds: the LocalTransport's virtual clock, else the engine's monotonic clock.
func now_ms() -> float:
	return _clock_src.now_ms() if _clock_src != null else float(Time.get_ticks_usec()) / 1000.0


## One received message (the transport's `packet` signal; also the fuzz entry). Never throws.
func receive(channel: int, bytes: PackedByteArray) -> void:
	packets_in += 1
	if bytes.is_empty() or Protocol.is_client_to_server(bytes[0]) or not Protocol.channel_allows(channel, bytes[0]) \
			or bytes.size() > Protocol.max_bytes(bytes[0]) or state == State.ENDED:
		dropped += 1
		return
	var id: int = bytes[0]
	if id == Protocol.WELCOME or id == Protocol.REFUSE or id == Protocol.MATCH_STATE or id == Protocol.MATCH_END \
			or id == Protocol.PONG:
		_on_session(id, bytes)
	elif state != State.LOADING and state != State.PLAYING:
		dropped += 1
	else:
		_on_world(id, bytes)


func _on_session(id: int, b: PackedByteArray) -> void:
	if id == Protocol.WELCOME:
		if state != State.CONNECTING or not SessionCodec.decode_welcome(b, welcome):
			_bad()
			return
		team = welcome.team
		decoder.store.team = team
		_view.team_id = team
		_view.slot_id = welcome.slot
		clock.reset()
		clock.observe(welcome.tick, now_ms())
		_set_state(State.LOADING)
	elif id == Protocol.REFUSE:
		if not SessionCodec.decode_refuse(b, _scratch):
			_bad()
			return
		refuse_reason = int(_scratch[0])
		_set_state(State.ENDED)
	elif id == Protocol.MATCH_STATE:
		if not SessionCodec.decode_match_state(b, _scratch):
			_bad()
			return
		phase = int(_scratch[0])
	elif id == Protocol.MATCH_END:
		if not SessionCodec.decode_match_end_head(b, _scratch):
			_bad()
			return
		end_reason = int(_scratch[1])
		_set_state(State.ENDED)
	elif SessionCodec.decode_pong(b, _scratch):
		clock.observe_rtt(now_ms() - float(_scratch[0]))
		clock.observe(int(_scratch[1]), now_ms())
	else:
		_bad()


func _on_world(id: int, b: PackedByteArray) -> void:
	if id == Protocol.SNAPSHOT:
		_on_snapshot(b)
	elif id == Protocol.ENTITY_META:
		if roster_sync.on_meta(b) < 0:
			_bad()
		_retry_keyframe()
	elif id == Protocol.ROSTER_REMOVE:
		if roster_sync.on_remove(b) < 0:
			_bad()
	elif id == Protocol.KEYFRAME:
		_on_keyframe(b)
	elif id == Protocol.TEAM_STATE:
		if TeamStateCodec.decode(b, _team_wire):
			_view.set_team_state(_team_wire)
		else:
			_bad()
	elif id == Protocol.EVENTS:
		_on_events(b)
	else:
		dropped += 1                            # catalogue messages other lanes / tasks consume (NET-18, NET-39, ...)


func _on_snapshot(b: PackedByteArray) -> void:
	var st: int = decoder.decode(b)
	if st == SnapshotDecoder.Status.OK or st == SnapshotDecoder.Status.STALE:
		clock.observe(b.decode_u32(1), now_ms())
		snapshots_ok += 1 if st == SnapshotDecoder.Status.OK else 0
	elif st == SnapshotDecoder.Status.MISSING_ROSTER:
		held += 1
		roster_sync.hold(_now_tick(), b.decode_u32(1), b, decoder.missing.duplicate())
	elif st == SnapshotDecoder.Status.MALFORMED:
		malformed += 1


func _on_keyframe(b: PackedByteArray) -> void:
	var st: int = keyframes.decode(b, decoder)
	if st == KeyframeCodec.Status.OK:
		_held_kf = PackedByteArray()
		keyframes_applied += 1
		clock.observe(keyframes.tick, now_ms())
	elif st == KeyframeCodec.Status.MISSING_ROSTER:
		_held_kf = b
	elif st == KeyframeCodec.Status.MALFORMED:
		malformed += 1


func _retry_keyframe() -> void:
	if not _held_kf.is_empty():
		var b: PackedByteArray = _held_kf
		_held_kf = PackedByteArray()
		_on_keyframe(b)


func _on_events(b: PackedByteArray) -> void:
	var start: int = events.size()
	if EventCodec.decode(b, events) < 0:
		_bad()
		return
	for k: int in range(start, events.size()):
		var e: WireEvent = events[k]
		if e.kind == Protocol.EventKind.POSSESSED:
			_view.set_possessor(e.v[0], e.v[1])
		elif e.kind == Protocol.EventKind.RELEASED:
			_view.set_possessor(e.v[0], NetSimView.NONE)


## Held snapshot records whose ENTITY_META arrived (RosterSync), decoded in arrival order.
func _replay_held() -> void:
	var n: int = roster_sync.take_ready(_ready_ticks, _ready_bytes)
	for k: int in n:
		_on_snapshot(_ready_bytes[k])
	_ready_ticks.clear()
	_ready_bytes.clear()


func _now_tick() -> int:
	return maxi(floori(clock.clock), 0)


func _bad() -> void:
	malformed += 1


func _send(channel: int, b: PackedByteArray) -> void:
	_transport.send(_server_conn, channel, b, channel == Protocol.CH_CONTROL)


func _set_state(s: int) -> void:
	if s == state:
		return
	state = s
	state_changed.emit(s)


func _on_connected(conn: int) -> void:
	_server_conn = conn
	if state == State.CONNECTING and not _hello.is_empty():
		_send(Protocol.CH_CONTROL, _hello)


func _on_disconnected(_c: int, _reason: int) -> void:
	if state == State.LOADING or state == State.PLAYING:
		_set_state(State.RECONNECTING)
	elif state == State.CONNECTING:
		_set_state(State.ENDED)


func _on_packet(_c: int, channel: int, bytes: PackedByteArray) -> void:
	receive(channel, bytes)
