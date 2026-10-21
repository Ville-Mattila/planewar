extends GdUnitTestSuite
## ControlMachine (AI-02; 05 s2.3): one test per transition row C1-C18 through SimWorld.step() in the R0 B.5 order.
## C6r codes, ReleaseReason, hand-over, autopilot resume, determinism and S4: test_control_rules.gd.

const K := SimEvent.Kind
const S := ControlMachine.State
const O := ControlMachine.Overlay
const RR := ControlMachine.ReleaseReason
const F := ControlMachine.OrderFail
const C := CommandResult.Code


func test_c1_auto_order_valid_becomes_ordered_invalid_rejected() -> void:
	var w: SimWorld = ControlTestKit.world()
	var id: int = ControlTestKit.dart(w)
	assert_int(ControlTestKit.state(w, id)).is_equal(S.AUTO)
	assert_int(ControlTestKit.code(w, ControlTestKit.order(0, id, OrderSpec.Kind.HARVEST_HERE))).is_equal(C.REJECTED_INVALID_ORDER)
	var _e: Array[SimEvent] = ControlTestKit.step(w)
	assert_int(ControlTestKit.state(w, id)).is_equal(S.AUTO)
	var ev: Array[SimEvent] = ControlTestKit.run(w, ControlTestKit.order(0, id, OrderSpec.Kind.MOVE))
	assert_int(ControlTestKit.state(w, id)).is_equal(S.ORDERED)
	assert_int(w.view().order_head(id).kind).is_equal(OrderSpec.Kind.MOVE)
	assert_int(w.view().order_issuer(id)).is_equal(0)
	assert_int(ev.size()).is_equal(0)


func test_c2_replace_echoes_overridden_to_a_different_human_within_10_s() -> void:
	var w: SimWorld = ControlTestKit.world()
	var id: int = ControlTestKit.dart(w)
	var _a: Array[SimEvent] = ControlTestKit.run(w, ControlTestKit.order(0, id, OrderSpec.Kind.MOVE))
	var ev: Array[SimEvent] = ControlTestKit.run(w, ControlTestKit.order(ControlTestKit.MATE, id, OrderSpec.Kind.HOLD))
	assert_int(ev.size()).is_equal(1)
	assert_int(ev[0].kind).is_equal(K.ORDER_FAILED)
	assert_int(ev[0].a).is_equal(id)
	assert_int(ev[0].b).is_equal(0)                                   # to the old issuer
	assert_array(Array(ev[0].extra)).is_equal([F.OVERRIDDEN, ControlTestKit.MATE])  # by = new issuer
	assert_int(ControlTestKit.standing(w, id)).is_equal(1)
	assert_int(w.view().order_head(id).kind).is_equal(OrderSpec.Kind.HOLD)
	assert_int(ControlTestKit.run(w, ControlTestKit.order(ControlTestKit.MATE, id, OrderSpec.Kind.MOVE)).size()).is_equal(0)   # same issuer: no echo
	assert_int(ControlTestKit.run(w, ControlTestKit.order(2, id, OrderSpec.Kind.HOLD)).size()).is_equal(1)           # a bot replacing a human
	assert_int(ControlTestKit.run(w, ControlTestKit.order(0, id, OrderSpec.Kind.MOVE)).size()).is_equal(0)           # the old head was a bot's
	var _s: Array[SimEvent] = ControlTestKit.step(w, ControlMachine.ECHO_WINDOW_S * WorldTestKit.content().rules.tick_hz)
	assert_int(ControlTestKit.run(w, ControlTestKit.order(ControlTestKit.MATE, id, OrderSpec.Kind.HOLD)).size()).is_equal(0)     # older than 10 s


func test_c3_queue_appends_until_the_cap() -> void:
	var w: SimWorld = ControlTestKit.world()
	var id: int = ControlTestKit.dart(w)
	var _a: Array[SimEvent] = ControlTestKit.run(w, ControlTestKit.order(0, id, OrderSpec.Kind.MOVE))
	for _i: int in OrderQueue.QUEUE_MAX - 1:
		var ev: Array[SimEvent] = ControlTestKit.run(w, ControlTestKit.order(ControlTestKit.MATE, id, OrderSpec.Kind.HOLD, 0, OrderSpec.FLAG_QUEUE))
		assert_int(ev.size()).is_equal(0)                                # append never echoes
	assert_int(ControlTestKit.standing(w, id)).is_equal(OrderQueue.QUEUE_MAX)
	assert_int(w.view().order_head(id).kind).is_equal(OrderSpec.Kind.MOVE)
	assert_int(ControlTestKit.code(w, ControlTestKit.order(0, id, OrderSpec.Kind.HOLD, 0, OrderSpec.FLAG_QUEUE))).is_equal(C.REJECTED_CAP)
	assert_int(ControlTestKit.state(w, id)).is_equal(S.ORDERED)


func test_c4_head_complete_pops_and_falls_back_to_auto() -> void:
	var w: SimWorld = ControlTestKit.world()
	var id: int = ControlTestKit.dart(w)
	var _a: Array[SimEvent] = ControlTestKit.run(w, ControlTestKit.order(0, id, OrderSpec.Kind.MOVE))
	var _b: Array[SimEvent] = ControlTestKit.run(w, ControlTestKit.order(0, id, OrderSpec.Kind.HOLD, 0, OrderSpec.FLAG_QUEUE))
	var s: int = EntityId.slot(id)
	assert_bool(ControlTestKit.control(w).orders.complete_head(s)).is_true()
	var ev: Array[SimEvent] = w.drain_events()
	assert_int(ev.size()).is_equal(1)
	assert_int(ev[0].kind).is_equal(K.ORDER_DONE)
	assert_float(ev[0].value).is_equal(float(OrderSpec.Kind.MOVE))
	assert_int(ControlTestKit.state(w, id)).is_equal(S.ORDERED)
	assert_bool(ControlTestKit.control(w).orders.complete_head(s)).is_true()
	assert_int(ControlTestKit.state(w, id)).is_equal(S.AUTO)
	assert_bool(ControlTestKit.control(w).orders.complete_head(s)).is_false()


func test_c5_head_impossible_pops_with_reason_and_skips_invalid_heads() -> void:
	var w: SimWorld = ControlTestKit.world()
	var id: int = ControlTestKit.dart(w)
	var foe: int = ControlTestKit.dart(w, 1, 1, 600.0, 400.0)
	var _a: Array[SimEvent] = ControlTestKit.run(w, ControlTestKit.order(0, id, OrderSpec.Kind.RETURN))
	var _b: Array[SimEvent] = ControlTestKit.run(w, ControlTestKit.order(0, id, OrderSpec.Kind.ATTACK, foe, OrderSpec.FLAG_QUEUE))
	var _c: Array[SimEvent] = ControlTestKit.run(w, ControlTestKit.order(0, id, OrderSpec.Kind.HOLD, 0, OrderSpec.FLAG_QUEUE))
	var _d: Array[SimEvent] = ControlTestKit.run(w, CommandPayload.debug_set(0, foe, CommandPayload.SET_KILL, 0.0))
	assert_bool(ControlTestKit.control(w).orders.fail_head(EntityId.slot(id), F.NO_PAD)).is_true()
	var ev: Array[SimEvent] = w.drain_events()
	assert_int(ev.size()).is_equal(2)
	assert_int(ev[0].extra[0]).is_equal(F.NO_PAD)
	assert_int(ev[1].extra[0]).is_equal(F.INVALID_TARGET)          # ATTACK on the dead foe dropped
	assert_int(w.view().order_head(id).kind).is_equal(OrderSpec.Kind.HOLD)
	assert_bool(ControlTestKit.control(w).orders.fail_head(EntityId.slot(id), F.STUCK)).is_true()
	assert_int(ControlTestKit.state(w, id)).is_equal(S.AUTO)


func test_c6_possess_keeps_saved_queue_clears_pending_and_releases_previous_first() -> void:
	var w: SimWorld = ControlTestKit.world()
	var a: int = ControlTestKit.dart(w)
	var b: int = ControlTestKit.dart(w, 0, 0, 500.0, 300.0)
	var _o: Array[SimEvent] = ControlTestKit.run(w, ControlTestKit.order(0, b, OrderSpec.Kind.HOLD))
	var ev: Array[SimEvent] = ControlTestKit.run(w, Command.possess(0, a))
	assert_array(Array(WorldTestKit.kinds(ev))).is_equal([K.POSSESSED])
	assert_int(ev[0].b).is_equal(0)
	assert_int(ControlTestKit.state(w, a)).is_equal(S.POSSESSED)
	assert_int(w.view().possessor(a)).is_equal(0)
	assert_int(w.view().player_state(0).possessed).is_equal(a)
	ev = ControlTestKit.run(w, Command.possess(0, b))
	assert_array(Array(WorldTestKit.kinds(ev))).is_equal([K.RELEASED, K.POSSESSED])
	assert_int(ev[0].a).is_equal(a)
	assert_int(ev[0].extra[0]).is_equal(RR.PLAYER)
	assert_int(ev[1].a).is_equal(b)
	assert_int(ControlTestKit.state(w, a)).is_equal(S.AUTO)
	assert_int(ControlTestKit.standing(w, b)).is_equal(1)                         # saved order kept untouched
	assert_int(ControlTestKit.pending(w, b)).is_equal(0)


func test_c7_order_to_a_possessed_unit_goes_pending_with_an_alert() -> void:
	var w: SimWorld = ControlTestKit.world()
	var id: int = ControlTestKit.dart(w)
	var _o: Array[SimEvent] = ControlTestKit.run(w, ControlTestKit.order(0, id, OrderSpec.Kind.HOLD))
	var _p: Array[SimEvent] = ControlTestKit.run(w, Command.possess(ControlTestKit.MATE, id))
	var ev: Array[SimEvent] = ControlTestKit.run(w, ControlTestKit.order(0, id, OrderSpec.Kind.MOVE))
	assert_int(ev.size()).is_equal(1)
	assert_int(ev[0].kind).is_equal(K.ALERT)
	assert_int(ev[0].a).is_equal(AlertKind.Kind.PENDING_ORDER)
	assert_int(ev[0].b).is_equal(id)
	assert_int(ev[0].extra[0]).is_equal(ControlTestKit.MATE)                      # to the pilot
	assert_int(ControlTestKit.state(w, id)).is_equal(S.POSSESSED)
	assert_int(ControlTestKit.pending(w, id)).is_equal(1)
	assert_int(w.view().order_head(id).kind).is_equal(OrderSpec.Kind.HOLD)


func test_c8_request_possess_records_the_requester_and_alerts_the_pilot() -> void:
	var w: SimWorld = ControlTestKit.world()
	var id: int = ControlTestKit.dart(w)
	var _p: Array[SimEvent] = ControlTestKit.run(w, Command.possess(0, id))
	var ev: Array[SimEvent] = ControlTestKit.run(w, ControlTestKit.request(ControlTestKit.MATE, id))
	assert_array(Array(WorldTestKit.kinds(ev))).is_equal([K.POSSESS_REQUESTED, K.ALERT])
	assert_int(ev[0].a).is_equal(id)
	assert_int(ev[0].b).is_equal(ControlTestKit.MATE)
	assert_int(ev[0].extra[0]).is_equal(0)
	assert_int(ev[1].a).is_equal(AlertKind.Kind.HANDOVER_REQUEST)
	assert_int(ev[1].extra[0]).is_equal(0)
	assert_int(ControlTestKit.control(w).request_from(id)).is_equal(ControlTestKit.MATE)
	assert_int(ControlTestKit.state(w, id)).is_equal(S.POSSESSED)
	assert_int(ControlTestKit.code(w, ControlTestKit.request(2, id))).is_equal(C.REJECTED_NO_RIGHTS)     # live request from another
	assert_int(ControlTestKit.code(w, ControlTestKit.request(ControlTestKit.MATE, id))).is_equal(C.ACCEPTED)        # the same requester refreshes


func test_c9_release_resumes_pending_else_saved_with_safety() -> void:
	var w: SimWorld = ControlTestKit.world()
	var id: int = ControlTestKit.dart(w)
	var _o: Array[SimEvent] = ControlTestKit.run(w, ControlTestKit.order(0, id, OrderSpec.Kind.HOLD))
	var _p: Array[SimEvent] = ControlTestKit.run(w, Command.possess(0, id))
	var _q: Array[SimEvent] = ControlTestKit.run(w, ControlTestKit.order(ControlTestKit.MATE, id, OrderSpec.Kind.MOVE))
	var ev: Array[SimEvent] = ControlTestKit.run(w, Command.release(0))
	assert_array(Array(WorldTestKit.kinds(ev))).is_equal([K.RELEASED])
	assert_int(ev[0].extra[0]).is_equal(RR.PLAYER)
	assert_int(ControlTestKit.state(w, id)).is_equal(S.ORDERED)
	assert_int(w.view().order_head(id).kind).is_equal(OrderSpec.Kind.MOVE)    # pending wins
	assert_int(ControlTestKit.overlay(w, id)).is_equal(O.SAFETY)
	assert_int(w.view().possessor(id)).is_equal(-1)
	var bare: int = ControlTestKit.dart(w, 0, 0, 500.0, 600.0)
	var _r: Array[SimEvent] = ControlTestKit.run(w, Command.possess(0, bare))
	var _s: Array[SimEvent] = ControlTestKit.run(w, Command.release(0))
	assert_int(ControlTestKit.state(w, bare)).is_equal(S.AUTO)
	assert_int(ControlTestKit.overlay(w, bare)).is_equal(O.SAFETY)


func test_c9_release_drops_invalid_orders_with_invalid_on_resume() -> void:
	var w: SimWorld = ControlTestKit.world()
	var id: int = ControlTestKit.dart(w)
	var foe: int = ControlTestKit.dart(w, 1, 1, 600.0, 400.0)
	var _o: Array[SimEvent] = ControlTestKit.run(w, ControlTestKit.order(0, id, OrderSpec.Kind.ATTACK, foe))
	var _q: Array[SimEvent] = ControlTestKit.run(w, ControlTestKit.order(0, id, OrderSpec.Kind.HOLD, 0, OrderSpec.FLAG_QUEUE))
	var _p: Array[SimEvent] = ControlTestKit.run(w, Command.possess(0, id))
	var _r: Array[SimEvent] = ControlTestKit.run(w, ControlTestKit.order(0, id, OrderSpec.Kind.ATTACK, foe))   # pending, about to turn invalid
	var _k: Array[SimEvent] = ControlTestKit.run(w, CommandPayload.debug_set(0, foe, CommandPayload.SET_KILL, 0.0))
	var ev: Array[SimEvent] = ControlTestKit.run(w, Command.release(0))
	assert_array(Array(WorldTestKit.kinds(ev))).is_equal([K.RELEASED, K.ORDER_FAILED, K.ORDER_FAILED])
	assert_int(ev[1].extra[0]).is_equal(F.INVALID_ON_RESUME)          # the pending ATTACK
	assert_int(ev[2].extra[0]).is_equal(F.INVALID_ON_RESUME)          # the saved ATTACK
	assert_int(ControlTestKit.standing(w, id)).is_equal(1)
	assert_int(w.view().order_head(id).kind).is_equal(OrderSpec.Kind.HOLD)
	assert_int(ControlTestKit.state(w, id)).is_equal(S.ORDERED)


func test_c10_handover_swaps_the_pilot_under_link_bridge() -> void:
	var w: SimWorld = ControlTestKit.world()
	var id: int = ControlTestKit.dart(w)
	var _p: Array[SimEvent] = ControlTestKit.run(w, Command.possess(0, id))
	var _r: Array[SimEvent] = ControlTestKit.run(w, ControlTestKit.request(ControlTestKit.MATE, id))
	var ev: Array[SimEvent] = ControlTestKit.run(w, CommandPayload.handover(0, id, ControlTestKit.MATE))
	assert_array(Array(WorldTestKit.kinds(ev))).is_equal([K.RELEASED, K.HANDOVER, K.POSSESSED])
	assert_array(Array(ev[0].extra)).is_equal([RR.HANDOVER, ControlTestKit.MATE])
	assert_int(ev[0].b).is_equal(0)
	assert_int(ev[1].b).is_equal(ControlTestKit.MATE)
	assert_int(ev[2].b).is_equal(ControlTestKit.MATE)
	assert_int(w.view().possessor(id)).is_equal(ControlTestKit.MATE)
	assert_int(ControlTestKit.state(w, id)).is_equal(S.POSSESSED)
	assert_int(ControlTestKit.overlay(w, id)).is_equal(O.LINK_BRIDGE)
	assert_int(w.view().player_state(0).possessed).is_equal(0)
	assert_int(w.view().player_state(ControlTestKit.MATE).possessed).is_equal(id)
	assert_int(ControlTestKit.control(w).request_from(id)).is_equal(-1)


func test_c11_ceiling_releases_to_recover_ceiling() -> void:
	var w: SimWorld = ControlTestKit.world()
	var hard: float = WorldTestKit.content().rules.ceiling_hard_m
	var id: int = ControlTestKit.dart(w, 0, 0, hard - 60.0)
	var _p: Array[SimEvent] = ControlTestKit.run(w, Command.possess(0, id))
	w.store().pos[EntityId.slot(id)] = WorldTestKit.at(hard + 1.0)
	var ev: Array[SimEvent] = ControlTestKit.step(w)
	assert_array(Array(WorldTestKit.kinds(ev))).is_equal([K.RELEASED, K.CEILING_RELEASE])
	assert_int(ev[0].extra[0]).is_equal(RR.CEILING)
	assert_int(ControlTestKit.overlay(w, id)).is_equal(O.RECOVER_CEILING)
	assert_int(ControlTestKit.state(w, id)).is_equal(S.AUTO)


func test_c12_disconnect_releases_with_safety() -> void:
	var w: SimWorld = ControlTestKit.world()
	var id: int = ControlTestKit.dart(w, 1, 1)
	var _p: Array[SimEvent] = ControlTestKit.run(w, Command.possess(1, id))
	w.remove_player(1)
	var ev: Array[SimEvent] = ControlTestKit.step(w)
	assert_array(Array(WorldTestKit.kinds(ev))).is_equal([K.RELEASED])
	assert_int(ev[0].extra[0]).is_equal(RR.DISCONNECT)
	assert_int(ControlTestKit.overlay(w, id)).is_equal(O.SAFETY)
	assert_int(ControlTestKit.state(w, id)).is_equal(S.AUTO)


func test_c13_silent_pilot_decays_10_ticks_then_link_bridge_and_stays_possessed() -> void:
	var w: SimWorld = ControlTestKit.world()
	var id: int = ControlTestKit.dart(w)
	var s: int = EntityId.slot(id)
	var _p: Array[SimEvent] = ControlTestKit.run(w, Command.possess(0, id))
	var all: int = PilotInput.BOOST | PilotInput.BRAKE | PilotInput.FLIP | PilotInput.FIRE1 | PilotInput.FIRE2 | PilotInput.DOCK | PilotInput.RELEASE
	assert_int(ControlTestKit.pilot(w, 0, 0.75, 0.8, all)).is_equal(C.ACCEPTED)
	var _f: Array[SimEvent] = ControlTestKit.step(w)
	var io: InputSlots = ControlTestKit.inputs(w)
	assert_float(io.e_pitch[s]).is_equal(0.8)
	assert_int(io.e_buttons[s]).is_equal(all)
	var expect: float = 0.8
	for k: int in range(1, ControlMachine.DECAY_TICKS + 1):
		var ev: Array[SimEvent] = ControlTestKit.step(w)
		expect *= 0.5
		assert_int(ev.size()).override_failure_message("silent tick %d" % k).is_equal(0)
		assert_float(io.e_pitch[s]).is_equal_approx(expect, 1e-12)
		assert_float(io.e_yaw[s]).is_equal_approx(expect, 1e-12)
		assert_float(io.e_roll[s]).is_equal_approx(-expect, 1e-12)
		assert_float(io.e_thrust[s]).is_equal(0.75)                    # thrust held
		assert_int(io.e_buttons[s]).is_equal(PilotInput.BOOST | PilotInput.BRAKE)   # A-44
		assert_int(ControlTestKit.overlay(w, id)).is_equal(O.NONE)
	var ev11: Array[SimEvent] = ControlTestKit.step(w)
	assert_array(Array(WorldTestKit.kinds(ev11))).is_equal([K.ALERT])
	assert_int(ev11[0].a).is_equal(AlertKind.Kind.LINK_WEAK)
	assert_int(ev11[0].extra[0]).is_equal(0)
	assert_int(ControlTestKit.overlay(w, id)).is_equal(O.LINK_BRIDGE)
	var later: Array[SimEvent] = ControlTestKit.step(w, 60)
	assert_int(later.size()).is_equal(0)                              # LINK_WEAK once; no C12 without a transport timeout
	assert_int(ControlTestKit.state(w, id)).is_equal(S.POSSESSED)
	assert_int(w.view().possessor(id)).is_equal(0)


func test_c14_fresh_input_clears_link_bridge() -> void:
	var w: SimWorld = ControlTestKit.world()
	var id: int = ControlTestKit.dart(w)
	var _p: Array[SimEvent] = ControlTestKit.run(w, Command.possess(0, id))
	var _s: Array[SimEvent] = ControlTestKit.step(w, ControlMachine.DECAY_TICKS + 1)
	assert_int(ControlTestKit.overlay(w, id)).is_equal(O.LINK_BRIDGE)
	assert_int(ControlTestKit.pilot(w, 0, 1.0, 0.25)).is_equal(C.ACCEPTED)
	var ev: Array[SimEvent] = ControlTestKit.step(w)
	assert_int(ev.size()).is_equal(0)
	assert_int(ControlTestKit.overlay(w, id)).is_equal(O.NONE)
	assert_float(ControlTestKit.inputs(w).e_pitch[EntityId.slot(id)]).is_equal(0.25)
	assert_int(ControlTestKit.control(w).last_input_tick(0)).is_equal(w.tick())


func test_c15_death_releases_first_and_clears_control_fields() -> void:
	var w: SimWorld = ControlTestKit.world()
	var id: int = ControlTestKit.dart(w)
	var other: int = ControlTestKit.dart(w, 0, 0, 500.0, 300.0)
	var _p: Array[SimEvent] = ControlTestKit.run(w, Command.possess(0, id))
	var _r: Array[SimEvent] = ControlTestKit.run(w, ControlTestKit.request(ControlTestKit.MATE, id))
	var ev: Array[SimEvent] = ControlTestKit.run(w, CommandPayload.debug_set(0, id, CommandPayload.SET_KILL, 0.0))
	assert_array(Array(WorldTestKit.kinds(ev))).is_equal([K.WRECK_SPAWNED, K.RELEASED, K.DEATH])   # GD-19: the dart's wreck first (EconomyHub.on_death), then C15 release, then DEATH
	assert_int(ev[1].extra[0]).is_equal(RR.DEATH)
	assert_int(w.view().player_state(0).possessed).is_equal(0)
	var s: int = EntityId.slot(id)
	assert_int(w.store().possessor[s]).is_equal(EntityStore.NONE_U8)
	assert_int(w.store().control_state[s]).is_equal(S.AUTO)
	assert_int(ControlTestKit.control(w).request_from(id)).is_equal(-1)
	ev = ControlTestKit.run(w, CommandPayload.debug_set(0, other, CommandPayload.SET_KILL, 0.0))
	assert_array(Array(WorldTestKit.kinds(ev))).is_equal([K.WRECK_SPAWNED, K.DEATH])     # not possessed: no RELEASED (GD-19: the wreck first)


func test_c16_match_end_and_team_loss_release_to_auto() -> void:
	var w: SimWorld = ControlTestKit.world(7, WorldTestKit.rules(-1.0, 1.0))
	var id: int = ControlTestKit.dart(w)
	var _o: Array[SimEvent] = ControlTestKit.run(w, ControlTestKit.order(0, id, OrderSpec.Kind.HOLD))
	var _p: Array[SimEvent] = ControlTestKit.run(w, Command.possess(0, id))
	var got: Array[SimEvent] = ControlTestKit.step(w, WorldTestKit.content().rules.tick_hz)
	var rel: Array[SimEvent] = ControlTestKit.of_kind(got, K.RELEASED)
	assert_int(rel.size()).is_equal(1)
	assert_int(rel[0].extra[0]).is_equal(RR.MATCH)
	assert_int(ControlTestKit.state(w, id)).is_equal(S.AUTO)
	assert_int(ControlTestKit.overlay(w, id)).is_equal(O.SAFETY)
	var t: SimWorld = ControlTestKit.world()
	var mine: int = ControlTestKit.dart(t)
	var _q: Array[SimEvent] = ControlTestKit.run(t, Command.possess(0, mine))
	ControlTestKit.control(t).release_team(0)
	var ev: Array[SimEvent] = t.drain_events()
	assert_array(Array(WorldTestKit.kinds(ev))).is_equal([K.RELEASED])
	assert_int(ev[0].extra[0]).is_equal(RR.MATCH)
	assert_int(ControlTestKit.state(t, mine)).is_equal(S.AUTO)


func test_c16_commander_elimination_keeps_the_possession() -> void:
	var w: SimWorld = ControlTestKit.world()
	var id: int = ControlTestKit.dart(w)
	var _p: Array[SimEvent] = ControlTestKit.run(w, Command.possess(0, id))
	w._players.eliminated[0] = 1
	var ev: Array[SimEvent] = ControlTestKit.step(w, 5)
	assert_int(ControlTestKit.of_kind(ev, K.RELEASED).size()).is_equal(0)
	assert_int(w.view().possessor(id)).is_equal(0)


func test_c17_request_expires_after_10_s_and_on_release() -> void:
	var w: SimWorld = ControlTestKit.world()
	var id: int = ControlTestKit.dart(w)
	var hz: int = WorldTestKit.content().rules.tick_hz
	var _p: Array[SimEvent] = ControlTestKit.run(w, Command.possess(0, id))
	var _r: Array[SimEvent] = ControlTestKit.run(w, ControlTestKit.request(ControlTestKit.MATE, id))
	var _a: Array[SimEvent] = ControlTestKit.step(w, ControlMachine.REQUEST_TTL_S * hz)
	assert_int(ControlTestKit.control(w).request_from(id)).is_equal(ControlTestKit.MATE)       # exactly 10 s old: still live
	var _b: Array[SimEvent] = ControlTestKit.step(w)
	assert_int(ControlTestKit.control(w).request_from(id)).is_equal(-1)
	assert_int(ControlTestKit.code(w, CommandPayload.handover(0, id, ControlTestKit.MATE))).is_equal(C.REJECTED_NO_RIGHTS)
	assert_int(ControlTestKit.code(w, ControlTestKit.request(2, id))).is_equal(C.ACCEPTED)       # the slot is free for another requester
	var _c: Array[SimEvent] = ControlTestKit.step(w)
	assert_int(ControlTestKit.control(w).request_from(id)).is_equal(2)
	var _d: Array[SimEvent] = ControlTestKit.run(w, Command.release(0))
	assert_int(ControlTestKit.control(w).request_from(id)).is_equal(-1)


func test_c18_invalidation_and_admin_release() -> void:
	var w: SimWorld = ControlTestKit.world()
	var a: int = ControlTestKit.dart(w)
	var _p: Array[SimEvent] = ControlTestKit.run(w, Command.possess(0, a))
	w.store().team[EntityId.slot(a)] = 1                              # captured / changed team
	var ev: Array[SimEvent] = ControlTestKit.step(w)
	assert_array(Array(WorldTestKit.kinds(ev))).is_equal([K.RELEASED])
	assert_int(ev[0].extra[0]).is_equal(RR.INVALID)
	assert_int(ControlTestKit.overlay(w, a)).is_equal(O.SAFETY)
	var b: int = ControlTestKit.dart(w, 0, 0, 500.0, 300.0)
	var _q: Array[SimEvent] = ControlTestKit.run(w, Command.possess(0, b))
	w.store().flags[EntityId.slot(b)] &= ~EntityStore.F_POSSESSABLE  # def no longer possessable
	ev = ControlTestKit.step(w)
	assert_int(ev[0].extra[0]).is_equal(RR.INVALID)
	var c: int = ControlTestKit.dart(w, 0, 0, 500.0, 600.0)
	var _r: Array[SimEvent] = ControlTestKit.run(w, Command.possess(0, c))
	w.admin_release(0)
	assert_int(w.view().possessor(c)).is_equal(0)                    # S1: applied in the next step 1
	ev = ControlTestKit.step(w)
	assert_array(Array(WorldTestKit.kinds(ev))).is_equal([K.RELEASED])
	assert_int(ev[0].extra[0]).is_equal(RR.ADMIN)
	assert_int(ControlTestKit.state(w, c)).is_equal(S.AUTO)
