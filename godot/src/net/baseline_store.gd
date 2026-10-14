class_name BaselineStore extends RefCounted
## Per-client ring of the last DEPTH (32) snapshot frames (04 s3.4 baseline rule). The server keeps one per
## client as the mirror of what that client holds; the client keeps its own for decoding. Frames are reused,
## never reallocated; a frame is found by tick only while its ring slot still carries that tick.
## A client acknowledges only a complete tick (every packet index 0 .. LAST received, R0 B.10 A-36), so any
## acknowledged tick, split or not, is a server baseline.

const DEPTH: int = 32

var team: int = 0
var acked_tick: int = 0                     # server: newest acked usable tick; 0 = none
var newest_tick: int = 0                    # client: newest tick with at least one packet decoded
var complete_tick: int = 0                  # client: newest complete tick (the ack it sends, A-36)
var _frames: Array[BaselineFrame] = []


func _init(team_id: int = 0) -> void:
	team = team_id
	for _i: int in DEPTH:
		_frames.append(BaselineFrame.new())


## The frame for tick `t`, or null when it was never built or has been overwritten.
func frame_at(t: int) -> BaselineFrame:
	if t <= 0:
		return null
	var f: BaselineFrame = _frames[t % DEPTH]
	return f if f.tick == t else null


## Starts frame `t` as a copy of frame `base_tick` (or empty when base_tick is 0 or missing).
func begin(t: int, base_tick: int) -> BaselineFrame:
	var f: BaselineFrame = _frames[t % DEPTH]
	var b: BaselineFrame = frame_at(base_tick)
	if b == null or b == f:
		f.clear(t)
	else:
		f.copy_from(b, t)
	return f


## Server: the client acknowledged tick `t` (INPUT / SNAPSHOT_ACK ack_tick). Only usable frames advance.
func ack(t: int) -> void:
	var f: BaselineFrame = frame_at(t)
	if f != null and f.usable and t > acked_tick:
		acked_tick = t


## Server: the baseline to encode tick `t` against; 0 when none is acked within DEPTH ticks.
func base_for(t: int) -> int:
	if acked_tick <= 0 or t - acked_tick >= DEPTH or t <= acked_tick or frame_at(acked_tick) == null:
		return 0
	return acked_tick


## Forget everything (keyframe reset, NET-07).
func reset() -> void:
	acked_tick = 0
	newest_tick = 0
	complete_tick = 0
	for f: BaselineFrame in _frames:
		f.tick = 0
		f.usable = false
