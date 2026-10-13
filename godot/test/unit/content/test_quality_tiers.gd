extends GdUnitTestSuite
## TA-47: ContentDB loads the real quality_tiers.json (03 s13, R0 C2-29) as three QualityTierDef entries.


func before_test() -> void:
	var r: Result = ContentDB.load_all()
	assert_bool(r.ok).is_true()


func test_three_tiers_loaded_in_order() -> void:
	assert_int(ContentDB.quality_tiers.size()).is_equal(3)
	var ids: Array = []
	for q: QualityTierDef in ContentDB.quality_tiers:
		assert_array(q.errors).is_empty()
		ids.append(str(q.id))
	assert_array(ids).is_equal(["low", "medium", "high"])


func test_tier_names_follow_r0_c2_29() -> void:
	var names: Array = []
	for q: QualityTierDef in ContentDB.quality_tiers:
		names.append(str(q.raw["tier"]))
	assert_array(names).is_equal(["LOW", "MEDIUM", "HIGH"])


func test_knobs_match_the_03_s13_table() -> void:
	var by_id: Dictionary = {}
	for q: QualityTierDef in ContentDB.quality_tiers:
		by_id[str(q.id)] = q.raw
	var low: Dictionary = by_id["low"]
	var medium: Dictionary = by_id["medium"]
	var high: Dictionary = by_id["high"]
	assert_float(Def.num(low["scaling_3d_scale"])).is_equal(0.75)
	assert_float(Def.num(medium["planet_split_k"])).is_equal(2.2)
	assert_int(roundi(Def.num(high["max_fps"]))).is_equal(0)
	assert_int(roundi(Def.num(high["entity_views_cap"]))).is_equal(800)
	assert_int(roundi(Def.num(low["particle_quads_cap"]))).is_equal(500)
