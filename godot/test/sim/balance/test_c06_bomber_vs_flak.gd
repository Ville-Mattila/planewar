extends GdUnitTestSuite
## C-06 (02 s18.3, R0 B.25 A-128, GD-26): the real BomberBrain ATTACK on a Refinery guarded by one, then two finished,
## powered and supplied flak_battery towers, the Bomber 600 m over them, 50 fixed seeds each (`C06Rig`). The preconditions
## are asserted first: a failure there is a BUG for the owning lane, not a C-06 result. The band is read from
## `c06_bomber_vs_flak.json`: the 02 band (>= 60 % survive with one, >= 80 % die before release with two) while met,
## else the measured rate minus 10 points as a regression floor with the band open for GD-34.

const FILE: String = "res://test/sim/balance/c06_bomber_vs_flak.json"

var _cfg: Dictionary = {}
var _one: Dictionary = {}
var _two: Dictionary = {}


func before() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(FILE))
	_cfg = parsed as Dictionary
	var seeds: int = int(_cfg["seeds"])
	var rel: float = float(_cfg["bomber_rel_m"])
	_one = C06Rig.sweep(1, seeds, rel)
	_two = C06Rig.sweep(2, seeds, rel)


func _pct(n: int) -> float:
	return 100.0 * float(n) / float(int(_cfg["seeds"]))


func test_c06_preconditions_hold_for_every_seed() -> void:
	var msgs: PackedStringArray = PackedStringArray()
	msgs.append_array(_one["pre_fail"] as PackedStringArray)
	msgs.append_array(_two["pre_fail"] as PackedStringArray)
	assert_array(Array(msgs)).override_failure_message("A-128 precondition failure (file a BUG task, not a C-06 result): %s" % "; ".join(msgs.slice(0, 6))).is_empty()


func test_c06_one_flak_the_bomber_survives_to_release_at_least_the_floor() -> void:
	var rate: float = _pct(int(_one["released"]))
	assert_float(rate).override_failure_message("C-06 one Flak: %.0f %% released (floor %s, band %s)" % [rate, _cfg["one_flak_survive_min"], _cfg["band"]["one_flak_survive_min"]]).is_greater_equal(float(_cfg["one_flak_survive_min"]))


func test_c06_two_flak_the_bomber_dies_before_release_at_least_the_floor() -> void:
	var rate: float = _pct(int(_two["died"]))                                  # a run stops at the first bomb: died = before release
	assert_float(rate).override_failure_message("C-06 two Flak: %.0f %% died before release (floor %s, band %s)" % [rate, _cfg["two_flak_die_min"], _cfg["band"]["two_flak_die_min"]]).is_greater_equal(float(_cfg["two_flak_die_min"]))


func test_c06_the_floors_never_exceed_the_02_band_and_the_measured_rates_clear_them() -> void:
	var band: Dictionary = _cfg["band"]
	assert_float(float(_cfg["one_flak_survive_min"])).is_less_equal(float(band["one_flak_survive_min"]))
	assert_float(float(_cfg["two_flak_die_min"])).is_less_equal(float(band["two_flak_die_min"]))
	assert_float(float(_cfg["measured"]["one_flak_survive_pct"])).is_greater_equal(float(_cfg["one_flak_survive_min"]))
	assert_float(float(_cfg["measured"]["two_flak_die_pct"])).is_greater_equal(float(_cfg["two_flak_die_min"]))


func test_c06_the_recorded_measurement_is_what_the_sweep_measures() -> void:
	assert_float(_pct(int(_one["released"]))).is_equal_approx(float(_cfg["measured"]["one_flak_survive_pct"]), 0.5)
	assert_float(_pct(int(_two["died"]))).is_equal_approx(float(_cfg["measured"]["two_flak_die_pct"]), 0.5)


func test_c06_control_without_a_flak_every_bomber_releases() -> void:
	var r: Dictionary = C06Rig.sweep(0, 8, float(_cfg["bomber_rel_m"]))
	assert_int(int(r["released"])).is_equal(8)
	assert_int(int(r["died"])).is_equal(0)
	assert_array(Array(r["pre_fail"] as PackedStringArray)).is_empty()


func test_c06_a_second_flak_never_helps_the_bomber() -> void:
	assert_int(int(_two["released"])).is_less_equal(int(_one["released"]))


func test_c06_one_seed_is_deterministic() -> void:
	var a: C06Rig = C06Rig.new()
	a.build(7, 1, float(_cfg["bomber_rel_m"]))
	a.run()
	var b: C06Rig = C06Rig.new()
	b.build(7, 1, float(_cfg["bomber_rel_m"]))
	b.run()
	assert_int(a.death_tick).is_equal(b.death_tick)
	assert_int(a.release_tick).is_equal(b.release_tick)
	assert_bool(a.w.serialize() == b.w.serialize()).is_true()


func test_c06_the_forced_600_m_setup_holds_over_the_flak() -> void:
	var r: C06Rig = C06Rig.new()
	r.build(3, 1, float(_cfg["bomber_rel_m"]))
	r.run()
	assert_float(r.rel_min_in_range).is_greater_equal(float(_cfg["bomber_rel_m"]) - C06Rig.REL_TOL_M)
	assert_float(r.rel_max_in_range).is_less_equal(float(_cfg["bomber_rel_m"]) + C06Rig.REL_TOL_M)
	assert_array(Array(r.run_preconditions())).is_empty()


func _flak_floor_m() -> float:
	for sd: StructureDef in Ai17Kit.content().structures:
		if sd.id == &"flak_battery":
			return float(sd.tower["h_rel_min"])
	return 0.0


## BUG-2 (sim_ai) known-bug pin: the shipped bands (rel_m 0) put the Bomber at the 60 m DECK band, under the Flak's 150 m
## floor, so all 50 release and the defenders first see it at about 850-940 m (< A-128's 1,500 m). Passes while the bug
## stands; fails once it is fixed, and BUG-2 must then update `shipped_bands_pin` in the JSON and this test.
func test_c06_known_bug_bug2_shipped_bands_fly_under_the_flak_floor() -> void:
	var pin: Dictionary = _cfg["shipped_bands_pin"]
	var r: Dictionary = C06Rig.sweep(int(pin["n_flak"]), int(pin["seeds"]), 0.0)
	var what: String = "BUG-2 pin: released %s, rel %.0f..%.0f, seen %.0f..%.0f (fixed? update shipped_bands_pin)" % [r["released"], r["rel_lo"], r["rel_hi"], r["seen_lo"], r["seen_hi"]]
	assert_int(int(r["released"])).override_failure_message(what).is_equal(int(pin["released"]))
	assert_float(float(r["rel_lo"])).override_failure_message(what).is_greater_equal(float(pin["rel_at_release_min_m"]))
	assert_float(float(r["rel_hi"])).override_failure_message(what).is_less_equal(float(pin["rel_at_release_max_m"]))
	assert_float(float(r["rel_hi"])).override_failure_message(what).is_less(_flak_floor_m())
	assert_float(float(r["seen_lo"])).override_failure_message(what).is_greater_equal(float(pin["seen_min_m"]))
	assert_float(float(r["seen_hi"])).override_failure_message(what).is_less_equal(float(pin["seen_max_m"]))
	assert_float(float(r["seen_hi"])).override_failure_message(what).is_less(C06Rig.SEE_MIN_M)
	assert_bool((r["pre_fail"] as PackedStringArray).size() > 0).override_failure_message(what).is_true()
