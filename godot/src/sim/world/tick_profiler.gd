class_name TickProfiler extends RefCounted
## The 14 rows of 03 s4.4 for `SimWorld.profile()`, in milliseconds for the last tick: row 0 is `ServerSession`'s
## (transport poll + decode, never written here), rows 1..12 are the 03 s4.2 budget rows of `SimWorld.step()`,
## row 13 the whole step. 8b runs inside `Collision.step` interleaved per projectile (TA-14), so its time is in
## ROW_COLLISION and ROW_TERRAIN_8B stays 0 (the 8b sample count is `Collision.terrain_samples`). Wall-clock reads
## never feed back into sim state (determinism unaffected); disabled unless `MatchRules.profile_enabled`.

const ROWS: int = 14
const ROW_TRANSPORT: int = 0
const ROW_COMMANDS: int = 1
const ROW_AI: int = 2
const ROW_PATHING: int = 3
const ROW_KINEMATICS: int = 4
const ROW_PROJECTILES: int = 5
const ROW_SPATIAL: int = 6
const ROW_COLLISION: int = 7
const ROW_TERRAIN_8B: int = 8
const ROW_COMBAT: int = 9
const ROW_ECONOMY: int = 10
const ROW_VISION: int = 11
const ROW_EVENTS: int = 12
const ROW_TOTAL: int = 13
const _US_PER_MS: int = 1000

var enabled: bool = false
var rows: PackedFloat32Array = PackedFloat32Array()

var _t0: int = 0
var _lap: int = 0


func _init() -> void:
	var e: int = rows.resize(ROWS)
	assert(e == OK)
	rows.fill(0.0)


## Starts a tick: rows 1..13 reset (row 0 keeps whatever the session wrote).
func begin() -> void:
	if not enabled:
		return
	for r: int in range(ROW_COMMANDS, ROWS):
		rows[r] = 0.0
	_t0 = Time.get_ticks_usec()
	_lap = _t0


## Adds the time since the previous lap to `row`.
func lap(row: int) -> void:
	if not enabled:
		return
	var now: int = Time.get_ticks_usec()
	rows[row] += float(now - _lap) / float(_US_PER_MS)
	_lap = now


func finish() -> void:
	if enabled:
		rows[ROW_TOTAL] = float(Time.get_ticks_usec() - _t0) / float(_US_PER_MS)
