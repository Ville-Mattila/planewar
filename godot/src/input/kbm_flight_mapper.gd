class_name KbmFlightMapper extends FlightMapper
## Keyboard and mouse DIRECT mapper (06 s3.1, s3.5). The mouse moves a virtual stick that recentres with tau
## 0.15 s; Q/E and A/D yaw; Shift BOOST (one tick per press), Space FLIP, F DOCK, R RELEASE, LMB FIRE1, RMB FIRE2.
## Thrust: POWER_KEY (W ramps to 1 at 4/s, release ramps to 0; S = BRAKE) or LEVER (W/S step +-0.25, sticky;
## S pressed at 0 = BRAKE while held). MOUSE_AIM steering is an assist-stack concern (UX-07).

enum ThrottleMode { POWER_KEY, LEVER }

var throttle_mode: ThrottleMode = ThrottleMode.POWER_KEY
## Test seam: Callable() -> KbmState. Default polls Input with the accumulated mouse delta.
var poller: Callable

var _thrust: float = 0.0
var _stick: Vector2 = Vector2.ZERO
var _mouse_acc: Vector2 = Vector2.ZERO
var _prev_w: bool = false
var _prev_s: bool = false
var _brake_latched: bool = false
var _prev_edge: int = 0


## Adds a mouse motion delta (pixels); consumed by the next sample().
func add_mouse_motion(rel: Vector2) -> void:
	_mouse_acc += rel


func current_thrust() -> float:
	return _thrust


func sample(dt: float) -> PilotInput:
	var st: KbmState = null
	if poller.is_valid():
		var raw: Variant = poller.call()
		if raw is KbmState:
			st = raw
	if st == null:
		st = KbmState.poll(_mouse_acc)
	_mouse_acc = Vector2.ZERO
	return map(st, dt)


## Pure mapping of one KbmState; keeps thrust, the virtual stick and press edges between calls.
func map(st: KbmState, dt: float) -> PilotInput:
	var out: PilotInput = PilotInput.new()
	_stick = (_stick + st.mouse_delta * FlightMath.MOUSE_STICK_PER_PX).limit_length(1.0)
	_stick *= exp(-dt / FlightMath.MOUSE_STICK_TAU_S)
	out.roll = _stick.x
	out.pitch = _pitch(-_stick.y)
	out.yaw = (1.0 if (st.q or st.a) else 0.0) - (1.0 if (st.e or st.d) else 0.0)
	var bits: int = _update_throttle(st, dt)
	out.thrust = _thrust
	if st.lmb:
		bits |= PilotInput.FIRE1
	if st.rmb:
		bits |= PilotInput.FIRE2
	if st.f:
		bits |= PilotInput.DOCK
	var edge: int = 0
	if st.shift:
		edge |= PilotInput.BOOST
	if st.space:
		edge |= PilotInput.FLIP
	if st.r:
		edge |= PilotInput.RELEASE
	bits |= edge & ~_prev_edge
	_prev_edge = edge
	out.buttons = bits
	return out


## Updates `_thrust` for the throttle mode; returns the BRAKE bit.
func _update_throttle(st: KbmState, dt: float) -> int:
	var brake: int = 0
	if throttle_mode == ThrottleMode.POWER_KEY:
		_thrust = FlightMath.ramp(_thrust, 1.0 if st.w else 0.0, FlightMath.POWER_KEY_RATE, dt)
		if st.s:
			brake = PilotInput.BRAKE
	else:
		if st.w and not _prev_w:
			_thrust = minf(_thrust + FlightMath.LEVER_STEP, 1.0)
		if st.s and not _prev_s:
			if _thrust <= 0.0:
				_brake_latched = true
			else:
				_thrust = maxf(_thrust - FlightMath.LEVER_STEP, 0.0)
		if not st.s:
			_brake_latched = false
		if _brake_latched:
			brake = PilotInput.BRAKE
	_prev_w = st.w
	_prev_s = st.s
	return brake
