class_name BenchPlanet
extends SceneTree
## Planet renderer core benchmark (TA-23; 03 s7.3-7.4, s14.2 boost path). Per tier of quality_tiers.json:
## prebuild time, per-depth chunk build ms (p50 / p95, mesher arrays + ArrayMesh upload), and a scripted
## boost path (160 m/s at 30 m AGL) at a fixed 1/60 s step reporting plan ms, builds per second, visible
## chunks, pool use, refused splits and the longest queue wait of a chunk built within 400 m of the camera
## (the parent-shown hole time of 03 s14.2).
## godot --headless --path godot -s res://test/perf/bench_planet.gd [-- --frames=600 --map=s_world1_r6000]
## Headless uses the dummy RenderingServer: upload cost is a lower bound; frame time needs a windowed run
## (scenes/presentation/planet/planet_demo.tscn -- --bench).

const TIERS: String = "res://content/defs/quality_tiers.json"
const BOOST_MPS: float = 160.0
const BOOST_AGL: float = 30.0
const STEP_S: float = 1.0 / 60.0
const SAMPLES_PER_DEPTH: int = 24


func _initialize() -> void:
	var frames: int = 600
	var map_id: String = "s_world1_r6000"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--frames="):
			frames = int(arg.substr(9))
		elif arg.begins_with("--map="):
			map_id = arg.substr(6)
	var terrain: Terrain = Terrain.new()
	var err: Error = terrain.load_map("res://content/maps/" + map_id)
	print("BENCH_PLANET map=%s err=%d n=%d" % [map_id, err, terrain.face_resolution])
	var tiers: Array = JSON.parse_string(FileAccess.get_file_as_string(TIERS)).get("quality_tiers", [])
	for t: Variant in tiers:
		var d: Dictionary = t
		_bench_tier(terrain, PlanetTierConfig.from_dict(d), frames)
	quit(0)


func _bench_tier(terrain: Terrain, cfg: PlanetTierConfig, frames: int) -> void:
	var root: Node3D = Node3D.new()
	get_root().add_child(root)
	var r: PlanetRenderer = PlanetRenderer.new()
	root.add_child(r)
	var t0: int = Time.get_ticks_usec()
	r.setup(terrain, cfg)
	print("BENCH_PLANET tier=%s prebuild_chunks=%d prebuild_ms=%.1f" % [cfg.tier_id, r.prebuilt, float(Time.get_ticks_usec() - t0) * 0.001])
	_bench_depths(r, cfg)
	_boost_path(r, cfg, frames)
	root.queue_free()


func _bench_depths(r: PlanetRenderer, cfg: PlanetTierConfig) -> void:
	var mesh: ArrayMesh = ArrayMesh.new()
	for depth: int in cfg.max_depth + 1:
		var times: PackedFloat32Array = PackedFloat32Array()
		var side: int = 1 << depth
		for k: int in SAMPLES_PER_DEPTH:
			var n: ChunkNode = ChunkNode.make(k % 6, depth, (k * 7) % side, (k * 13) % side, Sphere.RELIEF_MIN, Sphere.RELIEF_MAX)
			var t0: int = Time.get_ticks_usec()
			r.mesher.build_into(n, mesh, r.material)
			var _a: bool = times.push_back(float(Time.get_ticks_usec() - t0) * 0.001)
		times.sort()
		print("BENCH_PLANET tier=%s depth=%d build_ms_p50=%.2f p95=%.2f max=%.2f" % [cfg.tier_id, depth,
			times[times.size() >> 1], times[int(float(times.size() - 1) * 0.95)], times[times.size() - 1]])


func _boost_path(r: PlanetRenderer, cfg: PlanetTierConfig, frames: int) -> void:
	var lat: float = deg_to_rad(30.0)
	var lon: float = deg_to_rad(Sphere.SLOT_LON0_DEG)
	var plan: PackedFloat32Array = PackedFloat32Array()
	var builds0: int = r.scheduler.total_builds
	var max_vis: int = 0
	var refused_pool: int = 0
	var refused_cap: int = 0
	var under_min: int = 99
	var forced: int = 0
	for f: int in frames:
		var dir: Vector3 = Sphere.from_lat_lon(lat, lon, 1.0)
		var pos: Vector3 = dir * (Sphere.PLANET_RADIUS + r.terrain.height_at(dir) + BOOST_AGL)
		var east: Vector3 = Sphere.tangent_frame(dir).x
		var fwd: Vector3 = (east - dir * 0.2).normalized()
		var view: PlanetView = PlanetView.make(pos, fwd, _frustum(pos, fwd, dir))
		r.update_view(view, int(float(f) * STEP_S * 1000.0))
		var _a: bool = plan.push_back(r.plan_ms)
		max_vis = maxi(max_vis, r.visible_chunks())
		forced += 1 if r.scheduler.last_forced else 0
		refused_pool += r.quadtree.splits_refused_by_pool
		refused_cap += r.quadtree.splits_refused_by_cap
		var leaf: ChunkNode = r.quadtree.leaf_at(dir)
		if f >= 120:
			under_min = mini(under_min, leaf.depth if leaf != null else -1)
		lon += BOOST_MPS * STEP_S / (Sphere.PLANET_RADIUS * cos(lat))
	plan.sort()
	var secs: float = float(frames) * STEP_S
	print("BENCH_PLANET tier=%s boost frames=%d plan_ms_p50=%.2f p95=%.2f builds_per_s=%.1f forced=%d max_visible=%d cap=%d pool_used=%d/%d pool_exhausted=%d refused_cap=%d refused_pool=%d worst_near_wait_s=%.2f depth_under_cam_min=%d build_ms_p50=%.2f p95=%.2f" % [
		cfg.tier_id, frames, plan[plan.size() >> 1], plan[int(float(plan.size() - 1) * 0.95)],
		float(r.scheduler.total_builds - builds0) / secs, forced, max_vis, cfg.visible_chunks_cap,
		r.pool.in_use(), r.pool.capacity(), r.pool_exhausted, refused_cap, refused_pool, float(r.worst_near_wait_ms) * 0.001, under_min,
		r.build_ms_percentile(0.5), r.build_ms_percentile(0.95)])


## Frustum of a 75 degree, 16:9 camera at `pos` looking along `fwd` with `up` (near 0.3, far 40 km).
static func _frustum(pos: Vector3, fwd: Vector3, up: Vector3) -> Array[Plane]:
	return PlanetView.perspective_planes(Transform3D(Basis.looking_at(fwd, up), pos), 75.0, 16.0 / 9.0, 0.3, 40000.0)
