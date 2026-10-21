extends GdUnitTestSuite
## Unit tests for input/gesture_intents.gd: Gesture -> Intent mapping of 06 s3.3 (Tactical and Commander touch column).


func _g(kind: int, phase: int = Gesture.Phase.BEGIN) -> Gesture:
	var g: Gesture = Gesture.new()
	g.kind = kind
	g.phase = phase
	g.pos = Vector2(10, 20)
	g.origin = Vector2(5, 6)
	return g


func _kind(r: Dictionary) -> String:
	return String(r[&"kind"] as StringName)


func _payload(r: Dictionary) -> Dictionary:
	return r[&"payload"] as Dictionary


func test_tap_is_select() -> void:
	var r: Dictionary = GestureIntents.rts_intent(_g(Gesture.Kind.TAP))
	assert_str(_kind(r)).is_equal(String(Intents.SELECT))
	assert_vector(_payload(r)[Intents.K_POS] as Vector2).is_equal(Vector2(10, 20))
	assert_bool(_payload(r)[Intents.K_ADD] as bool).is_false()


func test_double_tap_toggles_camera_tier() -> void:
	var r: Dictionary = GestureIntents.rts_intent(_g(Gesture.Kind.DOUBLE_TAP))
	assert_str(_kind(r)).is_equal(String(Intents.CAM_TIER_TOGGLE))
	assert_vector(_payload(r)[Intents.K_POS] as Vector2).is_equal(Vector2(10, 20))


func test_long_press_release_in_place_adds_to_selection() -> void:
	var r: Dictionary = GestureIntents.rts_intent(_g(Gesture.Kind.LONG_PRESS, Gesture.Phase.END))
	assert_str(_kind(r)).is_equal(String(Intents.SELECT))
	assert_bool(_payload(r)[Intents.K_ADD] as bool).is_true()


func test_long_press_begin_emits_nothing() -> void:
	assert_dict(GestureIntents.rts_intent(_g(Gesture.Kind.LONG_PRESS))).is_empty()


func test_plain_drag_grabs_the_globe() -> void:
	var r: Dictionary = GestureIntents.rts_intent(_g(Gesture.Kind.DRAG, Gesture.Phase.UPDATE))
	assert_str(_kind(r)).is_equal(String(Intents.CAM_PAN_GRAB))
	assert_vector(_payload(r)[Intents.K_FROM] as Vector2).is_equal(Vector2(5, 6))
	assert_vector(_payload(r)[Intents.K_TO] as Vector2).is_equal(Vector2(10, 20))
	assert_bool(_payload(r)[Intents.K_ON] as bool).is_true()


func test_drag_end_releases_the_grab() -> void:
	var r: Dictionary = GestureIntents.rts_intent(_g(Gesture.Kind.DRAG, Gesture.Phase.END))
	assert_bool(_payload(r)[Intents.K_ON] as bool).is_false()


func test_held_drag_is_a_box_select() -> void:
	var g: Gesture = _g(Gesture.Kind.DRAG, Gesture.Phase.UPDATE)
	g.held = true
	var r: Dictionary = GestureIntents.rts_intent(g)
	assert_str(_kind(r)).is_equal(String(Intents.SELECT_BOX))
	var rect: Rect2 = _payload(r)[Intents.K_RECT] as Rect2
	assert_bool(rect.is_equal_approx(Rect2(5, 6, 5, 14))).is_true()
	assert_bool(_payload(r)[Intents.K_ON] as bool).is_true()


func test_fling_is_pan_velocity() -> void:
	var g: Gesture = _g(Gesture.Kind.FLING)
	g.vel = Vector2(300, -100)
	var r: Dictionary = GestureIntents.rts_intent(g)
	assert_str(_kind(r)).is_equal(String(Intents.CAM_PAN_VEL))
	assert_vector(_payload(r)[Intents.K_VEL] as Vector2).is_equal(Vector2(300, -100))


func test_pinch_is_zoom_with_anchor() -> void:
	var g: Gesture = _g(Gesture.Kind.PINCH, Gesture.Phase.UPDATE)
	g.value = 0.2
	var r: Dictionary = GestureIntents.rts_intent(g)
	assert_str(_kind(r)).is_equal(String(Intents.CAM_ZOOM))
	assert_float(_payload(r)[Intents.K_LOG_DELTA] as float).is_equal(0.2)
	assert_vector(_payload(r)[Intents.K_ANCHOR] as Vector2).is_equal(Vector2(10, 20))


func test_twist_is_rotate() -> void:
	var g: Gesture = _g(Gesture.Kind.TWIST, Gesture.Phase.UPDATE)
	g.value = -0.3
	var r: Dictionary = GestureIntents.rts_intent(g)
	assert_str(_kind(r)).is_equal(String(Intents.CAM_ROTATE))
	assert_float(_payload(r)[Intents.K_RAD] as float).is_equal(-0.3)


func test_two_finger_drag_is_tilt() -> void:
	var g: Gesture = _g(Gesture.Kind.TWO_FINGER_DRAG, Gesture.Phase.UPDATE)
	g.delta = Vector2(1, 8)
	var r: Dictionary = GestureIntents.rts_intent(g)
	assert_str(_kind(r)).is_equal(String(Intents.CAM_TILT))
	assert_vector(_payload(r)[Intents.K_VEC] as Vector2).is_equal(Vector2(1, 8))


func test_end_phase_of_multi_gestures_emits_nothing() -> void:
	assert_dict(GestureIntents.rts_intent(_g(Gesture.Kind.PINCH, Gesture.Phase.END))).is_empty()


func test_flight_kinds_have_no_rts_intent() -> void:
	assert_dict(GestureIntents.rts_intent(_g(Gesture.Kind.FLICK_UP))).is_empty()
	assert_dict(GestureIntents.rts_intent(_g(Gesture.Kind.FIRE_HOLD))).is_empty()
