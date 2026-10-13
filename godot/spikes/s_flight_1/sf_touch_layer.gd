class_name SfTouchLayer extends Control
## Phone-landscape Chase touch layout (06 s4.3): sticky thrust slider (relative drag, set and forget), dynamic
## stick zone with flick-up FLIP, FIRE / BOMB / BOOST (tap) / BRAKE (hold) / DOCK (hold). Multi-touch: each
## control owns a finger index while it is down. Positions and sizes in du from 06 s4.3; 1 du is fitted so the
## 720 x 340 du reference safe rect fits the viewport.

enum Btn { FIRE, BOMB, BOOST, BRAKE, DOCK }
const _BTN_LABEL: PackedStringArray = ["FIRE", "BOMB", "BOOST", "BRAKE", "DOCK"]
const _BTN_POS: PackedVector2Array = [Vector2(-76, -76), Vector2(-184, -44), Vector2(-184, -112),
	Vector2(-176, -184), Vector2(-76, -168)]

var slider_h: float               # 0..1 sticky
var stick: Vector2 = Vector2.ZERO # x right, y up, |stick| <= 1
var held: PackedByteArray = PackedByteArray([0, 0, 0, 0, 0])
var boost_tap: bool               # consumed by SfInput
var flick: bool                   # consumed by SfInput
var active_touches: int
var _p: Dictionary
var _du: float = 1.0
var _btn_d: PackedFloat32Array
var _finger_ctl: Dictionary[int, int] = {}    # finger index -> control id (0..4 buttons, 10 slider, 11 stick)
var _stick_base: Vector2
var _stick_finger: int = -1
var _hist_t: PackedFloat64Array = PackedFloat64Array()
var _hist_y: PackedFloat32Array = PackedFloat32Array()
var _slider_last_y: float


func setup(input_params: Dictionary) -> void:
	_p = input_params
	_btn_d = PackedFloat32Array([SfDefs.num(_p, "touch_fire_du"), SfDefs.num(_p, "touch_bomb_du"),
		SfDefs.num(_p, "touch_button_du"), SfDefs.num(_p, "touch_button_du"), SfDefs.num(_p, "touch_button_du")])
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _process(_delta: float) -> void:
	_du = minf(size.x / 720.0, size.y / 340.0)
	if visible:
		queue_redraw()


func _btn_centre(i: int) -> Vector2:
	return Vector2(size.x, size.y) + _BTN_POS[i] * _du


func _slider_rect() -> Rect2:
	var w: float = SfDefs.num(_p, "touch_slider_w_du") * _du
	var h: float = SfDefs.num(_p, "touch_slider_h_du") * _du
	return Rect2(8.0 * _du, size.y - 260.0 * _du, w, h)


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		var t: InputEventScreenTouch = event as InputEventScreenTouch
		if t.pressed:
			_touch_down(t.index, t.position)
		else:
			_touch_up(t.index)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var g: InputEventScreenDrag = event as InputEventScreenDrag
		_drag(g.index, g.position, g.relative)
		get_viewport().set_input_as_handled()


func _touch_down(idx: int, pos: Vector2) -> void:
	active_touches += 1
	for i: int in _BTN_POS.size():
		if pos.distance_to(_btn_centre(i)) <= _btn_d[i] * 0.5 * _du + 8.0 * _du:
			_finger_ctl[idx] = i
			held[i] = 1
			if i == Btn.BOOST:
				boost_tap = true
			return
	var sr: Rect2 = _slider_rect().grow(12.0 * _du)
	if sr.has_point(pos):
		_finger_ctl[idx] = 10
		_slider_last_y = pos.y
		return
	if pos.x < size.x * 0.5 and _stick_finger < 0:
		_finger_ctl[idx] = 11
		_stick_finger = idx
		_stick_base = pos
		stick = Vector2.ZERO
		_hist_t.clear()
		_hist_y.clear()
		_hist(pos.y)


func _touch_up(idx: int) -> void:
	active_touches = maxi(active_touches - 1, 0)
	if not _finger_ctl.has(idx):
		return
	var c: int = _finger_ctl[idx]
	var _e: bool = _finger_ctl.erase(idx)
	if c < 10:
		held[c] = 0
	elif c == 11:
		_stick_finger = -1
		stick = Vector2.ZERO


func _drag(idx: int, pos: Vector2, rel: Vector2) -> void:
	if not _finger_ctl.has(idx):
		return
	var c: int = _finger_ctl[idx]
	if c == 10:
		slider_h = clampf(slider_h - rel.y / _slider_rect().size.y, 0.0, 1.0)
	elif c == 11:
		var r: float = SfDefs.num(_p, "touch_stick_base_du") * 0.5 * _du
		var off: Vector2 = (pos - _stick_base) / r
		stick = Vector2(off.x, -off.y).limit_length(1.0)
		_hist(pos.y)
		_check_flick()


func _hist(y: float) -> void:
	var _a: bool = _hist_t.push_back(float(Time.get_ticks_usec()) * 1.0e-6)
	var _b: bool = _hist_y.push_back(y)


# FLICK_UP: >= flick_du net upward travel within flick_s, peak speed >= flick_speed_du (06 s3.5).
func _check_flick() -> void:
	var now: float = _hist_t[_hist_t.size() - 1]
	var y_now: float = _hist_y[_hist_y.size() - 1]
	var peak: float = 0.0
	for i: int in range(_hist_t.size() - 1, 0, -1):
		if now - _hist_t[i - 1] > SfDefs.num(_p, "flick_s"):
			break
		var dt: float = maxf(_hist_t[i] - _hist_t[i - 1], 1.0e-4)
		peak = maxf(peak, (_hist_y[i - 1] - _hist_y[i]) / dt / _du)
		if (_hist_y[i - 1] - y_now) / _du >= SfDefs.num(_p, "flick_du") and peak >= SfDefs.num(_p, "flick_speed_du"):
			flick = true
			_hist_t.clear()
			_hist_y.clear()
			_hist(y_now)
			return


func _draw() -> void:
	var font: Font = ThemeDB.fallback_font
	var fs: int = maxi(int(13.0 * _du), 10)
	var sr: Rect2 = _slider_rect()
	draw_rect(sr, Color(1, 1, 1, 0.12), true)
	draw_rect(sr, Color(1, 1, 1, 0.5), false, 2.0)
	var hy: float = sr.end.y - sr.size.y * slider_h
	draw_rect(Rect2(sr.position.x - 4.0, hy - 6.0 * _du, sr.size.x + 8.0, 12.0 * _du), Color(1, 0.8, 0.2, 0.9), true)
	draw_string(font, Vector2(sr.position.x, sr.position.y - 6.0), "%d%%" % roundi(slider_h * 100.0),
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	if _stick_finger >= 0:
		var r: float = SfDefs.num(_p, "touch_stick_base_du") * 0.5 * _du
		draw_circle(_stick_base, r, Color(1, 1, 1, 0.15))
		draw_arc(_stick_base, r, 0.0, TAU, 32, Color(1, 1, 1, 0.5), 2.0)
		var knob: Vector2 = _stick_base + Vector2(stick.x, -stick.y) * r
		draw_circle(knob, SfDefs.num(_p, "touch_stick_knob_du") * 0.5 * _du, Color(1, 1, 1, 0.6))
	else:
		draw_string(font, Vector2(90.0 * _du, size.y - 60.0 * _du), "stick: touch here (flick up = FLIP)",
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.5))
	for i: int in _BTN_POS.size():
		var c: Vector2 = _btn_centre(i)
		var rr: float = _btn_d[i] * 0.5 * _du
		draw_circle(c, rr, Color(1, 1, 1, 0.35 if held[i] == 1 else 0.12))
		draw_arc(c, rr, 0.0, TAU, 32, Color(1, 1, 1, 0.6), 2.0)
		draw_string(font, c + Vector2(-rr, fs * 0.35), _BTN_LABEL[i], HORIZONTAL_ALIGNMENT_CENTER, rr * 2.0, fs)
