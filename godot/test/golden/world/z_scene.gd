class_name ZScene
extends Node3D
## TA-24 harness for the S-WORLD-1 z-fighting plan (03 s7.7): scenes Z1-Z5 and Z8 on the real planet renderer,
## moon_terrain, sky_moon, flatten sites and the near-plane schedule. Not shipped (export filters exclude test/**).
## User args after `--`: `--z=1|2|3|4|5|8`, `--tier=low|medium|high` (default high), `--poses=N` (poses per scene),
## `--shot=<png>` (saves the middle pose), `--map=<id>`, `--control` (adds two coplanar plates 20 m above the
## cluster: a deliberate z-fight that the metric must flag; proves the detector, exits non-zero).
## Method (the pass metric of 03 s7.7, made deterministic): at each pose the renderer settles (no chunk build for
## SETTLE_QUIET frames), image A is captured, the camera moves PROBE_SHIFT_M sideways, image B is captured, and
## the share of non-sky pixels whose colour changed by more than PIXEL_DELTA is `flicker_pct`. A z-fighting pair
## flips between two surfaces under a few-millimetre shift; correct depth ordering moves only edge pixels.
## Prints `Z_RESULT z=<n> ...` and exits non-zero when flicker_max_pct > PASS_PCT.

const TIERS: String = "res://content/defs/quality_tiers.json"
const PASS_PCT: float = 2.0                   ## 03 s7.7 Z1: no flicker > 2 percent of the footprint pixels
const PIXEL_DELTA: int = 36                   ## summed |dR| + |dG| + |dB| (0..765) that counts as changed
const PROBE_SHIFT_M: float = 0.004            ## 4 mm: 8 float32 steps at the 6.7 km radius, far below one pixel
const SETTLE_QUIET: int = 4
const SETTLE_MAX: int = 120
const SKY_RGB_MAX: int = 40                   ## summed channel value below which a pixel counts as space
const STRIDE_BYTES: int = 6                   ## compare every second pixel (RGB8)

var terrain: Terrain
var renderer: PlanetRenderer
var cam: Camera3D
var _z: int = 1
var _tier: String = "high"
var _map: String = "s_world1_r6000"
var _poses_n: int = 6
var _shot: String = ""
var _poses: Array[Transform3D] = []
var _pose: int = 0
var _phase: int = 0                           ## 0 settle, 1 capture A, 2 wait B, 3 capture B
var _quiet: int = 0
var _waited: int = 0
var _img_a: Image = null
var _results: PackedFloat32Array = PackedFloat32Array()
var _structures: int = 0
var _site_pos: PackedVector3Array = PackedVector3Array()
var _site_rad: PackedFloat32Array = PackedFloat32Array()
var _team_mat: ShaderMaterial
var _control: bool = false


func _ready() -> void:
	_parse_args()
	terrain = Terrain.new()
	if terrain.load_map("res://content/maps/" + _map) != OK:
		push_error("z_scene: map %s failed to load" % _map)
	MoonLight.ensure_globals()
	var sun: DirectionalLight3D = MoonLight.make_sun()
	add_child(sun)
	MoonLight.set_sun_dir(MoonLight.DEFAULT_SUN_DIR, sun)
	var we: WorldEnvironment = WorldEnvironment.new()
	we.environment = MoonLight.make_environment()
	SkyMoon.apply(we.environment)
	add_child(we)
	cam = Camera3D.new()
	cam.fov = 75.0
	cam.far = CamMath.FAR_PLANE
	add_child(cam)
	renderer = PlanetRenderer.new()
	add_child(renderer)
	renderer.setup(terrain, _config())
	renderer.camera = cam
	_team_mat = MoonLight.unit_material()
	_team_mat.set_shader_parameter(&"team_index", 1)
	_team_mat.set_shader_parameter(&"team_color", Color("#4C64ED"))
	match _z:
		1: _build_z1()
		2: _build_z2()
		3: _build_z3()
		4: _build_z4()
		5: _build_z5()
		8: _build_z8()
		_: push_error("z_scene: unknown --z=%d" % _z)
	if _control:
		_build_control()
	renderer.set_flatten_sites(_site_pos, _site_rad)
	cam.make_current()
	_goto_pose(0)


func _parse_args() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--z="):
			_z = int(arg.substr(4))
		elif arg.begins_with("--tier="):
			_tier = arg.substr(7)
		elif arg.begins_with("--map="):
			_map = arg.substr(6)
		elif arg.begins_with("--poses="):
			_poses_n = maxi(1, int(arg.substr(8)))
		elif arg == "--control":
			_control = true
		elif arg.begins_with("--shot="):
			_shot = arg.substr(7)


func _config() -> PlanetTierConfig:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(TIERS))
	for e: Variant in data.get("quality_tiers", []):
		var t: Dictionary = e
		if str(t.get("id", "")) == _tier:
			return PlanetTierConfig.from_dict(t)
	return PlanetTierConfig.new()


# region scene builders
## A structure stand-in on the terrain: footprint w x d, height h, foundation skirt max(0.27 x half, 0.6 m)
## below the footprint plane (07 s4.2), sitting at the footprint centre height; registers its flatten site.
func _structure(dir: Vector3, w: float, d: float, h: float, yaw: float) -> void:
	var skirt: float = maxf(0.27 * 0.5 * maxf(w, d), 0.6)
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(w, h + skirt, d)
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = LookdevMeshes.painted(box, LookdevMeshes.HULL_400)
	mi.material_override = _team_mat
	var xf: Transform3D = LookdevMeshes.site(dir, terrain.height_at(dir))
	mi.transform = xf.translated_local(Vector3(0.0, (h - skirt) * 0.5, 0.0)).rotated_local(Vector3.UP, yaw)
	add_child(mi)
	var _a: bool = _site_pos.push_back(dir * Sphere.PLANET_RADIUS)
	_a = _site_rad.push_back(0.5 * sqrt(w * w + d * d) + 2.0)
	_structures += 1


## `cols` x `rows` structures around `centre`: a Core-sized block, towers and pads (a Core cluster).
func _cluster(centre: Vector3, cols: int, rows: int, spacing: float) -> void:
	var f: Basis = Sphere.tangent_frame(centre)
	for r: int in rows:
		for c: int in cols:
			var off: Vector3 = f.x * (float(c) - float(cols - 1) * 0.5) * spacing + f.y * (float(r) - float(rows - 1) * 0.5) * spacing
			var dir: Vector3 = (centre + off / Sphere.PLANET_RADIUS).normalized()
			var k: int = r * cols + c
			if k == 0:
				_structure(dir, 36.0, 36.0, 14.0, 0.0)          # Core
			elif k % 5 == 1:
				_structure(dir, 24.0, 24.0, 0.8, 0.3)           # Pad
			elif k % 5 == 2:
				_structure(dir, 8.0, 8.0, 12.0, 0.7)            # tower
			else:
				_structure(dir, 18.0, 14.0, 6.0 + float(k % 4), 0.2 * float(k))


func _aim(pos: Vector3, target: Vector3, up: Vector3) -> Transform3D:
	return Transform3D(Basis.looking_at((target - pos).normalized(), up), pos)


func _surface(dir: Vector3, agl: float) -> Vector3:
	return dir * (Sphere.PLANET_RADIUS + terrain.height_at(dir) + agl)


func _push(pos: Vector3, target: Vector3) -> void:
	_poses.append(_aim(pos, target, pos.normalized()))


func _orbit(centre: Vector3, radius: float, agl: float, n: int, start_deg: float = 0.0) -> void:
	var f: Basis = Sphere.tangent_frame(centre)
	var target: Vector3 = _surface(centre, 5.0)
	for k: int in n:
		var a: float = deg_to_rad(start_deg + 360.0 * float(k) / float(n))
		var d: Vector3 = (centre + (f.x * cos(a) + f.y * sin(a)) * radius / Sphere.PLANET_RADIUS).normalized()
		_push(_surface(d, agl), target)


## Two coplanar plates of different swatches 20 m above the cluster centre: they must z-fight.
func _build_control() -> void:
	var c: Vector3 = Sphere.from_lat_lon(0.0, deg_to_rad(Sphere.SLOT_LON0_DEG), 1.0)
	for k: int in 2:
		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.mesh = LookdevMeshes.plate(240.0, LookdevMeshes.TEAM_GLOW if k == 0 else LookdevMeshes.HULL_700)
		mi.material_override = _team_mat
		mi.transform = LookdevMeshes.site(c, terrain.height_at(c) + 20.0).rotated_local(Vector3.UP, 0.0 if k == 0 else 0.6)
		add_child(mi)


func _build_z1() -> void:
	var c: Vector3 = Sphere.from_lat_lon(0.0, deg_to_rad(Sphere.SLOT_LON0_DEG), 1.0)
	_cluster(c, 5, 4, 55.0)
	_orbit(c, 140.0, 60.0, _poses_n)


func _build_z2() -> void:
	var c: Vector3 = Sphere.from_lat_lon(0.0, deg_to_rad(Sphere.SLOT_LON0_DEG), 1.0)
	_cluster(c, 5, 4, 55.0)
	var f: Basis = Sphere.tangent_frame(c)
	var heights: PackedFloat32Array = [300.0, 1000.0, 2500.0]
	for k: int in maxi(_poses_n, 3):
		var alt: float = heights[k % 3]
		var d: Vector3 = (c - f.y * (alt * 0.5 / Sphere.PLANET_RADIUS)).normalized()
		_push(_surface(d, alt), _surface(c, 0.0))


func _build_z3() -> void:
	# steepest sampled slope = a crater rim; skim it at 20 m AGL in a straight line (depth 6 next to coarser chunks)
	var best: Vector3 = Sphere.from_lat_lon(0.0, 0.0, 1.0)
	var best_slope: float = -1.0
	for i: int in 90:
		for j: int in 180:
			var d: Vector3 = Sphere.from_lat_lon(deg_to_rad(-60.0 + float(i) * 1.33), deg_to_rad(-180.0 + float(j) * 2.0), 1.0)
			var s: float = terrain.slope_deg_at_dir(d)
			if s > best_slope:
				best_slope = s
				best = d
	var f: Basis = Sphere.tangent_frame(best)
	for k: int in _poses_n:
		var along: float = (float(k) - float(_poses_n - 1) * 0.5) * 60.0
		var d: Vector3 = (best + f.x * (along / Sphere.PLANET_RADIUS)).normalized()
		var ahead: Vector3 = (best + f.x * ((along + 80.0) / Sphere.PLANET_RADIUS)).normalized()
		_poses.append(_aim(_surface(d, 20.0), _surface(ahead, 4.0), d))


func _build_z4() -> void:
	var c: Vector3 = Sphere.from_lat_lon(0.0, deg_to_rad(Sphere.SLOT_LON0_DEG), 1.0)
	var f: Basis = Sphere.tangent_frame(c)
	for k: int in _poses_n:
		var a: float = deg_to_rad(20.0 * float(k))
		var d: Vector3 = (c + (f.x * cos(a) + f.y * sin(a)) * 0.06).normalized()
		_push(_surface(d, 8000.0), Vector3.ZERO)


func _build_z5() -> void:
	var c: Vector3 = Sphere.from_lat_lon(deg_to_rad(5.0), deg_to_rad(Sphere.SLOT_LON0_DEG), 1.0)
	_structure(c, 24.0, 24.0, 0.8, 0.0)                    # landing pad, 12 m radius
	var f: Basis = Sphere.tangent_frame(c)
	for k: int in _poses_n:
		var t: float = float(k) / float(maxi(_poses_n - 1, 1))
		var agl: float = lerpf(10.0, 0.3, t)               # 03 s7.7 Z5: 0.3-10 m
		var back: float = lerpf(60.0, 14.0, t)
		var d: Vector3 = (c - f.y * (back / Sphere.PLANET_RADIUS)).normalized()
		_poses.append(_aim(_surface(d, agl), _surface(c, 1.0), d))
	var prim: MeshInstance3D = MeshInstance3D.new()        # the ship stand-in hovering over the pad
	prim.mesh = LookdevMeshes.painted(LookdevMeshes.primitive(0), LookdevMeshes.HULL_300, true)
	prim.material_override = _team_mat
	prim.transform = LookdevMeshes.site(c, terrain.height_at(c) + 3.0).rotated_local(Vector3.UP, PI)
	add_child(prim)


func _build_z8() -> void:
	var edge: Vector3 = Vector3(1.0, 1.0, 0.0).normalized()   # equatorial cube edge between faces 0 and 2
	_cluster(edge, 5, 4, 55.0)
	var chase: int = maxi(_poses_n >> 1, 1)
	_orbit(edge, 140.0, 60.0, chase)
	var f: Basis = Sphere.tangent_frame(edge)
	for k: int in maxi(_poses_n - chase, 1):
		var d: Vector3 = (edge - f.y * (500.0 / Sphere.PLANET_RADIUS) + f.x * (float(k) * 120.0 / Sphere.PLANET_RADIUS)).normalized()
		_push(_surface(d, 1000.0), _surface(edge, 0.0))
# endregion


# region run
func _goto_pose(i: int) -> void:
	_pose = i
	_phase = 0
	_quiet = 0
	_waited = 0
	cam.global_transform = _poses[i]
	_update_near()


func _update_near() -> void:
	cam.near = CamMath.near_plane(renderer.camera_height_agl(cam.global_position))


func _process(_delta: float) -> void:
	if _pose >= _poses.size():
		return
	match _phase:
		0:
			_waited += 1
			_quiet = _quiet + 1 if renderer.scheduler.last_builds == 0 and renderer.scheduler.queue.is_empty() else 0
			if _quiet >= SETTLE_QUIET or _waited >= SETTLE_MAX:
				_phase = 1
		1:
			_img_a = _grab()
			if _pose == _poses.size() >> 1 and not _shot.is_empty():
				var _e: Error = _img_a.save_png(_shot)
			cam.global_position += cam.global_basis.x * PROBE_SHIFT_M
			_phase = 2
			_waited = 0
		2:
			_waited += 1
			if _waited >= 2:
				_phase = 3
		3:
			var pct: float = _flicker(_img_a, _grab())
			var _a: bool = _results.push_back(pct)
			print("Z_POSE z=%d pose=%d agl=%.1f near=%.2f visible=%d flicker_pct=%.3f" % [
				_z, _pose, renderer.camera_height_agl(cam.global_position), cam.near, renderer.visible_chunks(), pct])
			if _pose + 1 < _poses.size():
				_goto_pose(_pose + 1)
			else:
				_finish()


func _grab() -> Image:
	var img: Image = get_viewport().get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	return img


## Percent of non-sky pixels (every second pixel) whose summed channel difference exceeds PIXEL_DELTA.
static func _flicker(a: Image, b: Image) -> float:
	var da: PackedByteArray = a.get_data()
	var db: PackedByteArray = b.get_data()
	var counted: int = 0
	var changed: int = 0
	var i: int = 0
	var n: int = mini(da.size(), db.size()) - 2
	while i < n:
		var sa: int = da[i] + da[i + 1] + da[i + 2]
		if sa > SKY_RGB_MAX:
			counted += 1
			if absi(da[i] - db[i]) + absi(da[i + 1] - db[i + 1]) + absi(da[i + 2] - db[i + 2]) > PIXEL_DELTA:
				changed += 1
		i += STRIDE_BYTES
	return 100.0 * float(changed) / float(maxi(counted, 1))


func _finish() -> void:
	var worst: float = 0.0
	var sum: float = 0.0
	for v: float in _results:
		worst = maxf(worst, v)
		sum += v
	var ok: bool = worst <= PASS_PCT
	print("Z_RESULT z=%d tier=%s poses=%d structures=%d flicker_max_pct=%.3f flicker_mean_pct=%.3f pass=%s adapter=%s driver=%s sites=%d rebuilds=%d" % [
		_z, _tier, _results.size(), _structures, worst, sum / float(maxi(_results.size(), 1)), ok,
		RenderingServer.get_video_adapter_name(), RenderingServer.get_current_rendering_driver_name(),
		renderer.flatten_site_count(), renderer.flatten_rebuilds])
	get_tree().quit(0 if ok else 1)
# endregion
