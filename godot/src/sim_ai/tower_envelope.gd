class_name TowerEnvelope extends RefCounted
## One tower def's targeting envelope and priority (05 s6.8, R0 C2-15): built from the `tower` block of `towers.json`, so
## no envelope number lives in sim_ai. `eligible` is the think's gate: range, height relative to the tower within
## [`h_rel_min`, `h_rel_max`], AGL >= `target_agl_min` when set, `target_kinds`. `base_weight` is the rank weight of
## `target_priority` (`TargetParams.rank_weights`), 0 for a class the tower never lists.

const KIND_SHIP: int = 1
const KIND_GROUND: int = 2

var weapon: StringName = &""
var h_rel_min: float = 0.0
var h_rel_max: float = 0.0
var agl_min: float = 0.0
var turn_rad_s: float = 0.0
var kinds: int = 0
var w_by_def: PackedFloat32Array = PackedFloat32Array()
var w_loaded: float = 0.0
var hauler_def: int = -1


## `block` = a towers.json `tower` dictionary; `entity_index` = `ContentSet.entity_index`.
static func from_block(block: Dictionary, entity_index: Dictionary, params: TargetParams) -> TowerEnvelope:
	var e: TowerEnvelope = TowerEnvelope.new()
	e.weapon = StringName(str(block.get("weapon", "")))
	e.h_rel_min = TargetParams.num(block, "h_rel_min", 0.0)
	e.h_rel_max = TargetParams.num(block, "h_rel_max", 0.0)
	e.agl_min = TargetParams.num(block, "target_agl_min", 0.0)
	e.turn_rad_s = deg_to_rad(TargetParams.num(block, "turret_turn_dps", 0.0))
	for k: String in _strings(block, "target_kinds"):
		e.kinds |= KIND_SHIP if k == "ship" else (KIND_GROUND if k == "ground" else 0)
	var _r: int = e.w_by_def.resize(DefRanges.END)
	e.w_by_def.fill(0.0)
	e.hauler_def = TargetParams.entity_def(entity_index, TargetParams.HAULER_KEY) if entity_index.has(TargetParams.HAULER_KEY) else -1
	var prio: PackedStringArray = _strings(block, "target_priority")
	for i: int in prio.size():
		var w: float = params.rank_weights[mini(i, params.rank_weights.size() - 1)] if params.rank_weights.size() > 0 else 0.0
		var name: StringName = StringName(prio[i])
		if name == TargetParams.LOADED_KEY:
			e.w_loaded = w
		elif entity_index.has(name):
			e.w_by_def[TargetParams.entity_def(entity_index, name)] = w
	return e


static func _strings(d: Dictionary, key: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var v: Variant = d.get(key)
	if v is Array:
		var a: Array = v
		for x: Variant in a:
			var _ok: bool = out.append(str(x))
	return out


func base_weight(def_id: int, loaded: bool) -> float:
	if loaded and def_id == hauler_def:
		return w_loaded
	return w_by_def[def_id] if def_id >= 0 and def_id < w_by_def.size() else 0.0


## Height of the target relative to the tower (m) and AGL (m) are the caller's `|p| - |p_tower|` and `|p| - R - terrain`.
func in_envelope(h_rel: float, agl: float) -> bool:
	return h_rel >= h_rel_min and h_rel <= h_rel_max and agl >= agl_min


func kind_ok(def_id: int) -> bool:
	var k: int = DefRanges.kind_of(def_id)
	return (k == DefRanges.K_SHIP and (kinds & KIND_SHIP) != 0) or (k == DefRanges.K_GROUND and (kinds & KIND_GROUND) != 0)


## Full eligibility of a target at `p_t` (def `def_id`) for a tower at `p_tower` with weapon range `range_m`.
func eligible(p_tower: Vector3, p_t: Vector3, def_id: int, range_m: float, terrain_h: float) -> bool:
	if not kind_ok(def_id) or p_tower.distance_squared_to(p_t) > range_m * range_m:
		return false
	var r_t: float = p_t.length()
	return in_envelope(r_t - p_tower.length(), r_t - Sphere.PLANET_RADIUS - terrain_h)
