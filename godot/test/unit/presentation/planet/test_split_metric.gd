extends GdUnitTestSuite
## TA-23: split metric, merge hysteresis and priority (03 s7.2, s7.4) and the tier knobs read from
## quality_tiers.json (03 s13).

const TIERS: String = "res://content/defs/quality_tiers.json"


func _tier(index: int) -> PlanetTierConfig:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(TIERS))
	var list: Array = data["quality_tiers"]
	var d: Dictionary = list[index]
	return PlanetTierConfig.from_dict(d)


func test_split_inside_k_edges_only() -> void:
	var edge: float = 147.0
	assert_bool(PlanetQuadtree.wants_split(0.0, edge, 2.5, 5, 6)).is_true()
	assert_bool(PlanetQuadtree.wants_split(2.5 * edge - 0.01, edge, 2.5, 5, 6)).is_true()
	assert_bool(PlanetQuadtree.wants_split(2.5 * edge, edge, 2.5, 5, 6)).is_false()


func test_never_split_at_max_depth() -> void:
	assert_bool(PlanetQuadtree.wants_split(0.0, 147.0, 2.5, 6, 6)).is_false()
	assert_bool(PlanetQuadtree.wants_split(0.0, 295.0, 1.8, 5, 5)).is_false()


func test_merge_has_half_chunk_hysteresis() -> void:
	var edge: float = 295.0
	# between K and K + 0.5 edges: a split node stays split, an unsplit one does not split
	var d: float = 2.7 * edge
	assert_bool(PlanetQuadtree.wants_split(d, edge, 2.5, 4, 6)).is_false()
	assert_bool(PlanetQuadtree.wants_merge(d, edge, 2.5, 0.5)).is_false()
	assert_bool(PlanetQuadtree.wants_merge(3.01 * edge, edge, 2.5, 0.5)).is_true()


func test_bounds_distance_is_to_sphere_surface_and_clamped() -> void:
	var n: ChunkNode = ChunkNode.make(0, 3, 4, 4, 0.0, 0.0)
	var outside: Vector3 = n.center + n.center.normalized() * (n.radius + 100.0)
	assert_float(PlanetQuadtree.bounds_distance(outside, n)).is_equal_approx(100.0, 1e-2)
	assert_float(PlanetQuadtree.bounds_distance(n.center, n)).is_equal(0.0)


func test_priority_orders_by_split_depth_then_frustum_and_ahead() -> void:
	var edge: float = 100.0
	var near: float = PlanetQuadtree.priority_of(10.0, edge, 2.5, false, false)
	var far: float = PlanetQuadtree.priority_of(200.0, edge, 2.5, false, false)
	assert_float(near).is_greater(far)
	assert_float(PlanetQuadtree.priority_of(200.0, edge, 2.5, true, false) - far).is_equal_approx(2.0, 1e-9)
	assert_float(PlanetQuadtree.priority_of(200.0, edge, 2.5, false, true) - far).is_equal_approx(1.0, 1e-9)


func test_chunk_edge_matches_03_s7_1_table() -> void:
	var expected: Array[float] = [9425.0, 4712.0, 2356.0, 1178.0, 589.0, 295.0, 147.0]
	for depth: int in expected.size():
		var n: ChunkNode = ChunkNode.make(0, depth, 0, 0, 0.0, 0.0)
		assert_float(n.edge_m).is_equal_approx(expected[depth], 1.0)


func test_tier_knobs_come_from_quality_tiers_json() -> void:
	var low: PlanetTierConfig = _tier(0)
	var med: PlanetTierConfig = _tier(1)
	var high: PlanetTierConfig = _tier(2)
	assert_float(low.split_k).is_equal(1.8)
	assert_int(low.max_depth).is_equal(5)
	assert_int(low.builds_per_frame).is_equal(2)
	assert_float(low.build_ms_cap).is_equal(2.0)
	assert_int(low.visible_chunks_cap).is_equal(90)
	assert_float(med.split_k).is_equal(2.2)
	assert_int(med.visible_chunks_cap).is_equal(120)
	assert_float(high.split_k).is_equal(2.5)
	assert_int(high.max_depth).is_equal(6)
	assert_int(high.builds_per_frame).is_equal(6)
	assert_float(high.build_ms_cap).is_equal(4.0)
	# not in the file yet: 03 s7 defaults
	assert_int(high.starvation_frames).is_equal(2)
	assert_float(high.merge_grace_s).is_equal(1.0)
	assert_int(high.pool_size).is_equal(220)


func test_optional_keys_override_defaults() -> void:
	var c: PlanetTierConfig = PlanetTierConfig.from_dict({"id": "x", "chunk_starvation_frames": 3, "chunk_pool_size": 64})
	assert_int(c.starvation_frames).is_equal(3)
	assert_int(c.pool_size).is_equal(64)
	assert_str(str(c.tier_id)).is_equal("x")


func test_from_def_reads_raw() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(TIERS))
	var list: Array = data["quality_tiers"]
	var d: Dictionary = list[1]
	var c: PlanetTierConfig = PlanetTierConfig.from_def(QualityTierDef.from_dict(d))
	assert_float(c.split_k).is_equal(2.2)
	assert_int(c.builds_per_frame).is_equal(4)
