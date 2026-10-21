extends GdUnitTestSuite
## Scenario layer runner (TA-33, 01 ADR-11, 03 TA-33): loads every godot/test/sim/scenarios/*.json, runs each active
## scenario headless through ScenarioRunner and expects no mismatch; planned scenarios are counted, not run. Each
## scenario must also fail when its expectation is broken (a corrupted copy reports mismatches), and the whole
## directory must run in under 60 s (TA-33 acceptance).
## timing: runaway guards only (R0 B.17 A-97)

const DIR: String = "res://test/sim/scenarios"
const BUDGET_MS: int = 60000


func _load_all() -> Dictionary:
	var out: Dictionary = {}
	for f: String in DirAccess.get_files_at(DIR):
		if f.ends_with(".json"):
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("%s/%s" % [DIR, f]))
			assert_bool(parsed is Dictionary).override_failure_message("%s is not a JSON object" % f).is_true()
			if parsed is Dictionary:
				out[f.get_basename()] = parsed
	return out


func test_scenario_files_exist_and_ids_match_file_stems() -> void:
	var all: Dictionary = _load_all()
	assert_int(all.size()).is_greater_equal(7)
	for stem: String in all:
		assert_str(str(all[stem]["id"])).is_equal(stem)
		assert_int(int(all[stem]["schema_version"])).is_equal(1)


func test_every_active_scenario_holds() -> void:
	var all: Dictionary = _load_all()
	var started: int = Time.get_ticks_msec()
	var ran: int = 0
	for stem: String in all:
		var sc: Dictionary = all[stem]
		if sc["status"] != "active":
			continue
		var fails: PackedStringArray = ScenarioRunner.new().run(sc)
		assert_array(Array(fails)).override_failure_message("scenario %s (%s): %s" % [stem, sc["refs"], "; ".join(fails)]).is_empty()
		ran += 1
	assert_int(ran).is_greater_equal(7)
	# runaway guard, measured about 1.5 s for the whole suite on the dev box (bound 60 s, 40x): ran >= 7 above is the hard counter
	assert_int(Time.get_ticks_msec() - started).is_less(BUDGET_MS)


func test_planned_scenarios_name_the_missing_feature() -> void:
	var planned: int = 0
	var all: Dictionary = _load_all()
	for stem: String in all:
		var sc: Dictionary = all[stem]
		if sc["status"] == "planned":
			planned += 1
			assert_str(str(sc.get("planned_reason", ""))).override_failure_message("%s: planned without a reason" % stem).is_not_empty()
	assert_int(planned).is_greater_equal(1)   # victory by Core loss and the tail-down landing grade are not implemented yet


func test_every_active_scenario_fails_when_its_expectation_is_broken() -> void:
	var all: Dictionary = _load_all()
	for stem: String in all:
		var sc: Dictionary = (all[stem] as Dictionary).duplicate(true)
		if sc["status"] != "active":
			continue
		assert_bool(_break(sc)).override_failure_message("%s has nothing to break" % stem).is_true()
		var fails: PackedStringArray = ScenarioRunner.new().run(sc)
		assert_int(fails.size()).override_failure_message("%s still passes with a broken expectation" % stem).is_greater(0)


func test_a_broken_rule_is_reported_with_the_tick_and_values() -> void:
	# Fixture: the possess scenario with the second player's possess no longer refused (the rule "a player may not
	# possess an enemy ship" broken in the script): the runner must say so.
	var sc: Dictionary = (_load_all()["possess_release_handoff"] as Dictionary).duplicate(true)
	for st: Dictionary in sc["script"]:
		if st.get("expect", "") == "REJECTED_NOT_OWNER":
			st["expect"] = "ACCEPTED"
	var fails: PackedStringArray = ScenarioRunner.new().run(sc)
	assert_bool(fails.size() > 0 and "REJECTED_NOT_OWNER" in fails[0] and "t" in fails[0]).is_true()


# Corrupts the first expectation: shifts the first expected event a tick, or negates the first check. True if done.
func _break(sc: Dictionary) -> bool:
	var events: Array = sc.get("events", [])
	if events.size() > 0:
		events[0]["tick"] = int(events[0]["tick"]) + 1
		return true
	var checks: Array = sc.get("checks", [])
	if checks.size() > 0:
		var v: Variant = checks[0]["value"]
		checks[0]["value"] = (not v) if v is bool else float(v) + 1000.0
		checks[0]["op"] = "eq"
		return true
	return false
