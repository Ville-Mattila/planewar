@abstract
class_name PortalSdk extends RefCounted
## Portal SDK seam (06 s9.2). v1.0 ships only PortalSdkNone: no SDK, no ad or tracking calls, break_allowed() false
## (A2 deferred to v1.1, R0 O-3). Poki and CrazyGames adapters are UX-32.

signal ready_changed(is_ready: bool)
signal break_started(kind: StringName)
signal break_finished(kind: StringName, rewarded: bool)


## Picks the adapter by feature tag; v1.0 always returns PortalSdkNone.
static func create() -> PortalSdk:
	return PortalSdkNone.new()


@abstract func portal_id() -> StringName
@abstract func init_sdk() -> void
@abstract func loading_progress(fraction: float) -> void
@abstract func loading_finished() -> void
@abstract func gameplay_start() -> void
@abstract func gameplay_stop() -> void
@abstract func happy_moment() -> void
@abstract func break_allowed() -> bool
@abstract func request_break(kind: StringName) -> void
@abstract func external_requests_allowed() -> bool
