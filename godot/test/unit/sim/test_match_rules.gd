extends GdUnitTestSuite
## MatchRules (TA-18; R0 C2-12, 02 s12.1, 01 s3.3): from_defs reads modes.json / match_rules.json / rules.json;
## phase() and arc() are clock functions scaled by the mode's timers.


func _mode(id: StringName) -> ModeDef:
	for m: ModeDef in WorldTestKit.content().modes:
		if m.id == id:
			return m
	return null


func test_from_defs_reads_the_mode_caps_and_rules() -> void:
	var c: ContentSet = WorldTestKit.content()
	var r: MatchRules = MatchRules.from_defs(_mode(&"pvp_1v1"), c.match_rules, c.rules, &"")
	assert_str(String(r.mode)).is_equal("pvp_1v1")
	assert_str(String(r.caps_profile)).is_equal("standard")
	assert_int(r.caps.units).is_equal((c.match_rules.caps[&"standard"] as CapsDef).units)
	assert_float(r.core_exposure_s).is_equal(_mode(&"pvp_1v1").core_exposure_s)
	assert_float(r.hard_end_s).is_equal(_mode(&"pvp_1v1").hard_end_s)
	assert_int(r.tick_hz).is_equal(c.rules.tick_hz)
	assert_array(Array(r.sim_budget_profile)).is_equal(Array(c.rules.sim_budget_profile))
	assert_bool(r.ranked).is_true()                          # hidden_mmr
	assert_str(String(r.adjutant_allowed)).is_equal("economy")
	var lite: MatchRules = MatchRules.from_defs(_mode(&"skirmish"), c.match_rules, c.rules, &"lite")
	assert_str(String(lite.caps.id)).is_equal("lite")
	assert_bool(lite.ranked).is_false()


func test_phase_boundaries() -> void:
	var r: MatchRules = MatchRules.new()
	r.tick_hz = 30
	r.core_exposure_s = 10.0
	r.hard_end_s = 20.0
	assert_int(r.phase(0)).is_equal(MatchRules.Phase.PLAYING)
	assert_int(r.phase(299)).is_equal(MatchRules.Phase.PLAYING)
	assert_int(r.phase(300)).is_equal(MatchRules.Phase.EXPOSURE)
	assert_int(r.phase(599)).is_equal(MatchRules.Phase.EXPOSURE)
	assert_int(r.phase(600)).is_equal(MatchRules.Phase.ENDED)
	r.core_exposure_s = -1.0
	r.hard_end_s = -1.0
	assert_int(r.phase(1000000)).is_equal(MatchRules.Phase.PLAYING)


func test_arc_bands_scale_with_core_exposure() -> void:
	var r: MatchRules = MatchRules.new()
	r.tick_hz = 30
	r.core_exposure_s = 1800.0                                # 01 s3.3: 0-5 open, 5-15 expand, 15-30 siege
	assert_int(r.arc(0)).is_equal(MatchArc.Arc.OPEN)
	assert_int(r.arc(300 * 30 - 1)).is_equal(MatchArc.Arc.OPEN)
	assert_int(r.arc(300 * 30)).is_equal(MatchArc.Arc.EXPAND)
	assert_int(r.arc(900 * 30)).is_equal(MatchArc.Arc.SIEGE)
	assert_int(r.arc(1800 * 30)).is_equal(MatchArc.Arc.OVERTIME)
	r.core_exposure_s = 1200.0                                # pvp_1v1 scales the bands
	assert_int(r.arc(200 * 30)).is_equal(MatchArc.Arc.EXPAND)
	assert_int(r.arc(600 * 30)).is_equal(MatchArc.Arc.SIEGE)
	r.core_exposure_s = -1.0
	assert_int(r.arc(999999)).is_equal(MatchArc.Arc.OPEN)
