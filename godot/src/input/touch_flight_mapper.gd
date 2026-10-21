class_name TouchFlightMapper extends FlightMapper
## Touch mapper (06 s2.1, s3.5): virtual stick -> roll/pitch (dead zone 0.12, gamma 1.6), sticky throttle handle ->
## thrust, BRAKE/FIRE1/FIRE2/DOCK while held, BOOST/RELEASE/FLIP for one tick per press. FLIP also comes from the
## FLICK_UP gesture (`queue_flip`), which leaves the stick axes untouched. ARCADE steering and auto-throttle are
## assist-stack concerns (UX-07); this mapper is the raw DIRECT reading.

## Test seam: Callable() -> TouchState. Default polls the InputMap actions.
var poller: Callable

var _prev_edge: int = 0
var _flip_queued: bool = false


## Sends FLIP on the next sample() for one tick (FLICK_UP).
func queue_flip() -> void:
	_flip_queued = true


func sample(dt: float) -> PilotInput:
	var st: TouchState = null
	if poller.is_valid():
		var raw: Variant = poller.call()
		if raw is TouchState:
			st = raw
	if st == null:
		st = TouchState.poll()
	return map(st, dt)


## Pure mapping of one TouchState; keeps press edges and the queued flip between calls.
func map(st: TouchState, _dt: float) -> PilotInput:
	var out: PilotInput = PilotInput.new()
	var s: Vector2 = FlightMath.stick(st.stick, FlightMath.TOUCH_DEAD_ZONE, FlightMath.TOUCH_GAMMA)
	out.roll = s.x
	out.pitch = _pitch(s.y)
	out.thrust = clampf(st.throttle, 0.0, 1.0)
	var bits: int = 0
	if st.brake:
		bits |= PilotInput.BRAKE
	if st.fire1:
		bits |= PilotInput.FIRE1
	if st.fire2:
		bits |= PilotInput.FIRE2
	if st.dock:
		bits |= PilotInput.DOCK
	var edge: int = 0
	if st.boost:
		edge |= PilotInput.BOOST
	if st.flip:
		edge |= PilotInput.FLIP
	if st.release:
		edge |= PilotInput.RELEASE
	bits |= edge & ~_prev_edge
	_prev_edge = edge
	if _flip_queued:
		bits |= PilotInput.FLIP
		_flip_queued = false
	out.buttons = bits
	return out
