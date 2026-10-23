extends GdUnitTestSuite
## AI-11: EscortPilot (05 s3.1 ESCORT, s5.6): slot assignment, LOST rules, the FORM / ENGAGE machine incl. the SL-2 FOCUS and
## BREAK modes, act, and the new AiState fields' S4 round trip. Real SimWorld (flat datum), no driver: the tests call
## `think` / `act` themselves with an AiState they register by hand.

const ALT: float = 300.0
const THREAT_FAR_M: float = 600.0


class Rig extends RefCounted:
	var w: SimWorld
	var st: AiState = AiState.new()
	var pilot: EscortPilot = FormationKit.pilot(&"dart")
	var bomber: int = 0
	var darts: PackedInt32Array = PackedInt32Array()

	func _init(n_darts: int, behind_m: float = 80.0) -> void:
		w = WorldTestKit.world(21)
		var vb: Vector3 = Vector3(0, 70, 0)
		bomber = WorldTestKit.spawn(w, &"bomber", 0, 0, WorldTestKit.at(ALT, 0.0), vb)
		for k: int in n_darts:
			var id: int = WorldTestKit.spawn(w, &"dart", 0, 0, WorldTestKit.at(ALT, -behind_m - 20.0 * k), vb)
			var _p: bool = darts.push_back(id)
			st.cls[EntityId.slot(id)] = 0
			st.eid[EntityId.slot(id)] = id
		st.cls[EntityId.slot(bomber)] = 1

	func order(id: int, slot: int = -1, mode: int = 0, focus: int = 0) -> void:
		FormationKit.escort_order(w, PackedInt32Array([id]), bomber, slot, mode, focus)

	func think(i: int, threat: int = 0, utility: float = 0.0) -> EscortPilot.Outcome:
		return pilot.think(darts[i], w.view(), st, w.tick(), threat, utility)

	func enemy(east: float) -> int:
		var id: int = WorldTestKit.spawn(w, &"dart", 1, 1, WorldTestKit.at(ALT, east), Vector3(0, 60, 0))
		for _k: int in 10:   # vision refreshes on its own cadence
			w.step()
		var _e: Array[SimEvent] = w.drain_events()
		return id

	func slot_of(i: int) -> int:
		return st.form_slot[EntityId.slot(darts[i])]

	func state_of(i: int) -> int:
		return st.form_state[EntityId.slot(darts[i])]


func test_escorts_take_distinct_class_slots_lowest_first() -> void:
	var r: Rig = Rig.new(3)
	for i: int in 3:
		r.order(r.darts[i])
	for i: int in 3:
		assert_int(r.think(i)).is_equal(EscortPilot.Outcome.FORMING)
	assert_int(r.slot_of(0)).is_equal(0)
	assert_int(r.slot_of(1)).is_equal(1)
	assert_int(r.slot_of(2)).is_equal(2)
	assert_int(r.st.aux_id[EntityId.slot(r.darts[1])]).is_equal(r.bomber)


func test_slot_is_kept_across_thinks_and_freed_by_release() -> void:
	var r: Rig = Rig.new(2)
	r.order(r.darts[0])
	r.order(r.darts[1])
	var _a: EscortPilot.Outcome = r.think(0)
	var _b: EscortPilot.Outcome = r.think(1)
	var _c: EscortPilot.Outcome = r.think(0)
	assert_int(r.slot_of(0)).is_equal(0)
	r.pilot.release(r.darts[0], r.st)
	assert_int(r.slot_of(0)).is_equal(AiState.NO_SLOT)
	assert_int(r.st.aux_id[EntityId.slot(r.darts[0])]).is_equal(0)


func test_guidance_velocity_points_at_the_slot_with_the_leader_velocity() -> void:
	var r: Rig = Rig.new(1)
	r.order(r.darts[0])
	var _o: EscortPilot.Outcome = r.think(0)
	var s: int = EntityId.slot(r.darts[0])
	var v: Vector3 = r.st.guidance_vel[s]
	var to_slot: Vector3 = r.st.guidance_point[s] - r.w.view().pos(r.darts[0])
	assert_float(v.y).is_greater(70.0)               # 50 m behind the slot: faster than the leader
	assert_float(v.dot(to_slot)).is_greater(0.0)
	assert_float(v.length()).is_less_equal(FormationKit.ship(&"dart").v_cruise * 1.1 + 0.01 + 40.0)   # + separation


func test_no_escort_order_or_dead_or_docked_escortee_is_lost() -> void:
	var r: Rig = Rig.new(1)
	assert_int(r.think(0)).is_equal(EscortPilot.Outcome.LOST)         # no order yet
	r.order(r.darts[0])
	assert_int(r.think(0)).is_equal(EscortPilot.Outcome.FORMING)
	var dead: Rig = Rig.new(1)
	dead.order(dead.darts[0])
	assert_int(dead.think(0)).is_equal(EscortPilot.Outcome.FORMING)
	assert_int(dead.w.apply_command(CommandPayload.debug_set(0, dead.bomber, CommandPayload.SET_HP, 0.0)).code).is_equal(CommandResult.Code.ACCEPTED)
	dead.w.step()
	var _ev: Array[SimEvent] = dead.w.drain_events()
	assert_bool(dead.w.view().alive(dead.bomber)).is_false()
	assert_int(dead.think(0)).is_equal(EscortPilot.Outcome.LOST)
	assert_int(dead.slot_of(0)).is_equal(AiState.NO_SLOT)


func test_break_needs_utility_distance_and_a_slot_that_may_break() -> void:
	var r: Rig = Rig.new(2)
	r.order(r.darts[0])
	r.order(r.darts[1])
	var _a: EscortPilot.Outcome = r.think(0)
	var _b: EscortPilot.Outcome = r.think(1)
	var foe: int = r.enemy(THREAT_FAR_M)
	r.w.step()
	var prm: FormationParams = r.pilot.prm
	# utility at or below 0.5: nobody breaks
	assert_int(r.think(1, foe, prm.break_utility)).is_equal(EscortPilot.Outcome.FORMING)
	# slot 0 stays (only half the escorts may break, the lower slots stay)
	assert_int(r.think(0, foe, 0.9)).is_equal(EscortPilot.Outcome.FORMING)
	# slot 1 breaks and has the threat as its target
	assert_int(r.think(1, foe, 0.9)).is_equal(EscortPilot.Outcome.ENGAGING)
	assert_int(r.st.target[EntityId.slot(r.darts[1])]).is_equal(foe)
	assert_int(r.state_of(1)).is_equal(EscortPilot.ENGAGE)
	# the threat is gone: back in formation, target cleared
	assert_int(r.think(1, 0, 0.0)).is_equal(EscortPilot.Outcome.FORMING)
	assert_int(r.state_of(1)).is_equal(EscortPilot.FORM)
	assert_int(r.st.target[EntityId.slot(r.darts[1])]).is_equal(0)


func test_threat_beyond_the_engage_radius_does_not_break_formation() -> void:
	var r: Rig = Rig.new(1)
	r.order(r.darts[0])
	var _a: EscortPilot.Outcome = r.think(0)
	var foe: int = r.enemy(r.pilot.prm.engage_radius_m + 200.0)
	r.w.step()
	assert_int(r.think(0, foe, 0.9)).is_equal(EscortPilot.Outcome.FORMING)


func test_engaging_escort_rejoins_beyond_the_rejoin_radius() -> void:
	var r: Rig = Rig.new(1, 1700.0)    # the Dart starts 1,700 m behind the escortee
	r.order(r.darts[0])
	var _a: EscortPilot.Outcome = r.think(0)
	var foe: int = r.enemy(THREAT_FAR_M)
	r.w.step()
	r.st.form_state[EntityId.slot(r.darts[0])] = EscortPilot.ENGAGE
	r.st.timer[EntityId.slot(r.darts[0])] = float(r.w.tick())
	assert_int(r.think(0, foe, 0.9)).is_equal(EscortPilot.Outcome.FORMING)   # past 1,500 m: rejoin
	assert_int(r.state_of(0)).is_equal(EscortPilot.FORM)
	assert_int(r.st.target[EntityId.slot(r.darts[0])]).is_equal(0)


func test_focus_engages_the_focus_target_then_returns_to_formation_after_the_timeout() -> void:
	var r: Rig = Rig.new(1)
	var foe: int = r.enemy(THREAT_FAR_M)
	r.w.step()
	r.order(r.darts[0], -1, OrderSpec.EscortMode.FOCUS, foe)
	var prm: FormationParams = r.pilot.prm
	var t0: int = r.w.tick()
	assert_int(r.pilot.think(r.darts[0], r.w.view(), r.st, t0)).is_equal(EscortPilot.Outcome.ENGAGING)
	assert_int(r.st.target[EntityId.slot(r.darts[0])]).is_equal(foe)
	var hz: int = FormationKit.content().rules.tick_hz
	var just_before: int = t0 + roundi(prm.focus_timeout_s * float(hz)) - 1
	assert_int(r.pilot.think(r.darts[0], r.w.view(), r.st, just_before)).is_equal(EscortPilot.Outcome.ENGAGING)
	var after: int = t0 + roundi(prm.focus_timeout_s * float(hz))
	assert_int(r.pilot.think(r.darts[0], r.w.view(), r.st, after)).is_equal(EscortPilot.Outcome.FORMING)
	assert_int(r.state_of(0)).is_equal(EscortPilot.SPENT)
	# the FOCUS order is still standing: it does not start a second engagement
	assert_int(r.pilot.think(r.darts[0], r.w.view(), r.st, after + 10)).is_equal(EscortPilot.Outcome.FORMING)


func test_break_mode_engages_a_threat_without_the_utility_gate() -> void:
	var r: Rig = Rig.new(1)
	r.order(r.darts[0], -1, OrderSpec.EscortMode.BREAK)
	var foe: int = r.enemy(THREAT_FAR_M)
	r.w.step()
	assert_int(r.think(0, foe, 0.0)).is_equal(EscortPilot.Outcome.ENGAGING)
	var hz: int = FormationKit.content().rules.tick_hz
	var after: int = r.w.tick() + roundi(r.pilot.prm.break_s * float(hz)) + 1
	assert_int(r.pilot.think(r.darts[0], r.w.view(), r.st, after, foe, 0.0)).is_equal(EscortPilot.Outcome.FORMING)


func test_wing_slot_uses_the_wing_table_and_keeps_no_class_slot() -> void:
	var r: Rig = Rig.new(1)
	r.order(r.darts[0], 1)
	assert_int(r.think(0)).is_equal(EscortPilot.Outcome.FORMING)
	assert_int(r.slot_of(0)).is_equal(AiState.NO_SLOT)
	var want: Vector3 = Formation.slot_world(r.w.view().pos(r.bomber), r.w.view().vel(r.bomber), r.w.view().basis(r.bomber), 1, true, r.pilot.prm)
	assert_vector(r.st.guidance_point[EntityId.slot(r.darts[0])]).is_equal_approx(want, Vector3(0.01, 0.01, 0.01))


func test_act_tracks_the_guidance_velocity_and_is_silent_while_engaging() -> void:
	var r: Rig = Rig.new(1)
	r.order(r.darts[0])
	var _o: EscortPilot.Outcome = r.think(0)
	var inp: PilotInput = PilotInput.new()
	assert_bool(r.pilot.act(r.darts[0], r.w.view(), r.st, inp)).is_true()
	assert_float(inp.thrust).is_greater(0.0)
	r.st.form_state[EntityId.slot(r.darts[0])] = EscortPilot.ENGAGE
	assert_bool(r.pilot.act(r.darts[0], r.w.view(), r.st, inp)).is_false()
	var idle: Rig = Rig.new(1)
	assert_bool(idle.pilot.act(idle.darts[0], idle.w.view(), idle.st, inp)).is_false()   # never thought: no escortee


func test_escort_state_round_trips_through_the_s4_bytes() -> void:
	var r: Rig = Rig.new(2)
	r.order(r.darts[0])
	r.order(r.darts[1])
	var _a: EscortPilot.Outcome = r.think(0)
	var _b: EscortPilot.Outcome = r.think(1)
	var foe: int = r.enemy(THREAT_FAR_M)
	r.w.step()
	var _c: EscortPilot.Outcome = r.think(1, foe, 0.9)
	var bytes: PackedByteArray = r.st.serialize()
	var copy: AiState = AiState.new()
	assert_bool(copy.deserialize(bytes)).is_true()
	for i: int in 2:
		var s: int = EntityId.slot(r.darts[i])
		assert_int(copy.form_slot[s]).is_equal(r.st.form_slot[s])
		assert_int(copy.form_state[s]).is_equal(r.st.form_state[s])
		assert_int(copy.form_order[s]).is_equal(r.st.form_order[s])
		assert_float(copy.timer[s]).is_equal(r.st.timer[s])
	assert_array(copy.serialize()).is_equal(bytes)


func test_a_dead_escorts_roster_entry_is_reused() -> void:
	var r: Rig = Rig.new(3)
	for i: int in 2:
		r.order(r.darts[i])
		var _o: EscortPilot.Outcome = r.think(i)
	assert_int(r.slot_of(1)).is_equal(1)
	assert_int(r.w.apply_command(CommandPayload.debug_set(0, r.darts[0], CommandPayload.SET_HP, 0.0)).code).is_equal(CommandResult.Code.ACCEPTED)
	r.w.step()
	var _e: Array[SimEvent] = r.w.drain_events()
	r.order(r.darts[2])
	var _o2: EscortPilot.Outcome = r.think(2)
	assert_int(r.slot_of(2)).is_equal(0)   # slot 0 was freed by the death; no spatial query involved


func test_released_escort_frees_its_roster_entry() -> void:
	var r: Rig = Rig.new(2)
	r.order(r.darts[0])
	var _a: EscortPilot.Outcome = r.think(0)
	r.pilot.release(r.darts[0], r.st)
	r.order(r.darts[1])
	var _b: EscortPilot.Outcome = r.think(1)
	assert_int(r.slot_of(1)).is_equal(0)


func test_separation_runs_every_second_think_and_is_held_in_between() -> void:
	var r: Rig = Rig.new(2, 80.0)
	r.order(r.darts[0])
	var s: int = EntityId.slot(r.darts[0])
	var _a: EscortPilot.Outcome = r.think(0)           # refresh
	assert_int(r.st.sep_age[s]).is_equal(1)
	var held: Vector3 = r.st.sep_push[s]
	r.st.sep_push[s] = Vector3(1, 2, 3)                # a marker: the next think must keep it
	var _b: EscortPilot.Outcome = r.think(0)
	assert_vector(r.st.sep_push[s]).is_equal(Vector3(1, 2, 3))
	assert_int(r.st.sep_age[s]).is_equal(0)
	var _c: EscortPilot.Outcome = r.think(0)           # refresh again
	assert_vector(r.st.sep_push[s]).is_equal_approx(held, Vector3(0.001, 0.001, 0.001))


func test_separation_refresh_policy_flags() -> void:
	assert_bool(Separation.needs_refresh(0)).is_true()                                   # held last think (or never ran)
	assert_bool(Separation.needs_refresh(Separation.AGE_FRESH)).is_false()               # refreshed, nobody closing: hold once
	assert_bool(Separation.needs_refresh(Separation.AGE_FRESH | Separation.AGE_CLOSING)).is_true()   # closing pair: refresh again


func test_a_closing_pair_refreshes_on_consecutive_thinks() -> void:
	var r: Rig = Rig.new(1, 80.0)
	# a friendly Dart 150 m behind the escort, 70 m/s faster: closing, predicted miss 0 m within the look-ahead horizon
	var _closer: int = WorldTestKit.spawn(r.w, &"dart", 0, 0, WorldTestKit.at(ALT, -250.0), Vector3(0, 140, 0))
	r.w.step()
	var _e: Array[SimEvent] = r.w.drain_events()
	r.order(r.darts[0])
	var s: int = EntityId.slot(r.darts[0])
	for k: int in 3:
		r.st.sep_push[s] = Vector3(1, 2, 3)            # a marker: every think must overwrite it
		var _o: EscortPilot.Outcome = r.think(0)
		assert_int(r.st.sep_age[s]).override_failure_message("think %d" % k).is_equal(Separation.AGE_FRESH | Separation.AGE_CLOSING)
		assert_bool(r.st.sep_push[s] == Vector3(1, 2, 3)).override_failure_message("think %d held the term" % k).is_false()


func test_six_escorts_overflow_outside_the_roster_and_restore_identically_after_release() -> void:
	var r: Rig = Rig.new(7)
	for i: int in 6:
		r.order(r.darts[i])
		var _o: EscortPilot.Outcome = r.think(i)
	for i: int in 4:
		assert_int(r.slot_of(i)).is_equal(i)
	var o4: int = r.slot_of(4)
	var o5: int = r.slot_of(5)
	assert_int(o4).is_greater_equal(AiState.ROSTER_WIDTH)   # overflow: outside the roster, not stacked on slot 0
	assert_int(o5).is_greater_equal(AiState.ROSTER_WIDTH)
	assert_int(o4).is_not_equal(o5)
	assert_float(r.pilot.slot_error(r.darts[4], r.w.view(), r.st)).is_less(INF)
	var copy: AiState = AiState.new()
	assert_bool(copy.deserialize(r.st.serialize())).is_true()
	assert_array(copy.form_roster).is_equal(r.st.form_roster)
	r.pilot.release(r.darts[0], r.st)                        # the slot-0 holder stops escorting, live and restored
	r.pilot.release(r.darts[0], copy)
	var v: SimView = r.w.view()
	assert_int(r.pilot._group_size(r.bomber, v, copy)).is_equal(r.pilot._group_size(r.bomber, v, r.st))
	assert_int(r.pilot._group_size(r.bomber, v, r.st)).is_equal(3)
	assert_array(copy.form_roster).is_equal(r.st.form_roster)
	assert_array(copy.serialize()).is_equal(r.st.serialize())
	# continue: a 7th escort takes the freed slot 0 in both; every escort thinks (one with a threat) the same in both
	r.order(r.darts[6])
	var foe: int = r.enemy(THREAT_FAR_M)
	r.w.step()
	v = r.w.view()
	for i: int in range(1, 7):
		var a: EscortPilot.Outcome = r.pilot.think(r.darts[i], v, r.st, r.w.tick(), foe, 0.9)
		var b: EscortPilot.Outcome = r.pilot.think(r.darts[i], v, copy, r.w.tick(), foe, 0.9)
		assert_int(b).override_failure_message("escort %d" % i).is_equal(a)
	assert_int(r.slot_of(6)).is_equal(0)
	assert_int(copy.form_slot[EntityId.slot(r.darts[6])]).is_equal(0)
	assert_array(copy.form_roster).is_equal(r.st.form_roster)
	assert_array(copy.serialize()).is_equal(r.st.serialize())


func test_previous_format_bytes_are_refused() -> void:
	assert_int(AiState.FORMAT).is_equal(7)   # AI-17: FORMAT 7 (hit record); the bytes of the previous format are refused
	var r: Rig = Rig.new(1)
	r.order(r.darts[0])
	var _o: EscortPilot.Outcome = r.think(0)
	var bytes: PackedByteArray = r.st.serialize()
	bytes[0] = AiState.FORMAT - 1
	var copy: AiState = AiState.new()
	assert_bool(copy.deserialize(bytes)).is_false()
	assert_int(copy.registered_count()).is_equal(0)


func test_roster_is_rebuilt_from_the_s4_bytes() -> void:
	var r: Rig = Rig.new(2)
	r.order(r.darts[0])
	r.order(r.darts[1])
	var _a: EscortPilot.Outcome = r.think(0)
	var _b: EscortPilot.Outcome = r.think(1)
	var copy: AiState = AiState.new()
	assert_bool(copy.deserialize(r.st.serialize())).is_true()
	assert_array(copy.form_roster).is_equal(r.st.form_roster)


func test_slot_error_is_inf_without_an_escort_order() -> void:
	var r: Rig = Rig.new(1)
	assert_float(r.pilot.slot_error(r.darts[0], r.w.view(), r.st)).is_equal(INF)
	r.order(r.darts[0])
	var _o: EscortPilot.Outcome = r.think(0)
	assert_float(r.pilot.slot_error(r.darts[0], r.w.view(), r.st)).is_less(200.0)
