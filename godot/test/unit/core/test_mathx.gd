extends GdUnitTestSuite
## Unit tests for core/mathx.gd.


func test_floori_div_rounds_toward_negative_infinity() -> void:
	assert_int(MathX.floori_div(7, 2)).is_equal(3)
	assert_int(MathX.floori_div(-7, 2)).is_equal(-4)
	assert_int(MathX.floori_div(7, -2)).is_equal(-4)
	assert_int(MathX.floori_div(-8, 2)).is_equal(-4)


func test_posmod_i_is_non_negative() -> void:
	assert_int(MathX.posmod_i(-1, 5)).is_equal(4)
	assert_int(MathX.posmod_i(7, 5)).is_equal(2)


func test_move_toward_v3_steps_by_delta() -> void:
	var v: Vector3 = MathX.move_toward_v3(Vector3.ZERO, Vector3(10, 0, 0), 2.5)
	assert_vector(v).is_equal_approx(Vector3(2.5, 0, 0), Vector3.ONE * 0.0001)


func test_smoothstep01_clamps_and_interpolates() -> void:
	assert_float(MathX.smoothstep01(0.0, 1.0, 0.5)).is_equal_approx(0.5, 0.0001)
	assert_float(MathX.smoothstep01(0.0, 1.0, -1.0)).is_equal(0.0)
	assert_float(MathX.smoothstep01(0.0, 1.0, 2.0)).is_equal(1.0)
