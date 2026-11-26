class_name PadState extends RefCounted
## One tick snapshot of a gamepad as the flight mapper reads it (06 s3.1).

var left_stick: Vector2        ## raw LS, y positive = down (Godot joy convention)
var right_trigger: float       ## 0..1
var left_trigger: float        ## 0..1
var lb: bool
var rb: bool
var l3: bool
var a: bool
var b: bool
var x: bool
var y: bool
var dpad_down: bool
var right_stick: Vector2       ## raw RS (ground camera orbit, UX-48)
var barrel_up: bool            ## ground-set actions (UX-48), read by GroundMapper only
var barrel_down: bool


static var _defaults: BindingStore = null


## Reads the live Input singleton for `device`; `store` supplies the remapped buttons (null = defaults).
static func poll(device: int, store: BindingStore = null) -> PadState:
	var s: PadState = PadState.new()
	s.left_stick = Vector2(Input.get_joy_axis(device, JOY_AXIS_LEFT_X), Input.get_joy_axis(device, JOY_AXIS_LEFT_Y))
	s.right_stick = Vector2(Input.get_joy_axis(device, JOY_AXIS_RIGHT_X), Input.get_joy_axis(device, JOY_AXIS_RIGHT_Y))
	s.right_trigger = Input.get_joy_axis(device, JOY_AXIS_TRIGGER_RIGHT)
	s.left_trigger = Input.get_joy_axis(device, JOY_AXIS_TRIGGER_LEFT)
	var st: BindingStore = _store_or_default(store)
	var held: PackedInt32Array = PackedInt32Array()
	for c: int in st.all_codes(BindingStore.PAD):
		if Input.is_joy_button_pressed(device, c as JoyButton):
			var _ok: bool = held.append(c)
	return with_buttons(s, held, st)


## Pure: sets the button fields of `base` from the held JoyButtons under `store`.
static func with_buttons(base: PadState, held: PackedInt32Array, store: BindingStore = null) -> PadState:
	var st: BindingStore = _store_or_default(store)
	base.lb = _down(st, &"yaw_left", held)
	base.rb = _down(st, &"yaw_right", held)
	base.a = _down(st, &"fire1", held)
	base.b = _down(st, &"fire2", held)
	base.x = _down(st, &"dock", held)
	base.l3 = _down(st, &"boost", held)
	base.y = _down(st, &"flip", held)
	base.dpad_down = _down(st, &"release", held)
	base.barrel_up = _down(st, &"barrel_up", held)
	base.barrel_down = _down(st, &"barrel_down", held)
	return base


static func _down(st: BindingStore, action: StringName, held: PackedInt32Array) -> bool:
	var c: int = st.code(BindingStore.PAD, action)
	return c != BindingStore.UNBOUND and held.has(c)


static func _store_or_default(store: BindingStore) -> BindingStore:
	if store != null:
		return store
	if _defaults == null:
		_defaults = BindingStore.new()
	return _defaults
