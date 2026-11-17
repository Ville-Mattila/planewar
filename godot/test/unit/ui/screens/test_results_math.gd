extends GdUnitTestSuite
## UX-27 Results binds to every MATCH_END field of 06 s8 / R0 C2-17.


func _payload() -> Dictionary:
	return {
		"winner_team": 1, "end_reason": Protocol.MatchEndReason.CORES_DESTROYED, "tick": 36000,
		"structure_value": [4000, 9000],
		"players": [
			{"slot": 2, "team": 1, "name": "Aino", "score_pilot": 300, "score_commander": 1200, "kills": 7,
					"manual_landings": 4, "structures_destroyed": 3, "sorties": 9, "ore_mined": 12400, "ore_spent": 800,
					"ice_delivered": 55, "pilot_time_s": [65, 0, 120, 0, 3], "medals": [1, 0, 0, 1]},
			{"slot": 0, "team": 0, "name": "Ville", "score_pilot": 900, "score_commander": 50, "kills": 2,
					"manual_landings": 1, "structures_destroyed": 0, "sorties": 2, "ore_mined": 1, "ore_spent": 2,
					"ice_delivered": 3, "pilot_time_s": [1, 2, 3, 4, 5], "medals": []},
		],
	}


func test_from_dict_reads_every_field() -> void:
	var d: ResultsData = ResultsData.from_dict(_payload())
	assert_int(d.winner_team).is_equal(1)
	assert_int(d.end_reason).is_equal(0)
	assert_int(d.tick).is_equal(36000)
	assert_int(d.value_of(1)).is_equal(9000)
	assert_int(d.value_of(7)).is_equal(0)
	var r: ResultsRow = d.rows[0]
	assert_str(r.player_name).is_equal("Aino")
	assert_int(r.score_pilot).is_equal(300)
	assert_int(r.score_commander).is_equal(1200)
	assert_int(r.kills).is_equal(7)
	assert_int(r.manual_landings).is_equal(4)
	assert_int(r.structures_destroyed).is_equal(3)
	assert_int(r.sorties).is_equal(9)
	assert_int(r.ore_mined).is_equal(12400)
	assert_int(r.ore_spent).is_equal(800)
	assert_int(r.ice_delivered).is_equal(55)
	assert_int(r.pilot_time_s.size()).is_equal(5)
	assert_int(r.pilot_time_s[2]).is_equal(120)
	assert_int(r.medals.size()).is_equal(4)
	assert_array(d.team_ids()).is_equal(PackedInt32Array([0, 1]))


func test_cells_follow_the_columns_and_group_numbers() -> void:
	var r: ResultsRow = ResultsData.from_dict(_payload()).rows[0]
	var c: PackedStringArray = ResultsMath.cells(r, "en")
	assert_int(c.size()).is_equal(ResultsMath.COLUMNS.size())
	assert_str(c[0]).is_equal("Aino")
	assert_str(c[7]).is_equal("12,400")
	assert_str(ResultsMath.cells(r, "fi")[7]).is_equal("12 400")


func test_medals_come_out_in_medals_json_order() -> void:
	var r: ResultsRow = ResultsData.from_dict(_payload()).rows[0]
	var ids: PackedStringArray = PackedStringArray(["feather_touch", "two_speeds", "under_the_floor", "lock_breaker"])
	assert_array(ResultsMath.medal_ids(r, ids)).is_equal(PackedStringArray(["feather_touch", "lock_breaker"]))


func test_pilot_times_skip_unused_classes() -> void:
	var r: ResultsRow = ResultsData.from_dict(_payload()).rows[0]
	var t: Array[PackedStringArray] = ResultsMath.pilot_times(r)
	assert_int(t.size()).is_equal(3)
	assert_str(t[0][0]).is_equal("dart")
	assert_str(t[0][1]).is_equal("1:05")
	assert_str(t[1][0]).is_equal("bomber")


func test_outcome_states() -> void:
	assert_int(ResultsMath.outcome(1, 0, 1)).is_equal(ResultsMath.Outcome.VICTORY)
	assert_int(ResultsMath.outcome(1, 0, 0)).is_equal(ResultsMath.Outcome.DEFEAT)
	assert_int(ResultsMath.outcome(1, 2, 0)).is_equal(ResultsMath.Outcome.DEFEAT)   # surrender
	assert_int(ResultsMath.outcome(1, Protocol.MatchEndReason.HARD_END_VALUE, 0)).is_equal(ResultsMath.Outcome.TIME_LIMIT)
	assert_int(ResultsMath.outcome(-1, 0, 0)).is_equal(ResultsMath.Outcome.DEFEAT)
	assert_bool(ResultsMath.local_won(1, 1)).is_true()
	assert_bool(ResultsMath.local_won(-1, -1)).is_false()


func test_every_end_reason_has_a_distinct_key() -> void:
	var seen: Dictionary = {}
	for reason: int in 5:
		seen[ResultsMath.reason_key(reason)] = true
	assert_int(seen.size()).is_equal(5)


func test_rows_sort_by_team_then_total_score() -> void:
	var rows: Array[ResultsRow] = ResultsData.from_dict(_payload()).rows
	var s: Array[ResultsRow] = ResultsMath.sorted_rows(rows)
	assert_int(s[0].team).is_equal(0)
	assert_int(s[1].team).is_equal(1)
	assert_int(ResultsMath.total_score(s[1])).is_equal(1500)
	assert_int(rows[0].slot).is_equal(2)   # input untouched
