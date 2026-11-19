class_name WebBridge extends RefCounted
## The one place `JavaScriptBridge` is used (03 s11.4; D9 fails the build anywhere else). Every call is guarded by
## `OS.has_feature("web")`, so desktop and mobile builds never reach the bridge. Tests drive the web branch through
## `set_seams` without a browser.

## Test seams: web_override -1 = detect, 0 = force non-web, 1 = force web; eval_backend invalid = real bridge.
static var _web_override: int = -1
static var _eval_backend: Callable = Callable()


static func is_web() -> bool:
	if _web_override >= 0:
		return _web_override == 1
	return OS.has_feature("web")


## Evaluates JavaScript on web; returns null (and does nothing) elsewhere.
static func eval(code: String) -> Variant:
	if not is_web():
		return null
	if _eval_backend.is_valid():
		return _eval_backend.call(code)
	return JavaScriptBridge.eval(code, true)


## `console.log(...)` on web, no-op elsewhere (perf_overlay output, 03 s11.5).
static func console_log(msg: String) -> void:
	if not is_web():
		return
	var _r: Variant = eval("console.log(" + JSON.stringify(msg) + ")")


## `JavaScriptBridge.get_interface(name)` on web; null elsewhere.
static func get_interface(interface_name: String) -> Variant:
	if not is_web():
		return null
	return JavaScriptBridge.get_interface(interface_name)


static func set_seams(web_override: int, eval_backend: Callable) -> void:
	_web_override = web_override
	_eval_backend = eval_backend


static func reset_seams() -> void:
	_web_override = -1
	_eval_backend = Callable()
