extends GdUnitTestSuite
## Unit tests for core/result.gd.


func test_success_carries_value() -> void:
	var r: Result = Result.success(42)
	assert_bool(r.ok).is_true()
	assert_int(r.value).is_equal(42)


func test_failure_carries_code_and_message() -> void:
	var r: Result = Result.failure(3, "nope")
	assert_bool(r.ok).is_false()
	assert_int(r.error).is_equal(3)
	assert_str(r.message).is_equal("nope")
