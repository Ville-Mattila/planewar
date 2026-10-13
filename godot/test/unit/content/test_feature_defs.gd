extends GdUnitTestSuite
## FEAT-01: wing.json, callsigns.json, barks.json, commander_verbs.json and the scoring.json landing_grade block
## load through ContentDB (08 SL-1, SL-2, SL-3, SL-5); absent files load empty (N8).

const DEFS: String = "res://content/defs/"


func before_test() -> void:
	var r: Result = ContentDB.load_all()
	assert_bool(r.ok).is_true()


func _texts() -> Dictionary:
	var out: Dictionary = {}
	for f: String in DirAccess.get_files_at(DEFS):
		if f.ends_with(".json"):
			out[f] = FileAccess.get_file_as_string(DEFS + f)
	return out


func test_wing_file_loaded() -> void:
	var w: WingDef = ContentDB.wing
	assert_object(w).is_not_null()
	assert_array(w.errors).is_empty()
	assert_int(w.max_wingmen).is_equal(2)
	assert_float(w.min_fuel01).is_equal(0.4)
	assert_int(w.slots_brf_m.size()).is_equal(3)
	assert_array(Array(w.armed_classes)).is_equal(["dart", "lancer"])


func test_callsigns_file_loaded() -> void:
	var c: CallsignDef = ContentDB.callsigns
	assert_object(c).is_not_null()
	assert_array(c.errors).is_empty()
	assert_int(c.number_count).is_equal(9)
	var slot0: Dictionary = c.callsigns["0"]
	var ship_words: Array = slot0["ship"]
	assert_array(ship_words).is_equal(["Kestrel", "Wren", "Swift"])


func test_barks_loaded_one_per_key() -> void:
	assert_int(ContentDB.barks.size()).is_equal(14)
	var by_id: Dictionary = {}
	for b: BarkDef in ContentDB.barks:
		assert_array(b.errors).is_empty()
		by_id[str(b.id)] = b
	var launch: BarkDef = by_id["launch"]
	assert_int(launch.priority).is_equal(3)
	assert_float(launch.cooldown_s).is_equal(20.0)
	var supply: BarkDef = by_id["supply_away"]
	assert_str(str(supply.status)).is_equal("candidate")


func test_supply_canister_is_candidate() -> void:
	var sc: SupplyCanisterDef = ContentDB.supply_canister
	assert_object(sc).is_not_null()
	assert_array(sc.errors).is_empty()
	assert_str(str(sc.status)).is_equal("candidate")
	assert_int(sc.cost_ore).is_equal(15)
	assert_int(sc.cost_ice).is_equal(40)
	assert_int(sc.hp).is_equal(30)
	assert_float(sc.fuel_frac).is_equal(0.4)
	assert_float(sc.ammo_frac).is_equal(0.5)


func test_landing_grade_weights_sum_to_one_and_mirror_02() -> void:
	var lg: Dictionary = ContentDB.scoring.raw["landing_grade"]
	var w: Dictionary = lg["weights"]
	var total: float = Def.num(w["v_vert"]) + Def.num(w["v_horiz"]) + Def.num(w["tilt"]) + Def.num(w["offset"])
	assert_bool(absf(total - 1.0) < 0.000001).is_true()
	var landing: Dictionary = ContentDB.scoring.landing
	var points: Dictionary = lg["points"]
	assert_int(int(Def.num(points["ace"]))).is_equal(int(Def.num(landing["points"]["ace"])))


func test_absent_feature_files_load_empty() -> void:
	var texts: Dictionary = _texts()
	for name: String in ["wing.json", "callsigns.json", "barks.json", "commander_verbs.json"]:
		texts.erase(name)
	var s: ContentSet = ContentLoader.build(texts, {})
	assert_bool(s.ok()).is_true()
	assert_object(s.wing).is_null()
	assert_object(s.callsigns).is_null()
	assert_array(s.barks).is_empty()
	assert_object(s.supply_canister).is_null()


func test_present_wing_file_must_validate() -> void:
	var texts: Dictionary = _texts()
	texts["wing.json"] = str(texts["wing.json"]).replace("\"max_wingmen\": 2", "\"max_wingmen\": \"two\"")
	assert_bool(ContentLoader.build(texts, {}).ok()).is_false()
