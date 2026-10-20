class_name FlightMapper extends RefCounted
## Base for per-class flight mappers (06 s3.5): turns one tick of device state into a raw PilotInput.
## The assist stack (UX-07) runs after the mapper.

var invert_pitch: bool = false


## Raw PilotInput for one sim tick of `dt` seconds. Overridden by the concrete mappers.
func sample(_dt: float) -> PilotInput:
	return PilotInput.new()


## Pitch sign: stick/mouse up is nose up (+), flipped by `invert_pitch`.
func _pitch(up: float) -> float:
	return -up if invert_pitch else up
