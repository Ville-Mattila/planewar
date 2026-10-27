# app - MODULE.md

Contract for `godot/src/app/**` (01 s9.3, 06 s8). UX-24 lands the screen state machine; boot flow,
`SettingsModel`, `match_controller` and `offline_host` arrive with their own tasks. A change to "Public API" or
"Invariants" is a contract change: update the contract tests first, in the same PR; `tools/gen_module_api.py --check`
must pass; <= 300 lines.

| Field | Value |
|---|---|
| Responsibility | Application glue: screen flow (state machine, back stack, focus), later boot, settings model, offline host. |
| Lane owner tier | Sonnet |
| May depend on | everything below it (`tools/deps.json`) |
| Must never touch | sim internals; only `offline_host.gd` may use `Thread` (non-web branch) |
| Autoloads used | `App` (stub) |
| Status | UX-24 ScreenFlow and UX-44 CameraIntentDriver implemented; everything else planned |

## Public API

```gdscript
# autoload: godot/src/app/app.gd (stub: no public members yet)
class_name ScreenId extends RefCounted     # 06 s8 flowchart ids and edges
const BOOT: StringName; const START_GATE: StringName; const AGE_GATE: StringName; const MAIN_MENU: StringName
const ONLINE: StringName; const ACCOUNT: StringName; const QUEUE: StringName; const SETUP_CUSTOM: StringName
const SETUP_SKIRMISH: StringName; const SETUP_COOP: StringName; const CAMPAIGN: StringName; const BRIEFING: StringName
const REPLAYS: StringName; const REPLAY_VIEWER: StringName; const SETTINGS: StringName; const PROFILE: StringName
const LOBBY: StringName; const LOADING: StringName; const MATCH: StringName; const PAUSE: StringName
const SAVE_LOAD: StringName; const RECONNECTING: StringName; const RESULTS: StringName
static func all_ids() -> Array[StringName]
static func targets(from: StringName) -> Array[StringName]
static func clears_stack(id: StringName) -> bool
static func is_transient(id: StringName) -> bool

class_name FlowScreen extends Control      # base of every hosted screen
func enter(_args: Dictionary) -> void
func exit() -> void
func handle_back() -> bool
func initial_focus() -> Control

class_name ScreenFlow extends Node
signal screen_changed(id: StringName, args: Dictionary)
signal quit_requested
var current_id: StringName
var current: FlowScreen
func setup(host: Control) -> void
func register(id: StringName, factory: Callable) -> void
func register_scene(id: StringName, scene: PackedScene) -> void
func stack_depth() -> int
func stack_ids() -> Array[StringName]
func start(id: StringName, args: Dictionary = {}) -> bool
func go(id: StringName, args: Dictionary = {}) -> bool
func back() -> bool
func on_intent(kind: StringName, _payload: Dictionary) -> void

class_name CameraIntentDriver extends Node   # UX-44: router CAM_* intents -> OrbitController, RTS mode only
const TILT_DEG_PER_DU: float; const COMMANDER_SNAP_ALTITUDE: float; const MIN_GRAB_DT: float   # 0.15, 5000, 0.001
var controller: OrbitController; var router: InputRouter; var camera: Camera3D
var ray_source: Callable                     # Callable(Vector2) -> PackedVector3Array [origin, dir]; else camera rays
var core_dir: Vector3                        # own Core direction for Home and the compass in the polar cap
func bind(r: InputRouter) -> void
func step(dt: float) -> void                 # held pan, controller.update, camera transform; _process calls it
func on_intent(kind: StringName, payload: Dictionary) -> void
func compass_tap() -> void;  func toggle_north_up() -> void;  func follow(dir: Vector3, on: bool = true) -> void
```

## Invariants

- `go` only follows `ScreenId.targets` edges; going to the stack top pops instead (Pause -> Match).
- `BOOT`, `START_GATE`, `AGE_GATE`, `LOADING`, `RESULTS` are never pushed; entering `MAIN_MENU`, `LOADING` or `RESULTS` clears the stack (no back from a match into Lobby/Briefing; Save/Load cycles stay bounded).
- `back()` pops only when the reverse edge exists in `ScreenId.targets`; `go`/`back` change the stack only after the new screen showed.
- `back()` asks `handle_back()` first, then pops; at an empty stack on `MAIN_MENU` it emits `quit_requested` (native only).
- B on gamepad arrives only as `Intents.BACK`; keyboard Esc (`ui_cancel`, key events only, joypad events ignored so one press pops once) and `NOTIFICATION_WM_GO_BACK_REQUEST` all call `back()`; `quit_on_go_back` is false.
- `CameraIntentDriver` reacts to `Intents.CAM_*` and `BUILD_ARM` only while the router is in `RTS`; in any other mode intents are ignored, held pan stops and an open grab ends, so flight modes never move the orbit camera. `CAM_PAN_VEL` is a held stick deflection (|vel| <= 1); a larger vector is a touch fling already carried by `grab_end` and is ignored.
- Every shown screen ends with a focus owner inside it (`initial_focus()` or the first focusable descendant).

## Test entry points

- `godot/test/unit/app/test_screen_flow.gd`
- `godot/test/unit/app/test_camera_intent_driver.gd` (touch through InputRouter, mouse/gamepad intents, flight modes inert)

## Open items

- Real screens (UX-25..28) register factories; scene paths per 06 s8 table.
