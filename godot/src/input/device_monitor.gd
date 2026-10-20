class_name DeviceMonitor extends RefCounted
## Tracks the active input class and glyph set from raw events (06 s2.4). Pure logic: the caller supplies
## the clock, so tests need no Node. Emulated mouse events never count. No signals (the router emits).

const AXIS_THRESHOLD: float = 0.35
const MOTION_DU: float = 4.0
const MOTION_WINDOW_MS: int = 100
const LAYOUT_PERSIST_MS: int = 500

var active_class: int
var glyph_set: StringName = &"kbm"
## Optional Callable(event: InputEvent) -> bool: is this key bound? Default consults the InputMap.
var key_bound: Callable

var _layout_class: int
var _pending_since_ms: int = -1
var _motion_acc: float = 0.0
var _motion_start_ms: int = 0
var _du_per_px: float = 1.0


func _init(boot_class: int = InputClass.Kind.POINTER, du_per_px: float = 1.0) -> void:
	active_class = boot_class
	_layout_class = boot_class
	_du_per_px = du_per_px
	glyph_set = default_glyphs(boot_class)


## Class an event qualifies for, or -1 when it does not (06 s2.4 table).
func classify(event: InputEvent, now_ms: int) -> int:
	if event is InputEventScreenTouch:
		return InputClass.Kind.TOUCH if (event as InputEventScreenTouch).pressed else -1
	if event is InputEventScreenDrag:
		return InputClass.Kind.TOUCH
	if event is InputEventJoypadButton:
		return InputClass.Kind.GAMEPAD if (event as InputEventJoypadButton).pressed else -1
	if event is InputEventJoypadMotion:
		var jm: InputEventJoypadMotion = event as InputEventJoypadMotion
		return InputClass.Kind.GAMEPAD if absf(jm.axis_value) > AXIS_THRESHOLD else -1
	if event.device == InputEvent.DEVICE_ID_EMULATION:
		return -1
	if event is InputEventMouseButton:
		return InputClass.Kind.POINTER if (event as InputEventMouseButton).pressed else -1
	if event is InputEventMouseMotion:
		return InputClass.Kind.POINTER if _motion_qualifies(event as InputEventMouseMotion, now_ms) else -1
	if event is InputEventKey:
		var key: InputEventKey = event as InputEventKey
		if key.pressed and not key.echo and _is_bound(key):
			return InputClass.Kind.POINTER
	return -1


## Feeds one event. Returns true when the active class or glyph set changed.
func feed(event: InputEvent, now_ms: int) -> bool:
	var kind: int = classify(event, now_ms)
	if kind < 0:
		return false
	var before_class: int = active_class
	var before_glyphs: StringName = glyph_set
	active_class = kind
	glyph_set = _glyphs_for_event(kind, event)
	if _is_press(event):
		_layout_class = kind
		_pending_since_ms = -1
	elif kind == _layout_class:
		_pending_since_ms = -1
	elif _pending_since_ms < 0:
		_pending_since_ms = now_ms
	return before_class != active_class or before_glyphs != glyph_set


## Layout class (touch HUD, cursor): follows the active class once it persists 0.5 s, or at once on a press.
func layout_class(now_ms: int) -> int:
	if active_class != _layout_class and _pending_since_ms >= 0 \
			and now_ms - _pending_since_ms >= LAYOUT_PERSIST_MS:
		_layout_class = active_class
		_pending_since_ms = -1
	return _layout_class


static func default_glyphs(kind: int) -> StringName:
	if kind == InputClass.Kind.GAMEPAD:
		return &"generic"
	return &"kbm"


## Glyph set from a joypad name (Input.get_joy_name). No KBM glyphs while a gamepad is active.
static func glyphs_for_joy_name(joy_name: String) -> StringName:
	var n: String = joy_name.to_lower()
	if n.contains("steam deck") or n.contains("steamdeck"):
		return &"deck"
	if n.contains("xbox") or n.contains("xinput"):
		return &"xbox"
	if n.contains("playstation") or n.contains("dualsense") or n.contains("dualshock") \
			or n.contains("ps4") or n.contains("ps5"):
		return &"ps"
	if n.contains("nintendo") or n.contains("switch") or n.contains("joy-con"):
		return &"nintendo"
	return &"generic"


func _glyphs_for_event(kind: int, event: InputEvent) -> StringName:
	if kind != InputClass.Kind.GAMEPAD:
		return &"kbm"
	return glyphs_for_joy_name(Input.get_joy_name(event.device))


func _motion_qualifies(m: InputEventMouseMotion, now_ms: int) -> bool:
	if now_ms - _motion_start_ms > MOTION_WINDOW_MS:
		_motion_start_ms = now_ms
		_motion_acc = 0.0
	_motion_acc += m.relative.length() * _du_per_px
	return _motion_acc > MOTION_DU


func _is_bound(key: InputEventKey) -> bool:
	if key_bound.is_valid():
		var r: Variant = key_bound.call(key)
		return r is bool and r == true
	for action: StringName in InputMap.get_actions():
		if InputMap.event_is_action(key, action):
			return true
	return false


static func _is_press(event: InputEvent) -> bool:
	return event is InputEventScreenTouch or event is InputEventJoypadButton \
			or event is InputEventMouseButton or event is InputEventKey
