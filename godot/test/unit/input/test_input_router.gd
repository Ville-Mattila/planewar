extends GdUnitTestSuite
## Unit tests for input/input_router.gd: pilot_input once per tick, only in flight modes (06 s2.3).

var _router: InputRouter
var _count: int
var _last: PilotInput
var _classes: Array[int]


func before_test() -> void:
	_router = auto_free(InputRouter.new()) as InputRouter
	_count = 0
	_last = null
	_classes = []
	_router.pilot_input.connect(_on_pilot)
	_router.input_class_changed.connect(func(k: int) -> void: _classes.append(k))


func _on_pilot(p: PilotInput) -> void:
	_count += 1
	_last = p


func test_priority_is_minus_10() -> void:
	assert_int(_router.process_physics_priority).is_equal(-10)


func test_flight_modes_emit_once_per_tick() -> void:
	for m: InputRouter.Mode in [InputRouter.Mode.FLIGHT, InputRouter.Mode.TURRET, InputRouter.Mode.GROUND, InputRouter.Mode.PEEK]:
		_count = 0
		_router.set_mode(m)
		assert_bool(_router.emit_tick()).is_true()
		assert_int(_count).is_equal(1)
		assert_bool(_router.emit_tick()).is_true()
		assert_int(_count).is_equal(2)


func test_non_flight_modes_never_emit() -> void:
	for m: InputRouter.Mode in [InputRouter.Mode.MENU, InputRouter.Mode.RTS, InputRouter.Mode.PLACEMENT, InputRouter.Mode.TEXT]:
		_router.set_mode(m)
		assert_bool(_router.emit_tick()).is_false()
	assert_int(_count).is_equal(0)


func test_default_mode_is_menu() -> void:
	assert_int(_router.current_mode()).is_equal(InputRouter.Mode.MENU)
	assert_bool(_router.emit_tick()).is_false()


func test_sampler_value_is_emitted() -> void:
	var raw: PilotInput = PilotInput.new()
	raw.thrust = 0.75
	raw.roll = 0.5
	_router.sampler = func() -> PilotInput: return raw
	_router.set_mode(InputRouter.Mode.FLIGHT)
	var _e: bool = _router.emit_tick()
	assert_float(_last.thrust).is_equal(0.75)
	assert_float(_last.roll).is_equal(0.5)


func test_peek_neutralises_axes_keeps_thrust() -> void:
	var raw: PilotInput = PilotInput.new()
	raw.thrust = 0.6
	raw.pitch = 1.0
	raw.yaw = -1.0
	raw.roll = 1.0
	raw.buttons = PilotInput.FIRE1
	_router.sampler = func() -> PilotInput: return raw
	_router.set_mode(InputRouter.Mode.PEEK)
	var _e: bool = _router.emit_tick()
	assert_float(_last.thrust).is_equal(0.6)
	assert_float(_last.pitch).is_equal(0.0)
	assert_float(_last.roll).is_equal(0.0)
	assert_int(_last.buttons).is_equal(0)


func test_class_change_signal_and_emulated_mouse_ignored() -> void:
	var t: InputEventScreenTouch = InputEventScreenTouch.new()
	t.pressed = true
	_router.route_event(t, 0)
	assert_int(_router.input_class()).is_equal(InputClass.Kind.TOUCH)
	assert_int(_classes.size()).is_equal(1)
	var m: InputEventMouseButton = InputEventMouseButton.new()
	m.pressed = true
	m.device = InputEvent.DEVICE_ID_EMULATION
	_router.route_event(m, 10)
	assert_int(_router.input_class()).is_equal(InputClass.Kind.TOUCH)
	assert_int(_classes.size()).is_equal(1)


func test_match_class_lock() -> void:
	assert_int(_router.match_input_class()).is_equal(-1)
	_router.set_match_input_class(InputClass.Kind.GAMEPAD)
	assert_int(_router.match_input_class()).is_equal(InputClass.Kind.GAMEPAD)


func test_glyph_accessor() -> void:
	assert_bool(String(_router.current_glyph_set()) != "").is_true()
