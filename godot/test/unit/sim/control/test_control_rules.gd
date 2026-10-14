extends GdUnitTestSuite
## ControlMachine (AI-02): every C6r and V-REQ rejection code, `ReleaseReason` exactly R0 B.3 and each reason
## reaching a RELEASED event, hand-over without replay of A's input (R0 C2-08), autopilot resuming on release,
## structures released without overlay, determinism of two identical runs and the S4 serialize round trip.

const K := SimEvent.Kind
const O := ControlMachine.Overlay
const RR := ControlMachine.ReleaseReason
const C := CommandResult.Code
const OPEN_SLOT: int = 4


func test_c6r_every_rejection_code() -> void:
	var w: SimWorld = ControlTestKit.world()
	w.add_player(OPEN_SLOT, 0, &"", PlayerTable.KIND_OPEN)
	var own: int = ControlTestKit.dart(w)
	var enemy: int = ControlTestKit.dart(w, 1, 1, 500.0, 100.0)
	var core: int = WorldTestKit.spawn(w, &"core", 0, 0, WorldTestKit.at(0.0, 900.0))
	var yard: int = WorldTestKit.spawn(w, &"shipyard", 0, 0, WorldTestKit.at(0.0, -900.0))
	w.store().flags[EntityId.slot(yard)] |= EntityStore.F_BUILDING
	var hard: float = WorldTestKit.content().rules.ceiling_hard_m
	var edge: int = ControlTestKit.dart(w, 0, 0, 1000.0, 300.0)
	var below: int = ControlTestKit.dart(w, 0, 0, 1000.0, 600.0)
	var uplink: float = hard - float(ControlMachine.UPLINK_MARGIN_M)
	w.store().pos[EntityId.slot(edge)] = WorldTestKit.at(uplink)                       # exactly 1,950 m
	w.store().pos[EntityId.slot(below)] = Vector3(0.0, 0.0, Sphere.PLANET_RADIUS + uplink - 1.0)
	assert_int(ControlTestKit.code(w, Command.possess(0, EntityId.make(77, 1)))).is_equal(C.REJECTED_DEAD)
	assert_int(ControlTestKit.code(w, Command.possess(0, enemy))).is_equal(C.REJECTED_NOT_OWNER)
	assert_int(ControlTestKit.code(w, Command.possess(0, core))).is_equal(C.REJECTED_NOT_POSSESSABLE)
	assert_int(ControlTestKit.code(w, Command.possess(0, yard))).is_equal(C.REJECTED_NOT_POSSESSABLE)   # under construction
	assert_int(ControlTestKit.code(w, Command.possess(OPEN_SLOT, own))).is_equal(C.REJECTED_NO_RIGHTS)  # open slot = spectator
	assert_int(ControlTestKit.code(w, Command.possess(0, edge))).is_equal(C.REJECTED_UPLINK)           # >= 1,950 m
	assert_int(ControlTestKit.code(w, Command.possess(ControlTestKit.MATE, own))).is_equal(C.ACCEPTED)
	assert_int(ControlTestKit.code(w, Command.possess(0, own))).is_equal(C.REJECTED_ALREADY_POSSESSED)  # same-tick claim
	assert_int(ControlTestKit.code(w, Command.possess(0, below))).is_equal(C.ACCEPTED)
	var _s: Array[SimEvent] = ControlTestKit.step(w)
	assert_int(ControlTestKit.code(w, Command.possess(0, own))).is_equal(C.REJECTED_ALREADY_POSSESSED)
	ControlTestKit.control(w).release_team(0)                                     # team lost its last Core: spectators
	assert_int(ControlTestKit.code(w, Command.possess(ControlTestKit.MATE, own))).is_equal(C.REJECTED_NO_RIGHTS)


func test_release_and_v_req_rejection_codes() -> void:
	var w: SimWorld = ControlTestKit.world()
	var id: int = ControlTestKit.dart(w)
	var foe: int = ControlTestKit.dart(w, 1, 1, 500.0, 300.0)
	assert_int(ControlTestKit.code(w, Command.release(0))).is_equal(C.REJECTED_DEAD)                   # nothing possessed
	assert_int(ControlTestKit.code(w, ControlTestKit.request(ControlTestKit.MATE, id))).is_equal(C.REJECTED_NO_RIGHTS)         # nobody pilots it
	var _p: Array[SimEvent] = ControlTestKit.run(w, Command.possess(0, id))
	var rel: Command = Command.release(0)
	rel.target = foe
	assert_int(ControlTestKit.code(w, rel)).is_equal(C.REJECTED_NOT_OWNER)
	assert_int(ControlTestKit.code(w, ControlTestKit.request(0, id))).is_equal(C.REJECTED_NO_RIGHTS)               # the pilot itself
	assert_int(ControlTestKit.code(w, ControlTestKit.request(1, id))).is_equal(C.REJECTED_NOT_OWNER)               # other team
	assert_int(ControlTestKit.code(w, ControlTestKit.request(ControlTestKit.MATE, EntityId.make(77, 1)))).is_equal(C.REJECTED_DEAD)
	var bad: Command = ControlTestKit.request(ControlTestKit.MATE, id)
	bad.payload = PackedByteArray([1])
	assert_int(ControlTestKit.code(w, bad)).is_equal(C.REJECTED_MALFORMED)
	assert_int(ControlTestKit.code(w, CommandPayload.handover(0, id, ControlTestKit.MATE))).is_equal(C.REJECTED_NO_RIGHTS)   # no request
	var _r: Array[SimEvent] = ControlTestKit.run(w, ControlTestKit.request(ControlTestKit.MATE, id))
	assert_int(ControlTestKit.code(w, CommandPayload.handover(ControlTestKit.MATE, id, ControlTestKit.MATE))).is_equal(C.REJECTED_NOT_OWNER)  # not the pilot
	assert_int(ControlTestKit.code(w, CommandPayload.handover(0, id, 1))).is_equal(C.REJECTED_NO_RIGHTS)        # other team
	assert_int(ControlTestKit.code(w, CommandPayload.handover(0, id, 2))).is_equal(C.REJECTED_NO_RIGHTS)        # not the requester
	var short: Command = CommandPayload.handover(0, id, ControlTestKit.MATE)
	short.payload = PackedByteArray()
	assert_int(ControlTestKit.code(w, short)).is_equal(C.REJECTED_MALFORMED)
	w.remove_player(ControlTestKit.MATE)
	assert_int(ControlTestKit.code(w, CommandPayload.handover(0, id, ControlTestKit.MATE))).is_equal(C.REJECTED_NO_RIGHTS)  # q left the match


func test_release_reason_is_exactly_r0_b3() -> void:
	assert_array(ControlMachine.ReleaseReason.keys()).is_equal(
		["PLAYER", "DEATH", "CEILING", "HANDOVER", "DISCONNECT", "MATCH", "INVALID", "ADMIN"])
	assert_array(ControlMachine.ReleaseReason.values()).is_equal([0, 1, 2, 3, 4, 5, 6, 7])
	assert_array(ControlMachine.OrderFail.keys()).is_equal(
		["INVALID_TARGET", "UNREACHABLE", "STUCK", "OVERRIDDEN", "INVALID_ON_RESUME", "NO_PAD", "NO_AMMO"])
	assert_array(ControlMachine.State.keys()).is_equal(["AUTO", "ORDERED", "POSSESSED"])
	assert_array(ControlMachine.Overlay.keys()).is_equal(["NONE", "SAFETY", "RECOVER_CEILING", "LINK_BRIDGE"])


func test_each_release_reason_reaches_a_released_event() -> void:
	var w: SimWorld = ControlTestKit.world(7, WorldTestKit.rules(-1.0, 4.0))
	var hard: float = WorldTestKit.content().rules.ceiling_hard_m
	var seen: PackedInt32Array = PackedInt32Array()
	var ids: PackedInt32Array = PackedInt32Array()
	for k: int in 7:
		ids.push_back(ControlTestKit.dart(w, 0, 0, 500.0, 200.0 * k))
	_collect(seen, ControlTestKit.run(w, Command.possess(0, ids[0])))
	_collect(seen, ControlTestKit.run(w, Command.release(0)))                                          # PLAYER
	_collect(seen, ControlTestKit.run(w, Command.possess(0, ids[1])))
	_collect(seen, ControlTestKit.run(w, CommandPayload.debug_set(0, ids[1], CommandPayload.SET_KILL, 0.0)))   # DEATH
	_collect(seen, ControlTestKit.run(w, Command.possess(0, ids[2])))
	w.store().pos[EntityId.slot(ids[2])] = WorldTestKit.at(hard + 1.0, 400.0)
	_collect(seen, ControlTestKit.step(w))                                                             # CEILING
	_collect(seen, ControlTestKit.run(w, Command.possess(0, ids[3])))
	_collect(seen, ControlTestKit.run(w, ControlTestKit.request(ControlTestKit.MATE, ids[3])))
	_collect(seen, ControlTestKit.run(w, CommandPayload.handover(0, ids[3], ControlTestKit.MATE)))                 # HANDOVER
	w.remove_player(ControlTestKit.MATE)
	_collect(seen, ControlTestKit.step(w))                                                             # DISCONNECT
	_collect(seen, ControlTestKit.run(w, Command.possess(0, ids[4])))
	w.store().team[EntityId.slot(ids[4])] = 1
	_collect(seen, ControlTestKit.step(w))                                                             # INVALID
	_collect(seen, ControlTestKit.run(w, Command.possess(0, ids[5])))
	w.admin_release(0)
	_collect(seen, ControlTestKit.step(w))                                                             # ADMIN
	_collect(seen, ControlTestKit.run(w, Command.possess(0, ids[6])))
	_collect(seen, ControlTestKit.step(w, 4 * WorldTestKit.content().rules.tick_hz))                   # MATCH
	assert_array(Array(seen)).is_equal([RR.PLAYER, RR.DEATH, RR.CEILING, RR.HANDOVER, RR.DISCONNECT, RR.INVALID,
		RR.ADMIN, RR.MATCH])


func test_handover_never_replays_a_input() -> void:
	var w: SimWorld = ControlTestKit.world()
	var id: int = ControlTestKit.dart(w)
	var spare: int = ControlTestKit.dart(w, 0, 0, 500.0, 400.0)
	var s: int = EntityId.slot(id)
	var io: InputSlots = ControlTestKit.inputs(w)
	var _p: Array[SimEvent] = ControlTestKit.run(w, Command.possess(0, id))
	var _q: Array[SimEvent] = ControlTestKit.run(w, Command.possess(ControlTestKit.MATE, spare))
	var _r: Array[SimEvent] = ControlTestKit.run(w, ControlTestKit.request(ControlTestKit.MATE, id))
	assert_int(ControlTestKit.pilot(w, 0, 1.0, 0.9, PilotInput.FIRE1 | PilotInput.BOOST)).is_equal(C.ACCEPTED)   # A's last input
	var ev: Array[SimEvent] = ControlTestKit.run(w, CommandPayload.handover(0, id, ControlTestKit.MATE))
	assert_array(Array(WorldTestKit.kinds(ev))).is_equal([K.RELEASED, K.RELEASED, K.HANDOVER, K.POSSESSED])
	assert_int(ev[0].a).is_equal(spare)                                # q's own possession released first
	assert_int(ev[0].extra[0]).is_equal(RR.PLAYER)
	assert_int(ev[1].extra[0]).is_equal(RR.HANDOVER)
	for k: int in 2 * ControlMachine.DECAY_TICKS:
		assert_float(io.e_thrust[s]).override_failure_message("tick %d" % k).is_equal(0.0)
		assert_float(io.e_pitch[s]).is_equal(0.0)
		assert_int(io.e_buttons[s]).is_equal(0)
		assert_int(ControlTestKit.overlay(w, id)).is_equal(O.LINK_BRIDGE)
		assert_int(ControlTestKit.pilot(w, 0, 1.0, 0.9, PilotInput.FIRE1)).is_equal(C.ACCEPTED)   # A keeps sending: ignored
		assert_int(ControlTestKit.step(w).size()).is_equal(0)                       # no LINK_WEAK for a hand-over bridge
	assert_int(ControlTestKit.pilot(w, ControlTestKit.MATE, 0.5, -0.25)).is_equal(C.ACCEPTED)
	var _f: Array[SimEvent] = ControlTestKit.step(w)
	assert_int(ControlTestKit.overlay(w, id)).is_equal(O.NONE)                     # C14: B's first input
	assert_float(io.e_thrust[s]).is_equal(0.5)
	assert_float(io.e_pitch[s]).is_equal(-0.25)


func test_autopilot_resumes_on_release() -> void:
	var w: SimWorld = ControlTestKit.world()
	var id: int = ControlTestKit.dart(w)
	var hook: WorldTestKit.RecordingHook = WorldTestKit.RecordingHook.new()
	hook.drive_id = id
	hook.input.thrust = 0.4
	w.set_ai_hook(hook)
	var _a: Array[SimEvent] = ControlTestKit.step(w)
	var _p: Array[SimEvent] = ControlTestKit.run(w, Command.possess(0, id))
	var _b: Array[SimEvent] = ControlTestKit.step(w, 3)
	var _r: Array[SimEvent] = ControlTestKit.run(w, Command.release(0))
	var _c: Array[SimEvent] = ControlTestKit.step(w, 2)
	var drives: Array = []
	drives.assign(hook.drive_results)
	assert_array(drives).is_equal([true, false, false, false, false, true, true, true])
	assert_array(Array(hook.possessor_seen)).is_equal([-1, 0, 0, 0, 0, -1, -1, -1])
	assert_float(ControlTestKit.inputs(w).e_thrust[EntityId.slot(id)]).is_equal(0.4)   # the autopilot writes the slot again
	assert_int(ControlTestKit.overlay(w, id)).is_equal(O.SAFETY)                    # set for sim_ai's Overlays.run_safety


func test_structure_release_sets_no_overlay() -> void:
	var w: SimWorld = ControlTestKit.world()
	var yard: int = WorldTestKit.spawn(w, &"shipyard", 0, 0, WorldTestKit.at(0.0, -900.0))
	var _p: Array[SimEvent] = ControlTestKit.run(w, Command.possess(0, yard))
	assert_int(ControlTestKit.state(w, yard)).is_equal(ControlMachine.State.POSSESSED)
	var _r: Array[SimEvent] = ControlTestKit.run(w, Command.release(0))
	assert_int(ControlTestKit.overlay(w, yard)).is_equal(O.NONE)


func test_two_identical_runs_are_byte_identical() -> void:
	var a: SimWorld = ControlTestKit.world(3)
	var b: SimWorld = ControlTestKit.world(3)
	var ea: PackedStringArray = _script(a)
	var eb: PackedStringArray = _script(b)
	assert_array(Array(ea)).is_equal(Array(eb))
	assert_int(ea.size()).is_greater(10)
	assert_bool(a.serialize() == b.serialize()).is_true()


func test_s4_round_trip_keeps_requests_silence_and_bridge() -> void:
	var a: SimWorld = ControlTestKit.world(5)
	var id: int = ControlTestKit.dart(a)
	var other: int = ControlTestKit.dart(a, 0, 0, 500.0, 400.0)
	var _p: Array[SimEvent] = ControlTestKit.run(a, Command.possess(0, id))
	var _q: Array[SimEvent] = ControlTestKit.run(a, Command.possess(ControlTestKit.MATE, other))
	var _r: Array[SimEvent] = ControlTestKit.run(a, ControlTestKit.request(2, id))
	var _s: Array[SimEvent] = ControlTestKit.step(a, ControlMachine.DECAY_TICKS - 2)  # both pilots silent, near the window end
	assert_int(ControlTestKit.pilot(a, ControlTestKit.MATE, 0.6, 0.3)).is_equal(C.ACCEPTED)       # a fresh input waiting for step 2
	var b: SimWorld = SimWorld.deserialize(a.serialize(), WorldTestKit.content(), null)
	assert_object(b).is_not_null()
	assert_bool(b.serialize() == a.serialize()).is_true()
	assert_int(ControlTestKit.control(b).request_from(id)).is_equal(2)
	assert_int(ControlTestKit.control(b).silent_ticks(0)).is_equal(ControlTestKit.control(a).silent_ticks(0))
	for t: int in 40:
		if t == 20:
			assert_int(ControlTestKit.code(a, CommandPayload.handover(0, id, 2))).is_equal(C.ACCEPTED)
			assert_int(ControlTestKit.code(b, CommandPayload.handover(0, id, 2))).is_equal(C.ACCEPTED)
		var ea: PackedStringArray = _describe(ControlTestKit.step(a))
		var eb: PackedStringArray = _describe(ControlTestKit.step(b))
		assert_array(Array(eb)).override_failure_message("tick %d" % t).is_equal(Array(ea))
		assert_bool(b.serialize() == a.serialize()).override_failure_message("tick %d" % t).is_true()
	assert_int(b.view().possessor(id)).is_equal(2)


func _collect(out: PackedInt32Array, events: Array[SimEvent]) -> void:
	for e: SimEvent in events:
		if e.kind == K.RELEASED:
			out.push_back(e.extra[0])


func _describe(events: Array[SimEvent]) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for e: SimEvent in events:
		out.push_back("%d:%d:%d:%d:%s" % [e.tick, e.kind, e.a, e.b, str(e.extra)])
	return out


# A fixed control script: possess, silence into LINK_BRIDGE, request, hand-over, orders, release, death.
func _script(w: SimWorld) -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	var id: int = ControlTestKit.dart(w)
	var b: int = ControlTestKit.dart(w, 0, 0, 500.0, 300.0)
	var steps: Array = [
		Command.possess(0, id), null, ControlTestKit.order(ControlTestKit.MATE, id, OrderSpec.Kind.HOLD), null, null,
		ControlTestKit.request(ControlTestKit.MATE, id), CommandPayload.handover(0, id, ControlTestKit.MATE), Command.possess(0, b),
		ControlTestKit.order(0, b, OrderSpec.Kind.MOVE), Command.release(ControlTestKit.MATE),
		CommandPayload.debug_set(0, b, CommandPayload.SET_KILL, 0.0)]
	for c: Variant in steps:
		if c != null:
			var cmd: Command = c
			lines.push_back("r%d" % w.apply_command(cmd).code)
		lines.append_array(_describe(ControlTestKit.step(w, 6)))
	return lines
