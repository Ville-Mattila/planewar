extends GdUnitTestSuite
## Unit tests for core/config.gd (argument parsing; platform helpers).


func test_bare_flag_yields_true() -> void:
	var args := PackedStringArray(["--server"])
	assert_that(Config.parse_override(args, "server")).is_equal(PackedStringArray(["true"]))


func test_key_value_override() -> void:
	var args := PackedStringArray(["--caps=lite"])
	assert_that(Config.parse_override(args, "caps")).is_equal(PackedStringArray(["lite"]))


func test_absent_override_is_empty() -> void:
	var args := PackedStringArray(["--other"])
	assert_bool(Config.parse_override(args, "missing").is_empty()).is_true()


func test_prefix_of_another_key_does_not_match() -> void:
	var args := PackedStringArray(["--serverport=9000"])
	assert_bool(Config.parse_override(args, "server").is_empty()).is_true()


func test_default_offline_caps_profile_is_a_known_profile() -> void:
	var profile: StringName = Config.default_offline_caps_profile()
	assert_bool(profile == &"standard" or profile == &"lite").is_true()
