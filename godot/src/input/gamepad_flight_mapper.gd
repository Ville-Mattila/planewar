class_name GamepadFlightMapper extends FlightMapper
## Gamepad DIRECT mapper (06 s3.1, s3.5): LS -> roll/pitch, LB/RB -> yaw with a 0.15 s ramp, RT -> thrust,
## LT > 0.5 -> BRAKE, L3 BOOST, A FIRE1, B FIRE2, Y FLIP, X DOCK, D-pad Down RELEASE.
## BOOST, FLIP and RELEASE are sent for one tick per press.

var device: int = 0
## Test seam: Callable() -> PadState. Default polls the Input singleton for `device`.
var poller: Callable

var _yaw: float = 0.0
var _prev_edge: int = 0


func sample(dt: float) -> PilotInput:
	var st: PadState = null
	if poller.is_valid():
		var raw: Variant = poller.call()
		if raw is PadState:
			st = raw
	if st == null:
		st = PadState.poll(device)
	return map(st, dt)


## Pure mapping of one PadState; keeps the yaw ramp and press edges between calls.
func map(st: PadState, dt: float) -> PilotInput:
	var out: PilotInput = PilotInput.new()
	var s: Vector2 = FlightMath.stick(st.left_stick, FlightMath.PAD_DEAD_ZONE, FlightMath.PAD_GAMMA)
	out.roll = s.x
	out.pitch = _pitch(-s.y)
	var yaw_target: float = (1.0 if st.rb else 0.0) - (1.0 if st.lb else 0.0)
	_yaw = FlightMath.ramp(_yaw, yaw_target, 1.0 / FlightMath.YAW_RAMP_S, dt)
	out.yaw = -_yaw   # + yaw is nose left (PilotInput); RB turns right
	out.thrust = FlightMath.trigger(st.right_trigger, FlightMath.TRIGGER_DEAD_ZONE)
	var bits: int = 0
	if st.left_trigger > FlightMath.BRAKE_TRIGGER:
		bits |= PilotInput.BRAKE
	if st.a:
		bits |= PilotInput.FIRE1
	if st.b:
		bits |= PilotInput.FIRE2
	if st.x:
		bits |= PilotInput.DOCK
	var edge: int = 0
	if st.l3:
		edge |= PilotInput.BOOST
	if st.y:
		edge |= PilotInput.FLIP
	if st.dpad_down:
		edge |= PilotInput.RELEASE
	bits |= edge & ~_prev_edge
	_prev_edge = edge
	out.buttons = bits
	return out
