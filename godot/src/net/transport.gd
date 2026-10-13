class_name Transport extends RefCounted
## The transport interface (04 s6.1, 01 s9.4). Implementations: LocalTransport (NET-11), ENet (NET-12),
## WebSocket (NET-13). Connection ids are session-wide; signals are emitted synchronously from poll().
## No Nodes, no threads (web is single-threaded, 03 s11).

enum DisconnectReason { TIMEOUT, REMOTE_CLOSE, LOCAL_CLOSE, ERROR }   # append-only

signal connected(conn: int)
signal disconnected(conn: int, reason: int)
signal packet(conn: int, channel: int, bytes: PackedByteArray)


## Drain the underlying peer and emit signals synchronously.
func poll() -> void:
	pass


## `reliable` is advisory: the channel's mode (Protocol.CHANNEL_MODE) decides delivery.
func send(_conn: int, _channel: int, _bytes: PackedByteArray, _reliable: bool) -> void:
	pass


func rtt_ms(_conn: int) -> int:
	return 0


## &"enet" | &"ws" | &"local" | &"webrtc"
func kind() -> StringName:
	return &"none"


## Protocol.Platform.WEB for a browser peer (timeout policy), else a native value.
func platform_hint(_conn: int) -> int:
	return Protocol.Platform.LINUX


func close(_conn: int, _reason: int) -> void:
	pass


func stats(_conn: int) -> TransportStats:
	return TransportStats.new()


func _emit_connected(conn: int) -> void:
	connected.emit(conn)


func _emit_disconnected(conn: int, reason: int) -> void:
	disconnected.emit(conn, reason)


func _emit_packet(conn: int, channel: int, bytes: PackedByteArray) -> void:
	packet.emit(conn, channel, bytes)
