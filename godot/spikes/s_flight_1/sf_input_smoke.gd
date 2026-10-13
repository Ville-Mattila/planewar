class_name SfInputSmoke extends RefCounted
## Scripted device events for `--smoke=kbm|pad|touch`: injects real InputEvents through Input.parse_input_event
## so the whole device path (class detection, mapping, PilotInput, world) runs headless. Sequence: launch and
## climb 0-4 s, pitch over 4-6 s, fly, fire 8-9 s, bomb at 10 s; the caller reports the outcome at 14 s.

const END_S: float = 14.0

var kind: String
var _t: float
var _vp_size: Vector2
var _to_window: Transform2D = Transform2D.IDENTITY   # injected events are window coordinates


func _init(k: String, viewport_size: Vector2, to_window: Transform2D) -> void:
	kind = k
	_vp_size = viewport_size
	_to_window = to_window


func done() -> bool:
	return _t >= END_S


## Advance by `dt` and inject the events for this moment.
func step(dt: float) -> void:
	var t0: float = _t
	_t += dt
	match kind:
		"pad":
			_pad(t0)
		"touch":
			_touch(t0)
		_:
			_kbm(t0)


func _edge(t0: float, at: float) -> bool:
	return t0 < at and _t >= at


func _key(code: Key, down: bool) -> void:
	var e: InputEventKey = InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = down
	Input.parse_input_event(e)


func _kbm(t0: float) -> void:
	if _edge(t0, 0.0 + 1e-3):
		_key(KEY_W, true)
	if _edge(t0, 4.0):
		_key(KEY_DOWN, true)
	if _edge(t0, 4.5):
		_key(KEY_DOWN, false)
	if _edge(t0, 8.0):
		_key(KEY_CTRL, true)
	if _edge(t0, 9.0):
		_key(KEY_CTRL, false)
	if _edge(t0, 10.0):
		_key(KEY_V, true)
	if _edge(t0, 10.5):
		_key(KEY_V, false)


func _axis(axis: JoyAxis, v: float) -> void:
	var e: InputEventJoypadMotion = InputEventJoypadMotion.new()
	e.device = 0
	e.axis = axis
	e.axis_value = v
	Input.parse_input_event(e)


func _button(b: JoyButton, down: bool) -> void:
	var e: InputEventJoypadButton = InputEventJoypadButton.new()
	e.device = 0
	e.button_index = b
	e.pressed = down
	Input.parse_input_event(e)


func _pad(t0: float) -> void:
	if _edge(t0, 0.0 + 1e-3):
		_button(JOY_BUTTON_START, false)   # class switch on the first qualifying event (06 s2.4)
		_axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)
	if _edge(t0, 4.0):
		_axis(JOY_AXIS_LEFT_Y, 0.8)
	if _edge(t0, 5.2):
		_axis(JOY_AXIS_LEFT_Y, 0.0)
	if _edge(t0, 8.0):
		_button(JOY_BUTTON_A, true)
	if _edge(t0, 9.0):
		_button(JOY_BUTTON_A, false)
	if _edge(t0, 10.0):
		_button(JOY_BUTTON_B, true)
	if _edge(t0, 10.5):
		_button(JOY_BUTTON_B, false)


func _touch_ev(idx: int, pos: Vector2, down: bool) -> void:
	var e: InputEventScreenTouch = InputEventScreenTouch.new()
	e.index = idx
	e.position = _to_window * pos
	e.pressed = down
	Input.parse_input_event(e)


func _drag(idx: int, pos: Vector2, rel: Vector2) -> void:
	var e: InputEventScreenDrag = InputEventScreenDrag.new()
	e.index = idx
	e.position = _to_window * pos
	e.relative = _to_window.basis_xform(rel)
	Input.parse_input_event(e)


func _touch(t0: float) -> void:
	var du: float = minf(_vp_size.x / 720.0, _vp_size.y / 340.0)
	var slider: Vector2 = Vector2(36.0 * du, _vp_size.y - 130.0 * du)
	var stick: Vector2 = Vector2(200.0 * du, _vp_size.y - 120.0 * du)
	var fire: Vector2 = _vp_size + Vector2(-76.0, -76.0) * du
	var bomb: Vector2 = _vp_size + Vector2(-184.0, -44.0) * du
	if _edge(t0, 0.0 + 1e-3):
		_touch_ev(0, slider, true)
		_drag(0, slider + Vector2(0.0, -150.0 * du), Vector2(0.0, -150.0 * du))   # slider to ~60 %
		_touch_ev(0, slider, false)
	if _edge(t0, 4.0):
		_touch_ev(1, stick, true)
		_drag(1, stick + Vector2(0.0, 40.0 * du), Vector2(0.0, 40.0 * du))        # stick down: nose down
	if _edge(t0, 5.2):
		_touch_ev(1, stick, false)
	if _edge(t0, 8.0):
		_touch_ev(2, fire, true)
	if _edge(t0, 9.0):
		_touch_ev(2, fire, false)
	if _edge(t0, 10.0):
		_touch_ev(3, bomb, true)
	if _edge(t0, 10.5):
		_touch_ev(3, bomb, false)
