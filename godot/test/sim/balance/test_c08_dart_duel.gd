extends GdUnitTestSuite
## C-08 (02 s18.3, GD-26; setup R0 B.27 A-140, AI-46): Dart vs Dart, both under the real DartBrain AUTO, 200 fixed
## seeds on `C08Rig` (1,200 m apart nose to nose at 300 m AGL, symmetric world, seed pairs with the sides and the spawn
## order swapped, cap 60 s). Asserts >= `min_decided` duels decided and each side's share of the decided ones inside
## the band of `c08_dart_duel.json`, pins the measured counts, and reports the AI-46 per-duel diagnosis (rounds fired,
## rounds with the lead in the fire cone, hits, EXTEND / break-off entries, median time to the kill).

const FILE: String = "res://test/sim/balance/c08_dart_duel.json"

var _cfg: Dictionary = {}
var _wins: Array[int] = [0, 0, 0]       # draws, team 0, FOE
var _n: PackedInt32Array = PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0, 0])   # rounds, in cone, hits, extends, breakoffs, rams, within, shot, -
var _kill_s: PackedFloat32Array = PackedFloat32Array()


func before() -> void:
	_cfg = JSON.parse_string(FileAccess.get_file_as_string(FILE)) as Dictionary
	for sd: int in range(1, int(_cfg["seeds"]) + 1):
		var r: C08Rig = C08Rig.new()
		r.max_s = float(_cfg["cap_s"])
		r.build(sd, float(_cfg["separation_m"]))
		r.run()
		_wins[r.winner + 1] += 1
		if r.winner >= 0:
			_kill_s.append(float(r.end_tick) / float(C08Rig.HZ))
		_n[0] += r.rounds
		_n[1] += r.fired_in_cone[0] + r.fired_in_cone[1]
		_n[2] += r.hits[0] + r.hits[1]
		_n[3] += r.extends_n[0] + r.extends_n[1]
		_n[4] += r.breakoffs[0] + r.breakoffs[1]
		_n[5] += 1 if r.rammed else 0
		_n[6] += 1 if r.min_dist_m < _gun_range_m() else 0
		_n[7] += 1 if r.rounds > 0 else 0
	_kill_s.sort()
	var k: float = float(int(_cfg["seeds"]))
	print("C-08 AI-46 per duel: rounds %.1f, in the cone %.1f, hits %.1f (%.0f %% of rounds; 02 s11.2 goal 12-18 %%), EXTEND %.1f, break-offs %.1f; rams %d; decided %d (%d / %d); median kill %.1f s" % [
			_n[0] / k, _n[1] / k, _n[2] / k, 100.0 * _n[2] / maxf(_n[0], 1.0), _n[3] / k, _n[4] / k, _n[5], _wins[1] + _wins[2],
			_wins[1], _wins[2], _kill_s[_kill_s.size() >> 1] if _kill_s.size() > 0 else -1.0])
	print("C-08 totals: draws %d, rounds %d, in cone %d, hits %d, extends %d, breakoffs %d, rams %d, within %d, shot %d" % [
			_wins[0], _n[0], _n[1], _n[2], _n[3], _n[4], _n[5], _n[6], _n[7]])


func _gun_range_m() -> float:
	return float(Ai14Kit.ap(&"dart")["gun"]["fire_range_m"])


func test_c08_preconditions_every_duel_closes_inside_the_gun_range() -> void:
	assert_int(_n[6]).override_failure_message("a duel never reached fire_range_m: the pair did not engage (BUG for the AI lane, not a C-08 result)").is_equal(int(_cfg["seeds"]))
	assert_int(_n[7]).override_failure_message("no Dart fired in a duel: the guns are not live").is_greater(0)


func test_c08_the_band_over_the_decided_duels() -> void:
	var decided: int = _wins[1] + _wins[2]
	var band: Dictionary = _cfg["band"]
	assert_int(decided).override_failure_message("C-08: %d of %d duels decided, fewer than min_decided" % [decided, int(_cfg["seeds"])]).is_greater_equal(int(_cfg["min_decided"]))
	var s0: float = 100.0 * float(_wins[1]) / float(maxi(decided, 1))
	var s1: float = 100.0 * float(_wins[2]) / float(maxi(decided, 1))
	assert_float(s0).override_failure_message("C-08: team 0 wins %.1f %% of %d decided duels" % [s0, decided]).is_between(float(band["win_share_min_pct"]), float(band["win_share_max_pct"]))
	assert_float(s1).override_failure_message("C-08: FOE wins %.1f %% of %d decided duels" % [s1, decided]).is_between(float(band["win_share_min_pct"]), float(band["win_share_max_pct"]))
	assert_bool(_cfg.has("band_open")).override_failure_message("band_open is gone once the band is asserted (AI-46)").is_false()


func test_c08_the_recorded_counts_are_what_the_fixed_seeds_measure() -> void:
	var m: Dictionary = _cfg["measured"]
	assert_int(_wins[1]).is_equal(int(m["team0_wins"]))
	assert_int(_wins[2]).is_equal(int(m["foe_wins"]))
	assert_int(_wins[0]).is_equal(int(m["draws"]))
	assert_int(_n[5]).is_equal(int(m["rams"]))
	assert_int(_n[0]).is_equal(int(m["rounds_total"]))
	assert_int(_n[1]).is_equal(int(m["rounds_in_cone"]))
	assert_int(_n[2]).is_equal(int(m["hits"]))
	assert_int(_n[3]).is_equal(int(m["extends"]))
	assert_int(_n[4]).is_equal(int(m["breakoffs"]))
	assert_int(_n[6]).is_equal(int(m["duels_within_650_m"]))
	assert_int(_n[7]).is_equal(int(m["duels_with_a_shot"]))


func test_c08_every_duel_is_accounted_for() -> void:
	assert_int(_wins[0] + _wins[1] + _wins[2]).is_equal(int(_cfg["seeds"]))


func test_c08_a_seed_pair_flies_one_geometry_with_the_sides_swapped() -> void:
	var odd: C08Rig = C08Rig.new()
	odd.build(5, float(_cfg["separation_m"]))
	var even: C08Rig = C08Rig.new()
	even.build(6, float(_cfg["separation_m"]))
	var vo: SimView = odd.w.view()
	var ve: SimView = even.w.view()
	assert_vector(vo.pos(odd.a)).is_equal_approx(ve.pos(even.b), Vector3.ONE * 1e-3)   # team 0 of the odd seed = FOE's place
	assert_vector(vo.pos(odd.b)).is_equal_approx(ve.pos(even.a), Vector3.ONE * 1e-3)
	assert_bool((odd.a < odd.b) == (even.a < even.b)).is_false()                         # the team spawn order is swapped


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
