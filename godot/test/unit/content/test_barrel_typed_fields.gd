extends GdUnitTestSuite
## CONTENT-5: typed GroundUnitDef barrel fields (R0 B.31 A-151); absent keys read 0.0 and are not unknown keys.

const DEFS: String = "res://content/defs/"


func before_test() -> void:
	var r: Result = ContentDB.load_all()
	assert_bool(r.ok).is_true()


func _unit(id: StringName) -> GroundUnitDef:
	for g: GroundUnitDef in ContentDB.ground_units:
		if g.id == id:
			return g
	return null


func test_siege_crawler_barrel_fields() -> void:
	var c: GroundUnitDef = _unit(&"siege_crawler")
	assert_float(c.barrel_slew_dps).is_equal(10.0)
	assert_float(c.barrel_min_deg).is_equal(0.0)
	assert_float(c.barrel_max_deg).is_equal(45.0)


func test_harvester_barrel_fields_read_zero() -> void:
	var h: GroundUnitDef = _unit(&"harvester")
	assert_float(h.barrel_slew_dps).is_equal(0.0)
	assert_float(h.barrel_min_deg).is_equal(0.0)
	assert_float(h.barrel_max_deg).is_equal(0.0)


func test_barrel_keys_parse_without_unknown() -> void:
	var g: GroundUnitDef = GroundUnitDef.from_dict(
		{"id": "x", "hp": 1, "cost_ore": 1, "cost_ice": 0, "build_time_s": 1.0, "produced_at": "vehicle_bay",
		"requires": [], "ground_speed": 1, "max_slope_deg": 1, "weapon": null, "sensor_radius": 1,
		"bounding_radius": 1, "score_value": 0, "possessable": false, "autopilot": "ap_harvester",
		"barrel_slew_dps": 10, "barrel_min_deg": -5, "barrel_max_deg": 30}
	)
	assert_array(g.errors).is_empty()
	assert_array(g.unknown).is_empty()
	assert_float(g.barrel_slew_dps).is_equal(10.0)
	assert_float(g.barrel_min_deg).is_equal(-5.0)
	assert_float(g.barrel_max_deg).is_equal(30.0)


func test_content_set_warnings_do_not_list_barrel_keys() -> void:
	var texts: Dictionary = {}
	for f: String in DirAccess.get_files_at(DEFS):
		if f.ends_with(".json"):
			texts[f] = FileAccess.get_file_as_string(DEFS + f)
	var s: ContentSet = ContentLoader.build(texts, {})
	for w: String in s.warnings:
		assert_bool(w.contains("barrel_")).is_false()
