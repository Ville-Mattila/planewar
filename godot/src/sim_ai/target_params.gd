class_name TargetParams extends RefCounted
## Parameters of the target choice points (05 s6.2 Dart `U(t)`, s6.4 class weights, s6.8 tower priority; R0 C2-15).
## Read from an `autopilots.json` entry: `target_weights` (class name -> weight), `target_dist_falloff_m`,
## `target_under_tower_penalty`, `switch_margin`. The multipliers 05 writes inline (1.5, 1.3, 0.5, ...) and the tower block
## are optional keys with the 05 values as defaults; **needs content:** `autopilots.schema.json` should list them.
## Class names are the weight keys: a ship's def id (`bomber`, `dart`, ...) plus the pseudo classes `hauler_loaded` and
## (AI-14, the Lancer's 05 s6.4 "structures under construction") `structure_building`: any structure still building.

const LOADED_KEY: StringName = &"hauler_loaded"
const HAULER_KEY: StringName = &"hauler"
const BUILDING_KEY: StringName = &"structure_building"
const DEFAULT_RANK_WEIGHTS: Array = [100.0, 80.0, 60.0, 50.0, 40.0, 30.0, 25.0, 20.0]

var falloff_m: float = 1000.0              ## target_dist_falloff_m
var under_tower_penalty: float = 1.0       ## target_under_tower_penalty (1 = off)
var switch_margin: float = 1.2             ## 05 s4.2: a new choice must beat the current by 20 %
var attacked_mult: float = 1.5             ## target attacked a friendly within `attacked_window_s`
var attacked_window_s: float = 5.0
var low_hp_mult: float = 1.3               ## hp01 below `low_hp01`
var low_hp01: float = 0.5
var focus_mult: float = 0.5                ## `focus_count`+ friendly ships already target it
var focus_count: int = 2
var tower_switch_margin: float = 1.3       ## 05 s6.8
var tower_attacking_mult: float = 1.5      ## target attacking a friendly structure within `tower_attack_radius_m`
var tower_attack_radius_m: float = 600.0
var tower_hp_gain: float = 0.5             ## (1 + gain * (1 - hp01))
var tower_crowd_mult: float = 0.7          ## more than `tower_crowd_count` friendly towers already target it
var tower_crowd_count: int = 2
var max_candidates: int = 8                ## 05 s10: full scoring for at most this many (cost bound; `out`/scratch must hold it)
var guard_mult: float = 2.0                ## GUARD order: attackers of the guarded structure
var rank_weights: PackedFloat32Array = PackedFloat32Array()   ## tower base weights by priority rank
var weights: Dictionary = {}               ## class name (StringName) -> weight

var w_by_def: PackedFloat32Array = PackedFloat32Array()       ## indexed by def id, filled by `bind`
var w_loaded: float = 0.0                  ## hauler_loaded weight
var w_building: float = 0.0                ## AI-14: structure_building weight (0: structures weigh by their def only)
var hauler_def: int = -1


static func from_dict(d: Dictionary) -> TargetParams:
	var p: TargetParams = TargetParams.new()
	for k: String in ["target_weights", "target_dist_falloff_m", "target_under_tower_penalty", "switch_margin"]:
		if not d.has(k):
			return null
	var w: Dictionary = dict_of(d, "target_weights")
	for k: Variant in w.keys():
		var name: String = str(k)
		p.weights[StringName(name)] = num(w, name, 0.0)
	p.falloff_m = num(d, "target_dist_falloff_m", p.falloff_m)
	p.under_tower_penalty = num(d, "target_under_tower_penalty", p.under_tower_penalty)
	p.switch_margin = num(d, "switch_margin", p.switch_margin)
	p._optional(d)
	return p


## Resolves class names to def ids (`ContentSet.entity_index`) so a weight lookup is one array read.
func bind(entity_index: Dictionary) -> void:
	var _r: int = w_by_def.resize(DefRanges.END)
	w_by_def.fill(0.0)
	for k: Variant in weights.keys():
		var name: StringName = StringName(str(k))
		var wk: float = num(weights, str(k), 0.0)
		if name == LOADED_KEY:
			w_loaded = wk
		elif name == BUILDING_KEY:
			w_building = wk
		elif entity_index.has(name):
			w_by_def[entity_def(entity_index, name)] = wk
	hauler_def = entity_def(entity_index, HAULER_KEY) if entity_index.has(HAULER_KEY) else -1


## Class weight of a candidate: the loaded-hauler weight when it is a hauler carrying cargo; the structure_building
## weight for a structure under construction (AI-14) when that is larger than its def's.
func weight(def_id: int, loaded: bool, building: bool = false) -> float:
	if loaded and def_id == hauler_def:
		return w_loaded
	if building and w_building > 0.0:
		return maxf(w_building, w_by_def[def_id] if def_id >= 0 and def_id < w_by_def.size() else 0.0)
	return w_by_def[def_id] if def_id >= 0 and def_id < w_by_def.size() else 0.0


func _optional(d: Dictionary) -> void:
	attacked_mult = num(d, "attacked_mult", attacked_mult)
	attacked_window_s = num(d, "attacked_window_s", attacked_window_s)
	low_hp_mult = num(d, "low_hp_mult", low_hp_mult)
	low_hp01 = num(d, "low_hp01", low_hp01)
	focus_mult = num(d, "focus_mult", focus_mult)
	focus_count = int(num(d, "focus_count", float(focus_count)))
	tower_switch_margin = num(d, "tower_switch_margin", tower_switch_margin)
	tower_attacking_mult = num(d, "tower_attacking_mult", tower_attacking_mult)
	tower_attack_radius_m = num(d, "tower_attack_radius_m", tower_attack_radius_m)
	tower_hp_gain = num(d, "tower_hp_gain", tower_hp_gain)
	tower_crowd_mult = num(d, "tower_crowd_mult", tower_crowd_mult)
	tower_crowd_count = int(num(d, "tower_crowd_count", float(tower_crowd_count)))
	guard_mult = num(d, "guard_mult", guard_mult)
	max_candidates = maxi(int(num(d, "max_candidates", float(max_candidates))), 1)
	var rw: Array = DEFAULT_RANK_WEIGHTS
	var v: Variant = d.get("tower_rank_weights")
	if v is Array:
		rw = v
	var _r: int = rank_weights.resize(rw.size())
	for i: int in rw.size():
		var x: Variant = rw[i]
		rank_weights[i] = as_num(x, 0.0)


## Typed readers for JSON dictionaries (no Variant escapes into arithmetic).
static func num(d: Dictionary, key: String, fallback: float) -> float:
	return as_num(d.get(key), fallback)


static func as_num(v: Variant, fallback: float) -> float:
	if v is float:
		var f: float = v
		return f
	if v is int:
		var i: int = v
		return float(i)
	return fallback


static func dict_of(d: Dictionary, key: String) -> Dictionary:
	var v: Variant = d.get(key)
	if v is Dictionary:
		var r: Dictionary = v
		return r
	return {}


static func entity_def(entity_index: Dictionary, name: StringName) -> int:
	var v: Variant = entity_index.get(name)
	if v is int:
		var i: int = v
		return i
	return 0
