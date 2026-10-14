class_name TrailPool
extends MultiMeshPool
## Smoke / trail ribbon segments (03 s7.10, 07 s6 `vfx_smoke_trail`): a ring buffer of stretched crossed quads, one
## draw. Capacity is the tier's `trail_segments` (1,024 HIGH, 512 MEDIUM, 0 = off on LOW). Segments fade over
## `LIFE_S`; colour alpha is refreshed at `UPDATE_INTERVAL_S`, not every frame.

const LIFE_S: float = 1.6
const WIDTH_M: float = 1.5
const UPDATE_INTERVAL_S: float = 0.0667

var _a: PackedVector3Array = PackedVector3Array()
var _b: PackedVector3Array = PackedVector3Array()
var _rgb: PackedColorArray = PackedColorArray()
var _age: PackedFloat32Array = PackedFloat32Array()
var _next: int = 0
var _accum: float = 0.0


func setup_trails(segments: int) -> void:
	setup(PlaceholderMeshes.crossed_quads(), PoolMaterials.additive_material(), maxi(segments, 0))
	var _r1: int = _a.resize(capacity)
	var _r2: int = _b.resize(capacity)
	var _r3: int = _rgb.resize(capacity)
	var _r4: int = _age.resize(capacity)
	_age.fill(LIFE_S)


func enabled() -> bool:
	return capacity > 0


## Appends one segment from `from` to `to`; false when trails are off.
func add_segment(from: Vector3, to: Vector3, color: Color) -> bool:
	if capacity == 0:
		return false
	var i: int = _next
	_next = (_next + 1) % capacity
	_a[i] = from
	_b[i] = to
	_rgb[i] = color
	_age[i] = 0.0
	count = maxi(count, i + 1)
	_write(i, 1.0)
	commit()
	return true


func update(delta: float) -> void:
	_accum += delta
	if _accum < UPDATE_INTERVAL_S or count == 0:
		return
	var dt: float = _accum
	_accum = 0.0
	for i: int in count:
		if _age[i] >= LIFE_S:
			continue
		_age[i] += dt
		_write(i, clampf(1.0 - _age[i] / LIFE_S, 0.0, 1.0))


func _write(i: int, alpha: float) -> void:
	var d: Vector3 = _b[i] - _a[i]
	var seg: float = maxf(d.length(), 0.01)
	var fwd: Vector3 = d / seg
	var side: Vector3 = fwd.cross(_a[i].normalized())
	side = side.normalized() if side.length_squared() > 0.0 else fwd.cross(Vector3.UP).normalized()
	var xf: Transform3D = Transform3D(Basis(side * WIDTH_M, fwd.cross(side) * WIDTH_M, fwd * seg), (_a[i] + _b[i]) * 0.5)
	set_at(i, xf, Color(_rgb[i].r, _rgb[i].g, _rgb[i].b, alpha))
