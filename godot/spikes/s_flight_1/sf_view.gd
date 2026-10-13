class_name SfView extends Node3D
## Spike presentation: environment, flat-shaded icosphere moon, stub pad, targets, the Dart, projectile and
## explosion pools, bomb impact ring and a height marker. `sync` draws the world at render time with the
## interpolation fraction `alpha` between the last two ticks (03 s10.1 render_state(alpha)).

const SLUG_POOL: int = 32
const BOMB_POOL: int = 8
const BOOM_POOL: int = 8

var ship_node: Node3D
var _d: SfDefs
var _flame: MeshInstance3D
var _targets: Array[MeshInstance3D] = []
var _slugs: Array[MeshInstance3D] = []
var _bombs: Array[MeshInstance3D] = []
var _booms: Array[MeshInstance3D] = []
var _boom_t: PackedFloat32Array = PackedFloat32Array()
var _boom_size: PackedFloat32Array = PackedFloat32Array()
var _ring: MeshInstance3D
var _ring_mat_on: StandardMaterial3D
var _ring_mat_off: StandardMaterial3D
var _marker: MeshInstance3D
var _beacon: MeshInstance3D
var _drop: MeshInstance3D
var _pred_acc: float
var _thrust_vis: float
var render_p: Vector3              # interpolated ship pose this frame (camera, HUD)
var render_fwd: Vector3
var render_up: Vector3


func build(d: SfDefs, w: SfWorld) -> void:
	_d = d
	_environment()
	var planet: MeshInstance3D = MeshInstance3D.new()
	planet.mesh = SfMeshes.icosphere(int(SfDefs.num(d.render, "icosphere_level")), Sphere.PLANET_RADIUS, Rng.new(42))
	add_child(planet)
	_boulders(w)
	_pad(w)
	for i: int in w.arena.t_pos.size():
		var m: MeshInstance3D = MeshInstance3D.new()
		if w.arena.t_ground[i] == 1:
			var bx: BoxMesh = BoxMesh.new()
			var r: float = w.arena.t_radius[i]
			bx.size = Vector3(r * 1.4, r * 0.6, r * 1.4)
			m.mesh = bx
			m.material_override = SfMeshes.flat(Color(0.7, 0.15, 0.1), 0.6)
		else:
			m.mesh = SfMeshes.octahedron(w.arena.t_radius[i], Color(0.9, 0.2, 0.15))
			m.material_override = SfMeshes.flat(Color(0.95, 0.25, 0.15), 0.8)
		m.transform = Transform3D(_basis_up(w.arena.t_pos[i].normalized()), w.arena.t_pos[i])
		add_child(m)
		_targets.append(m)
	_ship()
	_pools()


func _environment() -> void:
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.01, 0.01, 0.03)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.45, 0.47, 0.55)
	env.ambient_light_energy = 0.5
	var we: WorldEnvironment = WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.transform = Transform3D(Basis.IDENTITY, Vector3.ZERO)   # shines along -Z: the Noon Pole (+Z) faces the sun
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = SfDefs.num(_d.render, "shadow_distance_m")
	add_child(sun)


func _boulders(w: SfWorld) -> void:
	var rng: Rng = Rng.new(1234)
	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = SfMeshes.boulder()
	var count: int = int(SfDefs.num(_d.render, "boulders"))
	mm.instance_count = count
	var field: float = SfDefs.num(_d.render, "boulder_field_m")
	var lo: float = SfDefs.num(_d.render, "boulder_min_m")
	var hi: float = SfDefs.num(_d.render, "boulder_max_m")
	for i: int in count:
		var dist: float = field * sqrt(rng.next_float()) + _d.pad_radius_m * 3.0
		var sc: float = lo + (hi - lo) * pow(rng.next_float(), 3.0)
		var p: Vector3 = SfArena.place(w.pad_p, rng.range_f(0.0, 360.0), dist, sc * 0.2)
		var b: Basis = _basis_up(p.normalized()).rotated(p.normalized(), rng.range_f(0.0, TAU)).scaled(Vector3.ONE * sc)
		mm.set_instance_transform(i, Transform3D(b, p))
	var mmi: MultiMeshInstance3D = MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = SfMeshes.vertex_material()
	add_child(mmi)


func _pad(w: SfWorld) -> void:
	var b: Basis = _basis_up(w.pad_n)
	var disc: MeshInstance3D = MeshInstance3D.new()
	var cyl: CylinderMesh = CylinderMesh.new()
	cyl.top_radius = _d.pad_radius_m
	cyl.bottom_radius = _d.pad_radius_m
	cyl.height = 0.4
	disc.mesh = cyl
	disc.material_override = SfMeshes.flat(Color(0.25, 0.27, 0.32), 0.0)
	disc.transform = Transform3D(b, w.pad_p + w.pad_n * 0.1)
	add_child(disc)
	var ring: MeshInstance3D = MeshInstance3D.new()
	var tor: TorusMesh = TorusMesh.new()
	tor.inner_radius = _d.pad_radius_m - 0.7
	tor.outer_radius = _d.pad_radius_m
	ring.mesh = tor
	ring.material_override = SfMeshes.flat(Color(1.0, 0.85, 0.2), 1.5)
	ring.transform = Transform3D(b, w.pad_p + w.pad_n * 0.35)
	add_child(ring)
	var beacon: MeshInstance3D = MeshInstance3D.new()
	var bc: CylinderMesh = CylinderMesh.new()
	var bh: float = SfDefs.num(_d.render, "beacon_height_m")
	bc.top_radius = 0.6
	bc.bottom_radius = 1.2
	bc.height = bh
	beacon.mesh = bc
	beacon.material_override = SfMeshes.unlit(Color(0.3, 0.9, 1.0, 0.35))
	beacon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beacon.transform = Transform3D(b, w.pad_p + w.pad_n * (bh * 0.5 + _d.pad_radius_m * 2.0))
	add_child(beacon)
	_beacon = beacon


func _ship() -> void:
	ship_node = Node3D.new()
	add_child(ship_node)
	var hull: MeshInstance3D = MeshInstance3D.new()
	hull.mesh = SfMeshes.dart(Color(0.2, 0.45, 0.95), Color(0.75, 0.78, 0.82))
	hull.material_override = SfMeshes.vertex_material()
	ship_node.add_child(hull)
	_flame = MeshInstance3D.new()
	var cone: CylinderMesh = CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.9
	cone.height = 1.0
	_flame.mesh = cone
	_flame.material_override = SfMeshes.unlit(Color(1.0, 0.6, 0.15, 0.8))
	_flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flame.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	ship_node.add_child(_flame)


func _pools() -> void:
	var slug_mesh: BoxMesh = BoxMesh.new()
	slug_mesh.size = Vector3(0.3, 0.3, 7.0)
	var slug_mat: StandardMaterial3D = SfMeshes.unlit(Color(1.0, 0.95, 0.4))
	for i: int in SLUG_POOL:
		_slugs.append(_pooled(slug_mesh, slug_mat))
	var bomb_mesh: SphereMesh = SphereMesh.new()
	bomb_mesh.radius = 0.7
	bomb_mesh.height = 1.4
	for i: int in BOMB_POOL:
		_bombs.append(_pooled(bomb_mesh, SfMeshes.flat(Color(0.15, 0.15, 0.15), 0.0)))
	var boom_mesh: SphereMesh = SphereMesh.new()
	for i: int in BOOM_POOL:
		_booms.append(_pooled(boom_mesh, SfMeshes.unlit(Color(1.0, 0.55, 0.1, 0.8))))
		var _a: bool = _boom_t.push_back(0.0)
		var _b: bool = _boom_size.push_back(1.0)
	_ring_mat_off = SfMeshes.unlit(Color(1.0, 1.0, 1.0, 0.7))
	_ring_mat_on = SfMeshes.unlit(Color(0.2, 1.0, 0.3, 0.9))
	var tor: TorusMesh = TorusMesh.new()
	tor.inner_radius = _d.blast_radius_structure_m - 1.0
	tor.outer_radius = _d.blast_radius_structure_m
	_ring = _pooled(tor, _ring_mat_off)
	var mt: TorusMesh = TorusMesh.new()
	mt.inner_radius = 2.4
	mt.outer_radius = 3.0
	_marker = _pooled(mt, SfMeshes.unlit(Color(0.3, 0.9, 1.0, 0.8)))
	var line: CylinderMesh = CylinderMesh.new()
	line.top_radius = 0.08
	line.bottom_radius = 0.08
	line.height = 1.0
	_drop = _pooled(line, SfMeshes.unlit(Color(0.3, 0.9, 1.0, 0.5)))


func _pooled(mesh: Mesh, mat: Material) -> MeshInstance3D:
	var m: MeshInstance3D = MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.visible = false
	add_child(m)
	return m


static func _basis_up(n: Vector3) -> Basis:
	var f: Basis = Sphere.tangent_frame(n)
	return Basis(f.x, n, -f.y)      # x east, y up, z south (so -z = north)


## Ship basis (Godot convention: -Z forward, +Y up, +X right).
static func ship_basis(fwd: Vector3, up: Vector3) -> Basis:
	return Basis(fwd.cross(up), up, -fwd).orthonormalized()


func sync(w: SfWorld, alpha: float, delta: float) -> void:
	var q0: Quaternion = ship_basis(w.prev_fwd, w.prev_up).get_rotation_quaternion()
	var q1: Quaternion = ship_basis(w.s.fwd, w.s.up).get_rotation_quaternion()
	var b: Basis = Basis(q0.slerp(q1, alpha))
	render_p = w.prev_p.lerp(w.s.p, alpha)
	render_fwd = -b.z
	render_up = b.y
	ship_node.global_transform = Transform3D(b, render_p)
	ship_node.visible = w.state != SfWorld.State.DEAD
	var thr: float = w.input.thrust if w.state == SfWorld.State.FLYING or w.state == SfWorld.State.FORCED else 0.0
	if w.s.fuel <= 0.0:
		thr = 0.0
	_thrust_vis = lerpf(_thrust_vis, thr, 1.0 - exp(-delta * 20.0))
	var boost: float = 1.6 if w.s.boost_time > 0.0 else 1.0
	_flame.visible = _thrust_vis > 0.02
	_flame.scale = Vector3(1.0, 1.0 + _thrust_vis * 6.0 * boost, 1.0)
	_flame.position = Vector3(0.0, 0.0, 6.0 + (1.0 + _thrust_vis * 6.0 * boost) * 0.5)
	for i: int in _targets.size():
		_targets[i].visible = w.arena.alive(i)
	_sync_projectiles(w, alpha)
	_sync_booms(delta)
	_sync_markers(w, delta)


func _sync_projectiles(w: SfWorld, alpha: float) -> void:
	var a: SfArena = w.arena
	var h: float = w.dt() * alpha
	for i: int in SLUG_POOL:
		var on: bool = i < a.slug_p.size()
		_slugs[i].visible = on
		if on:
			var v: Vector3 = a.slug_v[i]
			var p: Vector3 = a.slug_p[i] + v * h
			_slugs[i].global_transform = Transform3D(ship_basis(v.normalized(), p.normalized()), p)
	for i: int in BOMB_POOL:
		var on: bool = i < a.bomb_p.size()
		_bombs[i].visible = on
		if on:
			_bombs[i].global_position = a.bomb_p[i] + a.bomb_v[i] * h


func _sync_booms(delta: float) -> void:
	for i: int in BOOM_POOL:
		if _boom_t[i] <= 0.0:
			_booms[i].visible = false
			continue
		_boom_t[i] = _boom_t[i] - delta
		var k: float = 1.0 - clampf(_boom_t[i], 0.0, 1.0)
		_booms[i].scale = Vector3.ONE * _boom_size[i] * (0.3 + k)
		var m: StandardMaterial3D = _booms[i].material_override as StandardMaterial3D
		m.albedo_color.a = 0.85 * (1.0 - k)


func _sync_markers(w: SfWorld, delta: float) -> void:
	var flying: bool = w.state == SfWorld.State.FLYING or w.state == SfWorld.State.FORCED
	_pred_acc += delta
	if _pred_acc >= 1.0 / SfDefs.num(_d.render, "bomb_predict_hz"):
		_pred_acc = 0.0
		if flying and w.bombs > 0:
			w.arena.predict_bomb(w.s, SfDefs.num(_d.render, "bomb_predict_horizon_s"), SfDefs.num(_d.render, "bomb_predict_hz"))
		else:
			w.arena.pred_valid = false
	var nose_up: bool = w.s.fwd.dot(w.s.p.normalized()) > sin(deg_to_rad(SfDefs.num(_d.camera, "hover_pitch_lo_deg")))
	_ring.visible = w.arena.pred_valid and flying and w.bombs > 0 and not nose_up
	_beacon.visible = render_p.distance_to(w.pad_p) > SfDefs.num(_d.render, "beacon_hide_m")
	if _ring.visible:
		var n: Vector3 = w.arena.pred_p.normalized()
		_ring.global_transform = Transform3D(_basis_up(n), w.arena.pred_p + n * 0.5)
		_ring.material_override = _ring_mat_on if w.arena.pred_on_target else _ring_mat_off
	var agl: float = render_p.length() - Sphere.PLANET_RADIUS
	_marker.visible = flying and agl < SfDefs.num(_d.render, "ground_marker_agl_m")
	_drop.visible = _marker.visible
	if _marker.visible:
		var n2: Vector3 = render_p.normalized()
		var ground: Vector3 = n2 * (Sphere.PLANET_RADIUS + 0.3)
		_marker.global_transform = Transform3D(_basis_up(n2), ground)
		_drop.global_transform = Transform3D(_basis_up(n2).scaled_local(Vector3(1.0, maxf(agl, 0.1), 1.0)), (ground + render_p) * 0.5)


func explode(at: Vector3, size: float) -> void:
	for i: int in BOOM_POOL:
		if _boom_t[i] <= 0.0:
			_boom_t[i] = 1.0
			_boom_size[i] = size
			_booms[i].global_position = at
			_booms[i].visible = true
			return
