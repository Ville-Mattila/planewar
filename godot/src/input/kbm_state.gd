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


## Reads the live Input singleton; `mouse_delta_px` is supplied by the caller (accumulated in _input).
static func poll(mouse_delta_px: Vector2) -> KbmState:
	var k: KbmState = KbmState.new()
	k.w = Input.is_physical_key_pressed(KEY_W)
	k.s = Input.is_physical_key_pressed(KEY_S)
	k.a = Input.is_physical_key_pressed(KEY_A)
	k.d = Input.is_physical_key_pressed(KEY_D)
	k.q = Input.is_physical_key_pressed(KEY_Q)
	k.e = Input.is_physical_key_pressed(KEY_E)
	k.shift = Input.is_physical_key_pressed(KEY_SHIFT)
	k.space = Input.is_physical_key_pressed(KEY_SPACE)
	k.f = Input.is_physical_key_pressed(KEY_F)
	k.r = Input.is_physical_key_pressed(KEY_R)
	k.lmb = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	k.rmb = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	k.mouse_delta = mouse_delta_px
	return k
