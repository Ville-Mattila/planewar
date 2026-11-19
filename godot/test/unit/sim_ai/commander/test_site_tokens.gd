extends GdUnitTestSuite
## AI-23 contract: the location tokens of 05 s7.3 (`SiteToken.parse`) and the map's static geometry they resolve on
## (`MapSites`, from features.json: ore fields, Cold Traps, start slots; 02 s9, R0 B.6, O-5).


func test_every_s73_token_parses() -> void:
	var cases: Dictionary = {
		"core": SiteToken.Kind.CORE, "approach:nearest_enemy": SiteToken.Kind.APPROACH,
		"toward:cold_trap:home": SiteToken.Kind.TOWARD, "cold_trap:home": SiteToken.Kind.COLD_TRAP,
		"ore_field:home_2": SiteToken.Kind.ORE_FIELD, "outpost_site:home_trap": SiteToken.Kind.OUTPOST_SITE,
		"contested_field": SiteToken.Kind.CONTESTED, "refinery": SiteToken.Kind.REFINERY, "outpost": SiteToken.Kind.OUTPOST}
	for s: String in cases:
		var t: SiteToken = SiteToken.parse(s)
		assert_object(t).override_failure_message("'%s' must parse" % s).is_not_null()
		assert_int(t.kind).override_failure_message(s).is_equal(int(cases[s]))
		assert_str(t.src).is_equal(s)


func test_arguments_are_read() -> void:
	assert_int(SiteToken.parse("ore_field:home_2").nth).is_equal(2)
	assert_int(SiteToken.parse("ore_field:home_1").nth).is_equal(1)
	assert_str(SiteToken.parse("approach:nearest_enemy").arg).is_equal("nearest_enemy")
	var t: SiteToken = SiteToken.parse("toward:cold_trap:home")
	assert_object(t.inner).is_not_null()
	assert_int(t.inner.kind).is_equal(SiteToken.Kind.COLD_TRAP)


func test_bad_tokens_do_not_parse() -> void:
	for s: String in ["", "nowhere", "ore_field:away_1", "ore_field:home_0", "ore_field:home_x", "toward:", "toward:ghost", "approach:", "cold_trap:far"]:
		assert_object(SiteToken.parse(s)).override_failure_message("'%s' must not parse" % s).is_null()


func test_cradle_home_geometry() -> void:
	var m: MapSites = Ai23Kit.sites()
	assert_int(m.slot_count()).is_equal(8)
	# slots 0 and 2 are 90 degrees apart (O-5)
	assert_float(rad_to_deg(m.slot_dir(0).angle_to(m.slot_dir(2)))).is_equal_approx(90.0, 0.5)
	var a: Vector3 = m.home_field(0, 1)
	var b: Vector3 = m.home_field(0, 2)
	assert_bool(a != Vector3.ZERO and b != Vector3.ZERO and a != b).is_true()
	assert_vector(m.home_field(0, 3)).is_equal(Vector3.ZERO)
	assert_bool(m.home_trap(0) != Vector3.ZERO).is_true()
	# a home field of slot 0 is nearer to slot 0 than to slot 2
	assert_float(m.slot_dir(0).angle_to(a)).is_less(m.slot_dir(2).angle_to(a))


func test_contested_field_is_the_nearest_neutral_field() -> void:
	var m: MapSites = Ai23Kit.sites()
	var c: Vector3 = m.contested(m.slot_dir(0))
	assert_bool(c != Vector3.ZERO).is_true()
	# no neutral field is nearer to the Core than the one returned
	var f: Dictionary = Ai23Kit.features()
	for n: Variant in f["nodes"]:
		var nd: Dictionary = n
		if nd["kind"] == "ore_field" and int(nd["slot"]) < 0:
			var d: Vector3 = Ai23Kit._vec(nd["dir"])
			assert_float(m.slot_dir(0).angle_to(c)).is_less_equal(m.slot_dir(0).angle_to(d) + 1e-6)


func test_a_map_without_neutral_fields_has_no_contested_site() -> void:
	var m: MapSites = Ai23Kit.sites(&"tiny_test")
	assert_vector(m.contested(m.slot_dir(0))).is_equal(Vector3.ZERO)
	assert_vector(m.home_field(0, 2)).is_equal(Vector3.ZERO)


func test_features_without_start_slots_are_refused() -> void:
	assert_object(MapSites.from_features({"nodes": []})).is_null()
