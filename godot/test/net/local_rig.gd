class_name LocalRig extends RefCounted
## Test helper (NET-11): one LocalTransport server, one client, a shared clock, and recorders for what each side
## received. Payload of a test packet = 4-byte little-endian index; helpers send/step/record.

var clock: LocalClock = LocalClock.new()
var server: LocalTransport = LocalTransport.new_server(clock)
var client: LocalTransport = null
var server_conn: int = 0
## Received log rows: [tick, channel, index]
var at_client: Array[Vector3i] = []
var at_server: Array[Vector3i] = []
var client_events: Array[String] = []
var server_events: Array[String] = []


func _init(model: FaultModel = null, to_clients: bool = true, to_server: bool = true) -> void:
	if model != null:
		server.set_fault_model(model, to_clients, to_server)
	client = server.connect_client()
	server_conn = client.server_conn_of()
	server.packet.connect(_on_server_packet)
	client.packet.connect(_on_client_packet)
	server.connected.connect(func(_c: int) -> void: server_events.append("connected"))
	client.connected.connect(func(_c: int) -> void: client_events.append("connected"))
	server.disconnected.connect(func(_c: int, r: int) -> void: server_events.append("disc%d" % r))
	client.disconnected.connect(func(_c: int, r: int) -> void: client_events.append("disc%d" % r))


func _on_server_packet(_conn: int, channel: int, bytes: PackedByteArray) -> void:
	at_server.append(Vector3i(clock.tick(), channel, bytes.decode_u32(0)))


func _on_client_packet(_conn: int, channel: int, bytes: PackedByteArray) -> void:
	at_client.append(Vector3i(clock.tick(), channel, bytes.decode_u32(0)))


static func payload(index: int, size: int = 8) -> PackedByteArray:
	var b: PackedByteArray = PackedByteArray()
	var _e: Error = b.resize(maxi(size, 4))
	b.encode_u32(0, index)
	return b


func send_s2c(channel: int, index: int, size: int = 8) -> void:
	server.send(server_conn, channel, payload(index, size), channel == Protocol.CH_CONTROL)


func send_c2s(channel: int, index: int, size: int = 8) -> void:
	client.send(LocalTransport.CLIENT_CONN, channel, payload(index, size), channel == Protocol.CH_CONTROL)


## Advance one tick and poll both ends.
func step() -> void:
	clock.advance_tick()
	server.poll()
	client.poll()


func run_ticks(n: int) -> void:
	for i: int in n:
		step()


## Delivery order fingerprint of a log: "tick:channel:index" joined; used for determinism checks.
static func fingerprint(log_rows: Array[Vector3i]) -> int:
	var h: int = 17
	for r: Vector3i in log_rows:
		h = (h * 31 + r.x) & 0x7FFFFFFF
		h = (h * 31 + r.y) & 0x7FFFFFFF
		h = (h * 31 + r.z) & 0x7FFFFFFF
	return h
