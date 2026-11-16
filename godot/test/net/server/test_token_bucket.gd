extends GdUnitTestSuite
## NET-14: TokenBucket (04 s11.4). Deterministic on caller-supplied milliseconds.


func test_starts_full_and_drains_to_burst() -> void:
	var b: TokenBucket = TokenBucket.new(10.0, 30.0, 0)
	for _i: int in 30:
		assert_bool(b.take(0)).is_true()
	assert_bool(b.take(0)).is_false()


func test_refills_at_rate_and_caps_at_burst() -> void:
	var b: TokenBucket = TokenBucket.new(10.0, 30.0, 0)
	for _i: int in 30:
		var _t: bool = b.take(0)
	assert_float(b.available(500)).is_equal_approx(5.0, 0.001)
	assert_float(b.available(60000)).is_equal_approx(30.0, 0.001)


func test_cost_and_backwards_clock() -> void:
	var b: TokenBucket = TokenBucket.new(1.0, 10.0, 1000)
	assert_bool(b.take(1000, 10.0)).is_true()
	assert_bool(b.take(1000, 1.0)).is_false()
	assert_bool(b.take(500, 1.0)).is_false()      # clock moved back: nothing refills
	assert_bool(b.take(2000, 1.0)).is_true()       # 1 s after the high-water mark
