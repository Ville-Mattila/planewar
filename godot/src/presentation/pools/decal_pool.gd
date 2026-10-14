class_name DecalPool
extends MultiMeshPool
## Bomb scorch decals (03 s7.10): a ring of 256 ground-hugging quads, one MultiMesh draw, fading out over 60 s.
## The oldest decal is recycled when the ring is full. Decals lie in the surface tangent plane (the scorch of a
## ground impact), not camera-facing: a flat mark reads better on slopes than a billboard (spec 7.10 says
## "camera-facing quad"; deviation noted in presentation/MODULE.md).

const CAPACITY: int = 256
const FADE_S: float = 60.0
const LIFT_M: float = 0.2            ## above the sampled surface, against z-fighting
const SOOT: Color = Color(0.03, 0.03, 0.035, 0.85)
const UPDATE_INTERVAL_S: float = 0.25

var _pos: PackedVector3Array = PackedVector3Array()
var _basis: Array[Basis] = []
var _age: PackedFloat32Array = PackedFloat32Array()
var _next: int = 0
var _live: int = 0
var _accum: float = 0.0


func setup_decals(p_capacity: int = CAPACITY) -> void:
	var mat: ShaderMaterial = PoolMaterials.decal_material()
	setup(PlaceholderMeshes.flat_quad(), mat, p_capacity)
	var _r1: int = _pos.resize(p_capacity)
	var _r2: int = _basis.resize(p_capacity)
	var _r3: int = _age.resize(p_capacity)


func live_count() -> int:
	return _live


## One scorch at `pos` on the surface with normal `up`.
func add(pos: Vector3, up: Vector3, radius_m: float) -> void:
	var i: int = _next
	_next = (_next + 1) % capacity
	var x: Vector3 = up.cross(Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	_basis[i] = Basis(x, up, x.cross(up)).scaled(Vector3.ONE * radius_m * 2.0)
	_pos[i] = pos + up * LIFT_M
	_age[i] = 0.0
	_live = mini(_live + 1, capacity)
	count = _live
	set_at(i, Transform3D(_basis[i], _pos[i]), SOOT)
	commit()


func update(delta: float) -> void:
	_accum += delta
	if _accum < UPDATE_INTERVAL_S or _live == 0:
		return
	var dt: float = _accum
	_accum = 0.0
	for i: int in _live:
		_age[i] += dt
		var a: float = SOOT.a * clampf(1.0 - _age[i] / FADE_S, 0.0, 1.0)
		set_at(i, Transform3D(_basis[i], _pos[i]), Color(SOOT.r, SOOT.g, SOOT.b, a))
