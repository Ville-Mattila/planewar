extends GdUnitTestSuite
## TA-24: flatten sites API (03 s7.6, R0 C2-31): the mesher flattens terrain under a footprint to the height at
## its centre (cosmetic; Terrain.height_at is untouched), consistent across chunk seams and cube edges, and
## PlanetRenderer.set_flatten_sites rebuilds the affected built chunks in place.

const MAP: String = "res://content/maps/s_world1_r6000"

var _terrain: Terrain


func before() -> void:
	_terrain = Terrain.new()
	assert_int(_terrain.load_map(MAP)).is_equal(OK)


func _sites(dirs: Array[Vector3], radii: Array[float]) -> FlattenSites:
	var f: FlattenSites = FlattenSites.new()
	var pos: PackedVector3Array = PackedVector3Array()
	var rad: PackedFloat32Array = PackedFloat32Array()
	for i: int in dirs.size():
		var _a: bool = pos.push_back(dirs[i] * Sphere.PLANET_RADIUS)
		var _b: bool = rad.push_back(radii[i])
	f.set_sites(_terrain, pos, rad)
	return f


## The node whose chunk contains `dir` at `depth`, built with the mesher.
func _node_at(dir: Vector3, depth: int) -> ChunkNode:
	var fuv: Vector3 = Sphere.dir_to_face_uv(dir)
	var side: int = 1 << depth
	return ChunkNode.make(int(fuv.x), depth, mini(int(fuv.y * float(side)), side - 1), mini(int(fuv.z * float(side)), side - 1), -100.0, 100.0)


func test_apply_is_flat_inside_and_untouched_outside() -> void:
	var c: Vector3 = Sphere.from_lat_lon(0.4, 1.0, 1.0)
	var f: FlattenSites = _sites([c], [30.0])
	var node: ChunkNode = _node_at(c, 6)
	assert_int(f.select_for(node)).is_equal(1)
	var site_h: float = _terrain.height_at(c)
	var frame: Basis = Sphere.tangent_frame(c)
	# inside the footprint: exactly the centre height regardless of the terrain
	for k: int in 8:
		var d: Vector3 = (c + frame.x * (float(k) * 3.0 / Sphere.PLANET_RADIUS)).normalized()
		assert_float(f.apply(d, site_h + 7.0)).is_equal_approx(site_h, 1e-9)
	# beyond 1.5 x radius: unchanged
	var far: Vector3 = (c + frame.y * (50.0 / Sphere.PLANET_RADIUS)).normalized()
	assert_float(f.apply(far, 123.0)).is_equal(123.0)
	# between: strictly between the two heights
	var mid: Vector3 = (c + frame.y * (38.0 / Sphere.PLANET_RADIUS)).normalized()
	var blended: float = f.apply(mid, site_h + 10.0)
	assert_float(blended).is_between(site_h + 0.01, site_h + 9.99)


func test_gameplay_height_is_untouched() -> void:
	var c: Vector3 = Sphere.from_lat_lon(0.1, 2.0, 1.0)
	var before_h: float = _terrain.height_at(c)
	var mesher: ChunkMesher = ChunkMesher.new(_terrain, 6)
	mesher.flatten = _sites([c], [40.0])
	var _a: Array = mesher.build_arrays(_node_at(c, 6))
	assert_float(_terrain.height_at(c)).is_equal(before_h)


func test_mesher_heights_under_a_footprint_equal_the_centre_height() -> void:
	var c: Vector3 = Sphere.from_lat_lon(0.4, 1.0, 1.0)
	var node: ChunkNode = _node_at(c, 6)
	var mesher: ChunkMesher = ChunkMesher.new(_terrain, 6)
	mesher.flatten = _sites([c], [20.0])
	var arrays: Array = mesher.build_arrays(node)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var site_h: float = _terrain.height_at(c)
	var inside: int = 0
	for v: int in ChunkMesher.GRID_VERTS:
		var p: Vector3 = verts[v]
		if (p.normalized() - c).length() * Sphere.PLANET_RADIUS <= 20.0:
			inside += 1
			assert_float(p.length() - Sphere.PLANET_RADIUS).is_equal_approx(site_h, 1e-3)
	assert_int(inside).is_greater(4)


func test_flatten_is_seamless_across_a_cube_edge() -> void:
	# a footprint centred on the face-0 / face-? edge: both sides must see identical heights on shared vertices
	var edge: Vector3 = Sphere.face_uv_to_dir(0, 1.0, 0.5)
	var f: FlattenSites = _sites([edge], [25.0])
	var m1: ChunkMesher = ChunkMesher.new(_terrain, 6)
	m1.flatten = f
	var n1: ChunkNode = _node_at(Sphere.face_uv_to_dir(0, 0.9999, 0.5), 6)
	var a1: Array = m1.build_arrays(n1)
	var v1: PackedVector3Array = a1[Mesh.ARRAY_VERTEX]
	var n2: ChunkNode = _node_at(Sphere.face_uv_to_dir(0, 0.99, 0.5), 6)
	var a2: Array = m1.build_arrays(n2)
	var v2: PackedVector3Array = a2[Mesh.ARRAY_VERTEX]
	# shared vertices between horizontally adjacent chunks (u = 1 edge of n2 == u = 0 edge of n1 when adjacent)
	var shared: int = 0
	for i: int in ChunkMesher.GRID_VERTS:
		for j: int in ChunkMesher.GRID_VERTS:
			if v1[i].distance_squared_to(v2[j]) < 1e-8:
				shared += 1
	if n1.ix != n2.ix or n1.iy != n2.iy:
		assert_int(shared).is_greater(0)
	# flattened mesh is finite and within the relief range
	for p: Vector3 in v1:
		assert_float(p.length()).is_between(Sphere.PLANET_RADIUS + Sphere.RELIEF_MIN - 50.0, Sphere.PLANET_RADIUS + Sphere.RELIEF_MAX)


func test_shader_sites_pick_the_nearest_and_cap() -> void:
	var dirs: Array[Vector3] = []
	var radii: Array[float] = []
	for i: int in 40:
		dirs.append(Sphere.from_lat_lon(0.2, float(i) * 0.002, 1.0))
		radii.append(5.0 + float(i))
	var f: FlattenSites = _sites(dirs, radii)
	assert_int(f.size()).is_equal(40)
	var cam: Vector3 = dirs[0] * (Sphere.PLANET_RADIUS + 100.0)
	var out: PackedVector4Array = f.shader_sites(cam)
	assert_int(out.size()).is_equal(FlattenSites.MAX_SHADER_SITES)
	assert_float(out[0].w).is_equal(5.0)         # nearest first
	var few: PackedVector4Array = _sites([dirs[0]], [9.0]).shader_sites(cam)
	assert_int(few.size()).is_equal(1)
	assert_float(few[0].w).is_equal(9.0)


func test_set_sites_ignores_invalid_entries() -> void:
	var f: FlattenSites = FlattenSites.new()
	f.set_sites(_terrain, PackedVector3Array([Vector3.ZERO, Vector3(0, 0, 6000), Vector3(0, 6000, 0)]), PackedFloat32Array([5.0, 0.0, 6.0]))
	assert_int(f.size()).is_equal(1)
	assert_float(f.radii[0]).is_equal(6.0)


func test_renderer_rebuilds_affected_chunks_in_place() -> void:
	var cfg: PlanetTierConfig = PlanetTierConfig.new()
	cfg.max_depth = 4
	cfg.pool_size = 200
	var r: PlanetRenderer = auto_free(PlanetRenderer.new())
	add_child(r)
	r.setup(_terrain, cfg)
	var c: Vector3 = Sphere.from_lat_lon(0.3, 0.5, 1.0)
	var pos: Vector3 = c * (Sphere.PLANET_RADIUS + 150.0)
	for f: int in 40:
		r.update_view(PlanetView.make(pos, -c, []), f * 100)
	var built_before: int = r.scheduler.total_builds
	r.set_flatten_sites(PackedVector3Array([c * Sphere.PLANET_RADIUS]), PackedFloat32Array([30.0]))
	assert_int(r.flatten_site_count()).is_equal(1)
	for f: int in 40:
		r.update_view(PlanetView.make(pos, -c, []), 4000 + f * 100)
	assert_int(r.flatten_rebuilds).is_greater(0)
	assert_int(r.scheduler.total_builds).is_greater_equal(built_before)
	var m: ShaderMaterial = r.material as ShaderMaterial
	assert_int(m.get_shader_parameter(&"site_count")).is_equal(1)
	# clearing the list rebuilds the same chunks once more and zeroes the shader sites
	var rebuilds: int = r.flatten_rebuilds
	r.set_flatten_sites(PackedVector3Array(), PackedFloat32Array())
	for f: int in 40:
		r.update_view(PlanetView.make(pos, -c, []), 9000 + f * 100)
	assert_int(r.flatten_rebuilds).is_greater(rebuilds)
	assert_int(m.get_shader_parameter(&"site_count")).is_equal(0)
	assert_float(r.camera_height_agl(pos)).is_equal_approx(150.0 + _terrain.height_at(c) - _terrain.height_at(pos), 0.01)
