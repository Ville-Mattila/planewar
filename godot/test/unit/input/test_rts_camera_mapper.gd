extends GdUnitTestSuite
## RtsCameraMapper (UX-45): pure event -> CAM_* intent table (06 s3.3 KBM and Gamepad columns). The end-to-end
## pose assertions live in test/unit/app/test_camera_intent_driver.gd.

var _m: RtsCameraMapper


func before_test() -> void:
	_m = RtsCameraMapper.new()


func _key(code: Key, pressed: bool = true) -> Array[Dictionary]:
	var e: InputEventKey = InputEventKey.new()
	e.physical_keycode = code
	e.pressed = pressed
	return _m.feed(e)


func _axis(axis: JoyAxis, v: float) -> Array[Dictionary]:
	var e: InputEventJoypadMotion = InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = v
	return _m.feed(e)


func _kinds(list: Array[Dictionary]) -> Array[StringName]:
	var out: Array[StringName] = []
	for r: Dictionary in list:
		out.append(r[&"kind"] as StringName)
	return out


func test_wheel_up_zooms_in_at_cursor() -> void:
	var e: InputEventMouseButton = InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_WHEEL_UP
	e.pressed = true
	e.position = Vector2(30, 40)
	var r: Array[Dictionary] = _m.feed(e)
	assert_array(_kinds(r)).is_equal([Intents.CAM_ZOOM])
	var p: Dictionary = r[0][&"payload"]
	assert_float(p[Intents.K_LOG_DELTA] as float).is_equal(RtsCameraMapper.WHEEL_LOG_STEP)
	assert_vector(p[Intents.K_ANCHOR] as Vector2).is_equal(Vector2(30, 40))


func test_pan_vel_is_clamped_and_zero_on_release() -> void:
	var _a: Array[Dictionary] = _key(KEY_W)
	var r: Array[Dictionary] = _key(KEY_D)
	var v: Vector2 = r[0][&"payload"][Intents.K_VEL] as Vector2
	assert_float(v.length()).is_equal_approx(1.0, 0.0001)
	assert_float(v.x).is_greater(0.0)
	assert_float(v.y).is_greater(0.0)
	var _b: Array[Dictionary] = _key(KEY_W, false)
	var z: Array[Dictionary] = _key(KEY_D, false)
	assert_vector(z[0][&"payload"][Intents.K_VEL] as Vector2).is_equal(Vector2.ZERO)


func test_unchanged_pan_is_not_resent() -> void:
	var _a: Array[Dictionary] = _key(KEY_W)
	assert_array(_key(KEY_UP)).is_empty()


func test_edge_zone_is_8_du() -> void:
	_m.viewport_size = Vector2(1000, 500)
	var e: InputEventMouseMotion = InputEventMouseMotion.new()
	e.position = Vector2(992, 250)
	assert_array(_kinds(_m.feed(e))).is_equal([Intents.CAM_PAN_VEL])
	e.position = Vector2(991, 250)
	var r1: Array[Dictionary] = _m.feed(e)
	assert_vector(r1[0][&"payload"][Intents.K_VEL] as Vector2).is_equal(Vector2.ZERO)
	e.position = Vector2(992, 250)
	var _r2: Array[Dictionary] = _m.feed(e)
	e.position = Vector2(900, 250)
	var r: Array[Dictionary] = _m.feed(e)
	assert_vector(r[0][&"payload"][Intents.K_VEL] as Vector2).is_equal(Vector2.ZERO)


func test_tab_and_h_and_pad_buttons() -> void:
	assert_array(_kinds(_key(KEY_TAB))).is_equal([Intents.CAM_TIER_TOGGLE])
	assert_array(_kinds(_key(KEY_H))).is_equal([Intents.CAM_HOME])
	var b: InputEventJoypadButton = InputEventJoypadButton.new()
	b.pressed = true
	b.button_index = JOY_BUTTON_BACK
	assert_array(_kinds(_m.feed(b))).is_equal([Intents.CAM_TIER_TOGGLE])
	b.button_index = JOY_BUTTON_LEFT_STICK
	assert_array(_kinds(_m.feed(b))).is_equal([Intents.CAM_HOME])
	b.pressed = false
	assert_array(_m.feed(b)).is_empty()


func test_tick_emits_rotate_tilt_zoom_from_held_input() -> void:
	var _a: Array[Dictionary] = _axis(JOY_AXIS_RIGHT_X, 1.0)
	var _b: Array[Dictionary] = _axis(JOY_AXIS_RIGHT_Y, -1.0)
	var _c: Array[Dictionary] = _axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)
	var r: Array[Dictionary] = _m.tick(0.1)
	assert_array(_kinds(r)).is_equal([Intents.CAM_ROTATE, Intents.CAM_TILT, Intents.CAM_ZOOM])
	assert_float(r[1][&"payload"][Intents.K_VEC].y as float).is_less(0.0)
	assert_float(r[2][&"payload"][Intents.K_LOG_DELTA] as float).is_greater(0.0)


func test_tick_is_empty_when_idle() -> void:
	assert_array(_m.tick(0.1)).is_empty()


func test_reset_clears_held_state() -> void:
	var _a: Array[Dictionary] = _key(KEY_E)
	_m.reset()
	assert_array(_m.tick(0.1)).is_empty()
