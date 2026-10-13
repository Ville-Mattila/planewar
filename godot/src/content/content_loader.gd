class_name ContentLoader extends RefCounted
## Builds a ContentSet from raw file texts: parse, typed defs, def_id assignment (N2), unique ids (A-1),
## dangling-reference checks, content hash. Pure: no Log, no scene tree. Fail-fast: any error is recorded
## and the caller discards the set (N3).

const REQUIRED: PackedStringArray = [
	"rules.json", "ships.json", "ground_units.json", "weapons.json", "projectiles.json", "structures.json",
	"towers.json", "economy.json", "match_rules.json", "modes.json", "bot_promises.json", "scoring.json",
]

var _s: ContentSet = ContentSet.new()
var _texts: Dictionary = {}


## texts: file name -> JSON text for the top-level def files; map_texts: map id -> recipe.json text.
static func build(texts: Dictionary, map_texts: Dictionary) -> ContentSet:
	var l: ContentLoader = ContentLoader.new()
	return l._run(texts, map_texts)


func _run(texts: Dictionary, map_texts: Dictionary) -> ContentSet:
	_texts = texts
	for n: String in REQUIRED:
		if not texts.has(n):
			_s.errors.append("required def file missing: %s" % n)
	if not _s.ok():
		return _s
	_load_world()
	_load_entities()
	_load_tables()
	_load_optional()
	_load_feature_defs()
	_load_maps(map_texts)
	_index_ids()
	if _s.ok():
		_check_refs()
	if _s.ok():
		_s.content_hash = ContentHash.hash_texts(texts)
		if _s.content_hash.is_empty():
			_s.errors.append("content hash failed: a def file holds an unsupported number")
	return _s


func _top(file: String) -> Dictionary:
	if not _texts.has(file):
		return {}
	var j: JSON = JSON.new()
	if j.parse(str(_texts[file]).trim_prefix("﻿")) != OK:
		_s.errors.append("%s: line %d: %s" % [file, j.get_error_line(), j.get_error_message()])
		return {}
	if typeof(j.data) != TYPE_DICTIONARY:
		_s.errors.append("%s: top level is not an object" % file)
		return {}
	var d: Dictionary = j.data
	return d


func _entries(top: Dictionary, key: String, file: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if top.is_empty():
		return out
	if typeof(top.get(key)) != TYPE_ARRAY:
		_s.errors.append("%s: '%s' must be an array" % [file, key])
		return out
	var src: Array = top[key]
	for e: Variant in src:
		if typeof(e) != TYPE_DICTIONARY:
			_s.errors.append("%s: '%s' entry is not an object" % [file, key])
			continue
		var ed: Dictionary = e
		out.append(ed)
	return out


func _take(d: Def, file: String) -> void:
	for e: String in d.errors:
		_s.errors.append("%s: %s: %s" % [file, d.id, e])
	for u: String in d.unknown:
		_s.warnings.append("%s: %s: unknown key '%s'" % [file, d.id, u])


func _load_world() -> void:
	_s.rules = RulesDef.from_dict(_top("rules.json"))
	_take(_s.rules, "rules.json")
	var ships_top: Dictionary = _top("ships.json")
	var fc: Variant = ships_top.get("flight_common")
	if typeof(fc) == TYPE_DICTIONARY:
		var fcd: Dictionary = fc
		_s.flight_common = FlightCommonDef.from_dict(fcd)
		for e: String in _s.flight_common.errors:
			_s.errors.append("ships.json: %s" % e)
		for u: String in _s.flight_common.unknown:
			_s.warnings.append("ships.json: flight_common: unknown key '%s'" % u)
	else:
		_s.errors.append("ships.json: flight_common missing")
	_s.economy = EconomyDef.from_dict(_top("economy.json"))
	_take(_s.economy, "economy.json")
	_s.match_rules = MatchRulesDef.from_dict(_top("match_rules.json"))
	_take(_s.match_rules, "match_rules.json")
	_s.scoring = ScoringDef.from_dict(_top("scoring.json"))
	_take(_s.scoring, "scoring.json")


func _load_entities() -> void:
	for e: Dictionary in _entries(_top("ships.json"), "ships", "ships.json"):
		var d: ShipDef = ShipDef.from_dict(e)
		_take(d, "ships.json")
		d.def_id = DefRanges.SHIP_BASE + _s.ships.size()
		_s.ships.append(d)
	for e: Dictionary in _entries(_top("ground_units.json"), "ground_units", "ground_units.json"):
		var d: GroundUnitDef = GroundUnitDef.from_dict(e)
		_take(d, "ground_units.json")
		d.def_id = DefRanges.GROUND_BASE + _s.ground_units.size()
		_s.ground_units.append(d)
	for file: String in ["structures.json", "towers.json"]:
		for e: Dictionary in _entries(_top(file), file.trim_suffix(".json"), file):
			var d: StructureDef = StructureDef.from_dict(e)
			_take(d, file)
			d.def_id = DefRanges.STRUCTURE_BASE + _s.structures.size()
			_s.structures.append(d)
	for e: Dictionary in _entries(_top("weapons.json"), "weapons", "weapons.json"):
		var d: WeaponDef = WeaponDef.from_dict(e)
		_take(d, "weapons.json")
		d.def_id = DefRanges.WEAPON_BASE + _s.weapons.size()
		_s.weapons.append(d)
	for e: Dictionary in _entries(_top("projectiles.json"), "projectiles", "projectiles.json"):
		var d: ProjectileDef = ProjectileDef.from_dict(e)
		_take(d, "projectiles.json")
		d.def_id = DefRanges.PROJECTILE_BASE + _s.projectiles.size()
		_s.projectiles.append(d)
	_check_range(_s.ships.size(), DefRanges.SHIP_BASE, "ships")
	_check_range(_s.ground_units.size(), DefRanges.GROUND_BASE, "ground_units")
	_check_range(_s.structures.size(), DefRanges.STRUCTURE_BASE, "structures+towers")
	_check_range(_s.weapons.size(), DefRanges.WEAPON_BASE, "weapons")
	_check_range(_s.projectiles.size(), DefRanges.PROJECTILE_BASE, "projectiles")


func _check_range(count: int, base: int, what: String) -> void:
	if base + count > DefRanges.base_of(DefRanges.kind_of(base) + 1):
		_s.errors.append("%s: %d entries overflow the def_id range (N2)" % [what, count])


func _load_tables() -> void:
	var modes_top: Dictionary = _top("modes.json")
	for e: Dictionary in _entries(modes_top, "modes", "modes.json"):
		var m: ModeDef = ModeDef.from_dict(e)
		_take(m, "modes.json")
		_s.modes.append(m)
	var slots: Variant = modes_top.get("slots_by_player_count")
	if typeof(slots) == TYPE_DICTIONARY:
		var sd: Dictionary = slots
		_s.slots_by_player_count = sd.duplicate(true)
	for e: Dictionary in _entries(_top("bot_promises.json"), "bot_promises", "bot_promises.json"):
		var b: BotPromiseDef = BotPromiseDef.from_dict(e)
		_take(b, "bot_promises.json")
		_s.bot_promises.append(b)


func _load_optional() -> void:
	for e: Dictionary in _entries(_top("doctrines.json"), "doctrines", "doctrines.json"):
		var d: DoctrineDef = DoctrineDef.from_dict(e)
		_take(d, "doctrines.json")
		_s.doctrines.append(d)
	for e: Dictionary in _entries(_top("bot_profiles.json"), "bot_profiles", "bot_profiles.json"):
		var b: BotProfileDef = BotProfileDef.from_dict(e)
		_take(b, "bot_profiles.json")
		_s.bot_profiles.append(b)
	for e: Dictionary in _entries(_top("autopilots.json"), "autopilots", "autopilots.json"):
		var a: AutopilotDef = AutopilotDef.from_dict(e)
		_take(a, "autopilots.json")
		_s.autopilots.append(a)
	for e: Dictionary in _entries(_top("build_orders.json"), "build_orders", "build_orders.json"):
		var o: BuildOrderDef = BuildOrderDef.from_dict(e)
		_take(o, "build_orders.json")
		_s.build_orders.append(o)
	for e: Dictionary in _entries(_top("medals.json"), "medals", "medals.json"):
		var m: MedalDef = MedalDef.from_dict(e)
		_take(m, "medals.json")
		_s.medals.append(m)
	for e: Dictionary in _entries(_top("quality_tiers.json"), "quality_tiers", "quality_tiers.json"):
		var q: QualityTierDef = QualityTierDef.from_dict(e)
		_take(q, "quality_tiers.json")
		_s.quality_tiers.append(q)
	if _texts.has("order_rules.json"):
		_s.order_rules = OrderRulesDef.from_dict(_top("order_rules.json"))
	if _texts.has("assists.json"):
		_s.assists = AssistDef.from_dict(_top("assists.json"))
	if _texts.has("progression.json"):
		_s.progression = ProgressionDef.from_dict(_top("progression.json"))


## FEAT-01 (08 SL-2, SL-3, SL-5): absent files load as null / empty (N8); a present file must validate.
func _load_feature_defs() -> void:
	if _texts.has("wing.json"):
		_s.wing = WingDef.from_dict(_top("wing.json"))
		_take(_s.wing, "wing.json")
	if _texts.has("callsigns.json"):
		_s.callsigns = CallsignDef.from_dict(_top("callsigns.json"))
		_take(_s.callsigns, "callsigns.json")
	for e: Dictionary in _entries(_top("barks.json"), "barks", "barks.json"):
		var b: BarkDef = BarkDef.from_dict(e)
		_take(b, "barks.json")
		_s.barks.append(b)
	for e: Dictionary in _entries(_top("commander_verbs.json"), "commander_verbs", "commander_verbs.json"):
		var sc: SupplyCanisterDef = SupplyCanisterDef.from_dict(e)
		_take(sc, "commander_verbs.json")
		if sc.id == &"supply_canister":
			_s.supply_canister = sc


func _load_maps(map_texts: Dictionary) -> void:
	for map_id: Variant in map_texts.keys():
		var j: JSON = JSON.new()
		if j.parse(str(map_texts[map_id])) != OK or typeof(j.data) != TYPE_DICTIONARY:
			_s.errors.append("maps/%s/recipe.json: not a JSON object" % map_id)
			continue
		var rd: Dictionary = j.data
		var m: MapDef = MapDef.from_dict(rd)
		if m.id == &"":
			m.id = StringName(str(map_id))
			m.errors.clear()
		_take(m, "maps/%s/recipe.json" % map_id)
		_s.maps.append(m)


func _index_ids() -> void:
	var groups: Array = [_s.ships, _s.ground_units, _s.structures]
	for g: Array in groups:
		for d: Def in g:
			if _s.entity_index.has(d.id):
				_s.errors.append("duplicate entity id '%s' across ships/ground_units/structures/towers (A-1)" % d.id)
			_s.entity_index[d.id] = d.def_id
	for w: WeaponDef in _s.weapons:
		if _s.weapon_index.has(w.id):
			_s.errors.append("duplicate weapon id '%s'" % w.id)
		_s.weapon_index[w.id] = w.def_id
	for p: ProjectileDef in _s.projectiles:
		if _s.projectile_index.has(p.id):
			_s.errors.append("duplicate projectile id '%s'" % p.id)
		_s.projectile_index[p.id] = p.def_id


func _check_refs() -> void:
	for sh: ShipDef in _s.ships:
		_ref_entity(sh.produced_at, "ship %s produced_at" % sh.id)
		_ref_each(sh.requires, "ship %s requires" % sh.id)
		_ref_weapon(sh.primary_weapon, "ship %s primary" % sh.id)
		_ref_weapon(sh.secondary_weapon, "ship %s secondary" % sh.id)
	for g: GroundUnitDef in _s.ground_units:
		_ref_entity(g.produced_at, "ground unit %s produced_at" % g.id)
		_ref_each(g.requires, "ground unit %s requires" % g.id)
		_ref_weapon(g.weapon, "ground unit %s weapon" % g.id)
	for st: StructureDef in _s.structures:
		_ref_each(st.requires, "structure %s requires" % st.id)
		_ref_entity(st.upgrade_from, "structure %s upgrade_from" % st.id)
		if st.is_tower():
			_ref_weapon(StringName(str(st.tower.get("weapon", ""))), "tower %s weapon" % st.id)
	for w: WeaponDef in _s.weapons:
		if not _s.projectile_index.has(w.projectile):
			_s.errors.append("weapon %s: unknown projectile '%s'" % [w.id, w.projectile])
	_ref_each(_s.economy.start_kit, "economy start_kit")
	for m: ModeDef in _s.modes:
		if m.caps != &"host" and not _s.match_rules.caps.has(m.caps):
			_s.errors.append("mode %s: unknown caps profile '%s'" % [m.id, m.caps])
	if _s.wing != null:
		_ref_each(_s.wing.armed_classes, "wing armed_classes")


func _ref_entity(id: StringName, what: String) -> void:
	if id != &"" and not _s.entity_index.has(id):
		_s.errors.append("%s: unknown id '%s'" % [what, id])


func _ref_weapon(id: StringName, what: String) -> void:
	if id != &"" and not _s.weapon_index.has(id):
		_s.errors.append("%s: unknown weapon '%s'" % [what, id])


func _ref_each(ids: PackedStringArray, what: String) -> void:
	for i: String in ids:
		_ref_entity(StringName(i), what)
