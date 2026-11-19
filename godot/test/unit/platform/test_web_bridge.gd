extends GdUnitTestSuite
## Unit tests for platform/web_bridge.gd, the only JavaScriptBridge seam (TA-36; 03 s11.4, D9).

var _calls: Array[String] = []


func before_test() -> void:
	_calls.clear()
	WebBridge.reset_seams()


func after_test() -> void:
	WebBridge.reset_seams()


func _fake(code: String) -> Variant:
	_calls.append(code)
	return "ok"


func test_desktop_is_not_web() -> void:
	assert_bool(WebBridge.is_web()).is_false()


func test_eval_is_a_noop_off_web() -> void:
	WebBridge.set_seams(0, Callable(self, "_fake"))
	assert_bool(WebBridge.is_web()).is_false()
	assert_that(WebBridge.eval("1+1")).is_null()
	assert_int(_calls.size()).is_equal(0)


func test_eval_reaches_backend_on_web() -> void:
	WebBridge.set_seams(1, Callable(self, "_fake"))
	assert_bool(WebBridge.is_web()).is_true()
	assert_that(WebBridge.eval("1+1")).is_equal("ok")
	assert_int(_calls.size()).is_equal(1)
	assert_str(_calls[0]).is_equal("1+1")


func test_console_log_escapes_and_routes_through_eval() -> void:
	WebBridge.set_seams(1, Callable(self, "_fake"))
	WebBridge.console_log("a'b\"c\nd")
	assert_int(_calls.size()).is_equal(1)
	assert_str(_calls[0]).starts_with("console.log(")
	assert_bool(_calls[0].contains("\n")).is_false()


func test_console_log_off_web_does_nothing() -> void:
	WebBridge.set_seams(0, Callable(self, "_fake"))
	WebBridge.console_log("x")
	assert_int(_calls.size()).is_equal(0)


func test_reset_seams_restores_detection() -> void:
	WebBridge.set_seams(1, Callable(self, "_fake"))
	WebBridge.reset_seams()
	assert_bool(WebBridge.is_web()).is_false()


func test_get_interface_off_web_is_null() -> void:
	assert_that(WebBridge.get_interface("PwPortal")).is_null()
