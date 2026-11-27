extends GdUnitTestSuite
## AI-45 acceptance (05 s6.2 / s2.5 row 3, R0 B.24 A-119): the DOCKED mode of the ship brains against the real Docking
## (no LandingWorld). Docked brain ships tag DOCKED and drive nothing; they leave on SERVICED, or on a service pause
## (ALERT WAITING_FOR_ICE) with fuel01 >= landing.auto_launch_fuel01; LAUNCH drives thrust 1.0 along the pad normal and
## the sim's hold launches them; the Bomber leaves only on an order. SC-17 possess_while_docked_and_launch and SC-18
## disconnect_while_docked (05 s16 table) run here.

var _w: SimWorld
var _d: AiDriver
var _hz: int
var _pad: int
var _log: Array[SimEvent] = []


func before_test() -> void:
	_w = Ai14Kit.world(11)
	_d = Ai14Kit.driver(_w, false)
	_hz = Ai14Kit.content().rules.tick_hz
	_pad = DockingTestKit.pad(_w, &"pad", 0, 0)
	_w._players.team_ice[0] = 100000
	_w._players.team_ore[0] = 100000
	_log.clear()


# A ship `def` of player `owner` docked on `_pad` with fuel01 `fuel`.
func _docked(def: StringName, fuel: float, owner: int = 0) -> int:
	var id: int = DockingTestKit.ship_over(_w, def, owner, 0, _pad, DockingTestKit.HIGH)
	DockingTestKit.dock(_w, id, _pad)
	_w.store().fuel[EntityId.slot(id)] = DockingTestKit.ship_def(def).fuel_s * fuel
	return id


# Steps up to n ticks collecting events, stopping at the first match; returns its 1-based step of `kind` for `id` (0: none).
func _run(id: int, n: int, kind: SimEvent.Kind = SimEvent.Kind.LAUNCHED) -> int:
	var at: int = 0
	for k: int in n:
		_w.step()
		for e: SimEvent in _w.drain_events():
			_log.append(e)
			if e.kind == kind and (e.a == id or e.kind == SimEvent.Kind.ALERT and e.b == id) and at == 0:
				at = k + 1
		if at > 0:
			break
	return at


func _docked_flag(id: int) -> bool:
	return _w.view().dock_state(id) == 2


func _count(kind: SimEvent.Kind, id: int) -> int:
	var n: int = 0
	for e: SimEvent in _log:
		n += 1 if e.kind == kind and e.a == id else 0
	return n


func test_the_def_value_is_the_02_s2_3_fifty_percent() -> void:
	var c: ContentSet = Ai14Kit.content()
	for def: StringName in [&"dart", &"lancer", &"scout"]:
		var p: DartParams = DartParams.from_content(Ai14Kit.ap(def), Ai14Kit.ship(def), c)
		assert_float(p.auto_launch_fuel01).override_failure_message(str(def)).is_equal(0.5)
	var bp: DartParams = DartParams.from_content(Ai14Kit.ap(&"bomber"), Ai14Kit.ship(&"bomber"), c)
	assert_float(bp.auto_launch_fuel01).is_less(0.0)


func test_a_full_service_launches_after_serviced_and_tags_docked_until_then() -> void:
	var id: int = _docked(&"dart", 0.4)
	var serviced: int = _run(id, 30 * _hz, SimEvent.Kind.SERVICED)
	assert_int(serviced).is_greater(0)
	assert_int(_count(SimEvent.Kind.LAUNCHED, id)).override_failure_message("launched before SERVICED").is_equal(0)
	var launched: int = _run(id, 3 * _hz)
	assert_int(launched).is_greater(0)
	assert_int(_count(SimEvent.Kind.LAUNCHED, id)).is_equal(1)
	assert_float(_w.view().fuel01(id)).is_greater(0.9)                     # the whole service was taken (a few ticks of burn)


func test_no_launch_before_serviced_while_the_pool_is_fed() -> void:
	var id: int = _docked(&"dart", 0.1)
	var tags: Dictionary = {}
	for k: int in 6 * _hz:
		_w.step()
		_log.append_array(_w.drain_events())
		tags[_w.view().ai_tag(id)] = true
	assert_bool(_docked_flag(id)).is_true()
	assert_int(_count(SimEvent.Kind.LAUNCHED, id)).is_equal(0)
	assert_bool(tags.has(AiTag.Tag.DOCKED)).is_true()
	assert_bool(tags.has(AiTag.Tag.LAUNCH)).is_false()


func test_a_paused_ice_service_launches_at_half_fuel_and_not_before() -> void:
	_w._players.team_ice[0] = 0
	var low: int = _docked(&"dart", 0.3)
	var alert: int = _run(low, 4 * _hz, SimEvent.Kind.ALERT)
	assert_int(alert).is_greater(0)
	assert_int(_run(low, 20 * _hz)).override_failure_message("launched below auto_launch_fuel01").is_equal(0)
	assert_bool(_docked_flag(low)).is_true()
	assert_int(_w.view().ai_tag(low)).is_equal(AiTag.Tag.DOCKED)
	_w._players.team_ice[0] = 0
	var id2: int = _docked_second(0.5)
	assert_int(_run(id2, 4 * _hz, SimEvent.Kind.ALERT)).is_greater(0)
	var at: int = _run(id2, 3 * _hz)
	assert_int(at).override_failure_message("a paused service at 50 % fuel must launch").is_greater(0)
	assert_float(_w.view().fuel01(id2)).is_greater_equal(0.5)
	assert_int(_count(SimEvent.Kind.SERVICED, id2)).is_equal(0)


# A second ship on a second pad (the first pad is occupied).
func _docked_second(fuel: float) -> int:
	var pad2: int = DockingTestKit.pad(_w, &"pad", 0, 0, 900.0)
	var id: int = DockingTestKit.ship_over(_w, &"dart", 0, 0, pad2, DockingTestKit.HIGH)
	DockingTestKit.dock(_w, id, pad2)
	_w.store().fuel[EntityId.slot(id)] = DockingTestKit.ship_def(&"dart").fuel_s * fuel
	return id


func test_lancer_and_scout_leave_on_serviced() -> void:
	for def: StringName in [&"lancer", &"scout"]:
		var id: int = _docked(def, 0.6)
		assert_int(_run(id, 40 * _hz, SimEvent.Kind.SERVICED)).override_failure_message(str(def)).is_greater(0)
		assert_int(_run(id, 3 * _hz)).override_failure_message(str(def)).is_greater(0)
		assert_int(_count(SimEvent.Kind.LAUNCHED, id)).is_equal(1)
		DockingTestKit.clear(_w, id)


func test_the_bomber_stays_docked_through_a_full_service_until_an_order_arrives() -> void:
	var id: int = _docked(&"bomber", 0.5)
	assert_int(_run(id, 40 * _hz, SimEvent.Kind.SERVICED)).is_greater(0)
	assert_int(_run(id, 10 * _hz)).is_equal(0)
	assert_bool(_docked_flag(id)).is_true()
	assert_int(_w.view().ai_tag(id)).is_equal(AiTag.Tag.DOCKED)
	var spec: OrderSpec = OrderSpec.make(OrderSpec.Kind.MOVE, 0, DartKit.above(_w, Vector3(1, 0.4, 0), 500.0), 0)
	var _r: CommandResult = _w.apply_command(Command.order(0, PackedInt32Array([id]), spec))
	assert_int(_run(id, 4 * _hz)).override_failure_message("a Bomber with an order must launch").is_greater(0)


func test_sc17_possess_while_docked_and_launch() -> void:
	var id: int = _docked(&"dart", 0.5)
	assert_bool(DockingTestKit.possess(_w, id, 0)).is_true()
	var inp: PilotInput = PilotInput.new()
	inp.thrust = 1.0
	var at: int = 0
	for k: int in _hz / 2 + 1:
		var _c: CommandResult = _w.apply_command(Command.pilot(0, _w.tick() + 1, inp))
		_w.step()
		for e: SimEvent in _w.drain_events():
			_log.append(e)
			at = k + 1 if e.kind == SimEvent.Kind.LAUNCHED and e.a == id and at == 0 else at
	assert_int(at).override_failure_message("thrust 1.0 for 0.5 s must launch").is_greater(0)
	assert_bool(_docked_flag(id)).is_false()
	var fuel: float = _w.view().fuel01(id)
	assert_float(fuel).is_greater_equal(0.5)
	assert_float(fuel).is_less(1.0)                                           # service aborted, partial fuel kept
	assert_int(_count(SimEvent.Kind.SERVICED, id)).is_equal(0)


func test_sc18_disconnect_while_docked() -> void:
	var pad1: int = DockingTestKit.pad(_w, &"pad", 1, 1, 1800.0)
	_w._players.team_ice[1] = 100000
	_w._players.team_ore[1] = 100000
	var id: int = DockingTestKit.ship_over(_w, &"dart", 1, 1, pad1, DockingTestKit.HIGH)
	DockingTestKit.dock(_w, id, pad1)
	_w.store().fuel[EntityId.slot(id)] = DockingTestKit.ship_def(&"dart").fuel_s * 0.3
	assert_bool(DockingTestKit.possess(_w, id, 1)).is_true()
	DockingTestKit.step_piloted(_w, 1)
	_log.append_array(_w.drain_events())
	_w.remove_player(1)
	_w.step()
	var released: Array[SimEvent] = DockingTestKit.of_kind(_w.drain_events(), SimEvent.Kind.RELEASED)
	assert_int(released.size()).is_equal(1)
	assert_int(released[0].extra[0]).is_equal(ControlMachine.ReleaseReason.DISCONNECT)
	assert_bool(_docked_flag(id)).is_true()
	assert_int(_run(id, 40 * _hz, SimEvent.Kind.SERVICED)).override_failure_message("service not completed").is_greater(0)
	assert_int(_run(id, 3 * _hz)).override_failure_message("did not relaunch").is_greater(0)
	var tag: int = 0
	for _k: int in 60 * _hz:
		_w.step()
		_log.append_array(_w.drain_events())
		tag = _w.view().ai_tag(id)
		if tag == AiTag.Tag.PATROL:
			break
	assert_int(tag).is_equal(AiTag.Tag.PATROL)


func test_launch_mode_holds_on_the_pad_until_the_sim_hold_passes() -> void:
	var id: int = _docked(&"dart", 0.99)
	var launch_ticks: int = 0
	for _k: int in 4 * _hz:
		_w.step()
		_log.append_array(_w.drain_events())
		launch_ticks += 1 if _docked_flag(id) and _w.view().ai_tag(id) == AiTag.Tag.LAUNCH else 0
	assert_int(launch_ticks).override_failure_message("LAUNCH never held while docked").is_greater(0)
	assert_int(_count(SimEvent.Kind.LAUNCHED, id)).is_equal(1)
