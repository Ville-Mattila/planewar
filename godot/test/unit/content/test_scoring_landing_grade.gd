extends GdUnitTestSuite
## CONTENT-2 (A-122): ScoringDef carries the typed landing_grade block from scoring.json.


func test_landing_grade_loaded_from_real_scoring_json() -> void:
	var r: Result = ContentDB.load_all()
	assert_bool(r.ok).is_true()
	var s: ScoringDef = ContentDB.scoring
	assert_array(s.errors).is_empty()
	var lg: Dictionary = s.landing_grade
	assert_int(int(lg["manual_window_m"])).is_equal(150)
	assert_float(float(lg["weights"]["v_vert"])).is_equal(0.35)


func test_missing_landing_grade_is_refused() -> void:
	var raw: Dictionary = (ContentDB.scoring.raw as Dictionary).duplicate(true)
	raw.erase("landing_grade")
	var s: ScoringDef = ScoringDef.from_dict(raw)
	assert_bool(s.errors.is_empty()).is_false()
	assert_str(" ".join(s.errors)).contains("landing_grade")
