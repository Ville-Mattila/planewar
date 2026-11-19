# platform - MODULE.md

Contract for `godot/src/platform/**` (03 s11.4; 06 s9; TA-36). A change to "Public API" or "Invariants" is a contract
change: update the contract tests first, in the same PR (ADR-11); `tools/gen_module_api.py --check` must pass; <= 300 lines.
TA-36 lands the web safety layer only; storefront, entitlement, crash and Nakama-auth services land with their tasks.

| Field | Value |
|---|---|
| Responsibility | Everything that touches the host environment: the single `JavaScriptBridge` seam, the portal SDK seam (v1.0 = no-op adapter), later storefront and entitlement services. |
| Lane owner tier | Sonnet |
| May depend on | `core` (`tools/deps.json`) |
| Must never touch | `sim`, `net` internals, any other module; `Thread`; any ad or tracking SDK; SDKs beyond Nakama |
| Autoloads used | none |
| Status | TA-36: `WebBridge`, `PortalSdk`, `PortalSdkNone` implemented |

## Public API

Anything not listed is private (prefix `_`). Source: 03 s11.4, 06 s9.2.

```gdscript
class_name WebBridge extends RefCounted      # the only JavaScriptBridge user; every call guarded by OS.has_feature("web")
static func is_web() -> bool
static func eval(code: String) -> Variant                    # null off web
static func console_log(msg: String) -> void                 # no-op off web
static func get_interface(interface_name: String) -> Variant # null off web
static func set_seams(web_override: int, eval_backend: Callable) -> void   # tests: 1 = force web, 0 = force non-web
static func reset_seams() -> void

@abstract
class_name PortalSdk extends RefCounted
signal ready_changed(is_ready: bool)
signal break_started(kind: StringName)
signal break_finished(kind: StringName, rewarded: bool)
static func create() -> PortalSdk                            # v1.0: always PortalSdkNone
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

class_name PortalSdkNone extends PortalSdk                   # v1.0 adapter: no-ops
func portal_id() -> StringName
func init_sdk() -> void
func loading_progress(fraction: float) -> void
func loading_finished() -> void
func gameplay_start() -> void
func gameplay_stop() -> void
func happy_moment() -> void
func break_allowed() -> bool
func request_break(kind: StringName) -> void
func external_requests_allowed() -> bool
```

## Invariants

- W1: `JavaScriptBridge`, `OS.execute` and `FileAccess.open("/...")` appear only under `src/platform/` (D9).
- W2: every `JavaScriptBridge` call is behind `WebBridge.is_web()`; off web the bridge is never reached.
- W3: `PortalSdkNone.break_allowed()` is false and no portal or ad SDK exists in any v1.0 build (06 A2 deferred, R0 O-3).
- W4: `PortalSdkNone` never calls `WebBridge`.

## Data owned

None.

## Events emitted / consumed

`PortalSdk` signals (`ready_changed`, `break_started`, `break_finished`); `PortalSdkNone` emits only `ready_changed(true)`
from `init_sdk()`. No `SimEvent`, no `Command`.

## Performance budget

Not on a hot path (boot and lifecycle events only).

## Test entry points

- `godot/test/unit/platform/test_web_bridge.gd` (web branch driven through `set_seams`)
- `godot/test/unit/platform/test_portal_sdk.gd`
- `tools/tests/test_rules.py` `D9WebSafety`

## Open items

- Web boot with IndexedDB disabled: `app` must route every `user://` access through `Saves.try_*` (`core`) and treat
  failure as "no persistence"; wiring belongs to the `app` lane (`needs app:`).
- UX-32 (v1.1): Poki and CrazyGames adapters under `platform/portal/`.
