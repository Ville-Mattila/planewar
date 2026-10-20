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


## Reads the live Input singleton for `device`.
static func poll(device: int) -> PadState:
	var s: PadState = PadState.new()
	s.left_stick = Vector2(Input.get_joy_axis(device, JOY_AXIS_LEFT_X), Input.get_joy_axis(device, JOY_AXIS_LEFT_Y))
	s.right_trigger = Input.get_joy_axis(device, JOY_AXIS_TRIGGER_RIGHT)
	s.left_trigger = Input.get_joy_axis(device, JOY_AXIS_TRIGGER_LEFT)
	s.lb = Input.is_joy_button_pressed(device, JOY_BUTTON_LEFT_SHOULDER)
	s.rb = Input.is_joy_button_pressed(device, JOY_BUTTON_RIGHT_SHOULDER)
	s.l3 = Input.is_joy_button_pressed(device, JOY_BUTTON_LEFT_STICK)
	s.a = Input.is_joy_button_pressed(device, JOY_BUTTON_A)
	s.b = Input.is_joy_button_pressed(device, JOY_BUTTON_B)
	s.x = Input.is_joy_button_pressed(device, JOY_BUTTON_X)
	s.y = Input.is_joy_button_pressed(device, JOY_BUTTON_Y)
	s.dpad_down = Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_DOWN)
	return s
