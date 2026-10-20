extends GdUnitTestSuite
## Unit tests for input/device_monitor.gd: the 06 s2.4 detection table, emulation, glyphs, layout persistence.

var _m: DeviceMonitor


func before_test() -> void:
	_m = DeviceMonitor.new(InputClass.Kind.POINTER)
	_m.key_bound = func(_e: InputEvent) -> bool: return true


func _touch(pressed: bool) -> InputEventScreenTouch:
	var e: InputEventScreenTouch = InputEventScreenTouch.new()
	e.pressed = pressed
	return e


func _pad_axis(v: float) -> InputEventJoypadMotion:
	var e: InputEventJoypadMotion = InputEventJoypadMotion.new()
	e.axis_value = v
	return e


func _mouse_move(rel: Vector2) -> InputEventMouseMotion:
	var e: InputEventMouseMotion = InputEventMouseMotion.new()
	e.relative = rel
	return e


func test_touch_press_and_drag_count() -> void:
	assert_int(_m.classify(_touch(true), 0)).is_equal(InputClass.Kind.TOUCH)
	assert_int(_m.classify(_touch(false), 0)).is_equal(-1)
	assert_int(_m.classify(InputEventScreenDrag.new(), 0)).is_equal(InputClass.Kind.TOUCH)


func test_gamepad_button_press_only() -> void:
	var b: InputEventJoypadButton = InputEventJoypadButton.new()
	b.pressed = true
	assert_int(_m.classify(b, 0)).is_equal(InputClass.Kind.GAMEPAD)
	b.pressed = false
	assert_int(_m.classify(b, 0)).is_equal(-1)


func test_gamepad_axis_threshold() -> void:
	assert_int(_m.classify(_pad_axis(0.36), 0)).is_equal(InputClass.Kind.GAMEPAD)
	assert_int(_m.classify(_pad_axis(-0.5), 0)).is_equal(InputClass.Kind.GAMEPAD)
	assert_int(_m.classify(_pad_axis(0.35), 0)).is_equal(-1)
	assert_int(_m.classify(_pad_axis(0.1), 0)).is_equal(-1)


func test_mouse_button_press() -> void:
	var e: InputEventMouseButton = InputEventMouseButton.new()
	e.pressed = true
	assert_int(_m.classify(e, 0)).is_equal(InputClass.Kind.POINTER)
	e.pressed = false
	assert_int(_m.classify(e, 0)).is_equal(-1)


func test_emulated_mouse_ignored() -> void:
	var b: InputEventMouseButton = InputEventMouseButton.new()
	b.pressed = true
	b.device = InputEvent.DEVICE_ID_EMULATION
	assert_int(_m.classify(b, 0)).is_equal(-1)
	var mv: InputEventMouseMotion = _mouse_move(Vector2(50, 50))
	mv.device = InputEvent.DEVICE_ID_EMULATION
	assert_int(_m.classify(mv, 0)).is_equal(-1)
	var t: DeviceMonitor = DeviceMonitor.new(InputClass.Kind.TOUCH)
	assert_bool(t.feed(b, 0)).is_false()
	assert_int(t.active_class).is_equal(InputClass.Kind.TOUCH)


func test_mouse_motion_needs_4_du_in_100_ms() -> void:
	assert_int(_m.classify(_mouse_move(Vector2(1, 0)), 1000)).is_equal(-1)
	assert_int(_m.classify(_mouse_move(Vector2(1, 0)), 1050)).is_equal(-1)
	assert_int(_m.classify(_mouse_move(Vector2(3, 0)), 1090)).is_equal(InputClass.Kind.POINTER)


func test_mouse_motion_window_resets() -> void:
	assert_int(_m.classify(_mouse_move(Vector2(3, 0)), 1000)).is_equal(-1)
	assert_int(_m.classify(_mouse_move(Vector2(3, 0)), 1200)).is_equal(-1)


func test_key_press_of_bound_key() -> void:
	var k: InputEventKey = InputEventKey.new()
	k.pressed = true
	assert_int(_m.classify(k, 0)).is_equal(InputClass.Kind.POINTER)
	k.echo = true
	assert_int(_m.classify(k, 0)).is_equal(-1)
	k.echo = false
	k.pressed = false
	assert_int(_m.classify(k, 0)).is_equal(-1)
	_m.key_bound = func(_e: InputEvent) -> bool: return false
	k.pressed = true
	assert_int(_m.classify(k, 0)).is_equal(-1)


func test_feed_switches_class_and_reports_change() -> void:
	assert_bool(_m.feed(_touch(true), 0)).is_true()
	assert_int(_m.active_class).is_equal(InputClass.Kind.TOUCH)
	assert_str(String(_m.glyph_set)).is_equal("kbm")
	assert_bool(_m.feed(_touch(true), 10)).is_false()


func test_gamepad_never_has_kbm_glyphs() -> void:
	var b: InputEventJoypadButton = InputEventJoypadButton.new()
	b.pressed = true
	var _c: bool = _m.feed(b, 0)
	assert_int(_m.active_class).is_equal(InputClass.Kind.GAMEPAD)
	assert_bool(_m.glyph_set != &"kbm").is_true()
	assert_str(String(DeviceMonitor.default_glyphs(InputClass.Kind.GAMEPAD))).is_not_equal("kbm")


func test_glyphs_for_joy_name() -> void:
	assert_str(String(DeviceMonitor.glyphs_for_joy_name("Xbox Series Controller"))).is_equal("xbox")
	assert_str(String(DeviceMonitor.glyphs_for_joy_name("PS5 Controller"))).is_equal("ps")
	assert_str(String(DeviceMonitor.glyphs_for_joy_name("Nintendo Switch Pro"))).is_equal("nintendo")
	assert_str(String(DeviceMonitor.glyphs_for_joy_name("Steam Deck Controller"))).is_equal("deck")
	assert_str(String(DeviceMonitor.glyphs_for_joy_name("Random Pad"))).is_equal("generic")


func test_layout_class_press_is_immediate() -> void:
	var _c: bool = _m.feed(_touch(true), 1000)
	assert_int(_m.layout_class(1000)).is_equal(InputClass.Kind.TOUCH)


func test_layout_class_motion_needs_persistence() -> void:
	var t: DeviceMonitor = DeviceMonitor.new(InputClass.Kind.TOUCH)
	var _c: bool = t.feed(_pad_axis(0.9), 1000)
	assert_int(t.active_class).is_equal(InputClass.Kind.GAMEPAD)
	assert_int(t.layout_class(1100)).is_equal(InputClass.Kind.TOUCH)
	assert_int(t.layout_class(1500)).is_equal(InputClass.Kind.GAMEPAD)
