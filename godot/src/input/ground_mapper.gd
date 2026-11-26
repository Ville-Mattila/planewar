class_name GroundMapper extends RefCounted
## GROUND-mode mapper for the three input classes (06 s3.2, UX-48, R0 B.31 A-154): drive, steer, BRAKE, FIRE1 and the
## barrel holds of a possessed Harvester or Siege Crawler. Roll is always 0; BOOST, FLIP, DOCK and FIRE2 are never
## sent; `invert_pitch` does not apply (`pitch` is a barrel slew rate: +1 raises, -1 lowers, 0 holds). Yaw is the steer,
## + = left (sim/ground). Stick Y and mouse Y never reach `pitch`; the right stick and the mouse are reported in
## `orbit` for the camera (the router emits them as FREE_LOOK with K_VEC). Steer, barrel and drive keys and the
## pad barrel buttons are read through BindingStore (the `ground` set); RELEASE is one tick per press.

## Test seams: Callable() -> PadState / KbmState / TouchState. Default polls the device.
var pad_poller: Callable
var kbm_poller: Callable
var touch_poller: Callable
var device: int = 0
## Remapped bindings; null uses the defaults. needs app: assign the shared BindingStore after load_file().
var bindings: BindingStore
## Camera orbit of the last sample: mouse pixels (KBM) or right-stick deflection (gamepad); zero on touch.
var orbit: Vector2 = Vector2.ZERO

var _mouse_acc: Vector2 = Vector2.ZERO
var _prev_edge: int = 0


## Adds a mouse motion delta (pixels); consumed by the next KBM sample, never turned into `pitch`.
func add_mouse_motion(rel: Vector2) -> void:
	_mouse_acc += rel


## Drops pending mouse motion, orbit and the RELEASE edge memory (the router calls it on a mode change).
func reset() -> void:
	_mouse_acc = Vector2.ZERO
	orbit = Vector2.ZERO
	_prev_edge = 0


## One raw PilotInput for the active class `kind` (InputClass.Kind).
func sample_for(kind: int) -> PilotInput:
	var acc: Vector2 = _mouse_acc
	_mouse_acc = Vector2.ZERO
	match kind:
		InputClass.Kind.GAMEPAD:
			var p: Variant = pad_poller.call() if pad_poller.is_valid() else null
			var pad: PadState = p if p is PadState else PadState.poll(device, bindings)
			return map_pad(pad)
		InputClass.Kind.POINTER:
			var k: Variant = kbm_poller.call() if kbm_poller.is_valid() else null
			var kbm: KbmState = k if k is KbmState else KbmState.poll(acc, bindings)
			return map_kbm(kbm)
		InputClass.Kind.TOUCH:
			var t: Variant = touch_poller.call() if touch_poller.is_valid() else null
			var touch: TouchState = t if t is TouchState else TouchState.poll()
			return map_touch(touch)
	return PilotInput.new()


## Gamepad: LS Y forward = thrust, back = BRAKE, LS X = steer, RT = FIRE1, RB / LB held = barrel up / down.
func map_pad(st: PadState) -> PilotInput:
	var out: PilotInput = PilotInput.new()
	var s: Vector2 = FlightMath.stick(st.left_stick, FlightMath.PAD_DEAD_ZONE, FlightMath.PAD_GAMMA)
	out.thrust = clampf(-s.y, 0.0, 1.0)
	out.yaw = -s.x
	out.pitch = _hold(st.barrel_up, st.barrel_down)
	var bits: int = _brake_bit(s.y > FlightMath.BRAKE_TRIGGER)
	if FlightMath.trigger(st.right_trigger, FlightMath.TRIGGER_DEAD_ZONE) > FlightMath.BRAKE_TRIGGER:
		bits |= PilotInput.FIRE1
	out.buttons = bits | _release_edge(st.dpad_down)
	orbit = FlightMath.stick(st.right_stick, FlightMath.PAD_DEAD_ZONE, FlightMath.PAD_GAMMA)
	return out


## KBM: W thrust, S BRAKE, steer_left / steer_right (A / D) steer, LMB FIRE1, E / Q held = barrel up / down.
func map_kbm(st: KbmState) -> PilotInput:
	var out: PilotInput = PilotInput.new()
	out.thrust = 1.0 if (st.w and not st.s) else 0.0
	out.yaw = (1.0 if st.steer_left else 0.0) - (1.0 if st.steer_right else 0.0)
	out.pitch = _hold(st.barrel_up, st.barrel_down)
	var bits: int = _brake_bit(st.s)
	if st.lmb:
		bits |= PilotInput.FIRE1
	out.buttons = bits | _release_edge(st.r)
	orbit = st.mouse_delta
	return out


## Touch: stick Y up = thrust, down = BRAKE, stick X = steer, ux_fire1 = FIRE1, ux_barrel_up / ux_barrel_down hold.
func map_touch(st: TouchState) -> PilotInput:
	var out: PilotInput = PilotInput.new()
	var s: Vector2 = FlightMath.stick(st.stick, FlightMath.TOUCH_DEAD_ZONE, FlightMath.TOUCH_GAMMA)
	out.thrust = clampf(s.y, 0.0, 1.0)
	out.yaw = -s.x
	out.pitch = _hold(st.barrel_up, st.barrel_down)
	var bits: int = _brake_bit(s.y < -FlightMath.BRAKE_TRIGGER)
	if st.fire1:
		bits |= PilotInput.FIRE1
	out.buttons = bits | _release_edge(st.release)
	orbit = Vector2.ZERO
	return out


func _hold(up: bool, down: bool) -> float:
	return (1.0 if up else 0.0) - (1.0 if down else 0.0)


func _brake_bit(brake: bool) -> int:
	return PilotInput.BRAKE if brake else 0


## RELEASE for one tick per press.
func _release_edge(held: bool) -> int:
	var edge: int = PilotInput.RELEASE if held else 0
	var out: int = edge & ~_prev_edge
	_prev_edge = edge
	return out
