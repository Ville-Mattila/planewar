extends GdUnitTestSuite
## GD-20 (02 s12.1 state diagram; sim/match/MODULE.md M1-M9): one test per transition, each run with the `pvp_1v1` and
## `pvp_team` timers of modes.json (1 Hz worlds: a tick is a second). 1v1 worlds have one human per team, team worlds two.

const K: GDScript = preload("res://test/unit/sim/match/match_flow_kit.gd")


func _per_team(mode: StringName) -> int:
	return 1 if mode == &"pvp_1v1" else 2


func _each(check: Callable) -> void:
	for m: String in K.MODES:
		check.call(StringName(m), _per_team(StringName(m)))


func test_the_modes_carry_the_documented_timers() -> void:
	assert_float(K.rules(&"pvp_1v1").core_exposure_s).is_equal(1200.0)
	assert_float(K.rules(&"pvp_1v1").hard_end_s).is_equal(1800.0)
	assert_float(K.rules(&"pvp_team").core_exposure_s).is_equal(1800.0)
	assert_float(K.rules(&"pvp_team").hard_end_s).is_equal(2400.0)


# --- Playing -> Exposure ------------------------------------------------------------------------------------------------

func test_playing_becomes_exposure_at_the_mode_timer() -> void:
	_each(_test_playing_becomes_exposure_at_the_mode_timer)


func _test_playing_becomes_exposure_at_the_mode_timer(mode: StringName, per_team: int) -> void:
	var w: SimWorld = K.world(mode, per_team)
	var at: int = int(K.rules(mode).core_exposure_s)
	var before: Array[SimEvent] = K.run_to(w, at - 1)
	assert_int(K.of_kind(before, SimEvent.Kind.CORE_EXPOSURE).size()).is_equal(0)
	assert_int(w.view().match_phase()).is_equal(MatchRules.Phase.PLAYING)
	assert_int(w.view().team_state(0).flags & TeamStateView.CORE_EXPOSURE).is_equal(0)
	var on: Array[SimEvent] = K.run_to(w, at)
	assert_int(K.of_kind(on, SimEvent.Kind.CORE_EXPOSURE).size()).is_equal(1)
	assert_int(w.view().match_phase()).is_equal(MatchRules.Phase.EXPOSURE)
	assert_int(w.view().team_state(0).flags & TeamStateView.CORE_EXPOSURE).is_equal(TeamStateView.CORE_EXPOSURE)
	assert_int(K.of_kind(K.run_to(w, at + 5), SimEvent.Kind.CORE_EXPOSURE).size()).is_equal(0)   # once


func test_the_core_shield_is_up_until_core_shield_until_s() -> void:
	_each(_shield_case)


func _shield_case(mode: StringName, per_team: int) -> void:
	var w: SimWorld = K.world(mode, per_team)
	var until: int = int(WorldTestKit.content().match_rules.core_shield_until_s)
	var early: Array[SimEvent] = K.run_to(w, until - 1)
	assert_int(w.view().team_state(0).flags & TeamStateView.CORE_SHIELD_UP).is_equal(TeamStateView.CORE_SHIELD_UP)
	var downs: int = 0
	for e: SimEvent in early:
		downs += 1 if e.kind == SimEvent.Kind.ALERT and e.a == AlertKind.Kind.CORE_SHIELD_DOWN else 0
	assert_int(downs).is_equal(0)
	var late: Array[SimEvent] = K.run_to(w, until)
	assert_int(w.view().team_state(0).flags & TeamStateView.CORE_SHIELD_UP).is_equal(0)
	for e: SimEvent in late:
		downs += 1 if e.kind == SimEvent.Kind.ALERT and e.a == AlertKind.Kind.CORE_SHIELD_DOWN else 0
	assert_int(downs).is_greater(0)


# --- Playing / Exposure -> Ended: a team has no Core ----------------------------------------------------------------------

func _core_loss(mode: StringName, per_team: int, at: int) -> void:
	var w: SimWorld = K.world(mode, per_team)
	var unit: int = WorldTestKit.spawn(w, &"dart", per_team, 1, WorldTestKit.at(400.0, -900.0))
	assert_int(w.apply_command(CommandPayload.simple(per_team, Command.Kind.POSSESS, unit)).code).is_equal(CommandResult.Code.ACCEPTED)
	var _pre: Array[SimEvent] = K.run_to(w, at - 1)
	assert_int(w.view().player_state(per_team).possessed).is_equal(unit)
	for p: int in per_team:                                       # the whole of team 1's Cores
		K.kill_core(w, per_team + p)
	var ev: Array[SimEvent] = K.run_to(w, at)
	var ends: Array[SimEvent] = K.of_kind(ev, SimEvent.Kind.MATCH_END)
	assert_int(ends.size()).is_equal(1)
	assert_int(ends[0].a).is_equal(0)                                # winner: team 0
	assert_int(ends[0].extra[0]).is_equal(MatchJudge.EndReason.CORES_DESTROYED)
	assert_int(K.of_kind(ev, SimEvent.Kind.PLAYER_ELIMINATED).size()).is_equal(per_team)
	assert_int(w.view().match_phase()).is_equal(MatchRules.Phase.ENDED)
	assert_int(w.match_result().winner_team).is_equal(0)
	assert_int(w.judge().winner()).is_equal(0)
	assert_bool(w.view().team_state(1).eliminated).is_true()          # TeamStateView.eliminated: the defeated team
	assert_bool(w.view().team_state(0).eliminated).is_false()
	assert_int(w.view().player_state(per_team).possessed).is_equal(0)   # C16: the team's pilots are released
	var released: Array[SimEvent] = K.of_kind(ev, SimEvent.Kind.RELEASED)
	assert_bool(released.any(func(e: SimEvent) -> bool: return e.a == unit)).is_true()
	assert_int(K.of_kind(K.run_to(w, at + 3), SimEvent.Kind.MATCH_END).size()).is_equal(0)   # M7: once


func test_core_loss_ends_a_playing_match() -> void:
	for m: String in K.MODES:
		_core_loss(StringName(m), _per_team(StringName(m)), 40)


func test_core_loss_ends_an_exposure_match() -> void:
	for m: String in K.MODES:
		_core_loss(StringName(m), _per_team(StringName(m)), int(K.rules(StringName(m)).core_exposure_s) + 20)


func test_a_dead_team_is_a_spectator_and_commands_after_the_end_are_refused_by_phase() -> void:
	var w: SimWorld = K.world(&"pvp_1v1", 1)
	K.kill_core(w, 1)
	var _ev: Array[SimEvent] = K.run_to(w, 5)
	assert_int(K.surrender(w, 0).code).is_equal(CommandResult.Code.REJECTED_PHASE)


# --- Playing / Exposure -> Ended: surrender -------------------------------------------------------------------------------

func _surrender_after(mode: StringName, per_team: int, min_s: int) -> void:
	var w: SimWorld = K.world(mode, per_team)
	var _a: Array[SimEvent] = K.run_to(w, min_s - 2)
	for p: int in per_team:                                          # would apply at tick min_s - 1: refused at intake (04 V-TEAM)
		assert_int(K.surrender(w, per_team + p).code).is_equal(CommandResult.Code.REJECTED_PHASE)
	var early: Array[SimEvent] = K.run_to(w, min_s - 1)
	assert_int(K.of_kind(early, SimEvent.Kind.MATCH_END).size()).is_equal(0)
	assert_int(K.surrender(w, per_team).code).is_equal(CommandResult.Code.ACCEPTED)   # one of the team
	var one: Array[SimEvent] = K.run_to(w, min_s)
	if per_team == 2:
		assert_int(K.of_kind(one, SimEvent.Kind.MATCH_END).size()).is_equal(0)    # unanimity: the other has not voted
		assert_int(K.surrender(w, per_team + 1).code).is_equal(CommandResult.Code.ACCEPTED)
		one = K.run_to(w, min_s + 1)
	var ends: Array[SimEvent] = K.of_kind(one, SimEvent.Kind.MATCH_END)
	assert_int(ends.size()).is_equal(1)
	assert_int(ends[0].a).is_equal(0)
	assert_int(ends[0].extra[0]).is_equal(MatchJudge.EndReason.SURRENDER)
	assert_int(w.view().match_phase()).is_equal(MatchRules.Phase.ENDED)


# The voters are the connected human members of the team (02 s12.1): an eliminated teammate still votes, a disconnected one
# is refused and not waited for, a bot is refused.
func test_an_eliminated_teammate_is_still_a_voter() -> void:
	var w: SimWorld = K.world(&"pvp_team", 2)
	K.kill_core(w, 2)                                                 # slot 2: eliminated, team 1 still has slot 3's Core
	var min_s: int = int(WorldTestKit.content().match_rules.surrender_min_s)
	var _a: Array[SimEvent] = K.run_to(w, min_s)
	assert_bool(w.view().player_state(2).eliminated).is_true()
	assert_int(K.surrender(w, 3).code).is_equal(CommandResult.Code.ACCEPTED)
	assert_int(K.of_kind(K.run_to(w, min_s + 1), SimEvent.Kind.MATCH_END).size()).is_equal(0)   # slot 2 has not voted
	assert_int(K.surrender(w, 2).code).is_equal(CommandResult.Code.ACCEPTED)
	assert_int(K.of_kind(K.run_to(w, min_s + 2), SimEvent.Kind.MATCH_END).size()).is_equal(1)


func test_a_disconnected_teammate_is_refused_and_not_waited_for() -> void:
	var w: SimWorld = K.world(&"pvp_team", 2)
	var min_s: int = int(WorldTestKit.content().match_rules.surrender_min_s)
	w.remove_player(3)
	var _a: Array[SimEvent] = K.run_to(w, min_s)
	assert_int(K.surrender(w, 3).code).is_equal(CommandResult.Code.REJECTED_NO_RIGHTS)
	assert_int(K.surrender(w, 2).code).is_equal(CommandResult.Code.ACCEPTED)
	assert_int(K.of_kind(K.run_to(w, min_s + 1), SimEvent.Kind.MATCH_END).size()).is_equal(1)


func test_surrender_while_playing_needs_the_minimum_clock_and_every_human() -> void:
	var c: MatchRulesDef = WorldTestKit.content().match_rules
	_surrender_after(&"pvp_1v1", 1, int(c.surrender_min_s_1v1))      # 1v1: from 3:00
	_surrender_after(&"pvp_team", 2, int(c.surrender_min_s))         # team: from 10:00


func test_surrender_while_in_exposure() -> void:
	for m: String in K.MODES:
		var mode: StringName = StringName(m)
		var per_team: int = _per_team(mode)
		var w: SimWorld = K.world(mode, per_team)
		var _a: Array[SimEvent] = K.run_to(w, int(K.rules(mode).core_exposure_s) + 10)
		assert_int(w.view().match_phase()).is_equal(MatchRules.Phase.EXPOSURE)
		for p: int in per_team:
			assert_int(K.surrender(w, per_team + p).code).is_equal(CommandResult.Code.ACCEPTED)
		var ends: Array[SimEvent] = K.of_kind(K.run_to(w, w.tick() + 1), SimEvent.Kind.MATCH_END)
		assert_int(ends.size()).is_equal(1)
		assert_int(ends[0].extra[0]).is_equal(MatchJudge.EndReason.SURRENDER)


# --- Exposure -> Ended: hard end -------------------------------------------------------------------------------------------

func test_hard_end_goes_to_the_higher_structure_value() -> void:
	_each(_test_hard_end_goes_to_the_higher_structure_value)


func _test_hard_end_goes_to_the_higher_structure_value(mode: StringName, per_team: int) -> void:
	var w: SimWorld = K.world(mode, per_team)
	var hard: int = int(K.rules(mode).hard_end_s)
	var refinery: int = K.structure(w, 0, &"refinery")
	var _a: Array[SimEvent] = K.run_to(w, hard - 2)
	var _r: CommandResult = w.apply_command(CommandPayload.debug_set(0, w.store().id_of(refinery), CommandPayload.SET_HP, 10.0))   # team 0 is bombed late (self-repair would heal it)
	var _early: Array[SimEvent] = K.run_to(w, hard - 1)
	assert_int(w.view().match_phase()).is_equal(MatchRules.Phase.EXPOSURE)
	assert_float(w.judge().structure_value(1)).is_greater(w.judge().structure_value(0))
	var ends: Array[SimEvent] = K.of_kind(K.run_to(w, hard), SimEvent.Kind.MATCH_END)
	assert_int(ends.size()).is_equal(1)
	assert_int(ends[0].tick).is_equal(hard)
	assert_int(ends[0].a).is_equal(1)
	assert_int(ends[0].extra[0]).is_equal(MatchJudge.EndReason.HARD_END_VALUE)
	assert_int(w.view().match_phase()).is_equal(MatchRules.Phase.ENDED)


func test_hard_end_tie_goes_to_structure_damage_then_draws() -> void:
	_each(_test_hard_end_tie_goes_to_structure_damage_then_draws)


func _test_hard_end_tie_goes_to_structure_damage_then_draws(mode: StringName, per_team: int) -> void:
	var hard: int = int(K.rules(mode).hard_end_s)
	var w: SimWorld = K.world(mode, per_team)                  # mirrored bases: equal value
	assert_float(w.judge().structure_value(0)).is_equal(w.judge().structure_value(1))
	w.judge().note_damage(1, 40.0)
	w.judge().note_damage(0, 90.0)
	var ends: Array[SimEvent] = K.of_kind(K.run_to(w, hard), SimEvent.Kind.MATCH_END)
	assert_int(ends[0].a).is_equal(0)                            # more damage dealt to enemy structures
	var d: SimWorld = K.world(mode, per_team)                  # no damage either side: draw
	var drawn: Array[SimEvent] = K.of_kind(K.run_to(d, hard), SimEvent.Kind.MATCH_END)
	assert_int(drawn[0].a).is_equal(-1)
	assert_int(d.judge().winner()).is_equal(-1)
	assert_int(d.judge().end_reason()).is_equal(MatchJudge.EndReason.HARD_END_VALUE)


# --- Commander elimination and the self-destruct ----------------------------------------------------------------------------

func test_a_lost_core_eliminates_the_commander_and_the_structures_self_destruct() -> void:
	for m: String in K.MODES:
		var mode: StringName = StringName(m)
		var w: SimWorld = K.world(mode, 2)                         # players 0 and 1 share team 0
		var unit: int = WorldTestKit.spawn(w, &"harvester", 1, 0, WorldTestKit.at(0.0, 700.0))
		K.kill_core(w, 1)
		var ev: Array[SimEvent] = K.run_to(w, w.tick() + 1)
		var t0: int = w.tick()
		var elim: Array[SimEvent] = K.of_kind(ev, SimEvent.Kind.PLAYER_ELIMINATED)
		assert_int(elim.size()).is_equal(1)
		assert_int(elim[0].a).is_equal(1)
		assert_int(K.of_kind(ev, SimEvent.Kind.MATCH_END).size()).is_equal(0)        # the team still has a Core
		assert_bool(w.view().player_state(1).eliminated).is_true()
		assert_bool(w.view().player_state(1).commander_rights).is_false()
		assert_bool(w.view().player_state(0).commander_rights).is_true()
		var secs: int = int(WorldTestKit.content().match_rules.eliminated_selfdestruct_s)
		assert_int(w.judge().selfdestruct_tick(1)).is_equal(t0 + secs)
		var refinery: int = K.structure(w, 1, &"refinery")
		var rid: int = w.store().id_of(refinery)
		var _wait: Array[SimEvent] = K.run_to(w, t0 + secs - 1)
		assert_bool(w.view().alive(rid)).is_true()                                    # 59 s: still standing
		var boom: Array[SimEvent] = K.run_to(w, t0 + secs + 1)
		assert_bool(w.view().alive(rid)).is_false()
		var causes: PackedInt32Array = PackedInt32Array()
		for e: SimEvent in K.of_kind(boom, SimEvent.Kind.DEATH):
			if e.a == rid:
				causes.append(e.extra[0])
		assert_array(Array(causes)).is_equal([SimEvent.DeathCause.SELF_DESTRUCT])
		assert_int(K.of_kind(boom, SimEvent.Kind.WRECK_SPAWNED).size()).is_greater(0)  # the normal wrecks (GD-19)
		assert_bool(w.view().alive(unit)).is_true()                                   # units stay with their owner
		assert_int(w.view().owner(unit)).is_equal(1)
		assert_bool(w.view().alive(w.store().id_of(K.structure(w, 0, &"refinery")))).is_true()   # a teammate's are untouched


# --- DEATH causes (R0 B.20 A-106) ------------------------------------------------------------------------------------------

func test_a_hit_that_empties_the_hull_reports_cause_killed() -> void:
	var w: SimWorld = CombatTestKit.world()
	var tgt: int = CombatTestKit.spawn(w, &"scout", 0, 0, WorldTestKit.at(500.0))
	var _s: int = CombatTestKit.shot(w, &"rail_slug", &"rail_gun", WorldTestKit.at(500.0), 1, 1, 9)
	w.step()
	var deaths: Array[SimEvent] = K.of_kind(w.drain_events(), SimEvent.Kind.DEATH)
	assert_int(deaths.size()).is_equal(1)
	assert_int(deaths[0].a).is_equal(tgt)
	assert_int(deaths[0].extra[0]).is_equal(SimEvent.DeathCause.KILLED)


# A real hit goes Combat -> DamageSink -> the judge: the team that dealt it wins the tie at the hard end.
func test_a_real_hit_on_an_enemy_structure_feeds_the_tie_break() -> void:
	var w: SimWorld = K.world(&"pvp_1v1", 1)
	var shooter: int = WorldTestKit.spawn(w, &"dart", 0, 0, WorldTestKit.at(300.0, 900.0))
	var victim: int = w.store().id_of(K.structure(w, 1, &"refinery"))
	assert_float(w.judge().structure_damage(0)).is_equal(0.0)
	var sink: DamageSink = w._combat._sink
	assert_bool(sink.damage(EntityId.slot(victim), 25.0, shooter, w.tick())).is_true()
	assert_float(w.judge().structure_damage(0)).is_equal(25.0)
	assert_float(w.judge().structure_damage(1)).is_equal(0.0)
	assert_bool(sink.damage(EntityId.slot(shooter), 5.0, victim, w.tick())).is_true()    # a hit on a ship is not structure damage
	assert_float(w.judge().structure_damage(1)).is_equal(0.0)
