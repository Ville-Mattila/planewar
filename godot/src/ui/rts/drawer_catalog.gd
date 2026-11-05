class_name DrawerCatalog extends RefCounted
## Which defs get a production drawer tile (docs/06 s7.5). Everything derives from the content defs: structures from
## `buildable`, unit tiles from `produced_at`, tech from `requires`, costs from the doctrine-resolved defs. No class lists.

static var _resolved: Dictionary = {}   ## doctrine id -> ResolvedDefs, dropped when the content hash changes
static var _hash: String = ""


## Buildable structures and towers in file order (the Core and the neutral Relay Station are not buildable).
static func structure_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for sd: StructureDef in ContentDB.structures:
		if sd.buildable:
			out.append(sd.id)
	return out


## Ships then ground units that have a factory.
static func unit_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for sh: ShipDef in ContentDB.ships:
		if sh.produced_at != &"":
			out.append(sh.id)
	for g: GroundUnitDef in ContentDB.ground_units:
		if g.produced_at != &"":
			out.append(g.id)
	return out


## The structure that produces `unit` (`produced_at`); empty for anything that is not a unit tile.
static func factory_of(unit: StringName) -> StringName:
	var d: int = ContentDB.def_index(unit)
	var sh: ShipDef = ContentDB.ship(d)
	if sh != null:
		return sh.produced_at
	var g: GroundUnitDef = ContentDB.ground_unit(d)
	return g.produced_at if g != null else &""


static func is_factory(def: StringName) -> bool:
	if def == &"":
		return false
	for id: StringName in unit_ids():
		if factory_of(id) == def:
			return true
	return false


## (ore, ice) of the def as `doctrine` resolves it; (-1, -1) for an unknown id.
static func cost(id: StringName, doctrine: StringName = &"") -> Vector2i:
	var d: int = ContentDB.def_index(id)
	var rd: ResolvedDefs = _resolved_for(doctrine)
	if rd == null:
		return Vector2i(-1, -1)
	if rd.ship(d) != null:
		return Vector2i(rd.ship(d).cost_ore, rd.ship(d).cost_ice)
	if rd.ground_unit(d) != null:
		return Vector2i(rd.ground_unit(d).cost_ore, rd.ground_unit(d).cost_ice)
	if rd.structure(d) != null:
		return Vector2i(rd.structure(d).cost_ore, rd.structure(d).cost_ice)
	return Vector2i(-1, -1)


## Structure ids that must be finished before `id` is available.
static func requires(id: StringName) -> PackedStringArray:
	var d: int = ContentDB.def_index(id)
	if ContentDB.ship(d) != null:
		return ContentDB.ship(d).requires
	if ContentDB.ground_unit(d) != null:
		return ContentDB.ground_unit(d).requires
	if ContentDB.structure(d) != null:
		return ContentDB.structure(d).requires
	return PackedStringArray()


## `max_per_player` of a structure; 0 = unlimited (and for every unit).
static func max_per_player(id: StringName) -> int:
	var sd: StructureDef = ContentDB.structure(ContentDB.def_index(id))
	return sd.max_per_player if sd != null else 0


static func name_key(id: StringName) -> String:
	return "ui.prod.def.%s" % id


static func _resolved_for(doctrine: StringName) -> ResolvedDefs:
	var h: String = ContentDB.content_hash_hex()
	if h != _hash:
		_resolved.clear()
		_hash = h
	if not _resolved.has(doctrine):
		_resolved[doctrine] = ContentDB.resolve_for_doctrine(doctrine)
	var rd: ResolvedDefs = _resolved[doctrine]
	return rd
