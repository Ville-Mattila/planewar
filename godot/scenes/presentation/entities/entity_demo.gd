class_name EntityDemo
extends Node3D
## TA-26 demo: a LocalSimView over an EntityDemoWorld (ships, ground units and structures around the eight bases of
## the s_world1_r6000 moon) drawn by EntityViewPool on the TA-24 planet renderer. Not shipped (export filters
## exclude scenes/presentation/**; it borrows the perf scenario from test/perf).
## User args after `--`: `--tier=low|medium|high`, `--n=<entities>` (default 400), `--cam=chase|base|wide`
## (chase follows one ship through the set_local_override path), `--frames=N` (print timing and quit),
## `--shot=<png path>`, `--novsync`, `--hud=0`, `--all-views` (every entity counts as close: the 800-view
## sync budget case; combine with `--headless`).

const TIERS: String = "res://content/defs/quality_tiers.json"
const DRIVER: String = "res://scenes/presentation/entities/entity_demo_world.gd"   # loaded at runtime: keeps the sim out of the scene compile
const SHIP_FRACTION: float = 0.6
const GROUND_FRACTION: float = 0.15
const CHASE_BACK_M: float = 45.0
const CHASE_UP_M: float = 14.0
const BASE_ALT_M: float = 140.0
const BASE_BACK_M: float = 380.0
const WIDE_ALT_M: float = 2600.0
const WARMUP_FRAMES: int = 30
const FOV_DEG: float = 75.0
const ALL_VIEWS_PX_PER_M: float = 1.0e6   ## every body counts as 'large on screen'

var tier: String = "high"
var n_entities: int = 400
var cam_mode: String = "chase"
var frames_target: int = 0
var shot_path: String = ""
var hud: bool = true
var no_vsync: bool = false
var all_views: bool = false

var world: RefCounted
var terrain: Terrain
var sim_view: SimView
var pool: EntityViewPool
var renderer: PlanetRenderer
var cam: Camera3D

var _cfg: Dictionary = {}
var _label: Label
var _frame: int = 0
var _frame_ms: PackedFloat32Array = PackedFloat32Array()
var _sync_ms: PackedFloat32Array = PackedFloat32Array()
var _hero: int = 0
var _prev_p: Vector3 = Vector3.ZERO
var _cur_p: Vector3 = Vector3.ZERO
var _prev_q: Quaternion = Quaternion.IDENTITY
var _cur_q: Quaternion = Quaternion.IDENTITY


func _ready() -> void:
	_parse_args()
	if no_vsync:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var n_ships: int = roundi(float(n_entities) * SHIP_FRACTION)
	var n_ground: int = roundi(float(n_entities) * GROUND_FRACTION)
	var driver: GDScript = load(DRIVER)
	world = driver.new()
	world.call("build", n_ships, n_ground, n_entities - n_ships - n_ground)
	sim_view = world.call("view")
	terrain = world.call("terrain")
	_setup_world()
	renderer = PlanetRenderer.new()
	add_child(renderer)
	renderer.setup(terrain, PlanetTierConfig.from_dict(_cfg))
	renderer.camera = cam
	pool = EntityViewPool.new()
	add_child(pool)
	var content: ContentSet = world.call("content")
	pool.setup(EntityViewConfig.from_dict(_cfg), EntityClassTable.from_content(content), UnitMaterialCache.new())
	pool.px_per_m = float(get_viewport().get_visible_rect().size.y) / (2.0 * tan(deg_to_rad(FOV_DEG) * 0.5))
	if all_views:
		pool.px_per_m = ALL_VIEWS_PX_PER_M
	_hero = world.call("hero_id")
	_read_hero()
	_prev_p = _cur_p
	_prev_q = _cur_q
	_label = Label.new()
	_label.position = Vector2(8, 8)
	_label.visible = hud
	var layer: CanvasLayer = CanvasLayer.new()
	layer.add_child(_label)
	add_child(layer)


func _parse_args() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--tier="):
			tier = arg.substr(7)
		elif arg.begins_with("--n="):
			n_entities = int(arg.substr(4))
		elif arg.begins_with("--cam="):
			cam_mode = arg.substr(6)
		elif arg.begins_with("--frames="):
			frames_target = int(arg.substr(9))
		elif arg.begins_with("--shot="):
			shot_path = arg.substr(7)
		elif arg == "--all-views":
			all_views = true
		elif arg == "--novsync":
			no_vsync = true
		elif arg == "--hud=0":
			hud = false
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(TIERS))
	for e: Dictionary in data["quality_tiers"]:
		if str(e["id"]) == tier:
			_cfg = e


func _setup_world() -> void:
	MoonLight.ensure_globals()
	var sun: DirectionalLight3D = MoonLight.make_sun()
	add_child(sun)
	MoonLight.set_sun_dir(MoonLight.DEFAULT_SUN_DIR, sun)
	var we: WorldEnvironment = WorldEnvironment.new()
	we.environment = MoonLight.make_environment()
	SkyMoon.apply(we.environment)
	add_child(we)
	cam = Camera3D.new()
	cam.fov = FOV_DEG
	cam.far = CamMath.FAR_PLANE
	add_child(cam)
	cam.make_current()


func _read_hero() -> void:
	_cur_p = sim_view.pos(_hero)
	_cur_q = sim_view.basis(_hero).get_rotation_quaternion()


func _physics_process(_delta: float) -> void:
	world.call("step")
	_prev_p = _cur_p
	_prev_q = _cur_q
	_read_hero()


func _process(delta: float) -> void:
	var alpha: float = Engine.get_physics_interpolation_fraction()
	var hero_p: Vector3 = _prev_p.lerp(_cur_p, alpha)
	var hero_b: Basis = Basis(_prev_q.slerp(_cur_q, alpha))
	pool.set_local_override(_hero, hero_p, hero_b)   # R0 C1-07: the pose of Prediction.render_state(alpha)
	_place_camera(hero_p, hero_b)
	var up: Vector3 = cam.global_position.normalized()
	cam.near = CamMath.near_plane(renderer.camera_height_agl(cam.global_position))
	pool.cam_pos = cam.global_position
	var t0: int = Time.get_ticks_usec()
	pool.sync(sim_view, (float(sim_view.tick() - 1) + alpha) / pool.tick_hz)
	var sync_ms: float = float(Time.get_ticks_usec() - t0) / 1000.0
	_frame += 1
	if _frame > WARMUP_FRAMES:
		var _a: bool = _frame_ms.push_back(delta * 1000.0)
		var _b: bool = _sync_ms.push_back(sync_ms)
	_label.text = "tier %s  fps %d  entities %d  views %d/%d  far %d  icons %d  sync %.2f ms  draws %d  up.y %.2f" % [
		tier, Engine.get_frames_per_second(), sim_view.visible_ids(0).size(), pool.last_views, pool.view_capacity(), pool.last_far,
		pool.last_icons, sync_ms, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME), up.y]
	if frames_target > 0 and _frame >= frames_target:
		_finish()


func _place_camera(hero_p: Vector3, hero_b: Basis) -> void:
	var up: Vector3 = hero_p.normalized()
	match cam_mode:
		"base":
			var base_world: Vector3 = world.call("base_pos")
			var base: Vector3 = base_world.normalized()
			var f: Basis = Sphere.tangent_frame(base * Sphere.PLANET_RADIUS)
			var p: Vector3 = (base + (-f.x) * (BASE_BACK_M / Sphere.PLANET_RADIUS)).normalized()
			cam.global_position = p * (Sphere.PLANET_RADIUS + terrain.height_at(p) + BASE_ALT_M)
			cam.global_basis = Basis.looking_at((base * (Sphere.PLANET_RADIUS + BASE_ALT_M) - cam.global_position).normalized(), p)
		"wide":
			var p: Vector3 = hero_p.normalized()
			cam.global_position = p * (Sphere.PLANET_RADIUS + WIDE_ALT_M)
			cam.global_basis = Basis.looking_at(-p, hero_b.z)
		_:
			var fwd: Vector3 = -hero_b.z
			fwd = (fwd - up * fwd.dot(up)).normalized()   # horizontal heading: the camera stays level
			cam.global_position = hero_p - fwd * CHASE_BACK_M + up * CHASE_UP_M
			cam.global_basis = Basis.looking_at((hero_p - cam.global_position).normalized(), up)


func _finish() -> void:
	_frame_ms.sort()
	_sync_ms.sort()
	var n: int = _frame_ms.size()
	if n > 0:
		print("ENTITY_DEMO tier=%s entities=%d cam=%s frames=%d frame_ms_p50=%.2f p95=%.2f sync_ms_p50=%.3f p95=%.3f views=%d far=%d icons=%d draws=%d" % [
			tier, n_entities, cam_mode, n, _frame_ms[n >> 1], _frame_ms[int(float(n - 1) * 0.95)], _sync_ms[n >> 1],
			_sync_ms[int(float(n - 1) * 0.95)], pool.last_views, pool.last_far, pool.last_icons,
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)])
	if not shot_path.is_empty():
		var _e: Error = get_viewport().get_texture().get_image().save_png(shot_path)
	get_tree().quit(0)
