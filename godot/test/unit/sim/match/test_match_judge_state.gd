extends GdUnitTestSuite
## GD-20 (sim/match/MODULE.md): the structure value formula of 02 s12.1, the enum ordinals, the surrender guard for bots,
## and the S4 round trip of the judge state (the elimination deadline and the votes ride in `MatchState`, format 17).

const K: GDScript = preload("res://test/unit/sim/match/match_flow_kit.gd")


func test_death_cause_and_end_reason_ordinals_are_frozen() -> void:
	assert_int(SimEvent.DeathCause.DEBUG).is_equal(0)
	assert_int(SimEvent.DeathCause.EXPIRED).is_equal(1)
	assert_int(SimEvent.DeathCause.KILLED).is_equal(2)
	assert_int(SimEvent.DeathCause.SELF_DESTRUCT).is_equal(3)
	assert_int(MatchJudge.EndReason.CORES_DESTROYED).is_equal(0)
	assert_int(MatchJudge.EndReason.HARD_END_VALUE).is_equal(1)
	assert_int(MatchJudge.EndReason.SURRENDER).is_equal(2)


func test_structure_value_is_cost_times_hp01_and_the_core_counts_core_value() -> void:
	var w: SimWorld = K.world(&"pvp_1v1", 1)
	var c: ContentSet = WorldTestKit.content()
	var ref: StructureDef = c.structures[WorldTestKit.def_id(&"refinery") - DefRanges.STRUCTURE_BASE]
	var cost: float = float(ref.cost_ore + ref.cost_ice)
	assert_float(w.judge().structure_value(0)).is_equal_approx(float(c.match_rules.core_value) + cost, 0.01)
	var core: int = w.store().id_of(K.structure(w, 0, &"core"))
	var _r: CommandResult = w.apply_command(CommandPayload.debug_set(0, core, CommandPayload.SET_HP, w.view().hp01(core) * 1500.0))
	w.step()
	var expect: float = float(c.match_rules.core_value) * w.view().hp01(core) + cost
	assert_float(w.view().hp01(core)).is_equal_approx(0.5, 0.001)
	assert_float(w.judge().structure_value(0)).is_equal_approx(expect, 0.01)
	assert_float(w.judge().structure_value(3)).is_equal(0.0)          # an empty team


func test_a_bot_cannot_surrender() -> void:
	var w: SimWorld = K.world(&"pvp_team", 2)
	w._players.kind[3] = PlayerTable.KIND_BOT                          # slot 3 is a bot on team 1
	var _a: Array[SimEvent] = K.run_to(w, int(WorldTestKit.content().match_rules.surrender_min_s))
	assert_int(K.surrender(w, 3).code).is_equal(CommandResult.Code.REJECTED_NO_RIGHTS)


func test_the_elimination_deadline_survives_the_save() -> void:
	var w: SimWorld = K.world(&"pvp_team", 2)
	K.kill_core(w, 1)
	var _a: Array[SimEvent] = K.run_to(w, w.tick() + 10)
	var due: int = w.judge().selfdestruct_tick(1)
	assert_int(due).is_greater(w.tick())
	var bytes: PackedByteArray = w.serialize()
	var r: SimWorld = SimWorld.deserialize(bytes, WorldTestKit.content(), null)
	assert_object(r).is_not_null()
	assert_int(r.judge().selfdestruct_tick(1)).is_equal(due)
	var rid: int = r.store().id_of(K.structure(r, 1, &"refinery"))
	var _b: Array[SimEvent] = K.run_to(r, due - 1)
	assert_bool(r.view().alive(rid)).is_true()
	var boom: Array[SimEvent] = K.run_to(r, due + 1)
	assert_bool(r.view().alive(rid)).is_false()
	var causes: Array[int] = []
	for e: SimEvent in K.of_kind(boom, SimEvent.Kind.DEATH):
		causes.append(e.extra[0])
	assert_array(causes).contains([SimEvent.DeathCause.SELF_DESTRUCT])
	var _c: Array[SimEvent] = K.run_to(w, due + 1)                   # the original goes the same way
	assert_bool(w.serialize() == r.serialize()).is_true()


func test_a_surrender_vote_survives_the_save() -> void:
	var w: SimWorld = K.world(&"pvp_team", 2)
	var min_s: int = int(WorldTestKit.content().match_rules.surrender_min_s)
	var _a: Array[SimEvent] = K.run_to(w, min_s)
	assert_int(K.surrender(w, 2).code).is_equal(CommandResult.Code.ACCEPTED)
	var _b: Array[SimEvent] = K.run_to(w, min_s + 1)
	assert_bool(w.view().match_phase() == MatchRules.Phase.ENDED).is_false()
	var r: SimWorld = SimWorld.deserialize(w.serialize(), WorldTestKit.content(), null)
	assert_int(K.surrender(r, 3).code).is_equal(CommandResult.Code.ACCEPTED)
	var ends: Array[SimEvent] = K.of_kind(K.run_to(r, min_s + 2), SimEvent.Kind.MATCH_END)
	assert_int(ends.size()).is_equal(1)
	assert_int(ends[0].extra[0]).is_equal(MatchJudge.EndReason.SURRENDER)


func test_the_format_counts_the_judge_state() -> void:
	assert_int(SimSerialize.FORMAT).is_greater_equal(17)
