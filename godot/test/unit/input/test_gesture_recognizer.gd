extends GdUnitTestSuite
## Unit tests for input/gesture_recognizer.gd (06 s2.3, s3.1, s3.3, s3.5): synthetic touch events, time driven by
## the explicit now_ms argument. UX-04 acceptance: tap, double tap, long press 0.35 s, drag, pinch, twist,
## two-finger drag, flick; no false pinch on a two-finger drag.

var _g: GestureRecognizer
var _pos: Dictionary = {}


func before_test() -> void:
	_g = GestureRecognizer.new()
	_pos.clear()


func _down(idx: int, p: Vector2, t: int) -> Array[Gesture]:
	var e: InputEventScreenTouch = InputEventScreenTouch.new()
	e.index = idx
	e.pressed = true
	e.position = p
	_pos[idx] = p
	return _g.feed(e, t)


func _up(idx: int, t: int) -> Array[Gesture]:
	var e: InputEventScreenTouch = InputEventScreenTouch.new()
	e.index = idx
	e.pressed = false
	e.position = _pos[idx] as Vector2
	return _g.feed(e, t)


func _move(idx: int, p: Vector2, t: int) -> Array[Gesture]:
	var e: InputEventScreenDrag = InputEventScreenDrag.new()
	e.index = idx
	e.position = p
	e.relative = p - (_pos[idx] as Vector2)
	_pos[idx] = p
	return _g.feed(e, t)


func _kinds(gs: Array[Gesture]) -> Array[int]:
	var out: Array[int] = []
	for g: Gesture in gs:
		out.append(g.kind)
	return out


func _count(gs: Array[Gesture], kind: int) -> int:
	return _kinds(gs).count(kind)


func _sum_value(gs: Array[Gesture], kind: int) -> float:
	var total: float = 0.0
	for g: Gesture in gs:
		if g.kind == kind and g.phase != Gesture.Phase.END:
			total += g.value
	return total


func test_tap_emits_on_release() -> void:
	assert_array(_down(0, Vector2(100, 100), 0)).is_empty()
	var out: Array[Gesture] = _up(0, 100)
	assert_array(_kinds(out)).is_equal([Gesture.Kind.TAP])
	assert_vector(out[0].pos).is_equal(Vector2(100, 100))


func test_small_wobble_is_still_a_tap() -> void:
	var _a: Array[Gesture] = _down(0, Vector2(100, 100), 0)
	var _b: Array[Gesture] = _move(0, Vector2(104, 103), 50)
	assert_array(_kinds(_up(0, 120))).is_equal([Gesture.Kind.TAP])


func test_double_tap_replaces_second_tap() -> void:
	var _a: Array[Gesture] = _down(0, Vector2(100, 100), 0)
	var first: Array[Gesture] = _up(0, 80)
	var _b: Array[Gesture] = _down(0, Vector2(102, 100), 200)
	var second: Array[Gesture] = _up(0, 260)
	assert_array(_kinds(first)).is_equal([Gesture.Kind.TAP])
	assert_array(_kinds(second)).is_equal([Gesture.Kind.DOUBLE_TAP])


func test_slow_second_tap_is_a_plain_tap() -> void:
	var _a: Array[Gesture] = _down(0, Vector2(100, 100), 0)
	var _b: Array[Gesture] = _up(0, 80)
	var _c: Array[Gesture] = _down(0, Vector2(100, 100), 600)
	assert_array(_kinds(_up(0, 650))).is_equal([Gesture.Kind.TAP])


func test_far_second_tap_is_a_plain_tap() -> void:
	var _a: Array[Gesture] = _down(0, Vector2(100, 100), 0)
	var _b: Array[Gesture] = _up(0, 80)
	var _c: Array[Gesture] = _down(0, Vector2(400, 100), 200)
	assert_array(_kinds(_up(0, 250))).is_equal([Gesture.Kind.TAP])


func test_third_tap_is_not_a_double_tap() -> void:
	var _a: Array[Gesture] = _down(0, Vector2(100, 100), 0)
	var _b: Array[Gesture] = _up(0, 50)
	var _c: Array[Gesture] = _down(0, Vector2(100, 100), 150)
	var _d: Array[Gesture] = _up(0, 200)
	var _e: Array[Gesture] = _down(0, Vector2(100, 100), 300)
	assert_array(_kinds(_up(0, 350))).is_equal([Gesture.Kind.TAP])


func test_long_press_fires_at_0_35_s_via_poll() -> void:
	var _a: Array[Gesture] = _down(0, Vector2(300, 200), 0)
	assert_array(_g.poll(349)).is_empty()
	var out: Array[Gesture] = _g.poll(350)
	assert_array(_kinds(out)).is_equal([Gesture.Kind.LONG_PRESS])
	assert_int(out[0].phase).is_equal(Gesture.Phase.BEGIN)
	assert_array(_g.poll(900)).is_empty()   # once only


func test_long_press_fires_from_the_next_event_too() -> void:
	var _a: Array[Gesture] = _down(0, Vector2(300, 200), 0)
	var out: Array[Gesture] = _move(0, Vector2(302, 200), 400)
	assert_int(_count(out, Gesture.Kind.LONG_PRESS)).is_equal(1)


func test_long_press_release_ends_without_tap() -> void:
	var _a: Array[Gesture] = _down(0, Vector2(300, 200), 0)
	var _b: Array[Gesture] = _g.poll(400)
	var out: Array[Gesture] = _up(0, 500)
	assert_array(_kinds(out)).is_equal([Gesture.Kind.LONG_PRESS])
	assert_int(out[0].phase).is_equal(Gesture.Phase.END)


func test_moving_finger_cancels_long_press() -> void:
	var _a: Array[Gesture] = _down(0, Vector2(300, 200), 0)
	var _b: Array[Gesture] = _move(0, Vector2(340, 200), 100)
	assert_int(_count(_g.poll(500), Gesture.Kind.LONG_PRESS)).is_equal(0)


func test_drag_begins_after_slop_then_updates_and_ends() -> void:
	var _a: Array[Gesture] = _down(0, Vector2(100, 100), 0)
	var small: Array[Gesture] = _move(0, Vector2(105, 100), 20)
	assert_array(small).is_empty()
	var begin: Array[Gesture] = _move(0, Vector2(130, 100), 40)
	assert_array(_kinds(begin)).is_equal([Gesture.Kind.DRAG])
	assert_int(begin[0].phase).is_equal(Gesture.Phase.BEGIN)
	assert_vector(begin[0].origin).is_equal(Vector2(100, 100))
	var upd: Array[Gesture] = _move(0, Vector2(150, 110), 60)
	assert_int(upd[0].phase).is_equal(Gesture.Phase.UPDATE)
	assert_vector(upd[0].delta).is_equal(Vector2(20, 10))
	var _pause: Array[Gesture] = _move(0, Vector2(150, 110), 300)
	var end: Array[Gesture] = _up(0, 400)
	assert_array(_kinds(end)).is_equal([Gesture.Kind.DRAG])
	assert_int(end[0].phase).is_equal(Gesture.Phase.END)


func test_fast_release_after_drag_flings() -> void:
	var _a: Array[Gesture] = _down(0, Vector2(100, 400), 0)
	var _b: Array[Gesture] = _move(0, Vector2(200, 400), 50)
	var _c: Array[Gesture] = _move(0, Vector2(400, 400), 100)
	var end: Array[Gesture] = _up(0, 110)
	assert_int(_count(end, Gesture.Kind.FLING)).is_equal(1)
	for g: Gesture in end:
		if g.kind == Gesture.Kind.FLING:
			assert_float(g.vel.x).is_greater(1000.0)


func test_drag_after_long_press_is_held() -> void:
	var _a: Array[Gesture] = _down(0, Vector2(100, 100), 0)
	var _b: Array[Gesture] = _g.poll(400)
	var out: Array[Gesture] = _move(0, Vector2(160, 140), 450)
	assert_int(out[0].kind).is_equal(Gesture.Kind.DRAG)
	assert_bool(out[0].held).is_true()


func test_pinch_out_reports_positive_log_ratio() -> void:
	var _a: Array[Gesture] = _down(0, Vector2(500, 300), 0)
	var _b: Array[Gesture] = _down(1, Vector2(600, 300), 10)
	var first: Array[Gesture] = _move(0, Vector2(450, 300), 40)
	var out: Array[Gesture] = first + _move(1, Vector2(650, 300), 50)
	assert_int(_count(out, Gesture.Kind.PINCH)).is_greater(0)
	assert_float(_sum_value(out, Gesture.Kind.PINCH)).is_greater(0.0)
	assert_int(_count(out, Gesture.Kind.TWIST)).is_equal(0)
	assert_int(_count(out, Gesture.Kind.TWO_FINGER_DRAG)).is_equal(0)


func test_pinch_in_reports_negative_log_ratio() -> void:
	var _a: Array[Gesture] = _down(0, Vector2(400, 300), 0)
	var _b: Array[Gesture] = _down(1, Vector2(700, 300), 10)
	var first: Array[Gesture] = _move(0, Vector2(450, 300), 40)
	var out: Array[Gesture] = first + _move(1, Vector2(650, 300), 50)
	assert_float(_sum_value(out, Gesture.Kind.PINCH)).is_less(0.0)


func test_two_finger_drag_never_pinches() -> void:
	var _a: Array[Gesture] = _down(0, Vector2(500, 300), 0)
	var _b: Array[Gesture] = _down(1, Vector2(600, 300), 10)
	var all: Array[Gesture] = []
	for step: int in range(1, 9):
		var dy: float = 12.0 * float(step)
		all.append_array(_move(0, Vector2(500, 300 + dy), 10 + step * 16))
		all.append_array(_move(1, Vector2(600, 300 + dy), 10 + step * 16))
	assert_int(_count(all, Gesture.Kind.PINCH)).is_equal(0)
	assert_int(_count(all, Gesture.Kind.TWIST)).is_equal(0)
	assert_int(_count(all, Gesture.Kind.TWO_FINGER_DRAG)).is_greater(0)
	var sum: Vector2 = Vector2.ZERO
	for g: Gesture in all:
		if g.kind == Gesture.Kind.TWO_FINGER_DRAG and g.phase != Gesture.Phase.END:
			sum += g.delta
	assert_float(sum.y).is_greater(50.0)


func test_two_finger_drag_with_jitter_in_spacing_never_pinches() -> void:
	var _a: Array[Gesture] = _down(0, Vector2(500, 300), 0)
	var _b: Array[Gesture] = _down(1, Vector2(600, 300), 10)
	var all: Array[Gesture] = []
	for step: int in range(1, 9):
		var dy: float = 12.0 * float(step)
		var wob: float = 3.0 if step % 2 == 0 else -3.0
		all.append_array(_move(0, Vector2(500 - wob, 300 + dy), 10 + step * 16))
		all.append_array(_move(1, Vector2(600 + wob, 300 + dy), 10 + step * 16))
	assert_int(_count(all, Gesture.Kind.PINCH)).is_equal(0)


func test_twist_reports_signed_angle() -> void:
	var _a: Array[Gesture] = _down(0, Vector2(500, 300), 0)
	var _b: Array[Gesture] = _down(1, Vector2(700, 300), 10)
	var all: Array[Gesture] = []
	for step: int in range(1, 7):
		var a: float = 0.12 * float(step)
		var off: Vector2 = Vector2(cos(a), sin(a)) * 100.0
		all.append_array(_move(0, Vector2(600, 300) - off, 10 + step * 16))
		all.append_array(_move(1, Vector2(600, 300) + off, 10 + step * 16))
	assert_int(_count(all, Gesture.Kind.TWIST)).is_greater(0)
	assert_int(_count(all, Gesture.Kind.PINCH)).is_equal(0)
	assert_float(_sum_value(all, Gesture.Kind.TWIST)).is_equal_approx(0.72, 0.05)


func test_second_finger_cancels_single_finger_gestures() -> void:
	var _a: Array[Gesture] = _down(0, Vector2(300, 200), 0)
	var _b: Array[Gesture] = _down(1, Vector2(400, 200), 100)
	assert_int(_count(_g.poll(600), Gesture.Kind.LONG_PRESS)).is_equal(0)
	var _c: Array[Gesture] = _up(1, 700)
	assert_int(_count(_up(0, 750), Gesture.Kind.TAP)).is_equal(0)


func test_multi_touch_lift_emits_end_once() -> void:
	var _a: Array[Gesture] = _down(0, Vector2(500, 300), 0)
	var _b: Array[Gesture] = _down(1, Vector2(600, 300), 10)
	var _c: Array[Gesture] = _move(0, Vector2(440, 300), 40)
	var _d: Array[Gesture] = _move(1, Vector2(660, 300), 50)
	var end: Array[Gesture] = _up(1, 100)
	assert_int(_count(end, Gesture.Kind.PINCH)).is_equal(1)
	assert_int(end[0].phase).is_equal(Gesture.Phase.END)
	assert_array(_up(0, 120)).is_empty()


func test_flick_up_in_stick_zone_fires_once() -> void:
	_g.stick_zone = Rect2(0, 400, 300, 300)
	var _a: Array[Gesture] = _down(0, Vector2(150, 600), 0)
	var _b: Array[Gesture] = _move(0, Vector2(150, 580), 16)
	var _c: Array[Gesture] = _move(0, Vector2(150, 540), 32)
	var out: Array[Gesture] = _move(0, Vector2(150, 480), 48)
	assert_int(_count(out, Gesture.Kind.FLICK_UP)).is_equal(1)
	var more: Array[Gesture] = _move(0, Vector2(150, 400), 64)
	assert_int(_count(more, Gesture.Kind.FLICK_UP)).is_equal(0)


func test_slow_upward_travel_is_not_a_flick() -> void:
	_g.stick_zone = Rect2(0, 400, 300, 300)
	var _a: Array[Gesture] = _down(0, Vector2(150, 690), 0)
	var all: Array[Gesture] = []
	for step: int in range(1, 30):   # 87 du over 0.46 s: slow
		all.append_array(_move(0, Vector2(150, 690 - 3.0 * float(step)), step * 16))
	assert_int(_count(all, Gesture.Kind.FLICK_UP)).is_equal(0)


func test_travel_over_longer_than_0_2_s_is_not_a_flick() -> void:
	_g.stick_zone = Rect2(0, 400, 300, 300)
	var _a: Array[Gesture] = _down(0, Vector2(150, 600), 0)
	var _b: Array[Gesture] = _move(0, Vector2(150, 560), 20)   # fast burst, 40 du
	var out: Array[Gesture] = _move(0, Vector2(150, 520), 300)   # the burst is outside the 0.2 s window
	assert_int(_count(out, Gesture.Kind.FLICK_UP)).is_equal(0)


func test_downward_flick_is_not_flick_up() -> void:
	_g.stick_zone = Rect2(0, 400, 300, 300)
	var _a: Array[Gesture] = _down(0, Vector2(150, 450), 0)
	var out: Array[Gesture] = _move(0, Vector2(150, 600), 30)
	assert_int(_count(out, Gesture.Kind.FLICK_UP)).is_equal(0)


func test_flick_outside_stick_zone_is_ignored() -> void:
	_g.stick_zone = Rect2(0, 400, 300, 300)
	var _a: Array[Gesture] = _down(0, Vector2(900, 600), 0)
	var out: Array[Gesture] = _move(0, Vector2(900, 400), 30)
	assert_int(_count(out, Gesture.Kind.FLICK_UP)).is_equal(0)


func test_no_stick_zone_means_no_flick() -> void:
	var _a: Array[Gesture] = _down(0, Vector2(150, 600), 0)
	var out: Array[Gesture] = _move(0, Vector2(150, 400), 30)
	assert_int(_count(out, Gesture.Kind.FLICK_UP)).is_equal(0)


func test_fire_hold_after_0_5_s_in_fire_zone() -> void:
	_g.fire_zone = Rect2(1000, 500, 200, 200)
	var _a: Array[Gesture] = _down(0, Vector2(1100, 600), 0)
	assert_array(_g.poll(499)).is_empty()
	var out: Array[Gesture] = _g.poll(500)
	assert_array(_kinds(out)).is_equal([Gesture.Kind.FIRE_HOLD])
	assert_int(out[0].phase).is_equal(Gesture.Phase.BEGIN)
	var end: Array[Gesture] = _up(0, 800)
	assert_array(_kinds(end)).is_equal([Gesture.Kind.FIRE_HOLD])
	assert_int(end[0].phase).is_equal(Gesture.Phase.END)


func test_fire_zone_press_has_no_generic_long_press() -> void:
	_g.fire_zone = Rect2(1000, 500, 200, 200)
	var _a: Array[Gesture] = _down(0, Vector2(1100, 600), 0)
	var out: Array[Gesture] = _g.poll(400)
	assert_int(_count(out, Gesture.Kind.LONG_PRESS)).is_equal(0)


func test_short_fire_press_has_no_fire_hold() -> void:
	_g.fire_zone = Rect2(1000, 500, 200, 200)
	var _a: Array[Gesture] = _down(0, Vector2(1100, 600), 0)
	var out: Array[Gesture] = _up(0, 200)
	assert_int(_count(out, Gesture.Kind.FIRE_HOLD)).is_equal(0)


func test_emulated_device_events_are_ignored() -> void:
	var e: InputEventScreenTouch = InputEventScreenTouch.new()
	e.device = InputEvent.DEVICE_ID_EMULATION
	e.pressed = true
	e.position = Vector2(10, 10)
	assert_array(_g.feed(e, 0)).is_empty()
	assert_int(_g.active_touches()).is_equal(0)


func test_non_touch_events_are_ignored() -> void:
	var e: InputEventMouseMotion = InputEventMouseMotion.new()
	assert_array(_g.feed(e, 0)).is_empty()


func test_reset_forgets_fingers() -> void:
	var _a: Array[Gesture] = _down(0, Vector2(10, 10), 0)
	_g.reset()
	assert_int(_g.active_touches()).is_equal(0)
	assert_array(_g.poll(1000)).is_empty()
