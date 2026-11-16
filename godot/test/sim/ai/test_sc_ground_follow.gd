extends GdUnitTestSuite
## AI-16 scenarios of the ground follower (05 s5.7, R0 C1-05, C2-09): SC-48 ground_brake_reverse (the sim's BRAKE rule on a
## Harvester the AI drives, handed to a pilot and back) and SC-51 path_ticket_flow (20 Harvesters re-path in one tick on
## `tiny_test`). The sim runs the real Pathing, GroundMotion and Harvest; the brain only drives (`Ai16Kit`).

const HZ: int = 30

var _w: SimWorld
var _d: AiDriver
var _brain: HarvesterBrain


# Signed speed along the unit's heading (negative = reversing).
func _along(id: int) -> float:
	return _w.view().vel(id).dot(-_w.view().basis(id).z)


func _pilot(buttons: int, thrust: float) -> void:
	var inp: PilotInput = PilotInput.new()
	inp.thrust = thrust
	inp.buttons = buttons
	OverlayKit.ok(_w, Command.pilot(0, _w.tick() + 1, inp))


func _tick() -> void:
	Ai16Kit.step(_w)


# SC-48 ground_brake_reverse: a Harvester driving (the AI's drive, then a pilot's) with BRAKE held for 2 s -> it stops at once;
# after 0.5 s stationary with BRAKE still held it reverses at <= 3 m/s; released, the AI drives it on again.
func test_sc48_ground_brake_reverse() -> void:
	_w = Ai16Kit.world(5)
	var _r: int = Ai16Kit.put(_w, &"refinery", 0, 0.0)
	var _f: int = Ai16Kit.field(_w, 900.0)
	var h: int = Ai16Kit.put(_w, &"harvester", 0, 60.0)
	_d = Ai16Kit.driver(_w)
	Ai16Kit.step(_w, 6 * HZ)
	assert_int(_w.view().ai_tag(h)).is_equal(AiTag.Tag.TO_FIELD)
	assert_float(_along(h)).is_greater(9.0)                                  # driving: top speed 12 less the turn
	OverlayKit.ok(_w, Command.possess(0, h))
	for _k: int in 10:
		_pilot(0, 1.0)
		_tick()
	assert_float(_along(h)).is_greater(9.0)
	var held: int = 0
	var first_reverse: int = -1
	var worst: float = 0.0
	var p_stop: Vector3 = Vector3.ZERO
	for k: int in 2 * HZ:                                                    # BRAKE held 2 s
		_pilot(PilotInput.BRAKE, 1.0)                                        # thrust is ignored under BRAKE
		_tick()
		held += 1
		var v: float = _along(h)
		if held == 1:
			assert_float(_w.view().vel(h).length()).is_equal(0.0)            # stops at once
			p_stop = _w.view().pos(h)
		if v < 0.0 and first_reverse < 0:
			first_reverse = held
		worst = minf(worst, v)
		if first_reverse < 0:
			assert_float(_w.view().pos(h).distance_to(p_stop)).is_less(0.01) # stationary until the hold is up
	var hold: int = ceili(Ai16Kit.content().ground_common.ground_reverse_hold_s * float(HZ))
	assert_int(first_reverse).is_between(hold - 1, hold + 1)                  # after 0.5 s stationary
	assert_float(worst).is_greater_equal(-Ai16Kit.content().ground_common.ground_reverse_speed_mps - 0.001)   # <= 3 m/s
	assert_float(worst).is_less(-2.9)                                        # and it does reverse at that speed
	_pilot(0, 0.0)
	_tick()
	assert_float(_w.view().vel(h).length()).is_equal(0.0)                    # BRAKE released, thrust 0: still
	OverlayKit.ok(_w, Command.release(0))
	Ai16Kit.step(_w, 3 * HZ)                                                 # ground SAFETY, then the brain resumes
	assert_float(_along(h)).is_greater(9.0)
	assert_int(_w.view().ai_tag(h)).is_equal(AiTag.Tag.TO_FIELD)


# SC-51 path_ticket_flow: 20 Harvesters re-path in one tick on `tiny_test` -> every unit brakes while its ticket is pending, none
# ever reverses (BRAKE is never held up to the sim's reverse hold), and every route has arrived within 30 ticks.
func test_sc51_path_ticket_flow() -> void:
	_w = Ai16Kit.world(13, &"tiny_test")
	var ids: PackedInt32Array = PackedInt32Array()
	for i: int in 20:
		var _a: bool = ids.push_back(Ai16Kit.put(_w, &"harvester", 0, 1900.0 + float(i % 5) * 25.0, float(i / 5) * 25.0 - 40.0))
	_brain = Ai16Kit.brain()
	_d = Ai16Kit.driver(_w, _brain)
	Ai16Kit.step(_w, 15 * HZ)
	var pa: Pathing = _w._pathing
	for id: int in ids:
		assert_int(_w.view().ai_tag(id)).is_equal(AiTag.Tag.TO_FIELD)
		assert_bool(_d.state.path.has(EntityId.slot(id))).is_true()
	var faces: int = _d.state.ground.faces[EntityId.slot(ids[0])]
	assert_int(faces).is_not_equal(0)
	var face: int = 0
	while ((faces >> face) & 1) == 0:
		face += 1
	var requests0: int = pa.requests
	pa.set_weight((face << (2 * PathGrid.SHIFT)) | 5, PathGrid.W_BLOCKED)        # a far corner cell of a face the routes cross
	for id: int in ids:
		assert_bool(_d.wake(id, _w.tick())).is_true()                            # every think falls on the next tick
	var pending: PackedInt32Array = PackedInt32Array()
	var _p: int = pending.resize(20)
	var longest: int = 0
	var run: PackedInt32Array = PackedInt32Array()
	var _r: int = run.resize(20)
	var arrived: int = -1
	var worst: float = 0.0
	for k: int in 120:
		_tick()
		var have: int = 0
		for i: int in 20:
			var s: int = EntityId.slot(ids[i])
			var b: bool = (_w._inputs.e_buttons[s] & PilotInput.BRAKE) != 0
			if _d.state.path_ticket[s] >= 0 and HarvesterBrain.moving(_d.state.mode[s]):
				pending[i] += 1
				assert_bool(b).override_failure_message("unit %d pending but not braking at tick %d" % [i, k]).is_true()
			run[i] = run[i] + 1 if b else 0
			longest = maxi(longest, run[i])
			worst = minf(worst, _along(ids[i]))
			have += 1 if _d.state.path.has(s) and _d.state.path_ticket[s] < 0 else 0
		if k == 0:
			assert_int(pa.requests - requests0).is_equal(20)                      # all 20 asked in that one tick
		if have == 20 and arrived < 0:
			arrived = k + 1
	assert_int(arrived).is_between(1, 30)                                        # every route within 30 ticks
	assert_int(longest).is_less(ceili(Ai16Kit.content().ground_common.ground_reverse_hold_s * float(HZ)))
	assert_float(worst).is_greater_equal(-0.001)                                 # nobody reversed
	for i: int in 20:
		assert_int(pending[i]).is_greater(0)                                     # every unit really did wait on a ticket
	assert_int(_brain.stats_strikes).is_equal(0)
