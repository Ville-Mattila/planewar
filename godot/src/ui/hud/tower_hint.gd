class_name TowerHint extends RefCounted
## "Flak: stay below 150 m" / "Autocannon: climb above 400 m" (docs/06 s6.1, UX-19; refresh 4 Hz). The advice comes from the
## tower def envelope in ContentDB (`h_rel_min`, `h_rel_max`, `target_agl_min`), never from literals.

enum Rule { BELOW, ABOVE }

var tower: int = 0
var def: StringName = &""
var rule: Rule = Rule.BELOW
var limit_m: float = 0.0
var inside: bool = false
var dist: float = 0.0


## An AGL floor means the tower cannot hit a ship below it; a positive `h_rel_min` is a floor above the tower; otherwise
## the way out is over the ceiling.
static func rule_for(env: Dictionary) -> Rule:
	if _num(env, "target_agl_min", 0.0) > 0.0 or _num(env, "h_rel_min", 0.0) > 0.0:
		return Rule.BELOW
	return Rule.ABOVE


static func limit_for(env: Dictionary) -> float:
	var agl_min: float = _num(env, "target_agl_min", 0.0)
	if agl_min > 0.0:
		return agl_min
	if _num(env, "h_rel_min", 0.0) > 0.0:
		return _num(env, "h_rel_min", 0.0)
	return _num(env, "h_rel_max", 0.0)


## True when the ship (height above the tower `h_rel`, height above ground `agl`) is inside the envelope.
static func in_envelope(env: Dictionary, h_rel: float, agl: float) -> bool:
	if h_rel < _num(env, "h_rel_min", -INF) or h_rel > _num(env, "h_rel_max", INF):
		return false
	return agl >= _num(env, "target_agl_min", 0.0)


static func key(r: Rule) -> StringName:
	return &"hud.hint.below" if r == Rule.BELOW else &"hud.hint.above"


## One hint per hostile, visible tower type inside its sensor radius (nearest of the type), nearest first, at most
## hud.json `tower_hint_max`. `agl` is the ship's height above ground (the caller reads the terrain).
static func from_view(v: SimView, ship: int, team: int, agl: float) -> Array[TowerHint]:
	var out: Array[TowerHint] = []
	if not v.alive(ship):
		return out
	var p: Vector3 = v.pos(ship)
	var seen: Dictionary = {}
	var found: Array[TowerHint] = []
	for id: int in v.ids_near(p, HudMath.param("threat_range_m"), int(HudMath.param("tower_mask"))):
		var sd: StructureDef = ContentDB.structure(v.def_id(id))
		if sd == null or not sd.is_tower() or v.team(id) == team or not v.visible_to(team, id):
			continue
		var tp: Vector3 = v.pos(id)
		var d: float = p.distance_to(tp)
		if d > sd.sensor_radius:
			continue
		var h: TowerHint = TowerHint.new()
		h.tower = id
		h.def = sd.id
		h.dist = d
		h.rule = rule_for(sd.tower)
		h.limit_m = limit_for(sd.tower)
		h.inside = in_envelope(sd.tower, p.length() - tp.length(), agl)
		found.append(h)
	found.sort_custom(func(a: TowerHint, b: TowerHint) -> bool: return a.dist < b.dist)
	var cap: int = int(HudMath.param("tower_hint_max"))
	for h: TowerHint in found:
		if out.size() >= cap:
			break
		if not seen.has(h.def):
			seen[h.def] = true
			out.append(h)
	return out


func text() -> String:
	return tr(key(rule)).format({"name": tr(StringName("hud.tower.%s" % def)), "m": int(roundf(limit_m))})


static func _num(env: Dictionary, k: String, fallback: float) -> float:
	var x: Variant = env.get(k, fallback)
	return x if x is float or x is int else fallback
