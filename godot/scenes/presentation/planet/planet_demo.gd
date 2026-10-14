class_name PlanetDemo extends Node3D
## TA-23 demo: a free camera over the s_world1_r6000 moon on the planet renderer core (not shipped; export
## filters exclude scenes/presentation/**). Mouse look (hold right button), WASD + Q/E, Shift = x8 speed.
## User args after `--`: `--tier=low|medium|high`, `--map=<id>`, `--autofly` (160 m/s boost path at the
## start altitude), `--lod` (tint chunks by depth), `--alt=<m AGL>`, `--pitch=<deg>`, `--frames=N` (print fps / frame-time / build stats and
## quit after N frames), `--shot=<png path>` (save the frame before quitting). ART-01: the moon is drawn with the
## first-pass moon_surface material on the shared light model (MoonLight sun, LDR environment, `sun_dir`);
## `--lat=<deg>` / `--lon=<deg>` / `--yaw=<deg>` place the camera (default 30 / slot 0 / 0), `--interim` keeps the
## TA-23 chunk shader, `--hud=0` hides the stats label (goldens).

const TIERS: String = "res://content/defs/quality_tiers.json"
const BOOST_MPS: float = 160.0
const LOOK_RAD_PER_PX: float = 0.003

var renderer: PlanetRenderer
var cam: Camera3D
var terrain: Terrain
var _tier: String = "high"
var _map: String = "s_world1_r6000"
var _autofly: bool = false
var _alt: float = 120.0
var _pitch_deg: float = -12.0
var _frames_target: int = 0
var _shot: String = ""
var _lod_tint: bool = false
var _frame: int = 0
var _yaw: float = 0.0
var _pitch: float = 0.0
var _ft: PackedFloat32Array = PackedFloat32Array()
var _label: Label
var _lat_deg: float = 30.0
var _lon_deg: float = Sphere.SLOT_LON0_DEG
var _interim: bool = false
var _hud: bool = true


func _ready() -> void:
	_parse_args()
	terrain = Terrain.new()
	var err: Error = terrain.load_map("res://content/maps/" + _map)
	if err != OK:
		push_error("planet_demo: map %s failed to load (%d)" % [_map, err])
	_setup_world()
	renderer = PlanetRenderer.new()
	renderer.debug_depth_tint = _lod_tint
	add_child(renderer)
	renderer.setup(terrain, _config(), null if _interim else MoonLight.moon_material())
	renderer.camera = cam
	_label = Label.new()
	_label.position = Vector2(8, 8)
	var layer: CanvasLayer = CanvasLayer.new()
	_label.visible = _hud
	layer.add_child(_label)
	add_child(layer)


func _parse_args() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--tier="):
			_tier = arg.substr(7)
		elif arg.begins_with("--map="):
			_map = arg.substr(6)
		elif arg == "--autofly":
			_autofly = true
		elif arg.begins_with("--alt="):
			_alt = float(arg.substr(6))
		elif arg.begins_with("--pitch="):
			_pitch_deg = float(arg.substr(8))
		elif arg.begins_with("--frames="):
			_frames_target = int(arg.substr(9))
		elif arg == "--lod":
			_lod_tint = true
		elif arg.begins_with("--shot="):
			_shot = arg.substr(7)
		elif arg.begins_with("--lat="):
			_lat_deg = float(arg.substr(6))
		elif arg.begins_with("--lon="):
			_lon_deg = float(arg.substr(6))
		elif arg.begins_with("--yaw="):
			_yaw = deg_to_rad(float(arg.substr(6)))
		elif arg == "--interim":
			_interim = true
		elif arg == "--hud=0":
			_hud = false


func _config() -> PlanetTierConfig:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(TIERS))
	if data is Dictionary:
		var d: Dictionary = data
		var list: Array = d.get("quality_tiers", [])
		for e: Variant in list:
			var t: Dictionary = e
			if str(t.get("id", "")) == _tier:
				return PlanetTierConfig.from_dict(t)
	return PlanetTierConfig.new()


func _setup_world() -> void:
	MoonLight.ensure_globals()
	var sun: DirectionalLight3D = MoonLight.make_sun()   # light travels -Z (07 s1.5)
	add_child(sun)
	MoonLight.set_sun_dir(MoonLight.DEFAULT_SUN_DIR, sun)
	var we: WorldEnvironment = WorldEnvironment.new()
	we.environment = MoonLight.make_environment()
	add_child(we)
	cam = Camera3D.new()
	cam.fov = 75.0
	cam.far = CamMath.FAR_PLANE
	add_child(cam)
	var dir: Vector3 = Sphere.from_lat_lon(deg_to_rad(_lat_deg), deg_to_rad(_lon_deg), 1.0)
	cam.global_position = dir * (Sphere.PLANET_RADIUS + terrain.height_at(dir) + _alt)
	_pitch = deg_to_rad(_pitch_deg)
	_orient()
	cam.make_current()


## Heading `_yaw` from local east, pitch `_pitch`, up = local radial.
func _orient() -> void:
	var up: Vector3 = cam.global_position.normalized()
	var f: Basis = Sphere.tangent_frame(up)
	var heading: Vector3 = f.x * cos(_yaw) + f.y * sin(_yaw)
	var fwd: Vector3 = (heading * cos(_pitch) + up * sin(_pitch)).normalized()
	cam.global_basis = Basis.looking_at(fwd, up)


func _unhandled_input(event: InputEvent) -> void:
	var mm: InputEventMouseMotion = event as InputEventMouseMotion
	if mm != null and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		_yaw -= mm.relative.x * LOOK_RAD_PER_PX
		_pitch = clampf(_pitch - mm.relative.y * LOOK_RAD_PER_PX, -1.5, 1.5)


func _process(delta: float) -> void:
	_fly(delta)
	var ground: float = terrain.height_at(cam.global_position)
	var h_cam: float = Sphere.altitude(cam.global_position) - ground
	cam.near = CamMath.near_plane(h_cam)
	_frame += 1
	if _frame > 30:
		var _a: bool = _ft.push_back(delta * 1000.0)
	_label.text = "tier %s  fps %d  visible %d/%d  builds %d (forced %s)  build ms p50 %.2f p95 %.2f  plan %.2f ms  AGL %.0f m" % [
		_tier, Engine.get_frames_per_second(), renderer.visible_chunks(), renderer.config.visible_chunks_cap,
		renderer.scheduler.last_builds, renderer.scheduler.last_forced, renderer.build_ms_percentile(0.5),
		renderer.build_ms_percentile(0.95), renderer.plan_ms, h_cam]
	if _frames_target > 0 and _frame >= _frames_target:
		_finish()


func _fly(delta: float) -> void:
	var up: Vector3 = cam.global_position.normalized()
	var move: Vector3 = Vector3.ZERO
	if _autofly:
		move = Sphere.tangent_frame(up).x * BOOST_MPS * delta
	else:
		var b: Basis = cam.global_basis
		var speed: float = BOOST_MPS * (8.0 if Input.is_key_pressed(KEY_SHIFT) else 1.0)
		var axis: Vector3 = Vector3(_key(KEY_D) - _key(KEY_A), _key(KEY_E) - _key(KEY_Q), _key(KEY_S) - _key(KEY_W))
		move = (b.x * axis.x + up * axis.y + b.z * axis.z) * speed * delta
	var p: Vector3 = cam.global_position + move
	var dir: Vector3 = p.normalized()
	var min_r: float = Sphere.PLANET_RADIUS + terrain.height_at(dir) + 2.0
	if _autofly:
		p = dir * (Sphere.PLANET_RADIUS + terrain.height_at(dir) + _alt)
	cam.global_position = dir * maxf(p.length(), min_r)
	_orient()


static func _key(k: Key) -> float:
	return 1.0 if Input.is_key_pressed(k) else 0.0


func _finish() -> void:
	_ft.sort()
	var n: int = _ft.size()
	if n > 0:
		print("PLANET_DEMO tier=%s frames=%d frame_ms_p50=%.2f p95=%.2f p99=%.2f visible=%d builds=%d build_ms_p50=%.2f p95=%.2f worst_near_wait_ms=%d pool=%d/%d" % [
			_tier, n, _ft[n >> 1], _ft[int(float(n - 1) * 0.95)], _ft[int(float(n - 1) * 0.99)],
			renderer.visible_chunks(), renderer.scheduler.total_builds, renderer.build_ms_percentile(0.5),
			renderer.build_ms_percentile(0.95), renderer.worst_near_wait_ms, renderer.pool.in_use(), renderer.pool.capacity()])
	if not _shot.is_empty():
		var img: Image = get_viewport().get_texture().get_image()
		var _e: Error = img.save_png(_shot)
	get_tree().quit(0)
