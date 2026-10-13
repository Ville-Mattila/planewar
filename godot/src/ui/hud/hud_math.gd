class_name HudMath extends RefCounted
## Pure flight-instrument maths (docs/06 s6.2). Thresholds come from res://content/ui/hud.json.
## Basis convention (03): forward f = -basis.z. n is the unit surface normal at the craft.

enum Band { DECK, LOW, HIGH, FADE }

const PARAMS_PATH: String = "res://content/ui/hud.json"

static var _params: Dictionary = {}


static func param(key: String) -> float:
	if _params.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PARAMS_PATH))
		var d: Dictionary = {}
		if parsed is Dictionary:
			d = parsed
		_params = d
	var v: Variant = _params.get(key, 0.0)
	return v if v is float or v is int else 0.0


## Pitch above the local tangent plane, radians: asin(clamp(f.n, -1, 1)).
static func pitch(f: Vector3, n: Vector3) -> float:
	return asin(clampf(f.dot(n), -1.0, 1.0))


## Datum altitude in metres: |pos| - PLANET_RADIUS.
static func altitude(pos: Vector3) -> float:
	return pos.length() - Sphere.PLANET_RADIUS


## True within pole_deg of either pole (heading tape shows POLE and freezes).
static func is_pole(n: Vector3) -> bool:
	return absf(n.dot(Sphere.POLE_AXIS)) >= cos(deg_to_rad(param("pole_deg")))


## ENU heading in degrees [0, 360): 0 = north, 90 = east. NAN when undefined (pole or looking straight up/down).
static func heading_deg(f: Vector3, n: Vector3) -> float:
	if is_pole(n):
		return NAN
	var north: Vector3 = Sphere.POLE_AXIS - n * Sphere.POLE_AXIS.dot(n)
	var f_t: Vector3 = f - n * f.dot(n)
	if f_t.length_squared() < 1e-8 or north.length_squared() < 1e-8:
		return NAN
	north = north.normalized()
	var east: Vector3 = north.cross(n)
	return wrap_deg(rad_to_deg(atan2(f_t.dot(east), f_t.dot(north))))


## Wraps degrees into [0, 360).
static func wrap_deg(a: float) -> float:
	return fposmod(a, 360.0)


## Signed shortest difference b - a in (-180, 180].
static func delta_deg(a: float, b: float) -> float:
	var d: float = wrap_deg(b - a)
	return d - 360.0 if d > 180.0 else d


## Horizon dip below the tangent plane at height h, radians: acos(R / (R + h)). h < 0 clamps to 0.
static func limb_dip(h: float) -> float:
	return acos(Sphere.PLANET_RADIUS / (Sphere.PLANET_RADIUS + maxf(h, 0.0)))


## Ladder rung angles (deg, multiples of step) within half_range of the current pitch, ascending.
static func ladder_marks(pitch_rad: float, step_deg: float, half_range_deg: float) -> PackedFloat32Array:
	var out: PackedFloat32Array = PackedFloat32Array()
	var p: float = rad_to_deg(pitch_rad)
	var k: int = ceili((p - half_range_deg) / step_deg)
	while float(k) * step_deg <= p + half_range_deg:
		var _ok: bool = out.append(float(k) * step_deg)
		k += 1
	return out


## Screen y offset (down positive) of a rung at mark_deg from the ladder centre, before bank rotation.
static func ladder_y(mark_deg: float, pitch_rad: float, px_per_deg: float) -> float:
	return (rad_to_deg(pitch_rad) - mark_deg) * px_per_deg


## Screen y offset of the visible limb: below the 0 deg rung by the dip.
static func limb_y(pitch_rad: float, h: float, px_per_deg: float) -> float:
	return ladder_y(-rad_to_deg(limb_dip(h)), pitch_rad, px_per_deg)


## Altitude band: AGL < deck -> DECK; else datum altitude < low -> LOW, < high -> HIGH, otherwise FADE.
static func band(agl: float, alt: float) -> Band:
	if agl < param("deck_agl_m"):
		return Band.DECK
	if alt < param("low_alt_m"):
		return Band.LOW
	if alt < param("high_alt_m"):
		return Band.HIGH
	return Band.FADE


## Uplink strength 1..0 over [uplink_start, uplink_lost]; 1 below the start.
static func uplink(alt: float) -> float:
	var a: float = param("uplink_start_m")
	return clampf(1.0 - (alt - a) / (param("uplink_lost_m") - a), 0.0, 1.0)


static func uplink_visible(alt: float) -> bool:
	return alt >= param("uplink_start_m")


static func uplink_lost(alt: float) -> bool:
	return alt >= param("uplink_lost_m")


## Pulse intensity 0..1: 0 below uplink_pulse_from_m, else a pulse_hz sine of time t seconds.
static func uplink_pulse(alt: float, t: float) -> float:
	if alt < param("uplink_pulse_from_m"):
		return 0.0
	return 0.5 + 0.5 * sin(TAU * param("uplink_pulse_hz") * t)


## Tape x offset (du from centre) of a bearing relative to the current heading.
static func tape_x(bearing: float, heading: float, width_du: float, span_deg: float) -> float:
	return delta_deg(heading, bearing) / span_deg * width_du
