class_name KbmState extends RefCounted
## One tick snapshot of keyboard and mouse as the flight mapper reads it (06 s3.1).

var w: bool
var s: bool
var a: bool
var d: bool
var q: bool
var e: bool
var shift: bool
var space: bool
var f: bool
var r: bool
var lmb: bool
var rmb: bool
var mouse_delta: Vector2       ## pixels accumulated since the last tick
## Ground-set actions (UX-48): `steer_*` and `barrel_*` bindings, read by GroundMapper only.
var steer_left: bool
var steer_right: bool
var barrel_up: bool
var barrel_down: bool


static var _defaults: BindingStore = null


## Reads the live Input singleton; `mouse_delta_px` is supplied by the caller (accumulated in _input).
## `store` supplies the (remapped) keys; null uses the defaults of content/ui/remap.json.
static func poll(mouse_delta_px: Vector2, store: BindingStore = null) -> KbmState:
	var st: BindingStore = _store_or_default(store)
	var held: PackedInt32Array = PackedInt32Array()
	for c: int in st.all_codes(BindingStore.KBM):
		if Input.is_physical_key_pressed(c as Key):
			var _ok: bool = held.append(c)
	var k: KbmState = from_held(held, mouse_delta_px, st)
	k.lmb = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	k.rmb = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	return k


## Pure: the snapshot for a set of held physical keycodes under `store` (mouse buttons are not remappable).
## Yaw keeps its two slots as the s3.1 pairs: slot 0 -> a / d, slot 1 -> q / e.
static func from_held(held: PackedInt32Array, mouse_delta_px: Vector2, store: BindingStore = null) -> KbmState:
	var st: BindingStore = _store_or_default(store)
	var k: KbmState = KbmState.new()
	k.w = _down(st, &"throttle_up", held)
	k.s = _down(st, &"brake", held)
	k.a = held.has(st.code(BindingStore.KBM, &"yaw_left", 0)) and st.code(BindingStore.KBM, &"yaw_left", 0) != BindingStore.UNBOUND
	k.q = held.has(st.code(BindingStore.KBM, &"yaw_left", 1)) and st.code(BindingStore.KBM, &"yaw_left", 1) != BindingStore.UNBOUND
	k.d = held.has(st.code(BindingStore.KBM, &"yaw_right", 0)) and st.code(BindingStore.KBM, &"yaw_right", 0) != BindingStore.UNBOUND
	k.e = held.has(st.code(BindingStore.KBM, &"yaw_right", 1)) and st.code(BindingStore.KBM, &"yaw_right", 1) != BindingStore.UNBOUND
	k.shift = _down(st, &"boost", held)
	k.space = _down(st, &"flip", held)
	k.f = _down(st, &"dock", held)
	k.r = _down(st, &"release", held)
	k.steer_left = _down(st, &"steer_left", held)
	k.steer_right = _down(st, &"steer_right", held)
	k.barrel_up = _down(st, &"barrel_up", held)
	k.barrel_down = _down(st, &"barrel_down", held)
	k.mouse_delta = mouse_delta_px
	return k


static func _down(st: BindingStore, action: StringName, held: PackedInt32Array) -> bool:
	for c: int in st.codes_of(BindingStore.KBM, action):
		if held.has(c):
			return true
	return false


static func _store_or_default(store: BindingStore) -> BindingStore:
	if store != null:
		return store
	if _defaults == null:
		_defaults = BindingStore.new()
	return _defaults
