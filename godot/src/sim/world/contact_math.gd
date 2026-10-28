class_name ContactMath extends RefCounted
## The pure classification and sweep math of `Collision` (A-73 extract, GD-15): `Collision.classify_terrain`,
## `landing_band` and `sweep_sphere` delegate here and its hot loops call these directly (static either way). Static,
## allocation-free; constants from `flight_common` only.


## 03 s6.1 ship-terrain classes from flight_common: > terrain_kill_speed destroy, > terrain_damage_speed damage,
## else scrape.
static func classify_terrain(hit_normal_speed: float, common: FlightCommonDef) -> int:
	if hit_normal_speed > common.terrain_kill_speed:
		return Collision.T_DESTROY
	if hit_normal_speed > common.terrain_damage_speed:
		return Collision.T_DAMAGE
	return Collision.T_SCRAPE


## 03 s6.4 / R0 B.5 landing band: safe within all landing_safe_* limits, destroyed beyond any landing_damage_*
## limit (tilt: landing_damage_tilt_deg), else damage. v_vert is the descent speed along the pad normal.
static func landing_band(v_vert: float, v_hor: float, tilt_deg: float, common: FlightCommonDef) -> int:
	if v_vert > common.landing_damage_v_vert or v_hor > common.landing_damage_v_hor \
			or tilt_deg > common.landing_damage_tilt_deg:
		return Collision.L_DESTROY
	if v_vert > common.landing_safe_v_vert or v_hor > common.landing_safe_v_hor \
			or tilt_deg > common.landing_safe_pitch_deg:
		return Collision.L_DAMAGE
	return Collision.L_SAFE


## Entry parameter t in [0, 1] of the segment a -> b into the sphere (c, r); 0 if a starts inside; -1.0 on a miss.
static func sweep_sphere(a: Vector3, b: Vector3, c: Vector3, r: float) -> float:
	var d: Vector3 = b - a
	var f: Vector3 = a - c
	var cc: float = f.length_squared() - r * r
	if cc <= 0.0:
		return 0.0
	var aa: float = d.length_squared()
	var bb: float = f.dot(d)
	if bb >= 0.0 or aa <= 0.0:
		return -1.0
	var disc: float = bb * bb - aa * cc
	if disc < 0.0:
		return -1.0
	var t: float = (-bb - sqrt(disc)) / aa
	return t if t <= 1.0 else -1.0
