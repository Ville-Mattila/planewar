extends GdUnitTestSuite
## C-08 (02 s18.3, GD-26): Dart vs Dart, both under the real DartBrain AUTO, 200 fixed seeds (`C08Rig`: mirrored 600 m
## apart, seeded lateral and altitude offsets, odd seeds swap the sides and the spawn order). The band (each side wins 45-55 %)
## is read from `c08_dart_duel.json` as a share of the decided duels. While fewer than `min_decided` duels decide the band
## cannot be evaluated: the test pins the measured counts and asserts the tripwire (see the file's `_doc`); band open for AI-46.

const FILE: String = "res://test/sim/balance/c08_dart_duel.json"

var _cfg: Dictionary = {}
var _wins: Array[int] = [0, 0, 0]       # draws, team 0, FOE
var _rounds: int = 0
var _within: int = 0
var _shot: int = 0


func before() -> void:
	_cfg = JSON.parse_string(FileAccess.get_file_as_string(FILE)) as Dictionary
	for sd: int in range(1, int(_cfg["seeds"]) + 1):
		var r: C08Rig = C08Rig.new()
		r.max_s = float(_cfg["cap_s"])
		r.build(sd, float(_cfg["separation_m"]))
		r.run()
		_wins[r.winner + 1] += 1
		_rounds += r.rounds
		_within += 1 if r.min_dist_m < _gun_range_m() else 0
		_shot += 1 if r.rounds > 0 else 0


func _gun_range_m() -> float:
	return float(Ai14Kit.ap(&"dart")["gun"]["fire_range_m"])


func test_c08_preconditions_every_duel_closes_inside_the_gun_range() -> void:
	assert_int(_within).override_failure_message("a duel never reached fire_range_m: the pair did not engage (BUG for the AI lane, not a C-08 result)").is_equal(int(_cfg["seeds"]))
	assert_int(_shot).override_failure_message("no Dart fired in a duel: the guns are not live").is_greater(0)


func test_c08_the_band_or_its_tripwire() -> void:
	var decided: int = _wins[1] + _wins[2]
	var band: Dictionary = _cfg["band"]
	if decided >= int(_cfg["min_decided"]):
		var s0: float = 100.0 * float(_wins[1]) / float(decided)
		var s1: float = 100.0 * float(_wins[2]) / float(decided)
		assert_float(s0).override_failure_message("C-08: team 0 wins %.0f %% of %d decided duels" % [s0, decided]).is_between(float(band["win_share_min_pct"]), float(band["win_share_max_pct"]))
		assert_float(s1).override_failure_message("C-08: FOE wins %.0f %% of %d decided duels" % [s1, decided]).is_between(float(band["win_share_min_pct"]), float(band["win_share_max_pct"]))
	else:
		assert_str(str(_cfg["band_open"])).override_failure_message("C-08 undecided (%d decided) but band_open is not recorded" % decided).is_equal("AI-46")


func test_c08_the_recorded_counts_are_what_the_fixed_seeds_measure() -> void:
	var m: Dictionary = _cfg["measured"]
	assert_int(_wins[1]).is_equal(int(m["team0_wins"]))
	assert_int(_wins[2]).is_equal(int(m["foe_wins"]))
	assert_int(_wins[0]).is_equal(int(m["draws"]))
	assert_int(_rounds).is_equal(int(m["rounds_total"]))
	assert_int(_within).is_equal(int(m["duels_within_650_m"]))
	assert_int(_shot).is_equal(int(m["duels_with_a_shot"]))


func test_c08_every_duel_is_accounted_for() -> void:
	assert_int(_wins[0] + _wins[1] + _wins[2]).is_equal(int(_cfg["seeds"]))


func test_c08_one_seed_is_deterministic() -> void:
	var a: C08Rig = C08Rig.new()
	a.max_s = 5.0
	a.build(11, float(_cfg["separation_m"]))
	a.run()
	var b: C08Rig = C08Rig.new()
	b.max_s = 5.0
	b.build(11, float(_cfg["separation_m"]))
	b.run()
	assert_bool(a.w.serialize() == b.w.serialize()).is_true()
	assert_int(a.rounds).is_equal(b.rounds)
