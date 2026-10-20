extends GdUnitTestSuite
## Unit tests for InputRouter sampling the flight mappers by active class (06 s2.3, s3.5).

var _router: InputRouter
var _last: PilotInput


func before_test() -> void:
	_router = auto_free(InputRouter.new()) as InputRouter
	_last = null
	_router.pilot_input.connect(func(p: PilotInput) -> void: _last = p)


func test_gamepad_class_samples_gamepad_mapper() -> void:
	var b: InputEventJoypadButton = InputEventJoypadButton.new()
	b.pressed = true
	_router.route_event(b, 0)
	var st: PadState = PadState.new()
	st.right_trigger = 1.0
	st.a = true
	_router.gamepad_mapper.poller = func() -> PadState: return st
	_router.set_mode(InputRouter.Mode.FLIGHT)
	var _e: bool = _router.emit_tick()
	assert_float(_last.thrust).is_equal(1.0)
	assert_int(_last.buttons & PilotInput.FIRE1).is_equal(PilotInput.FIRE1)


func test_pointer_class_samples_kbm_mapper() -> void:
	var k: InputEventMouseButton = InputEventMouseButton.new()
	k.pressed = true
	_router.route_event(k, 0)
	var st: KbmState = KbmState.new()
	st.w = true
	_router.kbm_mapper.poller = func() -> KbmState: return st
	_router.set_mode(InputRouter.Mode.FLIGHT)
	var _e: bool = _router.emit_tick()
	assert_float(_last.thrust).is_greater(0.0)


func test_touch_class_is_neutral_until_touch_mapper() -> void:
	var t: InputEventScreenTouch = InputEventScreenTouch.new()
	t.pressed = true
	_router.route_event(t, 0)
	_router.set_mode(InputRouter.Mode.FLIGHT)
	var _e: bool = _router.emit_tick()
	assert_float(_last.thrust).is_equal(0.0)
	assert_int(_last.buttons).is_equal(0)


func test_sampler_overrides_mappers() -> void:
	var raw: PilotInput = PilotInput.new()
	raw.thrust = 0.3
	_router.sampler = func() -> PilotInput: return raw
	_router.set_mode(InputRouter.Mode.FLIGHT)
	var _e: bool = _router.emit_tick()
	assert_float(_last.thrust).is_equal(0.3)


func test_mouse_motion_feeds_kbm_mapper_only_in_flight() -> void:
	var m: InputEventMouseMotion = InputEventMouseMotion.new()
	m.relative = Vector2(100.0, 0.0)
	_router.route_event(m, 0)   # MENU: dropped
	var none: PilotInput = _router.kbm_mapper.map(KbmState.new(), 1.0 / 30.0)
	assert_float(none.roll).is_equal(0.0)
	_router.set_mode(InputRouter.Mode.FLIGHT)
	_router.route_event(m, 1000)
	var sampled: PilotInput = _router.kbm_mapper.sample(1.0 / 30.0)
	assert_float(sampled.roll).is_greater(0.0)
