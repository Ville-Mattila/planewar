extends GdUnitTestSuite
## Unit tests for input/flight_math.gd: dead zone, curve, trigger, ramp (06 s3.5).


func test_stick_inside_dead_zone_is_zero() -> void:
	assert_float(FlightMath.stick(Vector2(0.1, 0.1), 0.15, 1.8).length()).is_equal(0.0)
	assert_float(FlightMath.stick(Vector2(0.149, 0.0), 0.15, 1.8).length()).is_equal(0.0)


func test_stick_full_deflection_is_full() -> void:
	var v: Vector2 = FlightMath.stick(Vector2(1.0, 0.0), 0.15, 1.8)
	assert_float(v.x).is_equal_approx(1.0, 0.0001)


func test_stick_rescales_after_dead_zone_and_applies_gamma() -> void:
	var v: Vector2 = FlightMath.stick(Vector2(0.575, 0.0), 0.15, 1.8)   # s = 0.5
	assert_float(v.x).is_equal_approx(pow(0.5, 1.8), 0.0001)


func test_stick_preserves_direction() -> void:
	var v: Vector2 = FlightMath.stick(Vector2(0.6, 0.8), 0.15, 1.8)
	assert_float(v.angle()).is_equal_approx(Vector2(0.6, 0.8).angle(), 0.0001)
	assert_float(v.length()).is_equal_approx(1.0, 0.0001)


func test_stick_gamma_one_is_linear_after_dead_zone() -> void:
	var v: Vector2 = FlightMath.stick(Vector2(0.575, 0.0), 0.15, 1.0)
	assert_float(v.x).is_equal_approx(0.5, 0.0001)


func test_trigger_dead_zone_and_scale() -> void:
	assert_float(FlightMath.trigger(0.05, 0.05)).is_equal(0.0)
	assert_float(FlightMath.trigger(1.0, 0.05)).is_equal(1.0)
	assert_float(FlightMath.trigger(0.525, 0.05)).is_equal_approx(0.5, 0.0001)


func test_ramp_limits_step_and_does_not_overshoot() -> void:
	assert_float(FlightMath.ramp(0.0, 1.0, 4.0, 0.1)).is_equal_approx(0.4, 0.0001)
	assert_float(FlightMath.ramp(0.9, 1.0, 4.0, 0.1)).is_equal(1.0)
	assert_float(FlightMath.ramp(0.3, 0.0, 4.0, 0.1)).is_equal(0.0)
