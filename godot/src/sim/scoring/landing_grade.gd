class_name LandingGrade extends RefCounted
## The single v1 landing grade (02 s17.1, 03 s6.4; 08 SL-1 as simplified by R0 C3-13): a weighted quality score
## q = w_vert (1 - v_vert / n_vert) + w_horiz (1 - v_horiz / n_horiz) + w_tilt (1 - tilt / n_tilt) + w_offset (1 - offset /
## pad_radius_m), every term clamped to [0, 1], and the grade from the Collision landing band, q and the manual flag.
## Weights, norms, thresholds and the hot / dead-stick / manual / repair constants are `scoring.json` `landing` (+ the
## SL-1 `landing_grade.manual_window_m`); `from_def` reads them once. Points are GD-27's (`sim/scoring/` score table).
## Pure after construction: no state, no RNG, no allocation per call.

enum Grade { CRASH, BENT, HARD, FAIR, CLEAN, ACE, AUTO }   # R0 B.3, ordinals frozen (sim/MODULE.md Enumerations)

var w_vert: float = 0.0
var w_horiz: float = 0.0
var w_tilt: float = 0.0
var w_offset: float = 0.0
var n_vert: float = 0.0              ## q norm of the descent speed (m/s; 8 = landing_safe_v_vert)
var n_horiz: float = 0.0             ## q norm of the tangential speed (m/s; 15)
var n_tilt: float = 0.0              ## q norm of the thrust-axis tilt (degrees; 25)
var t_fair: float = 0.0
var t_clean: float = 0.0
var t_ace: float = 0.0
var hot_radius_m: float = 0.0        ## an enemy ship within this of the pad makes the landing hot
var hot_window_s: float = 0.0        ## ... as does a hit taken within this many seconds
var dead_stick_fuel01: float = 0.0   ## fuel01 below this at touchdown: dead stick
var manual_window_m: float = 0.0     ## an assist tick within this horizontal distance of the pad makes it AUTO
var repair_time_mult: float = 1.0    ## repair_time_s x this after a manual FAIR+ landing (P-3)


## The parameters of `scoring.landing` (q_weights, q_norms, q_thresholds, hot_enemy_range_m, hot_hit_window_s,
## dead_stick_fuel01, repair_time_mult) and `scoring.landing_grade.manual_window_m` (the typed `ScoringDef.landing_grade`); null when a key is missing or a
## norm is not positive (validate_content.py enforces the shipped file).
static func from_def(scoring: ScoringDef) -> LandingGrade:
	if scoring == null:
		return null
	var l: Dictionary = scoring.landing
	var w: Dictionary = _dict(l, "q_weights")
	var n: Dictionary = _dict(l, "q_norms")
	var t: Dictionary = _dict(l, "q_thresholds")
	var lg: Dictionary = scoring.landing_grade   # typed ScoringDef.landing_grade (CONTENT-2, R0 B.24 A-122)
	var keys: Array = [[w, "v_vert"], [w, "v_horiz"], [w, "tilt"], [w, "offset"], [n, "v_vert_mps"], [n, "v_horiz_mps"],
		[n, "tilt_deg"], [t, "fair"], [t, "clean"], [t, "ace"], [l, "hot_enemy_range_m"], [l, "hot_hit_window_s"],
		[l, "dead_stick_fuel01"], [l, "repair_time_mult"], [lg, "manual_window_m"]]
	for k: Array in keys:
		var d: Dictionary = k[0]
		if not d.has(k[1]):
			return null
	var g: LandingGrade = LandingGrade.new()
	g.w_vert = Def.num(w["v_vert"])
	g.w_horiz = Def.num(w["v_horiz"])
	g.w_tilt = Def.num(w["tilt"])
	g.w_offset = Def.num(w["offset"])
	g.n_vert = Def.num(n["v_vert_mps"])
	g.n_horiz = Def.num(n["v_horiz_mps"])
	g.n_tilt = Def.num(n["tilt_deg"])
	g.t_fair = Def.num(t["fair"])
	g.t_clean = Def.num(t["clean"])
	g.t_ace = Def.num(t["ace"])
	g.hot_radius_m = Def.num(l["hot_enemy_range_m"])
	g.hot_window_s = Def.num(l["hot_hit_window_s"])
	g.dead_stick_fuel01 = Def.num(l["dead_stick_fuel01"])
	g.repair_time_mult = Def.num(l["repair_time_mult"])
	g.manual_window_m = Def.num(lg["manual_window_m"])
	if g.n_vert <= 0.0 or g.n_horiz <= 0.0 or g.n_tilt <= 0.0:
		return null
	return g


## q in [0, 1] of one touchdown: `v_vert` the descent speed along the pad normal (climbing is negative and scores as 0),
## `v_horiz` the tangential speed, `tilt_deg` the angle between the thrust axis and the pad normal, `offset_m` the
## horizontal distance from the pad centre in the pad frame. A pad radius <= 0 scores the offset term 0.
func q(v_vert: float, v_horiz: float, tilt_deg: float, offset_m: float, pad_radius_m: float) -> float:
	var off: float = 1.0 - offset_m / pad_radius_m if pad_radius_m > 0.0 else 0.0
	return w_vert * clampf(1.0 - v_vert / n_vert, 0.0, 1.0) + w_horiz * clampf(1.0 - v_horiz / n_horiz, 0.0, 1.0) \
			+ w_tilt * clampf(1.0 - tilt_deg / n_tilt, 0.0, 1.0) + w_offset * clampf(off, 0.0, 1.0)


## Grade of a landing in Collision band `band` (L_SAFE / L_DAMAGE / L_DESTROY) with quality `q_value`: CRASH when
## destroyed (band or hull), BENT in the damage band, AUTO for a safe landing that is not manual, else ACE / CLEAN /
## FAIR / HARD by the q thresholds (>=). The physical outcome outranks AUTO (03 s6.4 order: CRASH, BENT, then q).
func grade(band: int, q_value: float, manual: bool) -> Grade:
	if band == Collision.L_DESTROY:
		return Grade.CRASH
	if band == Collision.L_DAMAGE:
		return Grade.BENT
	if not manual:
		return Grade.AUTO
	if q_value >= t_ace:
		return Grade.ACE
	if q_value >= t_clean:
		return Grade.CLEAN
	return Grade.FAIR if q_value >= t_fair else Grade.HARD


## True for the grades that earn the x `repair_time_mult` repair (02 s17.1: a manual landing graded FAIR or better;
## FAIR, CLEAN and ACE are only ever given to manual landings).
static func repair_bonus(g: int) -> bool:
	return g == Grade.FAIR or g == Grade.CLEAN or g == Grade.ACE


static func _dict(d: Dictionary, key: String) -> Dictionary:
	var v: Variant = d.get(key)
	if typeof(v) != TYPE_DICTIONARY:
		return {}
	var out: Dictionary = v
	return out
