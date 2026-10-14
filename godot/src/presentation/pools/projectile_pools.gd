class_name ProjectilePools
extends Node3D
## Projectile tracers (03 s7.10): six MultiMeshes, one per cube face, so a face entirely behind the horizon is culled
## whole (MultiMesh has no per-instance culling in Compatibility, R2 s2.2). Each draws crossed quads stretched along
## the velocity, team-tinted. Capacity per face = the tier's `projectile_pool` (worst case: every projectile in one
## face); `vfx_tracer` length = speed x 0.02 s (07 s6).

const FACES: int = 6
const TRACER_S: float = 0.02
const MIN_LENGTH_M: float = 0.6        ## 03 s7.10 "0.6 m elongated quad"
const WIDTH_M: float = 0.3
## Used when the view has no team for a projectile id (SimView.team covers entities only).
const NEUTRAL: Color = Color(1.0, 0.91, 0.66)

var faces: Array[MultiMeshPool] = []
var dropped: int = 0   ## projectiles skipped in the last sync because a face pool was full

var _team_color: PackedColorArray = PackedColorArray()


func setup(capacity_per_face: int) -> void:
	var mat: ShaderMaterial = PoolMaterials.additive_material()
	for f: int in FACES:
		var p: MultiMeshPool = MultiMeshPool.new()
		p.name = "Face%d" % f
		p.setup(PlaceholderMeshes.crossed_quads(), mat, capacity_per_face)
		add_child(p)
		faces.append(p)
	for t: int in UnitMaterialCache.TEAM_COUNT:
		var _a: bool = _team_color.push_back(UnitMaterialCache.team_color(t))


## Cube face of a direction (dominant axis, ties to the lower face; same rule as `Sphere`).
static func face_of(d: Vector3) -> int:
	var ax: float = absf(d.x)
	var ay: float = absf(d.y)
	var az: float = absf(d.z)
	if ax >= ay and ax >= az:
		return 0 if d.x > 0.0 else 1
	if ay >= az:
		return 2 if d.y > 0.0 else 3
	return 4 if d.z > 0.0 else 5


## Redraws all pools from `ids` (e.g. `view.projectiles_near(...)`); one transform per projectile.
func sync(view: SimView, ids: PackedInt32Array) -> void:
	for f: MultiMeshPool in faces:
		f.begin()
	dropped = 0
	for id: int in ids:
		var p: Vector3 = view.pos(id)
		var v: Vector3 = view.vel(id)
		var speed: float = v.length()
		var fwd: Vector3 = v / speed if speed > 0.0 else p.normalized()
		var side: Vector3 = fwd.cross(p.normalized())
		side = side.normalized() if side.length_squared() > 0.0 else fwd.cross(Vector3.UP).normalized()
		var team: int = view.team(id)
		var col: Color = _team_color[team] if team >= 0 and team < _team_color.size() else NEUTRAL
		var b: Basis = Basis(side * WIDTH_M, fwd.cross(side) * WIDTH_M, fwd * maxf(MIN_LENGTH_M, speed * TRACER_S))
		if not faces[face_of(p)].push(Transform3D(b, p), col):
			dropped += 1
	for f: MultiMeshPool in faces:
		f.commit()


func draw_calls() -> int:
	var n: int = 0
	for f: MultiMeshPool in faces:
		n += f.draw_calls()
	return n


func instance_total() -> int:
	var n: int = 0
	for f: MultiMeshPool in faces:
		n += f.count
	return n
