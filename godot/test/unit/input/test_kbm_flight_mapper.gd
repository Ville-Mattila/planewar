extends GdUnitTestSuite
## Unit tests for input/kbm_flight_mapper.gd (06 s3.1, s3.5): power-key ramp 4/s, lever mode, mouse stick, buttons.

const DT: float = 1.0 / 30.0

var _m: KbmFlightMapper


func before_test() -> void:
	_m = KbmFlightMapper.new()


func test_neutral_state_is_neutral() -> void:
	var o: PilotInput = _m.map(KbmState.new(), DT)
	assert_float(o.thrust).is_equal(0.0)
	assert_float(o.roll).is_equal(0.0)
	assert_float(o.yaw).is_equal(0.0)
	assert_int(o.buttons).is_equal(0)


func test_power_key_ramps_up_at_4_per_second() -> void:
	var st: KbmState = KbmState.new()
	st.w = true
	assert_float(_m.map(st, 0.1).thrust).is_equal_approx(0.4, 0.0001)
	assert_float(_m.map(st, 0.1).thrust).is_equal_approx(0.8, 0.0001)
	assert_float(_m.map(st, 0.1).thrust).is_equal(1.0)


func test_power_key_full_ramp_takes_quarter_second() -> void:
	var st: KbmState = KbmState.new()
	st.w = true
	var o: PilotInput = null
	for i in 7:
		o = _m.map(st, DT)
	assert_float(o.thrust).is_less(1.0)
	o = _m.map(st, DT)
	assert_float(o.thrust).is_equal(1.0)


func test_power_key_release_ramps_down_at_4_per_second() -> void:
	var st: KbmState = KbmState.new()
	st.w = true
	var _o: PilotInput = _m.map(st, 1.0)
	st.w = false
	assert_float(_m.map(st, 0.1).thrust).is_equal_approx(0.6, 0.0001)
	assert_float(_m.map(st, 1.0).thrust).is_equal(0.0)


func test_power_key_s_is_brake_while_held() -> void:
	var st: KbmState = KbmState.new()
	st.s = true
	assert_int(_m.map(st, DT).buttons).is_equal(PilotInput.BRAKE)
	st.s = false
	assert_int(_m.map(st, DT).buttons).is_equal(0)


func test_lever_steps_quarter_and_is_sticky() -> void:
	_m.throttle_mode = KbmFlightMapper.ThrottleMode.LEVER
	var st: KbmState = KbmState.new()
	st.w = true
	assert_float(_m.map(st, DT).thrust).is_equal(0.25)
	assert_float(_m.map(st, DT).thrust).is_equal(0.25)   # held does not repeat
	st.w = false
	assert_float(_m.map(st, DT).thrust).is_equal(0.25)   # sticky
	st.w = true
	assert_float(_m.map(st, DT).thrust).is_equal(0.5)


func test_lever_caps_at_one_and_steps_down() -> void:
	_m.throttle_mode = KbmFlightMapper.ThrottleMode.LEVER
	var st: KbmState = KbmState.new()
	for i in 6:
		st.w = true
		var _a: PilotInput = _m.map(st, DT)
		st.w = false
		var _b: PilotInput = _m.map(st, DT)
	assert_float(_m.current_thrust()).is_equal(1.0)
	st.s = true
	var o: PilotInput = _m.map(st, DT)
	assert_float(o.thrust).is_equal(0.75)
	assert_int(o.buttons & PilotInput.BRAKE).is_equal(0)


func test_lever_s_at_zero_brakes_while_held() -> void:
	_m.throttle_mode = KbmFlightMapper.ThrottleMode.LEVER
	var st: KbmState = KbmState.new()
	st.s = true
	var o: PilotInput = _m.map(st, DT)
	assert_int(o.buttons & PilotInput.BRAKE).is_equal(PilotInput.BRAKE)
	assert_float(o.thrust).is_equal(0.0)
	st.s = false
	assert_int(_m.map(st, DT).buttons & PilotInput.BRAKE).is_equal(0)


func test_lever_s_stepping_to_zero_does_not_brake_same_press() -> void:
	_m.throttle_mode = KbmFlightMapper.ThrottleMode.LEVER
	var st: KbmState = KbmState.new()
	st.w = true
	var _o: PilotInput = _m.map(st, DT)
	st.w = false
	st.s = true
	var o: PilotInput = _m.map(st, DT)
	assert_float(o.thrust).is_equal(0.0)
	assert_int(o.buttons & PilotInput.BRAKE).is_equal(0)


func test_mouse_moves_virtual_stick_and_recentres() -> void:
	var st: KbmState = KbmState.new()
	st.mouse_delta = Vector2(40.0, -40.0)
	var o: PilotInput = _m.map(st, DT)
	assert_float(o.roll).is_greater(0.0)
	assert_float(o.pitch).is_greater(0.0)   # mouse up = nose up
	st.mouse_delta = Vector2.ZERO
	var first: float = o.roll
	for i in 30:
		o = _m.map(st, DT)
	assert_float(o.roll).is_less(first * 0.01)


func test_mouse_stick_is_clamped_to_unit() -> void:
	var st: KbmState = KbmState.new()
	st.mouse_delta = Vector2(100000.0, 0.0)
	assert_float(_m.map(st, DT).roll).is_less_equal(1.0)


func test_invert_pitch() -> void:
	_m.invert_pitch = true
	var st: KbmState = KbmState.new()
	st.mouse_delta = Vector2(0.0, -40.0)
	assert_float(_m.map(st, DT).pitch).is_less(0.0)


func test_yaw_keys() -> void:
	var st: KbmState = KbmState.new()
	st.q = true
	assert_float(_m.map(st, DT).yaw).is_equal(1.0)
	st.q = false
	st.e = true
	assert_float(_m.map(st, DT).yaw).is_equal(-1.0)
	st.q = true
	assert_float(_m.map(st, DT).yaw).is_equal(0.0)


func test_hold_buttons_and_edge_buttons() -> void:
	var st: KbmState = KbmState.new()
	st.lmb = true
	st.rmb = true
	st.f = true
	st.shift = true
	st.space = true
	st.r = true
	var held: int = PilotInput.FIRE1 | PilotInput.FIRE2 | PilotInput.DOCK
	var edges: int = PilotInput.BOOST | PilotInput.FLIP | PilotInput.RELEASE
	assert_int(_m.map(st, DT).buttons).is_equal(held | edges)
	assert_int(_m.map(st, DT).buttons).is_equal(held)


func test_sample_uses_poller() -> void:
	var st: KbmState = KbmState.new()
	st.w = true
	_m.poller = func() -> KbmState: return st
	assert_float(_m.sample(0.1).thrust).is_equal_approx(0.4, 0.0001)


func test_add_mouse_motion_is_consumed_by_sample() -> void:
	_m.add_mouse_motion(Vector2(100.0, 0.0))
	assert_float(_m.sample(DT).roll).is_greater(0.0)
	assert_float(_m.sample(DT).roll).is_less(0.5)
