class_name SunPath extends RefCounted
## Sun direction for the power model (02 s8.4, O-4). A period of 0 is the matchmade fixed sun along +Z; a positive
## `sun_period_s` (campaign / custom moving sun, MatchRules) turns the sun about the X axis once per period, starting at +Z.
## GD-33 owns the phase, the terminator crossing and `cold_trap_sunlit_mult`; this is the minimal `sun_dir(t)` GD-13 needs.


## Unit sun direction `t_s` seconds into the match.
static func dir_at(period_s: float, t_s: float) -> Vector3:
	if period_s <= 0.0:
		return Vector3.BACK
	var a: float = TAU * fposmod(t_s, period_s) / period_s
	return Vector3(0.0, sin(a), cos(a))


## True when `up` lies within `radius_m` (arc length on the datum sphere) of any plateau centre (unit vectors).
static func on_plateau(up: Vector3, centres: PackedVector3Array, radius_m: float) -> bool:
	var min_cos: float = cos(radius_m / Sphere.PLANET_RADIUS)
	for c: Vector3 in centres:
		if up.dot(c) >= min_cos:
			return true
	return false
