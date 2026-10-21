extends GdUnitTestSuite
## Unit tests for input/touch_flight_mapper.gd (06 s2.1, s3.5): reads InputMap-driven TouchState, FLIP from a flick.

const DT: float = 1.0 / 30.0

var _m: TouchFlightMapper


func before_test() -> void:
	_m = TouchFlightMapper.new()


func test_neutral_state_is_neutral() -> void:
	var o: PilotInput = _m.map(TouchState.new(), DT)
	assert_float(o.thrust).is_equal(0.0)
	assert_float(o.roll).is_equal(0.0)
	assert_float(o.pitch).is_equal(0.0)
	assert_int(o.buttons).is_equal(0)


func test_stick_inside_dead_zone_is_zero() -> void:
	var st: TouchState = TouchState.new()
	st.stick = Vector2(0.1, 0.0)
	assert_float(_m.map(st, DT).roll).is_equal(0.0)


func test_stick_uses_touch_dead_zone_and_gamma() -> void:
	var st: TouchState = TouchState.new()
	st.stick = Vector2(0.6, 0.3)
	var o: PilotInput = _m.map(st, DT)
	var want: Vector2 = FlightMath.stick(st.stick, FlightMath.TOUCH_DEAD_ZONE, FlightMath.TOUCH_GAMMA)
	assert_float(o.roll).is_equal_approx(want.x, 0.0001)
	assert_float(o.pitch).is_equal_approx(want.y, 0.0001)
	assert_float(FlightMath.TOUCH_DEAD_ZONE).is_equal(0.12)
	assert_float(FlightMath.TOUCH_GAMMA).is_equal(1.6)


func test_stick_up_is_nose_up_and_invert_flips() -> void:
	var st: TouchState = TouchState.new()
	st.stick = Vector2(0.0, 1.0)
	assert_float(_m.map(st, DT).pitch).is_equal(1.0)
	_m.invert_pitch = true
	assert_float(_m.map(st, DT).pitch).is_equal(-1.0)


func test_stick_right_is_positive_roll() -> void:
	var st: TouchState = TouchState.new()
	st.stick = Vector2(1.0, 0.0)
	assert_float(_m.map(st, DT).roll).is_equal(1.0)


func test_throttle_handle_maps_to_thrust() -> void:
	var st: TouchState = TouchState.new()
	st.throttle = 0.6
	assert_float(_m.map(st, DT).thrust).is_equal(0.6)
	assert_float(_m.map(st, DT).thrust).is_equal(0.6)


func test_held_buttons() -> void:
	var st: TouchState = TouchState.new()
	st.brake = true
	st.fire1 = true
	st.fire2 = true
	st.dock = true
	var want: int = PilotInput.BRAKE | PilotInput.FIRE1 | PilotInput.FIRE2 | PilotInput.DOCK
	assert_int(_m.map(st, DT).buttons).is_equal(want)
	assert_int(_m.map(st, DT).buttons).is_equal(want)


func test_boost_and_release_fire_one_tick_per_press() -> void:
	var st: TouchState = TouchState.new()
	st.boost = true
	st.release = true
	assert_int(_m.map(st, DT).buttons).is_equal(PilotInput.BOOST | PilotInput.RELEASE)
	assert_int(_m.map(st, DT).buttons).is_equal(0)
	st.boost = false
	st.release = false
	var _o: PilotInput = _m.map(st, DT)
	st.boost = true
	assert_int(_m.map(st, DT).buttons).is_equal(PilotInput.BOOST)


func test_flip_action_fires_one_tick() -> void:
	var st: TouchState = TouchState.new()
	st.flip = true
	assert_int(_m.map(st, DT).buttons).is_equal(PilotInput.FLIP)
	assert_int(_m.map(st, DT).buttons).is_equal(0)


func test_queue_flip_sends_flip_for_one_tick_and_keeps_axes() -> void:
	var st: TouchState = TouchState.new()
	st.stick = Vector2(1.0, 0.0)
	_m.queue_flip()
	var o: PilotInput = _m.map(st, DT)
	assert_int(o.buttons & PilotInput.FLIP).is_equal(PilotInput.FLIP)
	assert_float(o.roll).is_greater(0.0)
	assert_int(_m.map(st, DT).buttons).is_equal(0)


func test_sample_uses_poller_seam() -> void:
	var st: TouchState = TouchState.new()
	st.throttle = 0.25
	_m.poller = func() -> TouchState: return st
	assert_float(_m.sample(DT).thrust).is_equal(0.25)


func test_poll_without_actions_is_neutral() -> void:
	var st: TouchState = TouchState.poll()
	assert_vector(st.stick).is_equal(Vector2.ZERO)
	assert_float(st.throttle).is_equal(0.0)
