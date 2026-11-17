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


## Unit centres of the `plateau` named_features of `<map_dir>/features.json` (02 s8.4, GD-23); empty when unreadable.
static func load_plateaus(map_dir: String) -> PackedVector3Array:
	var out: PackedVector3Array = PackedVector3Array()
	var f: FileAccess = FileAccess.open(map_dir + "/features.json", FileAccess.READ)
	if f == null:
		return out
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if not (parsed is Dictionary):
		return out
	var d: Dictionary = parsed
	var named: Variant = d.get("named_features", [])
	if not (named is Array):
		return out
	var list: Array = named
	for item: Variant in list:
		if item is Dictionary:
			var e: Dictionary = item
			var dir: Variant = e.get("dir", null)
			if e.get("type", "") == "plateau" and dir is Array:
				var a: Array = dir
				if a.size() == 3:
					var _err: bool = out.append(Vector3(Def.num(a[0]), Def.num(a[1]), Def.num(a[2])).normalized())
	return out

