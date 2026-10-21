class_name TouchState extends RefCounted
## One tick snapshot of the touch flight controls as the mapper reads it (06 s2.1). The `ui` touch controls drive
## the InputMap actions (`ux_stick_*`, `ux_throttle`, `ux_boost`, ...) with Input.action_press(action, strength);
## `input` only reads them, so it never depends on `ui`.

const A_LEFT: StringName = &"ux_stick_left"
const A_RIGHT: StringName = &"ux_stick_right"
const A_UP: StringName = &"ux_stick_up"
const A_DOWN: StringName = &"ux_stick_down"
const A_THROTTLE: StringName = &"ux_throttle"
const A_BOOST: StringName = &"ux_boost"
const A_BRAKE: StringName = &"ux_brake"
const A_FLIP: StringName = &"ux_flip"
const A_FIRE1: StringName = &"ux_fire1"
const A_FIRE2: StringName = &"ux_fire2"
const A_DOCK: StringName = &"ux_dock"
const A_RELEASE: StringName = &"ux_release"

var stick: Vector2             ## raw virtual stick, x right, y up (nose up), unit disc
var throttle: float            ## slider handle h in 0..1 (sticky; the UI holds the action at h)
var boost: bool
var brake: bool
var flip: bool
var fire1: bool
var fire2: bool
var dock: bool
var release: bool


## Reads the live InputMap actions; actions that are not registered read as released.
static func poll() -> TouchState:
	var s: TouchState = TouchState.new()
	s.stick = Vector2(_strength(A_RIGHT) - _strength(A_LEFT), _strength(A_UP) - _strength(A_DOWN))
	s.throttle = clampf(_strength(A_THROTTLE), 0.0, 1.0)
	s.boost = _strength(A_BOOST) > 0.5
	s.brake = _strength(A_BRAKE) > 0.5
	s.flip = _strength(A_FLIP) > 0.5
	s.fire1 = _strength(A_FIRE1) > 0.5
	s.fire2 = _strength(A_FIRE2) > 0.5
	s.dock = _strength(A_DOCK) > 0.5
	s.release = _strength(A_RELEASE) > 0.5
	return s


static func _strength(action: StringName) -> float:
	if not InputMap.has_action(action):
		return 0.0
	return Input.get_action_strength(action)
