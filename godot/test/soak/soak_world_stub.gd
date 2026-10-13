class_name SoakWorldStub
extends RefCounted
## S-CI-1 stand-in for SimWorld: 200 entities moving on a sphere, one step() per tick.
## Test-only; shared by the soak and the A/B perf scene. Not part of the game sim.

const ENTITY_COUNT: int = 200
const RADIUS: float = 100.0
const SPEED: float = 8.0
const TURN_RATE: float = 0.4
const SUBSTEPS: int = 6

var _pos: PackedVector3Array = PackedVector3Array()
var _dir: PackedVector3Array = PackedVector3Array()
var _rng: Rng
var _checksum: float = 0.0


func _init(seed_value: int) -> void:
	_rng = Rng.new(seed_value, 1)
	var _r1: int = _pos.resize(ENTITY_COUNT)
	var _r2: int = _dir.resize(ENTITY_COUNT)
	for i: int in ENTITY_COUNT:
		var p: Vector3 = Vector3(_rng.range_f(-1.0, 1.0), _rng.range_f(-1.0, 1.0), _rng.range_f(-1.0, 1.0))
		if p.length_squared() < 0.001:
			p = Vector3.UP
		p = p.normalized()
		var d: Vector3 = p.cross(Vector3(_rng.range_f(-1.0, 1.0), 0.5, _rng.range_f(-1.0, 1.0)))
		if d.length_squared() < 0.001:
			d = p.cross(Vector3.RIGHT)
		_pos[i] = p * RADIUS
		_dir[i] = d.normalized()


func step(dt: float) -> void:
	var sub_dt: float = dt / float(SUBSTEPS)
	for _s: int in SUBSTEPS:
		_substep(sub_dt)
	_checksum += _pos[0].x


func _substep(dt: float) -> void:
	for i: int in ENTITY_COUNT:
		var p: Vector3 = _pos[i]
		var d: Vector3 = _dir[i]
		var up: Vector3 = p.normalized()
		d = (d - up * d.dot(up)).normalized()
		d = d.rotated(up, TURN_RATE * dt * sin(p.x * 0.05 + p.z * 0.03))
		p = (p + d * (SPEED * dt)).normalized() * RADIUS
		_pos[i] = p
		_dir[i] = d


func checksum() -> float:
	return _checksum
