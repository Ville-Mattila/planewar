class_name LocalTransport extends Transport
## In-process transport (04 s6.2): used by offline modes, the listen-server host and every net test. A server
## endpoint (`LocalTransport.new_server`) hands out client endpoints with `connect_client()`; each connection is
## a pair of LocalPipe queues delivered on poll() against the shared LocalClock. Zero latency unless a FaultModel
## is set (04 s15.1). Connection ids come from one counter per endpoint; a client endpoint's only peer is conn 1.

class _Conn extends RefCounted:
	var id: int = 0
	var out: LocalPipe = null           # this endpoint -> peer
	var inbound: LocalPipe = null       # peer -> this endpoint (the peer's `out`)
	var peer: LocalTransport = null
	var peer_conn: int = 0
	var platform: int = Protocol.Platform.LINUX
	var closed_by_peer: bool = false
	var pending_connect: bool = true
	var bytes_in: int = 0
	var bytes_out: int = 0
	var packets_in: int = 0
	var packets_out: int = 0
	var last_sent: int = 0
	var last_dropped: int = 0

const CLIENT_CONN: int = 1

var clock: LocalClock = null
var _conns: Dictionary[int, _Conn] = {}
var _next_conn: int = 1
var _is_server: bool = false
var _model_c2s: FaultModel = null
var _model_s2c: FaultModel = null
var _closed_events: Array[Vector2i] = []        # (conn, reason) queued by local close()
var _in_channels: PackedInt32Array = PackedInt32Array()
var _in_bytes: Array[PackedByteArray] = []


static func new_server(shared_clock: LocalClock = null) -> LocalTransport:
	var t: LocalTransport = LocalTransport.new()
	t._is_server = true
	t.clock = shared_clock if shared_clock != null else LocalClock.new()
	return t


## Server side: creates a client endpoint connected to this server. Returns the client transport; the server's
## conn id for it is `client.server_conn_of()`.
func connect_client(platform: int = Protocol.Platform.LINUX) -> LocalTransport:
	assert(_is_server)
	var c: LocalTransport = LocalTransport.new()
	c.clock = clock
	var s_conn: _Conn = _Conn.new()
	var c_conn: _Conn = _Conn.new()
	s_conn.id = _next_conn
	_next_conn += 1
	c_conn.id = CLIENT_CONN
	s_conn.platform = platform
	c_conn.platform = Protocol.Platform.SERVER_BOT
	s_conn.out = LocalPipe.new(clock)
	c_conn.out = LocalPipe.new(clock)
	s_conn.inbound = c_conn.out
	c_conn.inbound = s_conn.out
	s_conn.peer = c
	s_conn.peer_conn = c_conn.id
	c_conn.peer = self
	c_conn.peer_conn = s_conn.id
	_conns[s_conn.id] = s_conn
	c._conns[c_conn.id] = c_conn
	_apply_models(s_conn)
	return c


## Server conn id of a client endpoint (what the server sees); 0 when disconnected.
func server_conn_of() -> int:
	var c: _Conn = _conns.get(CLIENT_CONN)
	return 0 if c == null else c.peer_conn


## Applies `model` to server->client (`to_clients`) and/or client->server (`to_server`); null removes impairment.
## Existing and future connections are affected. Each pipe draws from its own fork of the model's seed.
func set_fault_model(model: FaultModel, to_clients: bool = true, to_server: bool = true) -> void:
	assert(_is_server)
	if to_clients:
		_model_s2c = model
	if to_server:
		_model_c2s = model
	for id: int in _conns:
		_apply_models(_conns[id])


func _apply_models(sc: _Conn) -> void:
	var tag: String = str(sc.id)
	sc.out.configure(_model_s2c, StringName("s2c:" + tag))
	sc.inbound.configure(_model_c2s, StringName("c2s:" + tag))


func link_pipe(conn: int, outbound: bool) -> LocalPipe:
	var c: _Conn = _conns.get(conn)
	if c == null:
		return null
	return c.out if outbound else c.inbound


func is_connected_to(conn: int) -> bool:
	return _conns.has(conn)


func connection_count() -> int:
	return _conns.size()


func kind() -> StringName:
	return &"local"


func platform_hint(conn: int) -> int:
	var c: _Conn = _conns.get(conn)
	return Protocol.Platform.LINUX if c == null else c.platform


func rtt_ms(conn: int) -> int:
	var c: _Conn = _conns.get(conn)
	if c == null:
		return 0
	var ms: float = 0.0
	if c.out.model != null:
		ms += c.out.model.latency_ms
	if c.inbound.model != null:
		ms += c.inbound.model.latency_ms
	return roundi(ms)


func send(conn: int, channel: int, bytes: PackedByteArray, _reliable: bool) -> void:
	var c: _Conn = _conns.get(conn)
	if c == null or channel < 0 or channel >= Protocol.CHANNEL_COUNT:
		return
	c.bytes_out += bytes.size()
	c.packets_out += 1
	c.out.push(channel, bytes)


func close(conn: int, _reason: int) -> void:
	var c: _Conn = _conns.get(conn)
	if c == null:
		return
	var _e: bool = _conns.erase(conn)
	_closed_events.append(Vector2i(conn, DisconnectReason.LOCAL_CLOSE))
	var pc: _Conn = c.peer._conns.get(c.peer_conn)
	if pc != null:
		pc.closed_by_peer = true


func stats(conn: int) -> TransportStats:
	var s: TransportStats = TransportStats.new()
	var c: _Conn = _conns.get(conn)
	if c == null:
		return s
	s.bytes_in = c.bytes_in
	s.bytes_out = c.bytes_out
	s.packets_in = c.packets_in
	s.packets_out = c.packets_out
	var sent: int = c.out.sent_unreliable - c.last_sent
	var dropped: int = c.out.dropped_unreliable - c.last_dropped
	s.loss_estimate = 0.0 if sent <= 0 else float(dropped) / float(sent)
	c.bytes_in = 0
	c.bytes_out = 0
	c.packets_in = 0
	c.packets_out = 0
	c.last_sent = c.out.sent_unreliable
	c.last_dropped = c.out.dropped_unreliable
	return s


func poll() -> void:
	for ev: Vector2i in _closed_events:
		_emit_disconnected(ev.x, ev.y)
	_closed_events.clear()
	var ids: Array[int] = _conns.keys()
	for id: int in ids:
		var c: _Conn = _conns.get(id)
		if c == null:
			continue
		if c.pending_connect:
			c.pending_connect = false
			_emit_connected(id)
		if c.closed_by_peer:
			var _e: bool = _conns.erase(id)
			_emit_disconnected(id, DisconnectReason.REMOTE_CLOSE)
			continue
		_deliver(c)


func _deliver(c: _Conn) -> void:
	_in_channels.clear()
	_in_bytes.clear()
	c.inbound.collect(_in_channels, _in_bytes)
	for i: int in _in_channels.size():
		var b: PackedByteArray = _in_bytes[i]
		c.bytes_in += b.size()
		c.packets_in += 1
		_emit_packet(c.id, _in_channels[i], b)
