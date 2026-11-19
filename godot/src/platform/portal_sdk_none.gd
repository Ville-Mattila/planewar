class_name PortalSdkNone extends PortalSdk
## v1.0 adapter for itch.io, self-hosted web, Steam and Android: every call is a no-op, nothing touches
## JavaScriptBridge, and no break is ever allowed (06 A2 deferred).


func portal_id() -> StringName:
	return &"none"


func init_sdk() -> void:
	ready_changed.emit(true)


func loading_progress(_fraction: float) -> void:
	pass


func loading_finished() -> void:
	pass


func gameplay_start() -> void:
	pass


func gameplay_stop() -> void:
	pass


func happy_moment() -> void:
	pass


func break_allowed() -> bool:
	return false


func request_break(_kind: StringName) -> void:
	pass


func external_requests_allowed() -> bool:
	return true
