class_name DoctrineResolver extends RefCounted
## Pure doctrine resolution (02 s7, N7): base raw dicts -> modifiers in file order -> rounding applied once per
## touched field -> typed copies. Never writes to the base defs. Per-match call, not per tick.
##
## Selection: `weapon_mount` selects weapons only; without it, `ids` / `tags_any` select ship, ground unit and
## structure defs (every present key must match). A modifier skips defs that lack the field path (dotted).
## Rounding (02 s1.2): cost fields to the nearest 5, HP / damage / counts to the nearest integer, everything
## else to 0.1; halves round up.

const ROUND5: PackedStringArray = ["cost_ore", "cost_ice", "upgrade_cost_ore"]
const ROUND1: PackedStringArray = [
	"hp", "damage_min", "damage_max", "cargo_ore", "cargo_ice", "tow_slots", "count", "ammo", "score_value",
]
const HALF_EPS: float = 0.000001  ## absorbs 172.49999999999997 style products before the half-up floor


static func resolve(doctrine: DoctrineDef, ships: Array[ShipDef], ground: Array[GroundUnitDef],
		structures: Array[StructureDef], weapons: Array[WeaponDef],
		projectiles: Array[ProjectileDef]) -> ResolvedDefs:
	var groups: Array = [ships, ground, structures, weapons]
	var raws: Array = []  # per group: Array[Dictionary]
	var touched: Array = []  # per group: Array[PackedStringArray]
	for g: Array in groups:
		var rs0: Array = []
		var ts0: Array = []
		for d: Def in g:
			rs0.append(d.raw.duplicate(true))
			ts0.append([] as Array[String])
		raws.append(rs0)
		touched.append(ts0)
	var out: ResolvedDefs = ResolvedDefs.new()
	if doctrine != null:
		out.doctrine_id = doctrine.id
		out.rules = doctrine.rules.duplicate(true)
		for m: Variant in doctrine.modifiers:
			var md: Dictionary = m
			for gi: int in groups.size():
				var defs: Array = groups[gi]
				var rs: Array = raws[gi]
				var ts: Array = touched[gi]
				_apply_group(md, gi, defs, rs, ts)
		_read_rules(out)
	if out.flip_cooldown_s_override > 0.0:
		var ship_raws: Array = raws[0]
		for sr: Dictionary in ship_raws:
			sr["flip_cooldown_s"] = out.flip_cooldown_s_override
	for gi: int in groups.size():
		var rs2: Array = raws[gi]
		var ts2: Array = touched[gi]
		_round_touched(rs2, ts2)
	_rebuild(out, raws, ships, ground, structures, weapons)
	out.projectiles = projectiles
	return out


static func _rebuild(out: ResolvedDefs, raws: Array, ships: Array[ShipDef], ground: Array[GroundUnitDef],
		structures: Array[StructureDef], weapons: Array[WeaponDef]) -> void:
	var rd: Dictionary
	for i: int in ships.size():
		rd = raws[0][i]
		var s: ShipDef = ShipDef.from_dict(rd)
		s.def_id = ships[i].def_id
		out.ships.append(s)
	for i: int in ground.size():
		rd = raws[1][i]
		var g: GroundUnitDef = GroundUnitDef.from_dict(rd)
		g.def_id = ground[i].def_id
		out.ground_units.append(g)
	for i: int in structures.size():
		rd = raws[2][i]
		var st: StructureDef = StructureDef.from_dict(rd)
		st.def_id = structures[i].def_id
		out.structures.append(st)
	for i: int in weapons.size():
		rd = raws[3][i]
		var w: WeaponDef = WeaponDef.from_dict(rd)
		w.def_id = weapons[i].def_id
		out.weapons.append(w)


static func _read_rules(out: ResolvedDefs) -> void:
	out.flip_cooldown_s_override = Def.num(out.rules.get("flip_cooldown_s_override", 0.0))
	out.hangar_blocks_rockets = Def.flag(out.rules.get("hangar_blocks_rockets", false))
	out.reactor_unlock_s = Def.num(out.rules.get("reactor_unlock_s", 0.0))


static func _apply_group(m: Dictionary, gi: int, defs: Array, raws: Array, touched: Array) -> void:
	var sel: Dictionary = m["select"]
	var is_weapons: bool = gi == 3
	if sel.has("weapon_mount") != is_weapons:
		return
	var path: PackedStringArray = str(m["field"]).split(".")
	for i: int in defs.size():
		var d: Def = defs[i]
		if not _selects(sel, d):
			continue
		var t: Array[String] = touched[i]
		var rd: Dictionary = raws[i]
		if _apply(rd, path, str(m["op"]), m["value"]):
			t.append(".".join(path))


static func _selects(sel: Dictionary, d: Def) -> bool:
	if sel.is_empty():
		return false
	if sel.has("ids"):
		var ids: Array = sel["ids"]
		if not ids.has(str(d.id)):
			return false
	if sel.has("tags_any"):
		var any: bool = false
		var wanted: Array = sel["tags_any"]
		for tag: Variant in wanted:
			if d.tags.has(str(tag)):
				any = true
		if not any:
			return false
	if sel.has("weapon_mount") and str(d.raw.get("weapon_mount", "")) != str(sel["weapon_mount"]):
		return false
	return true


## Applies one op at a dotted path inside a raw dict; false when the path is missing or not numeric.
static func _apply(raw: Dictionary, path: PackedStringArray, op: String, value: Variant) -> bool:
	var node: Dictionary = raw
	for k: int in path.size() - 1:
		var next: Variant = node.get(path[k])
		if typeof(next) != TYPE_DICTIONARY:
			return false
		node = next
	var leaf: String = path[path.size() - 1]
	var cur: Variant = node.get(leaf)
	if typeof(cur) != TYPE_FLOAT and typeof(cur) != TYPE_INT:
		return false
	match op:
		"mul":
			node[leaf] = Def.num(cur) * Def.num(value)
		"add":
			node[leaf] = Def.num(cur) + Def.num(value)
		_:
			node[leaf] = value
	return true


static func _round_touched(raws: Array, touched: Array) -> void:
	for i: int in raws.size():
		var t: Array[String] = touched[i]
		for p: String in t:
			var path: PackedStringArray = p.split(".")
			var node: Dictionary = raws[i]
			for k: int in path.size() - 1:
				node = node[path[k]]
			var leaf: String = path[path.size() - 1]
			node[leaf] = round_field(leaf, Def.num(node[leaf]))


static func round_field(leaf: String, x: float) -> float:
	if ROUND5.has(leaf):
		return floorf(x / 5.0 + 0.5 + HALF_EPS) * 5.0
	if ROUND1.has(leaf):
		return floorf(x + 0.5 + HALF_EPS)
	return floorf(x * 10.0 + 0.5 + HALF_EPS) / 10.0
