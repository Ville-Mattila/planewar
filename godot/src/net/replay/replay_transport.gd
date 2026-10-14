class_name ReplayTransport extends Transport
## Plays a `.pwr` into a ClientSession as if it were a server (04 s13.2): poll() advances the playhead by
## `speed` ticks (30 Hz, fractions accumulate) and emits every frame due as the wire packets it holds (ENTITY_META,
## ROSTER_REMOVE, SNAPSHOT, EVENTS) on their live channels, connection id 1. Playback never touches the reader's own
## state. seek(tick) rewinds to the newest keyframe at or before `tick` and returns its tick: the client resets its
## baselines when it sees `keyframe_started` and then receives the frames up to the playhead. kind() == &"replay".

signal keyframe_started(tick: int)
signal finished

const CONN: int = 1

var speed: float = 1.0
var paused: bool = false
var playhead: float = 0.0
var packets_sent: int = 0
var _reader: ReplayReader = null
var _started: bool = false
var _done: bool = false


func _init(reader: ReplayReader) -> void:
	_reader = reader


func kind() -> StringName:
	return &"replay"


func poll() -> void:
	if not _started:
		_started = true
		_emit_connected(CONN)
		playhead = float(maxi(_reader.peek_tick(), 0))
	if paused or _done:
		return
	playhead += speed
	_deliver()


## Moves the playhead to `target` (clamped to the file) and returns the keyframe tick playback restarts from, or -1.
func seek(target: int) -> int:
	var k: int = _reader.seek_keyframe(target)
	if k < 0:
		return -1
	playhead = float(k)
	_done = false
	_reader.tick = k
	return k


func _deliver() -> void:
	while not _reader.at_end() and float(_reader.peek_tick()) <= playhead:
		var t: int = _reader.peek_tick()
		var type: int = _reader.next_frame(false)
		if type == ReplayReader.NO_FRAME:
			break
		if type == ReplayFormat.FrameType.KEYFRAME:
			keyframe_started.emit(t)
		for p: PackedByteArray in _reader.packets:
			packets_sent += 1
			_emit_packet(CONN, maxi(Protocol.channel_of(p[0]), 0), p)
	if _reader.at_end() and not _done:
		_done = true
		finished.emit()
		_emit_disconnected(CONN, DisconnectReason.REMOTE_CLOSE)


func close(_conn: int, _reason: int) -> void:
	_done = true
