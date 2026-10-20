extends GdUnitTestSuite
## Unit tests for input/input_class.gd (06 s2.4 boot default, tier defaults, ranked min).


func test_boot_defaults() -> void:
	assert_int(InputClass.boot_class_from(true, false, false)).is_equal(InputClass.Kind.TOUCH)
	assert_int(InputClass.boot_class_from(false, true, false)).is_equal(InputClass.Kind.TOUCH)
	assert_int(InputClass.boot_class_from(false, false, true)).is_equal(InputClass.Kind.GAMEPAD)
	assert_int(InputClass.boot_class_from(false, false, false)).is_equal(InputClass.Kind.POINTER)


func test_boot_class_is_valid_kind() -> void:
	var k: int = InputClass.boot_class()
	assert_bool(k >= InputClass.Kind.TOUCH and k <= InputClass.Kind.POINTER).is_true()


func test_default_tiers() -> void:
	assert_int(InputClass.default_tier(InputClass.Kind.TOUCH)).is_equal(InputClass.TIER_FULL)
	assert_int(InputClass.default_tier(InputClass.Kind.GAMEPAD)).is_equal(InputClass.TIER_STANDARD)
	assert_int(InputClass.default_tier(InputClass.Kind.POINTER)).is_equal(InputClass.TIER_RAW)


func test_ranked_tier_is_min() -> void:
	assert_int(InputClass.ranked_tier(InputClass.Kind.TOUCH, InputClass.Kind.POINTER)).is_equal(InputClass.TIER_RAW)
	assert_int(InputClass.ranked_tier(InputClass.Kind.POINTER, InputClass.Kind.TOUCH)).is_equal(InputClass.TIER_RAW)
	assert_int(InputClass.ranked_tier(InputClass.Kind.TOUCH, InputClass.Kind.GAMEPAD)).is_equal(InputClass.TIER_STANDARD)
	assert_int(InputClass.ranked_tier(InputClass.Kind.TOUCH, InputClass.Kind.TOUCH)).is_equal(InputClass.TIER_FULL)


func test_ranked_tier_offline_uses_active() -> void:
	assert_int(InputClass.ranked_tier(-1, InputClass.Kind.GAMEPAD)).is_equal(InputClass.TIER_STANDARD)
