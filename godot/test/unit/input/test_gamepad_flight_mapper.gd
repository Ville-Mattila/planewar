extends GdUnitTestSuite
## Unit tests for input/gamepad_flight_mapper.gd (06 s3.1, s3.5): DIRECT axes, yaw ramp, RT, LT brake, buttons.

const DT: float = 1.0 / 30.0

var _m: GamepadFlightMapper


func before_test() -> void:
	_m = GamepadFlightMapper.new()


func test_neutral_state_is_neutral() -> void:
	var o: PilotInput = _m.map(PadState.new(), DT)
	assert_float(o.thrust).is_equal(0.0)
	assert_float(o.roll).is_equal(0.0)
	assert_float(o.pitch).is_equal(0.0)
	assert_float(o.yaw).is_equal(0.0)
	assert_int(o.buttons).is_equal(0)


func test_dead_zone_swallows_small_stick() -> void:
	var st: PadState = PadState.new()
	st.left_stick = Vector2(0.1, -0.1)
	var o: PilotInput = _m.map(st, DT)
	assert_float(o.roll).is_equal(0.0)
	assert_float(o.pitch).is_equal(0.0)


func test_stick_up_is_nose_up_and_right_is_roll_right() -> void:
	var st: PadState = PadState.new()
	st.left_stick = Vector2(1.0, -1.0)
	var o: PilotInput = _m.map(st, DT)
	assert_float(o.roll).is_greater(0.0)
	assert_float(o.pitch).is_greater(0.0)


func test_invert_pitch_flips_sign() -> void:
	_m.invert_pitch = true
	var st: PadState = PadState.new()
	st.left_stick = Vector2(0.0, -1.0)
	assert_float(_m.map(st, DT).pitch).is_less(0.0)


func test_curve_uses_gamma_1_8() -> void:
	var st: PadState = PadState.new()
	st.left_stick = Vector2(0.575, 0.0)
	assert_float(_m.map(st, DT).roll).is_equal_approx(pow(0.5, 1.8), 0.0001)


func test_bumpers_ramp_yaw_over_015_s() -> void:
	var st: PadState = PadState.new()
	st.lb = true
	var o: PilotInput = _m.map(st, 0.075)
	assert_float(o.yaw).is_equal_approx(0.5, 0.0001)   # LB = nose left = +yaw
	o = _m.map(st, 0.075)
	assert_float(o.yaw).is_equal_approx(1.0, 0.0001)
	st.lb = false
	st.rb = true
	o = _m.map(st, 0.075)
	assert_float(o.yaw).is_equal_approx(0.5, 0.0001)   # 1.0 ramping toward -1


func test_rt_analog_thrust_with_dead_zone() -> void:
	var st: PadState = PadState.new()
	st.right_trigger = 0.04
	assert_float(_m.map(st, DT).thrust).is_equal(0.0)
	st.right_trigger = 1.0
	assert_float(_m.map(st, DT).thrust).is_equal(1.0)
	st.right_trigger = 0.525
	assert_float(_m.map(st, DT).thrust).is_equal_approx(0.5, 0.0001)


func test_lt_above_half_sets_brake() -> void:
	var st: PadState = PadState.new()
	st.left_trigger = 0.5
	assert_int(_m.map(st, DT).buttons & PilotInput.BRAKE).is_equal(0)
	st.left_trigger = 0.51
	assert_int(_m.map(st, DT).buttons & PilotInput.BRAKE).is_equal(PilotInput.BRAKE)
	st.left_trigger = 1.0
	assert_int(_m.map(st, DT).buttons & PilotInput.BRAKE).is_equal(PilotInput.BRAKE)


func test_hold_buttons() -> void:
	var st: PadState = PadState.new()
	st.a = true
	st.b = true
	st.x = true
	var want: int = PilotInput.FIRE1 | PilotInput.FIRE2 | PilotInput.DOCK
	assert_int(_m.map(st, DT).buttons).is_equal(want)
	assert_int(_m.map(st, DT).buttons).is_equal(want)


func test_boost_flip_release_fire_one_tick_per_press() -> void:
	var st: PadState = PadState.new()
	st.l3 = true
	st.y = true
	st.dpad_down = true
	var all: int = PilotInput.BOOST | PilotInput.FLIP | PilotInput.RELEASE
	assert_int(_m.map(st, DT).buttons).is_equal(all)
	assert_int(_m.map(st, DT).buttons).is_equal(0)
	st.l3 = false
	st.y = false
	st.dpad_down = false
	var _o: PilotInput = _m.map(st, DT)
	st.l3 = true
	assert_int(_m.map(st, DT).buttons).is_equal(PilotInput.BOOST)


func test_sample_uses_poller() -> void:
	var st: PadState = PadState.new()
	st.right_trigger = 1.0
	_m.poller = func() -> PadState: return st
	assert_float(_m.sample(DT).thrust).is_equal(1.0)
