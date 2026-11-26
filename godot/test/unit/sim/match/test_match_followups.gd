extends GdUnitTestSuite
## GD-49 (sim/match/MODULE.md M1, M6; sim/scoring/MODULE.md): MatchResult.structure_value is the judge's 02 s12.1 value,
## PLAYER_ELIMINATED b names the team whose damage destroyed the last Core, and the hard-end damage tie-break keeps the
## damage of shooters that died before the end.

const K: GDScript = preload("res://test/unit/sim/match/match_flow_kit.gd")


# The shooter dies (one step, so the ScoreKeeper has recorded it); its id is then stale.
func _dead_shooter(w: SimWorld, team: int) -> int:
	var shooter: int = WorldTestKit.spawn(w, &"dart", team, team, WorldTestKit.at(300.0, 900.0))
	var _r: CommandResult = w.apply_command(CommandPayload.debug_set(0, shooter, CommandPayload.SET_HP, 0.0))
	w.step()
	assert_bool(w.view().alive(shooter)).is_false()
	return shooter


func test_match_result_uses_the_judge_structure_value() -> void:
	var w: SimWorld = K.world(&"pvp_1v1", 1)
	var core: int = w.store().id_of(K.structure(w, 0, &"core"))
	var ref: int = w.store().id_of(K.structure(w, 1, &"refinery"))
	var _a: CommandResult = w.apply_command(CommandPayload.debug_set(0, core, CommandPayload.SET_HP, 700.0))
	var _b: CommandResult = w.apply_command(CommandPayload.debug_set(0, ref, CommandPayload.SET_HP, 30.0))
	w.step()
	var r: MatchResult = w.match_result()
	for t: int in PlayerTable.TEAMS:
		assert_int(r.structure_value[t]).is_equal(roundi(w.judge().structure_value(t)))
	assert_int(r.structure_value[0]).is_not_equal(roundi(float(WorldTestKit.content().match_rules.core_value)))   # hp01 counts
	assert_int(r.structure_value[2]).is_equal(0)


func test_player_eliminated_names_the_team_that_destroyed_the_last_core() -> void:
	var w: SimWorld = K.world(&"pvp_1v1", 1)
	var shooter: int = WorldTestKit.spawn(w, &"dart", 0, 0, WorldTestKit.at(300.0, 900.0))
	var core: int = K.structure(w, 1, &"core")
	assert_bool(w._combat._sink.destroy(core, shooter, w.tick())).is_true()
	w.step()
	var el: Array[SimEvent] = K.of_kind(w.drain_events(), SimEvent.Kind.PLAYER_ELIMINATED)
	assert_int(el.size()).is_equal(1)
	assert_int(el[0].a).is_equal(1)
	assert_int(el[0].b).is_equal(0)
	assert_int(el[0].team).is_equal(1)


func test_player_eliminated_names_the_team_of_a_shooter_that_died_first() -> void:
	var w: SimWorld = K.world(&"pvp_1v1", 1)
	var shooter: int = _dead_shooter(w, 0)
	var _d: Array[SimEvent] = w.drain_events()
	assert_bool(w._combat._sink.destroy(K.structure(w, 1, &"core"), shooter, w.tick())).is_true()
	w.step()
	var el: Array[SimEvent] = K.of_kind(w.drain_events(), SimEvent.Kind.PLAYER_ELIMINATED)
	assert_int(el.size()).is_equal(1)
	assert_int(el[0].b).is_equal(0)


func test_player_eliminated_keeps_minus_one_when_the_killer_is_unknown() -> void:
	var w: SimWorld = K.world(&"pvp_1v1", 1)
	K.kill_core(w, 1)
	w.step()
	var el: Array[SimEvent] = K.of_kind(w.drain_events(), SimEvent.Kind.PLAYER_ELIMINATED)
	assert_int(el.size()).is_equal(1)
	assert_int(el[0].b).is_equal(-1)


func test_the_tie_break_counts_damage_of_a_shooter_that_died_first() -> void:
	var w: SimWorld = K.world(&"pvp_1v1", 1)
	var shooter: int = _dead_shooter(w, 0)
	var victim: int = K.structure(w, 1, &"refinery")
	assert_bool(w._combat._sink.damage(victim, 25.0, shooter, w.tick())).is_true()
	assert_float(w.judge().structure_damage(0)).is_equal(25.0)
	assert_float(w.judge().structure_damage(1)).is_equal(0.0)
