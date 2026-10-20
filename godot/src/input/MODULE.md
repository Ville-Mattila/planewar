# input - MODULE.md

Contract for `godot/src/input/**` (06 s2-s3; UX-03). A change to "Public API" or "Invariants" is a contract change:
update the contract tests first, in the same PR (ADR-11); `tools/gen_module_api.py --check` must pass; <= 300 lines.
UX-03 lands the router, class detection, glyph selection and the intent catalogue. Mappers, gesture recognizer,
assist stack and remap are later tasks (see "Open items").

| Field | Value |
|---|---|
| Responsibility | Turns device events into (a) the active input class and glyph set and (b) one `PilotInput` per sim tick in flight modes and `intent` signals for RTS/UI actions. Does not know the sim, `SimView` or any Control; touch HUD controls drive InputMap actions that mappers read. |
| Lane owner tier | Sonnet |
| May depend on | `core`; the sim public type `PilotInput` only (`tools/deps.json`) |
| Must never touch | `sim` beyond `PilotInput`, `net`, `ui`, `camera`, `presentation`, `content` loaders, `app` |
| Autoloads used | none |
| Status | UX-03 implemented (router, class, monitor, intents); mappers and assists planned |

## Public API

Anything not listed is private (prefix `_`). Source: 06 s2.1-s2.5.

```gdscript
class_name InputClass extends RefCounted       # classes, boot default, assist-tier defaults (s2.4)
enum Kind { TOUCH, GAMEPAD, POINTER }
const TIER_RAW: int; const TIER_STANDARD: int; const TIER_FULL: int            # 0, 1, 2 (ordered; min() picks the weaker)
static func boot_class_from(mobile: bool, web_touch: bool, steam_deck: bool) -> int
static func boot_class() -> int                                                # OS features and SteamDeck=1 env
static func default_tier(kind: int) -> int                                     # touch Full, gamepad Standard, pointer Raw
static func ranked_tier(match_class: int, active_class: int) -> int            # min of both defaults; match_class < 0 = offline

class_name DeviceMonitor extends RefCounted    # active class and glyph set from raw events (s2.4)
const AXIS_THRESHOLD: float; const MOTION_DU: float; const MOTION_WINDOW_MS: int; const LAYOUT_PERSIST_MS: int   # 0.35, 4, 100, 500
var active_class: int
var glyph_set: StringName
var key_bound: Callable                        # optional Callable(InputEventKey) -> bool; default consults InputMap
func _init(boot_class: int = InputClass.Kind.POINTER, du_per_px: float = 1.0) -> void
func classify(event: InputEvent, now_ms: int) -> int                           # qualifying class or -1
func feed(event: InputEvent, now_ms: int) -> bool                              # true when class or glyph set changed
func layout_class(now_ms: int) -> int                                          # follows active class after 0.5 s or on a press
static func default_glyphs(kind: int) -> StringName
static func glyphs_for_joy_name(joy_name: String) -> StringName                # &"xbox" &"ps" &"nintendo" &"deck" &"generic"

class_name InputRouter extends Node            # not an autoload; process_physics_priority = -10
enum Mode { MENU, FLIGHT, TURRET, GROUND, RTS, PLACEMENT, TEXT, PEEK }
signal pilot_input(input: PilotInput)                  # once per sim tick in FLIGHT, TURRET, GROUND, PEEK
signal intent(kind: StringName, payload: Dictionary)   # s2.5
signal input_class_changed(kind: int)
signal glyph_set_changed(glyphs: StringName)           # &"kbm" &"xbox" &"ps" &"nintendo" &"deck" &"generic"
var sampler: Callable                                  # Callable() -> PilotInput raw sample; invalid = neutral
func route_event(event: InputEvent, now_ms: int) -> void
func emit_tick() -> bool                               # emits pilot_input once in a flight mode; returns whether it did
static func is_flight_mode(m: Mode) -> bool
func input_class() -> int                              # 01 s9.4: active device class
func match_input_class() -> int                        # class locked at queue time; -1 offline
func set_match_input_class(kind: int) -> void
func set_mode(new_mode: Mode) -> void
func current_mode() -> Mode
func current_glyph_set() -> StringName

class_name Intents extends RefCounted          # s2.5 kinds (StringName consts) and payload keys
const SELECT: StringName; const SELECT_BOX: StringName; const SELECT_PAINT: StringName; const SELECT_SAME: StringName; const DESELECT: StringName
const ORDER_CONTEXT: StringName; const ORDER_MENU: StringName; const ORDER: StringName
const BUILD_ARM: StringName; const BUILD_MOVE: StringName; const BUILD_ROTATE: StringName; const BUILD_CONFIRM: StringName; const BUILD_CANCEL: StringName
const PRODUCE: StringName; const CANCEL_PRODUCE: StringName; const SET_REPLENISH: StringName
const CAM_PAN_GRAB: StringName; const CAM_PAN_VEL: StringName; const CAM_ZOOM: StringName; const CAM_ROTATE: StringName
const CAM_TILT: StringName; const CAM_TIER_TOGGLE: StringName; const CAM_HOME: StringName; const FREE_LOOK: StringName
const JUMP_ALERT: StringName; const POSSESS: StringName; const REQUEST_POSSESS: StringName; const QUICK_FLY: StringName
const RELEASE: StringName; const PEEK: StringName; const HANDOVER_ACCEPT: StringName
const GROUP_SELECT: StringName; const GROUP_ASSIGN: StringName; const GROUP_JUMP: StringName
const PING_WHEEL: StringName; const PING: StringName; const WING_RADIAL: StringName
const FEED_FILTER: StringName; const SPECTATE_NEXT: StringName; const SPECTATE_PREV: StringName
const CHAT_OPEN: StringName; const MENU: StringName; const BACK: StringName; const ROSTER: StringName
const K_POS: StringName; const K_RECT: StringName; const K_CENTER: StringName; const K_RADIUS: StringName; const K_ADD: StringName
const K_ORDER: StringName; const K_DEF_ID: StringName; const K_STEPS: StringName; const K_COUNT: StringName
const K_FROM: StringName; const K_TO: StringName; const K_VEL: StringName; const K_LOG_DELTA: StringName
const K_ANCHOR: StringName; const K_RAD: StringName; const K_VEC: StringName; const K_INDEX: StringName
const K_ENTITY: StringName; const K_ON: StringName; const K_SLOT: StringName; const K_OPEN: StringName
const K_PING: StringName; const K_LANE: StringName
static func all_kinds() -> Array[StringName]

# planned: AssistProfile, AssistContext, AssistStack, GestureRecognizer, BindingStore, Glyphs
```

## Invariants

- I1: classification follows the s2.4 table exactly: touch press/drag, gamepad button press and axis |v| > 0.35,
  mouse button press, mouse motion > 4 du within 100 ms, key press of a bound key (not echo).
- I2: an event with `device == InputEvent.DEVICE_ID_EMULATION` never changes the class (touch events are exempt,
  they are real touches).
- I3: `pilot_input` is emitted at most once per `emit_tick()` and never in MENU, RTS, PLACEMENT or TEXT.
- I4: PEEK emits neutral pitch/yaw/roll and no buttons; thrust is whatever the sampler held.
- I5: boot default: mobile or mobile-web -> TOUCH; `SteamDeck=1` -> GAMEPAD; else POINTER.
- I6: the layout class changes only on a press or after the new class persisted 0.5 s; glyphs switch at once.
- I7: `ranked_tier = min(default_tier(match), default_tier(active))`; offline (-1) uses the active class.
- I8: no KBM glyph set while the active class is GAMEPAD.
- I9: `input` never reads `SimView` and never imports `ui`; world knowledge arrives through a caller-filled context.

## Data owned

The `DeviceMonitor` state (active class, glyph set, pending layout class). `user://settings/input_map.cfg` and
`content/ui/glyphs.json` are planned (BindingStore, Glyphs).

## Events emitted / consumed

Signals (allowed in `input` Nodes): `pilot_input`, `intent`, `input_class_changed`, `glyph_set_changed`.
Consumes `_input` events and, when the mappers land, InputMap actions.

## Performance budget

Per physics tick (30 Hz): one `PilotInput` allocation plus one signal emit; per event: a type-test chain, O(1)
except the key-bound InputMap scan on key presses (only on press). Not on a sim hot path: client side, one call per tick.

## Test entry points

- `godot/test/unit/input/test_input_class.gd` (boot defaults, tiers, ranked min)
- `godot/test/unit/input/test_device_monitor.gd` (s2.4 table, emulation, glyphs, layout persistence)
- `godot/test/unit/input/test_input_router.gd` (once per tick, mode gating, PEEK, signals)
- `godot/test/unit/input/test_intents.gd` (catalogue complete and unique)

## How to add X (recipes for the cheapest tier)

- A new intent kind: add the const to `Intents` and to `all_kinds()`, append a row in 06 s2.5, extend `test_intents.gd`.
- A new class-qualifying event: add the branch in `DeviceMonitor.classify`, add a table row test.

## Open items

- UX-04+ mappers (`{Touch,Gamepad,Pointer}FlightMapper`) replace `sampler`; `AssistStack` runs between mapper and emit.
- `intent` has no emitter until the RTS mappers and `GestureRecognizer` land.
