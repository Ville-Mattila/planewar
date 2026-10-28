class_name LandingMath extends RefCounted
## Pure landing-guide maths (docs/06 s6.4, UX-18). Bands come from hud.json `gauge_*`, which mirror the sim's
## `flight_common` landing bands; a value strictly above a limit is in the next band (Collision.landing_band).

enum Zone { SAFE, DAMAGE, DESTROY }
enum Phase { APPROACH, FLARE, HOVER }


## Band of one gauge reading: <= safe is SAFE, <= damage is DAMAGE, above is DESTROY.
static func zone(value: float, safe: float, damage: float) -> Zone:
	if value > damage:
		return Zone.DESTROY
	if value > safe:
		return Zone.DAMAGE
	return Zone.SAFE


## Descent speed along the pad normal (m/s, positive = sinking). Climbing reads 0 (it never lands).
static func vert_speed(vel: Vector3, pad_up: Vector3) -> float:
	return maxf(-vel.dot(pad_up), 0.0)


## Speed tangent to the pad plane (m/s).
static func horiz_speed(vel: Vector3, pad_up: Vector3) -> float:
	return (vel - pad_up * vel.dot(pad_up)).length()


## "Nose from vertical": angle in degrees between the thrust axis (forward) and the pad normal.
static func nose_from_vertical_deg(fwd: Vector3, pad_up: Vector3) -> float:
	return rad_to_deg(acos(clampf(fwd.dot(pad_up), -1.0, 1.0)))


static func zone_vert(v: float) -> Zone:
	return zone(v, HudMath.param("gauge_vert_safe_mps"), HudMath.param("gauge_vert_damage_mps"))


static func zone_horiz(v: float) -> Zone:
	return zone(v, HudMath.param("gauge_horiz_safe_mps"), HudMath.param("gauge_horiz_damage_mps"))


static func zone_nose(deg: float) -> Zone:
	return zone(deg, HudMath.param("gauge_nose_safe_deg"), HudMath.param("gauge_nose_damage_deg"))


static func zone_color(z: Zone) -> Color:
	match z:
		Zone.SAFE:
			return UiTokens.UI_OK
		Zone.DAMAGE:
			return UiTokens.UI_WARN
	return UiTokens.UI_DANGER


## Gauge bar fill 0..1: the damage limit sits at 1 / gauge_full_scale of the bar, so the red zone has room.
static func fill01(value: float, damage_limit: float) -> float:
	return clampf(value / (damage_limit * HudMath.param("gauge_full_scale")), 0.0, 1.0)


## Position of the safe-band tick on a gauge bar, 0..1.
static func safe_tick01(safe: float, damage_limit: float) -> float:
	return clampf(safe / (damage_limit * HudMath.param("gauge_full_scale")), 0.0, 1.0)


## 06 s6.4: shown when a friendly pad is within landing_guide_range_m and the ship is below landing_guide_agl_m or
## its fuel is under landing_guide_fuel01. pad_dist_m < 0 means no pad.
static func guide_visible(pad_dist_m: float, agl_m: float, fuel01: float) -> bool:
	if pad_dist_m < 0.0 or pad_dist_m > HudMath.param("landing_guide_range_m"):
		return false
	return agl_m < HudMath.param("landing_guide_agl_m") or fuel01 < HudMath.param("landing_guide_fuel01")


## APPROACH until within flare_range_m; FLARE above flare_min_agl_m ("Pitch up, hold thrust"); HOVER below it.
static func phase(pad_dist_m: float, agl_m: float) -> Phase:
	if pad_dist_m < 0.0 or pad_dist_m > HudMath.param("flare_range_m"):
		return Phase.APPROACH
	return Phase.FLARE if agl_m > HudMath.param("flare_min_agl_m") else Phase.HOVER


## Offset of the ship from the pad centre in the pad plane: x along `east` (pad frame right), y along `north`.
## Axes are the pad frame's tangent basis; the drift arrow points from the ship toward the pad (negated offset).
static func pad_offset(pos: Vector3, pad_pos: Vector3, pad_up: Vector3, east: Vector3, north: Vector3) -> Vector2:
	var d: Vector3 = pos - pad_pos
	d -= pad_up * d.dot(pad_up)
	return Vector2(d.dot(east), d.dot(north))


## Drift arrow in du: points toward the pad, length scales with the offset over `pad_radius_m`, capped at
## `drift_arrow_du`. Zero when centred.
static func drift_arrow(offset_m: Vector2, pad_radius_m: float) -> Vector2:
	if offset_m.length_squared() < 0.0001 or pad_radius_m <= 0.0:
		return Vector2.ZERO
	var cap: float = HudMath.param("drift_arrow_du")
	return (-offset_m).normalized() * minf(offset_m.length() / pad_radius_m * cap * 0.5, cap)


## First pad index with no occupant (occupants[i] == 0), -1 if all are taken. `pads` is nearest first.
static func first_free(pads: PackedInt32Array, occupants: PackedInt32Array) -> int:
	for i: int in mini(pads.size(), occupants.size()):
		if occupants[i] == 0:
			return i
	return -1
