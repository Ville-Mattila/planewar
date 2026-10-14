extends GdUnitTestSuite
## TA-23: the chunk pool allocates all pairs up front and reuses them (03 s7.3); the renderer never creates
## Nodes per chunk beyond the pool.

var _parent: Node3D


func before_test() -> void:
	_parent = auto_free(Node3D.new())
	add_child(_parent)


func test_allocates_capacity_up_front_hidden() -> void:
	var pool: ChunkPool = ChunkPool.new(_parent, 12, null)
	assert_int(pool.capacity()).is_equal(12)
	assert_int(pool.allocated).is_equal(12)
	assert_int(_parent.get_child_count()).is_equal(12)
	assert_int(pool.free_count()).is_equal(12)
	for mi: MeshInstance3D in pool.instances:
		assert_bool(mi.visible).is_false()
		assert_object(mi.mesh).is_not_null()


func test_release_and_reacquire_reuses_same_instance_and_mesh() -> void:
	var pool: ChunkPool = ChunkPool.new(_parent, 4, null)
	var s: int = pool.acquire()
	var mi: MeshInstance3D = pool.instances[s]
	var mesh: ArrayMesh = pool.meshes[s]
	pool.set_visible(s, true)
	pool.release(s)
	assert_bool(mi.visible).is_false()
	var s2: int = pool.acquire()
	assert_int(s2).is_equal(s)
	assert_object(pool.instances[s2]).is_same(mi)
	assert_object(pool.meshes[s2]).is_same(mesh)
	assert_int(_parent.get_child_count()).is_equal(4)
	assert_int(pool.allocated).is_equal(4)


func test_exhaustion_returns_minus_one() -> void:
	var pool: ChunkPool = ChunkPool.new(_parent, 3, null)
	var got: Array[int] = []
	for k: int in 3:
		got.append(pool.acquire())
	assert_int(pool.acquire()).is_equal(-1)
	assert_int(pool.in_use()).is_equal(3)
	pool.release(got[1])
	assert_int(pool.acquire()).is_equal(got[1])


func test_renderer_churn_allocates_no_nodes() -> void:
	var terrain: Terrain = Terrain.new()
	var cfg: PlanetTierConfig = PlanetTierConfig.new()
	cfg.pool_size = 160
	cfg.max_depth = 4
	var r: PlanetRenderer = auto_free(PlanetRenderer.new())
	add_child(r)
	r.setup(terrain, cfg)
	var children: int = r.get_child_count()
	assert_int(children).is_equal(160)
	var lat: float = 0.3
	for f: int in 120:
		var dir: Vector3 = Sphere.from_lat_lon(lat, float(f) * 0.01, 1.0)
		var pos: Vector3 = dir * (Sphere.PLANET_RADIUS + 200.0)
		r.update_view(PlanetView.make(pos, Sphere.tangent_frame(dir).x, []), f * 100)
	assert_int(r.get_child_count()).is_equal(children)
	assert_int(r.pool.allocated).is_equal(160)
	assert_int(r.pool.acquires).is_greater(160)   # slots were released and reused
