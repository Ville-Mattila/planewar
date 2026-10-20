class_name FlightMath extends RefCounted
## Pure flight-mapping math (06 s3.5): radial dead zone, response curve, linear ramps.
## Client-side feel constants from 06 s3.5; they never reach the sim or the content hash, so they are consts here.

const PAD_DEAD_ZONE: float = 0.15
const PAD_GAMMA: float = 1.8
const TRIGGER_DEAD_ZONE: float = 0.05
const BRAKE_TRIGGER: float = 0.5
const YAW_RAMP_S: float = 0.15
const POWER_KEY_RATE: float = 4.0
const LEVER_STEP: float = 0.25
const MOUSE_STICK_TAU_S: float = 0.15
const MOUSE_STICK_PER_PX: float = 0.005


## Radial dead zone `d0` then response `s^gamma`, direction preserved (06 s3.5).
static func stick(v: Vector2, d0: float, gamma: float) -> Vector2:
	var m: float = v.length()
	if m <= d0 or m <= 0.0:
		return Vector2.ZERO
	var s: float = clampf((m - d0) / (1.0 - d0), 0.0, 1.0)
	return v * (pow(s, gamma) / m)


## Linear trigger with a 1-D dead zone, rescaled to 0..1.
static func trigger(v: float, d0: float) -> float:
	if v <= d0:
		return 0.0
	return clampf((v - d0) / (1.0 - d0), 0.0, 1.0)


## Moves `cur` toward `target` by at most `rate * dt`.
static func ramp(cur: float, target: float, rate: float, dt: float) -> float:
	return move_toward(cur, target, rate * dt)
