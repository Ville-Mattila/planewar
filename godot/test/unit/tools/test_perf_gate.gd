class_name TestPerfGate extends GdUnitTestSuite
## PerfGate (TEST-03, R0 B.17 A-97): both branches, driven by setting the variable in-process.

var _saved: String = ""


func before_test() -> void:
	_saved = OS.get_environment(PerfGate.ENV_NAME)


func after_test() -> void:
	if _saved == "":
		OS.unset_environment(PerfGate.ENV_NAME)
	else:
		OS.set_environment(PerfGate.ENV_NAME, _saved)


func test_not_pinned_never_fails() -> void:
	OS.unset_environment(PerfGate.ENV_NAME)
	assert_bool(PerfGate.pinned()).is_false()
	assert_bool(PerfGate.check("t.over", 500.0, 10.0, "row")).is_true()
	assert_bool(PerfGate.check("t.under", 1.0, 10.0, "row", 1.2)).is_true()


func test_other_values_are_not_pinned() -> void:
	OS.set_environment(PerfGate.ENV_NAME, "0")
	assert_bool(PerfGate.pinned()).is_false()
	OS.set_environment(PerfGate.ENV_NAME, "true")
	assert_bool(PerfGate.pinned()).is_false()
	assert_bool(PerfGate.check("t.over", 500.0, 10.0, "row")).is_true()


func test_pinned_asserts_the_bound() -> void:
	OS.set_environment(PerfGate.ENV_NAME, "1")
	assert_bool(PerfGate.pinned()).is_true()
	assert_bool(PerfGate.check("t.under", 9.9, 10.0, "row")).is_true()
	assert_bool(PerfGate.check("t.equal", 10.0, 10.0, "row")).is_false()
	assert_bool(PerfGate.check("t.over", 11.0, 10.0, "row", 1.3)).is_false()
