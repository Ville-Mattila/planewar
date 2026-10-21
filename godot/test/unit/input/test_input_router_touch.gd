extends GdUnitTestSuite
## Unit tests for the InputRouter touch path (UX-04): TOUCH samples TouchFlightMapper, flick -> FLIP, FIRE hold ->
## WING_RADIAL, RTS gestures -> intents. Time is driven by the now_ms arguments.

var _router: InputRouter
var _last: PilotInput
var _intents: Array[Dictionary] = []


func before_test() -> void:
	_router = auto_free(InputRouter.new()) as InputRouter
	_last = null
	_intents.clear()
	_router.pilot_input.connect(func(p: PilotInput) -> void: _last = p)
	_router.intent.connect(func(k: StringName, p: Dictionary) -> void: _intents.append({&"kind": k, &"payload": p}))


func _touch(idx: int, pressed: bool, p: Vector2, t: int) -> void:
	var e: InputEventScreenTouch = InputEventScreenTouch.new()
	e.index = idx
	e.pressed = pressed
	e.position = p
	_router.route_event(e, t)


func _drag(idx: int, p: Vector2, rel: Vector2, t: int) -> void:
	var e: InputEventScreenDrag = InputEventScreenDrag.new()
	e.index = idx
	e.position = p
	e.relative = rel
	_router.route_event(e, t)


func _kinds() -> Array[StringName]:
	var out: Array[StringName] = []
	for i: Dictionary in _intents:
		out.append(i[&"kind"] as StringName)
	return out


func test_touch_class_samples_touch_mapper() -> void:
	_touch(0, true, Vector2(5, 5), 0)
	var st: TouchState = TouchState.new()
	st.throttle = 0.7
	st.fire1 = true
	_router.touch_mapper.poller = func() -> TouchState: return st
	_router.set_mode(InputRouter.Mode.FLIGHT)
	var _e: bool = _router.emit_tick()
	assert_float(_last.thrust).is_equal(0.7)
	assert_int(_last.buttons & PilotInput.FIRE1).is_equal(PilotInput.FIRE1)


func test_flick_up_in_stick_zone_sends_flip_for_one_tick() -> void:
	_router.set_mode(InputRouter.Mode.FLIGHT)
	_router.gestures.stick_zone = Rect2(0, 400, 300, 300)
	_touch(0, true, Vector2(150, 600), 0)
	_drag(0, Vector2(150, 560), Vector2(0, -40), 16)
	_drag(0, Vector2(150, 480), Vector2(0, -80), 32)
	_router.touch_mapper.poller = func() -> TouchState: return TouchState.new()
	var _e: bool = _router.emit_tick()
	assert_int(_last.buttons & PilotInput.FLIP).is_equal(PilotInput.FLIP)
	var _e2: bool = _router.emit_tick()
	assert_int(_last.buttons & PilotInput.FLIP).is_equal(0)


func test_fire_hold_opens_and_closes_wing_radial() -> void:
	_router.set_mode(InputRouter.Mode.FLIGHT)
	_router.wing_radial_allowed = true
	_router.gestures.fire_zone = Rect2(1000, 500, 200, 200)
	_touch(0, true, Vector2(1100, 600), 0)
	_router.poll_gestures(500)
	assert_array(_kinds()).is_equal([Intents.WING_RADIAL])
	assert_bool((_intents[0][&"payload"] as Dictionary)[Intents.K_OPEN] as bool).is_true()
	_touch(0, false, Vector2(1100, 600), 700)
	assert_bool((_intents[1][&"payload"] as Dictionary)[Intents.K_OPEN] as bool).is_false()


func test_fire_hold_is_suppressed_when_hostile_near() -> void:
	_router.set_mode(InputRouter.Mode.FLIGHT)
	_router.wing_radial_allowed = false
	_router.gestures.fire_zone = Rect2(1000, 500, 200, 200)
	_touch(0, true, Vector2(1100, 600), 0)
	_router.poll_gestures(600)
	_touch(0, false, Vector2(1100, 600), 800)
	assert_array(_kinds()).is_empty()


func test_rts_tap_emits_select() -> void:
	_router.set_mode(InputRouter.Mode.RTS)
	_touch(0, true, Vector2(200, 200), 0)
	_touch(0, false, Vector2(200, 200), 80)
	assert_array(_kinds()).is_equal([Intents.SELECT])


func test_rts_long_press_then_drag_emits_box_select() -> void:
	_router.set_mode(InputRouter.Mode.RTS)
	_touch(0, true, Vector2(200, 200), 0)
	_router.poll_gestures(400)
	_drag(0, Vector2(260, 260), Vector2(60, 60), 450)
	_touch(0, false, Vector2(260, 260), 500)
	assert_bool(_kinds().has(Intents.SELECT_BOX)).is_true()
	assert_bool(_kinds().has(Intents.CAM_PAN_GRAB)).is_false()


func test_rts_pinch_emits_zoom() -> void:
	_router.set_mode(InputRouter.Mode.RTS)
	_touch(0, true, Vector2(500, 300), 0)
	_touch(1, true, Vector2(600, 300), 10)
	_drag(0, Vector2(450, 300), Vector2(-50, 0), 40)
	_drag(1, Vector2(650, 300), Vector2(50, 0), 50)
	assert_bool(_kinds().has(Intents.CAM_ZOOM)).is_true()
	assert_bool(_kinds().has(Intents.CAM_ROTATE)).is_false()


func test_menu_mode_emits_no_gesture_intents() -> void:
	_touch(0, true, Vector2(200, 200), 0)
	_touch(0, false, Vector2(200, 200), 80)
	assert_array(_kinds()).is_empty()


func test_flight_mode_tap_emits_no_intent() -> void:
	_router.set_mode(InputRouter.Mode.FLIGHT)
	_touch(0, true, Vector2(200, 200), 0)
	_touch(0, false, Vector2(200, 200), 80)
	assert_array(_kinds()).is_empty()
