extends GdUnitTestSuite
## UX-48: InputRouter samples the ground mapper in GROUND for every class and leaves FLIGHT, TURRET and PEEK unchanged.

var _router: InputRouter
var _last: PilotInput
var _intents: Array[Dictionary] = []


func before_test() -> void:
	_router = auto_free(InputRouter.new()) as InputRouter
	_last = null
	_intents.clear()
	_router.pilot_input.connect(func(p: PilotInput) -> void: _last = p)
	_router.intent.connect(func(kind: StringName, payload: Dictionary) -> void:
		_intents.append({&"kind": kind, &"payload": payload}))


func _become_pad() -> void:
	var b: InputEventJoypadButton = InputEventJoypadButton.new()
	b.pressed = true
	_router.route_event(b, 0)


func _become_kbm() -> void:
	var k: InputEventMouseButton = InputEventMouseButton.new()
	k.pressed = true
	_router.route_event(k, 0)


func _become_touch() -> void:
	var t: InputEventScreenTouch = InputEventScreenTouch.new()
	t.pressed = true
	_router.route_event(t, 0)


func test_ground_samples_the_ground_mapper_for_the_gamepad_not_the_flight_mapper() -> void:
	_become_pad()
	var st: PadState = PadState.new()
	st.left_stick = Vector2(0.0, -1.0)
	st.right_trigger = 1.0
	st.a = true
	_router.gamepad_mapper.poller = func() -> PadState: return st
	_router.ground_mapper.pad_poller = func() -> PadState: return st
	_router.set_mode(InputRouter.Mode.GROUND)
	assert_bool(_router.emit_tick()).is_true()
	assert_float(_last.thrust).is_equal(1.0)   # LS forward drives; RT alone would have set thrust on flight too
	assert_float(_last.pitch).is_equal(0.0)    # the flight mapper would have sent stick Y as pitch
	assert_int(_last.buttons & PilotInput.FIRE1).is_equal(PilotInput.FIRE1)
	st.left_stick = Vector2.ZERO
	st.right_trigger = 1.0
	var _e: bool = _router.emit_tick()
	assert_float(_last.thrust).is_equal(0.0)   # RT is FIRE1 on the ground, never thrust


func test_ground_kbm_mouse_motion_feeds_the_orbit_intent_and_never_pitch() -> void:
	# Real events through route_event, no poller override: the router's own GROUND wiring is under test.
	_become_kbm()
	_router.set_mode(InputRouter.Mode.GROUND)
	var m: InputEventMouseMotion = InputEventMouseMotion.new()
	m.relative = Vector2(12.0, -80.0)
	_router.route_event(m, 10)
	var _e: bool = _router.emit_tick()
	assert_float(_last.pitch).is_equal(0.0)
	assert_float(_last.roll).is_equal(0.0)
	assert_int(_intents.size()).is_equal(1)
	assert_str(String(_intents[0][&"kind"])).is_equal(String(Intents.FREE_LOOK))
	var payload: Dictionary = _intents[0][&"payload"]
	assert_vector(payload[Intents.K_VEC] as Vector2).is_equal(Vector2(12.0, -80.0))
	# Motion that arrives in GROUND and is never sampled must not reach the first FLIGHT sample.
	var late: InputEventMouseMotion = InputEventMouseMotion.new()
	late.relative = Vector2(0.0, -300.0)
	_router.route_event(late, 20)
	_router.set_mode(InputRouter.Mode.FLIGHT)
	_last = null
	var _f: bool = _router.emit_tick()
	assert_float(_last.pitch).is_equal(0.0)
	assert_float(_last.roll).is_equal(0.0)
	_intents.clear()
	_router.set_mode(InputRouter.Mode.GROUND)   # re-entering GROUND starts clean too
	var _g: bool = _router.emit_tick()
	assert_bool(_intents.is_empty()).is_true()


func test_ground_touch_barrel_and_release_work_and_the_menu_flow_is_untouched() -> void:
	_become_touch()
	var st: TouchState = TouchState.new()
	st.barrel_up = true
	st.release = true
	_router.ground_mapper.touch_poller = func() -> TouchState: return st
	_router.set_mode(InputRouter.Mode.GROUND)
	var _e: bool = _router.emit_tick()
	assert_float(_last.pitch).is_equal(1.0)
	assert_int(_last.buttons & PilotInput.RELEASE).is_equal(PilotInput.RELEASE)
	_router.set_mode(InputRouter.Mode.MENU)
	assert_bool(_router.emit_tick()).is_false()   # menu / pause still stops pilot_input in every mode


func test_flick_up_does_not_queue_a_flip_on_the_ground() -> void:
	_become_touch()
	_router.set_mode(InputRouter.Mode.GROUND)
	var g: Gesture = Gesture.make(Gesture.Kind.FLICK_UP, Gesture.Phase.BEGIN, Vector2.ZERO, Vector2.ZERO)
	_router._handle_gestures([g] as Array[Gesture])
	_router.set_mode(InputRouter.Mode.FLIGHT)
	var _e: bool = _router.emit_tick()
	assert_int(_last.buttons & PilotInput.FLIP).is_equal(0)


func test_flight_turret_and_peek_output_is_unchanged() -> void:
	_become_pad()
	var st: PadState = PadState.new()
	st.left_stick = Vector2(0.0, -1.0)
	st.right_trigger = 1.0
	st.rb = true
	_router.gamepad_mapper.poller = func() -> PadState: return st
	var ground_probe: PadState = PadState.new()
	ground_probe.barrel_up = true
	_router.ground_mapper.pad_poller = func() -> PadState: return ground_probe
	for mode: InputRouter.Mode in [InputRouter.Mode.FLIGHT, InputRouter.Mode.TURRET]:
		_router.set_mode(mode)
		_last = null
		var _e: bool = _router.emit_tick()
		assert_float(_last.thrust).is_equal(1.0)   # RT = thrust in the flight mappers
		assert_float(_last.pitch).is_greater(0.9)  # LS up = nose up
		assert_float(_last.yaw).is_less(0.0)       # RB = yaw right
	_router.set_mode(InputRouter.Mode.PEEK)
	var _p: bool = _router.emit_tick()
	assert_float(_last.thrust).is_equal(1.0)
	assert_float(_last.pitch).is_equal(0.0)
	assert_float(_last.yaw).is_equal(0.0)
	assert_int(_last.buttons).is_equal(0)
	assert_bool(_intents.is_empty()).is_true()   # no FREE_LOOK outside GROUND


func test_flight_mouse_motion_still_feeds_the_flight_mapper() -> void:
	_become_kbm()
	_router.set_mode(InputRouter.Mode.FLIGHT)
	var m: InputEventMouseMotion = InputEventMouseMotion.new()
	m.relative = Vector2(0.0, -100.0)
	_router.route_event(m, 10)
	var _e: bool = _router.emit_tick()
	assert_float(_last.pitch).is_greater(0.0)
