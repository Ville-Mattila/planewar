class_name RtsCameraMapper extends RefCounted
## Mouse, keyboard and gamepad -> CAM_* intents in RTS mode (06 s3.3 KBM and Gamepad columns; UX-45). Pure: `feed`
## and `tick` return intents as {&"kind": StringName, &"payload": Dictionary} and the router emits them. Payloads
## follow GestureIntents and CameraIntentDriver: CAM_PAN_VEL {vel} is held deflection |v| <= 1 (y positive = forward)
## re-sent on change with a zero vector on release; CAM_ZOOM {log_delta, anchor?}; CAM_ROTATE {rad}; CAM_TILT {vec}
## in du (drag up = more top-down); CAM_TIER_TOGGLE {pos}; CAM_HOME {}.
## The bindings 06 leaves open are client-only feel constants below (not hashed, no def; same rule as FlightMath).

const EDGE_DU: float = 8.0                  ## 06 s3.3: screen-edge pan zone, in du
const WHEEL_LOG_STEP: float = 0.15          ## client-only: log zoom per wheel notch
const MMB_ROT_RAD_PER_DU: float = 0.005     ## client-only: MMB drag X
const KEY_ROT_RAD_PER_S: float = 1.5        ## client-only: Q / E
const PAD_ROT_RAD_PER_S: float = 2.0        ## client-only: RS X at full deflection
const PAD_TILT_DU_PER_S: float = 200.0      ## client-only: RS Y at full deflection (30 deg/s at 0.15 deg/du)
const PAD_ZOOM_LOG_PER_S: float = 1.5       ## client-only: RT minus LT at full pull
const PAD_DEADZONE: float = 0.2             ## client-only: stick and trigger dead zone

## Window size in du for edge pan and the gamepad reticle (screen centre); zero disables edge pan.
var viewport_size: Vector2 = Vector2.ZERO

var _held: Dictionary = {}
var _axes: Dictionary = {}
var _mouse_pos: Vector2 = Vector2.ZERO
var _last_pan: Vector2 = Vector2.ZERO


## Clears held keys, axes and the pan memory (the router calls this when the mode changes).
func reset() -> void:
	_held.clear()
	_axes.clear()
	_last_pan = Vector2.ZERO


## Event-driven intents (wheel, MMB drag, Tab, H, View, L3, pan changes). Empty for events it does not bind.
func feed(event: InputEvent) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if event is InputEventMouseButton:
		_wheel(event as InputEventMouseButton, out)
	elif event is InputEventMouseMotion:
		_motion(event as InputEventMouseMotion, out)
		_pan(out)
	elif event is InputEventKey:
		_key(event as InputEventKey, out)
		_pan(out)
	elif event is InputEventJoypadMotion:
		var jm: InputEventJoypadMotion = event as InputEventJoypadMotion
		_axes[jm.axis] = jm.axis_value
		_pan(out)
	elif event is InputEventJoypadButton:
		_pad_button(event as InputEventJoypadButton, out)
	return out


## Per-physics-tick intents for held input: Q/E and RS X rotate, RS Y tilt, RT/LT zoom.
func tick(dt: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var rot: float = (_key_axis(KEY_E, KEY_Q) * KEY_ROT_RAD_PER_S + _stick(JOY_AXIS_RIGHT_X) * PAD_ROT_RAD_PER_S) * dt
	if rot != 0.0:
		out.append(_make(Intents.CAM_ROTATE, {Intents.K_RAD: rot}))
	var tilt: float = _stick(JOY_AXIS_RIGHT_Y) * PAD_TILT_DU_PER_S * dt
	if tilt != 0.0:
		out.append(_make(Intents.CAM_TILT, {Intents.K_VEC: Vector2(0.0, tilt)}))
	var zoom: float = (_stick(JOY_AXIS_TRIGGER_RIGHT) - _stick(JOY_AXIS_TRIGGER_LEFT)) * PAD_ZOOM_LOG_PER_S * dt
	if zoom != 0.0:
		out.append(_make(Intents.CAM_ZOOM, {Intents.K_LOG_DELTA: zoom}))
	return out


func _wheel(e: InputEventMouseButton, out: Array[Dictionary]) -> void:
	if not e.pressed:
		return
	var step: float = 0.0
	if e.button_index == MOUSE_BUTTON_WHEEL_UP:
		step = WHEEL_LOG_STEP
	elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		step = -WHEEL_LOG_STEP
	if step != 0.0:
		_mouse_pos = e.position
		out.append(_make(Intents.CAM_ZOOM, {Intents.K_LOG_DELTA: step, Intents.K_ANCHOR: e.position}))


func _motion(e: InputEventMouseMotion, out: Array[Dictionary]) -> void:
	_mouse_pos = e.position
	if (e.button_mask & MOUSE_BUTTON_MASK_MIDDLE) == 0:
		return
	if e.relative.x != 0.0:
		out.append(_make(Intents.CAM_ROTATE, {Intents.K_RAD: e.relative.x * MMB_ROT_RAD_PER_DU}))
	if e.relative.y != 0.0:
		out.append(_make(Intents.CAM_TILT, {Intents.K_VEC: Vector2(0.0, e.relative.y)}))


func _key(e: InputEventKey, out: Array[Dictionary]) -> void:
	var code: int = e.physical_keycode
	if e.echo:
		return
	_held[code] = e.pressed
	if not e.pressed:
		return
	if code == KEY_TAB:
		out.append(_make(Intents.CAM_TIER_TOGGLE, {Intents.K_POS: _mouse_pos}))
	elif code == KEY_H:
		out.append(_make(Intents.CAM_HOME, {}))


func _pad_button(e: InputEventJoypadButton, out: Array[Dictionary]) -> void:
	if not e.pressed:
		return
	if e.button_index == JOY_BUTTON_BACK:
		out.append(_make(Intents.CAM_TIER_TOGGLE, {Intents.K_POS: viewport_size * 0.5}))
	elif e.button_index == JOY_BUTTON_LEFT_STICK:
		out.append(_make(Intents.CAM_HOME, {}))


## Emits CAM_PAN_VEL when the combined deflection changed (zero vector on release).
func _pan(out: Array[Dictionary]) -> void:
	var v: Vector2 = Vector2(
		_key_axis(KEY_D, KEY_A) + _key_axis(KEY_RIGHT, KEY_LEFT) + _edge(_mouse_pos.x, viewport_size.x),
		_key_axis(KEY_W, KEY_S) + _key_axis(KEY_UP, KEY_DOWN) - _edge(_mouse_pos.y, viewport_size.y))
	v += Vector2(_stick(JOY_AXIS_LEFT_X), -_stick(JOY_AXIS_LEFT_Y))
	v = v.limit_length(1.0)
	if v == _last_pan:
		return
	_last_pan = v
	out.append(_make(Intents.CAM_PAN_VEL, {Intents.K_VEL: v}))


## -1 within EDGE_DU of the low edge, +1 within EDGE_DU of the high edge, else 0 (disabled without a viewport).
func _edge(pos: float, size: float) -> float:
	if size <= 0.0 or pos < 0.0 or pos > size:
		return 0.0
	if pos <= EDGE_DU:
		return -1.0
	return 1.0 if pos >= size - EDGE_DU else 0.0


func _key_axis(pos_key: int, neg_key: int) -> float:
	return (1.0 if _held.get(pos_key, false) else 0.0) - (1.0 if _held.get(neg_key, false) else 0.0)


func _stick(axis: int) -> float:
	var v: float = _axes.get(axis, 0.0)
	return v if absf(v) > PAD_DEADZONE else 0.0


static func _make(kind: StringName, payload: Dictionary) -> Dictionary:
	return {&"kind": kind, &"payload": payload}
