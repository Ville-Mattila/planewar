class_name GestureRecognizer extends RefCounted
## Touch gesture recognizer (06 s2.3): tap, double tap, long press, drag, fling, pinch, twist, two-finger drag,
## FLICK_UP (FLIP, 06 s3.5) and the FIRE long-press (wing radial, 06 s3.1). Pure and deterministic: time arrives as
## the `now_ms` argument of feed() and poll(); positions are viewport du (canvas_items stretch). Events with
## device == DEVICE_ID_EMULATION are ignored (06 s2.1).
## Thresholds are client-only feel values: LONG_PRESS_MS (06 s3.3 "long-press ground 0.35 s"), FIRE_HOLD_MS (06 s3.1
## "long-press FIRE 0.5 s") and the flick numbers (06 s3.5) are specified; the rest are UX-04 defaults for S-UX-1.
## A second finger cancels every single-finger gesture; the pair then locks to ONE of pinch, twist or two-finger
## drag (the largest travel past MULTI_SLOP_DU) until a finger lifts, so a two-finger drag can never pinch.

const TAP_SLOP_DU: float = 10.0
const DOUBLE_TAP_MS: int = 300
const DOUBLE_TAP_DU: float = 32.0
const LONG_PRESS_MS: int = 350
const FIRE_HOLD_MS: int = 500
const FLICK_MIN_DU: float = 80.0
const FLICK_WINDOW_MS: int = 200
const FLICK_MIN_SPEED: float = 600.0
const FLING_MIN_SPEED: float = 300.0
const FLING_WINDOW_MS: int = 100
const MULTI_SLOP_DU: float = 12.0

enum _Lock { NONE, PINCH, TWIST, DRAG }

## Screen rects (du) in which a press arms FLICK_UP and FIRE_HOLD; the HUD sets them. Empty rect = never.
var stick_zone: Rect2 = Rect2()
var fire_zone: Rect2 = Rect2()

var _fingers: Dictionary = {}          # int index -> _Finger
var _order: PackedInt32Array = PackedInt32Array()   # finger indices in press order
var _pair: PackedInt32Array = PackedInt32Array()
var _multi: bool = false               # >= 2 fingers seen since the last all-up
var _multi_live: bool = false          # the pair is still down
var _dead: bool = false                # single-finger gestures are off until all fingers lift
var _lock: _Lock = _Lock.NONE
var _began: bool = false
var _c0: Vector2 = Vector2.ZERO
var _d0: float = 1.0
var _a0: float = 0.0
var _c_prev: Vector2 = Vector2.ZERO
var _d_prev: float = 1.0
var _a_prev: float = 0.0
var _tap_valid: bool = false
var _tap_ms: int = 0
var _tap_pos: Vector2 = Vector2.ZERO


class _Finger extends RefCounted:
	var index: int = 0
	var start: Vector2 = Vector2.ZERO
	var start_ms: int = 0
	var pos: Vector2 = Vector2.ZERO
	var last_emit: Vector2 = Vector2.ZERO
	var moved: bool = false
	var dragging: bool = false
	var long_fired: bool = false
	var fire_fired: bool = false
	var in_stick: bool = false
	var in_fire: bool = false
	var flicked: bool = false
	var cancelled: bool = false
	var samples: PackedVector3Array = PackedVector3Array()   # x, y, t_ms


func active_touches() -> int:
	return _fingers.size()


func reset() -> void:
	_fingers.clear()
	_order = PackedInt32Array()
	_pair = PackedInt32Array()
	_multi = false
	_multi_live = false
	_dead = false
	_lock = _Lock.NONE
	_tap_valid = false


## Feeds one event; returns the gestures it completes or advances.
func feed(event: InputEvent, now_ms: int) -> Array[Gesture]:
	var out: Array[Gesture] = []
	if event.device == InputEvent.DEVICE_ID_EMULATION:
		return out
	if event is InputEventScreenTouch:
		var t: InputEventScreenTouch = event
		_check_timers(now_ms, out)
		if t.pressed:
			_on_down(t.index, t.position, now_ms, out)
		else:
			_on_up(t.index, now_ms, out)
	elif event is InputEventScreenDrag:
		var d: InputEventScreenDrag = event
		_check_timers(now_ms, out)
		_on_move(d.index, d.position, now_ms, out)
	return out


## Advances the timers (long press, FIRE hold) without an event; call every physics tick.
func poll(now_ms: int) -> Array[Gesture]:
	var out: Array[Gesture] = []
	_check_timers(now_ms, out)
	return out


func _check_timers(now_ms: int, out: Array[Gesture]) -> void:
	if _multi:
		return
	for key: Variant in _fingers.keys():
		var f: _Finger = _fingers[key]
		if f.moved or f.cancelled:
			continue
		var held: int = now_ms - f.start_ms
		if f.in_fire:
			if not f.fire_fired and held >= FIRE_HOLD_MS:
				f.fire_fired = true
				out.append(Gesture.make(Gesture.Kind.FIRE_HOLD, Gesture.Phase.BEGIN, f.pos, f.start))
		elif not f.long_fired and held >= LONG_PRESS_MS:
			f.long_fired = true
			out.append(Gesture.make(Gesture.Kind.LONG_PRESS, Gesture.Phase.BEGIN, f.pos, f.start))


func _on_down(index: int, p: Vector2, now_ms: int, out: Array[Gesture]) -> void:
	var f: _Finger = _Finger.new()
	f.index = index
	f.start = p
	f.pos = p
	f.last_emit = p
	f.start_ms = now_ms
	f.in_stick = stick_zone.has_area() and stick_zone.has_point(p)
	f.in_fire = fire_zone.has_area() and fire_zone.has_point(p)
	var _ok: bool = f.samples.append(Vector3(p.x, p.y, float(now_ms)))
	_fingers[index] = f
	if not _order.has(index):
		var _added: bool = _order.append(index)
	if _fingers.size() == 2 and not _multi:
		_begin_multi(out)
	elif _multi or _dead:
		f.cancelled = true


func _begin_multi(out: Array[Gesture]) -> void:
	_pair = PackedInt32Array([_order[0], _order[1]])
	var a: _Finger = _fingers[_pair[0]]
	var b: _Finger = _fingers[_pair[1]]
	_cancel_single(a, out)
	b.cancelled = true
	_multi = true
	_multi_live = true
	_lock = _Lock.NONE
	_began = false
	_c0 = (a.pos + b.pos) * 0.5
	_d0 = maxf(a.pos.distance_to(b.pos), 1.0)
	_a0 = (b.pos - a.pos).angle()
	_c_prev = _c0
	_d_prev = _d0
	_a_prev = _a0


## Closes whatever the first finger had open when a second one lands.
func _cancel_single(f: _Finger, out: Array[Gesture]) -> void:
	if f.dragging:
		out.append(_drag_gesture(f, Gesture.Phase.END))
	elif f.fire_fired:
		out.append(Gesture.make(Gesture.Kind.FIRE_HOLD, Gesture.Phase.END, f.pos, f.start))
	elif f.long_fired:
		out.append(Gesture.make(Gesture.Kind.LONG_PRESS, Gesture.Phase.END, f.pos, f.start))
	f.cancelled = true
	f.dragging = false


func _on_up(index: int, now_ms: int, out: Array[Gesture]) -> void:
	if not _fingers.has(index):
		return
	var f: _Finger = _fingers[index]
	var _erased: bool = _fingers.erase(index)
	var at: int = _order.find(index)
	if at >= 0:
		_order.remove_at(at)
	if _multi:
		if _multi_live and _pair.has(index):
			_end_multi(out)
		if _fingers.is_empty():
			_clear_multi()
		return
	_finish_single(f, now_ms, out)


func _clear_multi() -> void:
	_multi = false
	_multi_live = false
	_dead = false
	_pair = PackedInt32Array()
	_lock = _Lock.NONE


func _end_multi(out: Array[Gesture]) -> void:
	_multi_live = false
	_dead = true
	var kind: int = -1
	match _lock:
		_Lock.PINCH:
			kind = Gesture.Kind.PINCH
		_Lock.TWIST:
			kind = Gesture.Kind.TWIST
		_Lock.DRAG:
			kind = Gesture.Kind.TWO_FINGER_DRAG
	if kind >= 0 and _began:
		out.append(Gesture.make(kind as Gesture.Kind, Gesture.Phase.END, _c_prev, _c0))


func _finish_single(f: _Finger, now_ms: int, out: Array[Gesture]) -> void:
	if f.cancelled:
		return
	if f.fire_fired:
		out.append(Gesture.make(Gesture.Kind.FIRE_HOLD, Gesture.Phase.END, f.pos, f.start))
	elif f.dragging:
		out.append(_drag_gesture(f, Gesture.Phase.END))
		var v: Vector2 = _velocity(f, now_ms)
		if not f.long_fired and v.length() >= FLING_MIN_SPEED:
			var g: Gesture = Gesture.make(Gesture.Kind.FLING, Gesture.Phase.BEGIN, f.pos, f.start)
			g.vel = v
			out.append(g)
	elif f.long_fired:
		out.append(Gesture.make(Gesture.Kind.LONG_PRESS, Gesture.Phase.END, f.pos, f.start))
	elif not f.moved and now_ms - f.start_ms < LONG_PRESS_MS:
		out.append(_tap(f.pos, now_ms))


func _tap(p: Vector2, now_ms: int) -> Gesture:
	if _tap_valid and now_ms - _tap_ms <= DOUBLE_TAP_MS and p.distance_to(_tap_pos) <= DOUBLE_TAP_DU:
		_tap_valid = false
		return Gesture.make(Gesture.Kind.DOUBLE_TAP, Gesture.Phase.BEGIN, p, p)
	_tap_valid = true
	_tap_ms = now_ms
	_tap_pos = p
	return Gesture.make(Gesture.Kind.TAP, Gesture.Phase.BEGIN, p, p)


func _drag_gesture(f: _Finger, phase: Gesture.Phase) -> Gesture:
	var g: Gesture = Gesture.make(Gesture.Kind.DRAG, phase, f.pos, f.start)
	g.delta = f.pos - f.last_emit
	g.held = f.long_fired
	return g


func _on_move(index: int, p: Vector2, now_ms: int, out: Array[Gesture]) -> void:
	if not _fingers.has(index):
		return
	var f: _Finger = _fingers[index]
	f.pos = p
	if _multi:
		if _multi_live and _pair.has(index):
			_update_multi(out)
		return
	if f.cancelled:
		return
	var _ok: bool = f.samples.append(Vector3(p.x, p.y, float(now_ms)))
	_trim(f, now_ms)
	if f.in_stick and not f.flicked and _is_flick_up(f, now_ms):
		f.flicked = true
		out.append(Gesture.make(Gesture.Kind.FLICK_UP, Gesture.Phase.BEGIN, p, f.start))
	if not f.dragging and not f.fire_fired and f.start.distance_to(p) > TAP_SLOP_DU:
		f.moved = true
		f.dragging = true
		var g: Gesture = _drag_gesture(f, Gesture.Phase.BEGIN)
		g.delta = p - f.start
		out.append(g)
	elif f.dragging:
		out.append(_drag_gesture(f, Gesture.Phase.UPDATE))
	f.last_emit = p


func _trim(f: _Finger, now_ms: int) -> void:
	var keep: int = maxi(FLICK_WINDOW_MS, FLING_WINDOW_MS)
	while f.samples.size() > 2 and f.samples[0].z < float(now_ms - keep):
		f.samples.remove_at(0)


## FLICK_UP (06 s3.5): >= 80 du net upward travel within 0.2 s and peak upward speed >= 600 du/s.
func _is_flick_up(f: _Finger, now_ms: int) -> bool:
	var lo: float = float(now_ms - FLICK_WINDOW_MS)
	var first: int = -1
	for i: int in f.samples.size():
		if f.samples[i].z >= lo:
			first = i
			break
	if first < 0 or f.samples[first].y - f.pos.y < FLICK_MIN_DU:
		return false
	for i: int in range(first + 1, f.samples.size()):
		var dt: float = maxf(f.samples[i].z - f.samples[i - 1].z, 1.0) / 1000.0
		if (f.samples[i - 1].y - f.samples[i].y) / dt >= FLICK_MIN_SPEED:
			return true
	return false


func _velocity(f: _Finger, now_ms: int) -> Vector2:
	var lo: float = float(now_ms - FLING_WINDOW_MS)
	var first: int = -1
	for i: int in f.samples.size():
		if f.samples[i].z >= lo:
			first = i
			break
	if first < 0 or first >= f.samples.size() - 1:
		return Vector2.ZERO
	var a: Vector3 = f.samples[first]
	var b: Vector3 = f.samples[f.samples.size() - 1]
	var dt: float = maxf(b.z - a.z, 1.0) / 1000.0
	return Vector2(b.x - a.x, b.y - a.y) / dt


func _update_multi(out: Array[Gesture]) -> void:
	var a: _Finger = _fingers[_pair[0]]
	var b: _Finger = _fingers[_pair[1]]
	var c: Vector2 = (a.pos + b.pos) * 0.5
	var d: float = maxf(a.pos.distance_to(b.pos), 1.0)
	var ang: float = (b.pos - a.pos).angle()
	if _lock == _Lock.NONE:
		_try_lock(c, d, ang)
		if _lock == _Lock.NONE:
			return
	var phase: Gesture.Phase = Gesture.Phase.UPDATE if _began else Gesture.Phase.BEGIN
	var g: Gesture = null
	match _lock:
		_Lock.PINCH:
			g = Gesture.make(Gesture.Kind.PINCH, phase, c, _c0)
			g.value = log(d / _d_prev)
		_Lock.TWIST:
			g = Gesture.make(Gesture.Kind.TWIST, phase, c, _c0)
			g.value = wrapf(ang - _a_prev, -PI, PI)
		_Lock.DRAG:
			g = Gesture.make(Gesture.Kind.TWO_FINGER_DRAG, phase, c, _c0)
			g.delta = c - _c_prev
	var changed: bool = absf(g.value) > 0.0 or g.delta != Vector2.ZERO
	if changed or not _began:
		out.append(g)
		_began = true
	_c_prev = c
	_d_prev = d
	_a_prev = ang


## Locks the pair to the motion with the largest travel past MULTI_SLOP_DU.
func _try_lock(c: Vector2, d: float, ang: float) -> void:
	var pinch: float = absf(d - _d0)
	var twist: float = absf(wrapf(ang - _a0, -PI, PI)) * _d0 * 0.5
	var drag: float = c.distance_to(_c0)
	var best: float = maxf(pinch, maxf(twist, drag))
	if best <= MULTI_SLOP_DU:
		return
	if best == drag:
		_lock = _Lock.DRAG
	elif best == pinch:
		_lock = _Lock.PINCH
	else:
		_lock = _Lock.TWIST
