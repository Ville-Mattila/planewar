extends GdUnitTestSuite
## TA-26: the MultiMesh pools (03 s7.10): projectiles per cube face, trails, decals, icons.


func test_face_of_matches_sphere() -> void:
	for d: Vector3 in [Vector3(1, 0.2, 0.1), Vector3(-1, 0.2, 0.1), Vector3(0.1, 1, 0.3), Vector3(0.1, -1, 0.3), Vector3(0.1, 0.2, 1), Vector3(0.1, 0.2, -1), Vector3(1, 1, 1), Vector3(-1, 1, 1)]:
		assert_int(ProjectilePools.face_of(d)).is_equal(int(Sphere.dir_to_face_uv(d).x))


func test_projectiles_split_over_six_faces_and_draw_in_six_calls() -> void:
	var pools: ProjectilePools = auto_free(ProjectilePools.new())
	add_child(pools)
	pools.setup(16)
	var v: StubSimView = StubSimView.new()
	var dirs: Array[Vector3] = [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD]
	for i: int in 12:
		var id: int = v.put(i, dirs[i % 6] * Sphere.PLANET_RADIUS, 0)
		v.velocities[id] = Vector3(0.0, 0.0, 300.0)
	pools.sync(v, v.ids)
	assert_int(pools.faces.size()).is_equal(6)
	for f: MultiMeshPool in pools.faces:
		assert_int(f.count).is_equal(2)
		assert_int(f.multimesh.visible_instance_count).is_equal(2)
	assert_int(pools.draw_calls()).is_equal(6)
	assert_int(pools.instance_total()).is_equal(12)


func test_projectile_pool_drops_past_capacity() -> void:
	var pools: ProjectilePools = auto_free(ProjectilePools.new())
	add_child(pools)
	pools.setup(2)
	var v: StubSimView = StubSimView.new()
	for i: int in 5:
		var _id: int = v.put(i, Vector3(Sphere.PLANET_RADIUS, float(i), 0.0), 0)
	pools.sync(v, v.ids)
	assert_int(pools.instance_total()).is_equal(2)
	assert_int(pools.dropped).is_equal(3)


func test_tracer_length_follows_speed() -> void:
	var pools: ProjectilePools = auto_free(ProjectilePools.new())
	add_child(pools)
	pools.setup(4)
	var v: StubSimView = StubSimView.new()
	var id: int = v.put(0, Vector3(Sphere.PLANET_RADIUS, 0.0, 0.0), 0)
	v.velocities[id] = Vector3(0.0, 0.0, 500.0)
	pools.sync(v, v.ids)
	if _headless():
		return
	var xf: Transform3D = pools.faces[0].multimesh.get_instance_transform(0)
	assert_float(xf.basis.z.length()).is_equal_approx(500.0 * ProjectilePools.TRACER_S, 0.001)


func test_trails_are_off_without_segments_and_ring_when_on() -> void:
	var off: TrailPool = auto_free(TrailPool.new())
	add_child(off)
	off.setup_trails(0)
	assert_bool(off.enabled()).is_false()
	assert_bool(off.add_segment(Vector3.ZERO, Vector3.RIGHT, Color.WHITE)).is_false()
	var on: TrailPool = auto_free(TrailPool.new())
	add_child(on)
	on.setup_trails(4)
	for i: int in 6:
		assert_bool(on.add_segment(Vector3(0, 0, Sphere.PLANET_RADIUS), Vector3(float(i + 1), 0, Sphere.PLANET_RADIUS), Color.WHITE)).is_true()
	assert_int(on.count).is_equal(4)
	assert_int(on.multimesh.visible_instance_count).is_equal(4)
	if _headless():
		return
	on.update(TrailPool.LIFE_S + 0.1)
	assert_float(on.multimesh.get_instance_color(0).a).is_equal(0.0)


func test_decals_ring_and_fade() -> void:
	var d: DecalPool = auto_free(DecalPool.new())
	add_child(d)
	d.setup_decals(3)
	for i: int in 5:
		d.add(Vector3(float(i), 0.0, Sphere.PLANET_RADIUS), Vector3.BACK, 10.0)
	assert_int(d.live_count()).is_equal(3)
	assert_int(d.multimesh.visible_instance_count).is_equal(3)
	if _headless():
		return
	d.update(DecalPool.FADE_S / 2.0)
	assert_float(d.multimesh.get_instance_color(0).a).is_equal_approx(DecalPool.SOOT.a * 0.5, 0.01)
	d.update(DecalPool.FADE_S)
	assert_float(d.multimesh.get_instance_color(0).a).is_equal(0.0)


func test_icon_size_keeps_a_minimum_screen_size() -> void:
	var near: float = IconPool.icon_size(6.0, 100.0, 704.0)
	assert_float(near).is_equal(12.0)
	var far: float = IconPool.icon_size(6.0, 5000.0, 704.0)
	assert_float(far).is_equal_approx(5000.0 * IconPool.MIN_SCREEN_PX / 704.0, 0.001)


func test_icon_pool_writes_glyph_by_kind() -> void:
	var icons: IconPool = auto_free(IconPool.new())
	add_child(icons)
	icons.setup_icons(4)
	icons.begin()
	assert_bool(icons.add(Vector3.ZERO, 10.0, Color.RED, DefRanges.K_STRUCTURE)).is_true()
	icons.commit()
	if _headless():
		return
	assert_float(icons.multimesh.get_instance_custom_data(0).r).is_equal(2.0)
	assert_int(icons.draw_calls()).is_equal(1)


## The dummy renderer of a headless run does not keep per-instance buffers, so read-backs are skipped there.
func _headless() -> bool:
	return DisplayServer.get_name() == "headless"
