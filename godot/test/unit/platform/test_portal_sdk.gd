extends GdUnitTestSuite
## Unit tests for platform/portal_sdk.gd and portal_sdk_none.gd (TA-36; 06 s9.2, A2 deferred to v1.1).

var _evaluated: int = 0
var _signals: int = 0
var _ready_seen: Array[bool] = []


func before_test() -> void:
	_evaluated = 0
	_signals = 0
	_ready_seen.clear()
	WebBridge.reset_seams()


func after_test() -> void:
	WebBridge.reset_seams()


func _count(_code: String) -> Variant:
	_evaluated += 1
	return null


func _on_break(_kind: StringName) -> void:
	_signals += 1


func _on_ready(is_ready: bool) -> void:
	_ready_seen.append(is_ready)


func test_create_returns_none_adapter() -> void:
	var sdk: PortalSdk = PortalSdk.create()
	assert_object(sdk).is_instanceof(PortalSdkNone)
	assert_str(String(sdk.portal_id())).is_equal("none")


func test_break_never_allowed() -> void:
	var sdk: PortalSdk = PortalSdk.create()
	assert_bool(sdk.break_allowed()).is_false()


func test_request_break_does_nothing() -> void:
	var sdk: PortalSdk = PortalSdk.create()
	var _c: int = sdk.break_started.connect(_on_break)
	sdk.request_break(&"midgame")
	assert_int(_signals).is_equal(0)


func test_init_sdk_reports_ready_synchronously() -> void:
	var sdk: PortalSdk = PortalSdk.create()
	var _c: int = sdk.ready_changed.connect(_on_ready)
	sdk.init_sdk()
	assert_array(_ready_seen).is_equal([true])


func test_lifecycle_calls_never_touch_the_js_bridge_even_on_web() -> void:
	WebBridge.set_seams(1, Callable(self, "_count"))
	var sdk: PortalSdk = PortalSdk.create()
	sdk.init_sdk()
	sdk.loading_progress(0.5)
	sdk.loading_finished()
	sdk.gameplay_start()
	sdk.gameplay_stop()
	sdk.happy_moment()
	sdk.request_break(&"midgame")
	assert_int(_evaluated).is_equal(0)
	assert_bool(sdk.break_allowed()).is_false()


func test_external_requests_allowed_without_portal() -> void:
	assert_bool(PortalSdk.create().external_requests_allowed()).is_true()
