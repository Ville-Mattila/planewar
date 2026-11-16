class_name AiGround extends RefCounted
## The ground follower's state by entity slot (AI-16, 05 s5.7), kept out of `AiState`'s own arrays like `AiHitLog`; it is
## in the `AiState` S4 bytes (FORMAT 8). The route itself is `AiState.path` / `path_ticket`; this is what follows it:
## the progress index into the route, the tick the pending ticket was asked for, the path-grid face stamp the route was
## made under, the stuck window (where and when it began) with its strikes, and the last tick a threat was seen.
## Preallocated, no allocation per tick.

const RECORD_BYTES: int = 35         ## 5 x i32, 3 x u8, 1 Vector3 (3 x f32)
const RUN_UNKNOWN: int = 255         ## `brake_run` when someone else drove the unit (a pilot): treated as a run at the hold

var idx: PackedInt32Array = PackedInt32Array()          ## index of the route point the unit has reached (GroundFollower.drive)
var req: PackedInt32Array = PackedInt32Array()          ## tick the current ticket (or the last refused request) was made
var ver: PackedInt32Array = PackedInt32Array()          ## sum of the path-grid face versions of `faces` when the route arrived
var stuck_tick: PackedInt32Array = PackedInt32Array()   ## start tick of the current stuck window
var threat: PackedInt32Array = PackedInt32Array()       ## last tick the brain saw a threat (HIT or an armed enemy in range); 0 = never
var faces: PackedByteArray = PackedByteArray()          ## bit f: the route crosses path-grid face f
var strikes: PackedByteArray = PackedByteArray()        ## stuck strikes on the current destination (05 s5.7)
var brake_run: PackedByteArray = PackedByteArray()      ## consecutive ticks BRAKE was driven (overlay or brain), saturating; RUN_UNKNOWN while not the AI's
var stuck_pos: PackedVector3Array = PackedVector3Array() ## position at the start of the stuck window


func resize(slots: int) -> void:
	var _r: Array[int] = [idx.resize(slots), req.resize(slots), ver.resize(slots), stuck_tick.resize(slots),
		threat.resize(slots), faces.resize(slots), strikes.resize(slots), brake_run.resize(slots), stuck_pos.resize(slots)]


func clear(s: int) -> void:
	idx[s] = 0
	req[s] = 0
	ver[s] = 0
	stuck_tick[s] = 0
	threat[s] = 0
	faces[s] = 0
	strikes[s] = 0
	brake_run[s] = 0
	stuck_pos[s] = Vector3.ZERO


func write(b: StreamPeerBuffer, s: int) -> void:
	for v: int in [idx[s], req[s], ver[s], stuck_tick[s], threat[s]]:
		b.put_32(v)
	b.put_u8(faces[s])
	b.put_u8(strikes[s])
	b.put_u8(brake_run[s])
	b.put_float(stuck_pos[s].x)
	b.put_float(stuck_pos[s].y)
	b.put_float(stuck_pos[s].z)


func read(b: StreamPeerBuffer, s: int) -> void:
	idx[s] = b.get_32()
	req[s] = b.get_32()
	ver[s] = b.get_32()
	stuck_tick[s] = b.get_32()
	threat[s] = b.get_32()
	faces[s] = b.get_u8()
	strikes[s] = b.get_u8()
	brake_run[s] = b.get_u8()
	var x: float = b.get_float()
	var y: float = b.get_float()
	stuck_pos[s] = Vector3(x, y, b.get_float())
