extends GdUnitTestSuite
## TA-23: cut selection on the s_world1_r6000 map at all three tiers (03 s7.2-7.5): the cut covers the view
## with no hole during split and merge under the real per-frame budget, stays within the visible-chunk cap
## and MAX_DEPTH, and every crack between neighbouring leaves of different depth is closed by the skirt of the
## higher side (no neighbour constraint; skirts instead, 03 s7.3).

const MAP: String = "res://content/maps/s_world1_r6000"
const TIERS: String = "res://content/defs/quality_tiers.json"
const R: float = Sphere.PLANET_RADIUS
const EDGE_SAMPLES: int = 8
const NUDGE: float = 1e-6

var _terrain: Terrain
var _mesher: ChunkMesher
var _slots: int = 0


func before() -> void:
	_terrain = Terrain.new()
	assert_int(_terrain.load_map(MAP)).is_equal(OK)
	_mesher = ChunkMesher.new(_terrain, 6)


func _tier(index: int) -> PlanetTierConfig:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(TIERS))
	var list: Array = data["quality_tiers"]
	var d: Dictionary = list[index]
	return PlanetTierConfig.from_dict(d)


## Fake builder: the real mesher for heights and bounds, an unbounded slot counter instead of the pool.
func _build(node: ChunkNode) -> float:
	var _a: Array = _mesher.build_arrays(node)
	node.set_height_range(_mesher.last_h_min, _mesher.last_h_max)
	node.slot = _slots
	_slots += 1
	return 0.5


func _release(_node: ChunkNode) -> void:
	pass


func _tree(cfg: PlanetTierConfig) -> PlanetQuadtree:
	var s: ChunkScheduler = ChunkScheduler.new()
	s.configure(cfg)
	var q: PlanetQuadtree = PlanetQuadtree.new(cfg, s, _release)
	var _n: int = q.prebuild(2, _build)
	return q


## Camera at `agl` metres above the ground at (lat, lon), looking along local east, pitched down a little.
func _view(lat: float, lon: float, agl: float) -> PlanetView:
	var dir: Vector3 = Sphere.from_lat_lon(lat, lon, 1.0)
	var pos: Vector3 = dir * (R + _terrain.height_at(dir) + agl)
	var fwd: Vector3 = (Sphere.tangent_frame(dir).x - dir * 0.2).normalized()
	var xf: Transform3D = Transform3D(Basis.looking_at(fwd, dir), pos)
	return PlanetView.make(pos, fwd, PlanetView.perspective_planes(xf, 75.0, 16.0 / 9.0, 0.3, 40000.0))


## Updates and builds everything queued until the cut is stable.
func _converge(q: PlanetQuadtree, view: PlanetView, now_ms: int) -> void:
	for k: int in 40:
		q.update(view, now_ms)
		if q.scheduler.queue.is_empty():
			return
		for n: ChunkNode in q.scheduler.queue:
			var _ms: float = _build(n)


func test_cut_within_caps_and_max_depth_at_all_tiers() -> void:
	for t: int in 3:
		var cfg: PlanetTierConfig = _tier(t)
		for agl: float in [30.0, 1000.0, 8000.0]:
			var q: PlanetQuadtree = _tree(cfg)
			_converge(q, _view(0.5, 0.4, agl), 0)
			assert_int(q.cut.size()).is_less_equal(cfg.visible_chunks_cap)
			assert_int(q.cut.size()).is_greater(0)
			for n: ChunkNode in q.cut:
				assert_int(n.depth).is_less_equal(cfg.max_depth)
				assert_bool(n.is_built()).is_true()


func test_chase_view_reaches_max_depth_ahead_of_camera() -> void:
	for t: int in 3:
		var cfg: PlanetTierConfig = _tier(t)
		var q: PlanetQuadtree = _tree(cfg)
		var view: PlanetView = _view(0.5, 0.4, 30.0)
		_converge(q, view, 0)
		var ahead: Vector3 = (view.position + view.forward * 150.0).normalized()
		var leaf: ChunkNode = q.leaf_at(ahead)
		assert_object(leaf).is_not_null()
		assert_int(leaf.depth).is_equal(cfg.max_depth)


func test_no_hole_while_flying_with_the_real_budget() -> void:
	for t: int in [0, 2]:
		var cfg: PlanetTierConfig = _tier(t)
		var q: PlanetQuadtree = _tree(cfg)
		var lon: float = 0.4
		for f: int in 240:
			var view: PlanetView = _view(0.5, lon, 30.0 + 2.0 * float(f))     # climb: splits and merges
			q.update(view, f * 16)
			var _b: int = q.scheduler.run(_build)
			assert_int(q.cut.size()).is_less_equal(cfg.visible_chunks_cap)
			var ground: Vector3 = view.position.normalized()
			var side: Vector3 = view.forward.cross(ground).normalized()
			for k: int in 9:
				var p: Vector3 = view.position + view.forward * (100.0 * float(k)) + side * (60.0 * float(k - 4))
				if q.leaf_at(p.normalized()) == null:
					fail("tier %s frame %d: hole at sample %d" % [cfg.tier_id, f, k])
					return
			lon += 160.0 / 60.0 / (R * cos(0.5))


func test_merge_returns_children_after_grace() -> void:
	var cfg: PlanetTierConfig = _tier(2)
	var released: Array[ChunkNode] = []
	var s: ChunkScheduler = ChunkScheduler.new()
	s.configure(cfg)
	var q: PlanetQuadtree = PlanetQuadtree.new(cfg, s, func(n: ChunkNode) -> void: released.append(n))
	var _n: int = q.prebuild(2, _build)
	_converge(q, _view(0.5, 0.4, 30.0), 0)
	var deep: int = 0
	for n: ChunkNode in q.cut:
		deep = maxi(deep, n.depth)
	assert_int(deep).is_equal(6)
	var far: PlanetView = _view(-0.5, 2.5, 30.0)    # jump away: the old region merges
	q.update(far, 100)
	assert_int(released.size()).is_equal(0)          # within the 1 s grace nothing is freed
	q.update(far, 100 + int(cfg.merge_grace_s * 1000.0))
	assert_int(released.size()).is_greater(0)
	for n: ChunkNode in released:
		assert_bool(n.is_built()).is_false()


func test_cracks_between_leaves_are_covered_by_skirts() -> void:
	var poses: Array[Vector3] = [Vector3(0.5, 0.4, 30.0), Vector3(0.05, 0.785, 60.0), Vector3(0.3, 1.2, 1000.0), Vector3(0.2, 0.0, 8000.0)]
	for t: int in 3:
		var cfg: PlanetTierConfig = _tier(t)
		for pose: Vector3 in poses:
			var q: PlanetQuadtree = _tree(cfg)
			_converge(q, _view(pose.x, pose.y, pose.z), 0)
			var worst: Vector2 = _worst_gap(q)
			assert_float(worst.x).override_failure_message("tier %s pose %s: gap %.3f m exceeds skirt" % [cfg.tier_id, pose, worst.x]).is_less_equal(0.0)


## Over all leaf edges: max of (gap where this side is higher - this side's skirt depth), and the gap itself.
func _worst_gap(q: PlanetQuadtree) -> Vector2:
	var worst: Vector2 = Vector2(-INF, 0.0)
	for n: ChunkNode in q.cut:
		var s: float = float(1 << n.depth)
		for e: int in 4:
			for k: int in EDGE_SAMPLES:
				var tt: float = (float(k) + 0.37) / float(EDGE_SAMPLES)
				var u: float = (float(n.ix) + (tt if e >= 2 else float(e))) / s
				var v: float = (float(n.iy) + (tt if e < 2 else float(e - 2))) / s
				var nu: float = u + (NUDGE if e == 1 else (-NUDGE if e == 0 else 0.0))
				var nv: float = v + (NUDGE if e == 3 else (-NUDGE if e == 2 else 0.0))
				var m: ChunkNode = q.leaf_at(Sphere.face_uv_to_dir(n.face, nu, nv))
				if m == null or m == n:
					continue
				var bdir: Vector3 = Sphere.face_uv_to_dir(n.face, u, v)
				var gap: float = _edge_height(n, bdir) - _edge_height(m, bdir)
				if gap > 0.0:
					worst.x = maxf(worst.x, gap - ChunkMesher.skirt_depth(n.depth))
					worst.y = maxf(worst.y, gap)
	return worst


## Height of node n's mesh edge at boundary direction `d` (linear between the two edge vertices).
func _edge_height(n: ChunkNode, d: Vector3) -> float:
	var fuv: Vector3 = Sphere.dir_to_face_uv(d)
	var segs: float = float(32 << n.depth)
	var gx: float = fuv.y * segs
	var gy: float = fuv.z * segs
	if int(fuv.x) != n.face:
		# across a cube edge: map through the shared edge (along-edge coordinate preserved, 03 s2.6)
		var local: Vector3 = Sphere.face_frame(n.face).inverse() * d
		var x: float = local.x / local.z
		var y: float = local.y / local.z
		gx = (atan(clampf(x, -1.0, 1.0)) * 4.0 / PI + 1.0) * 0.5 * segs
		gy = (atan(clampf(y, -1.0, 1.0)) * 4.0 / PI + 1.0) * 0.5 * segs
	var on_x_edge: bool = absf(gx - roundf(gx / 32.0) * 32.0) < absf(gy - roundf(gy / 32.0) * 32.0)
	if on_x_edge:
		var fx: int = int(roundf(gx))
		var y0: int = clampi(int(floorf(gy)), n.gy(0), n.gy(31))
		return lerpf(_mesher.vertex_height(n.face, n.depth, fx, y0), _mesher.vertex_height(n.face, n.depth, fx, y0 + 1), gy - float(y0))
	var fy: int = int(roundf(gy))
	var x0: int = clampi(int(floorf(gx)), n.gx(0), n.gx(31))
	return lerpf(_mesher.vertex_height(n.face, n.depth, x0, fy), _mesher.vertex_height(n.face, n.depth, x0 + 1, fy), gx - float(x0))
