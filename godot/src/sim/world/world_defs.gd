class_name WorldDefs extends RefCounted
## The injected content of one `SimWorld` (no autoload in the sim): the `ContentSet`, one `ResolvedDefs` per player
## slot (02 s7 doctrine, resolved once at `add_player`, never mutated) and the flat per-def tables the hot loops
## index (03 s3.5 `resolved`). Owner u8 255 (neutral) reads the base defs (doctrine "").

const NEUTRAL: int = PlayerTable.SLOTS

var content: ContentSet
var rules: RulesDef
var common: FlightCommonDef
var economy: EconomyDef
var base: ResolvedDefs
var projectile_radius: PackedFloat32Array = PackedFloat32Array()   ## by ProjectileStore.projectile_def (local index)
var pad_radius_by_def: PackedFloat32Array = PackedFloat32Array()   ## by EntityStore.def_id; 0 = no pad
var straight: PackedByteArray = PackedByteArray()                  ## by projectile local index: 1 = no gravity, no transport
var turn_rad_per_s: PackedFloat32Array = PackedFloat32Array()      ## by weapon local index: guided re-aim limit

var _resolved: Array[ResolvedDefs] = []
var ship_table: Array[ShipDef] = []            ## [(owner slot or NEUTRAL) * ship_count + local]: step 5's lookup
var ship_count: int = 0


func _init(cs: ContentSet) -> void:
	content = cs
	rules = cs.rules
	common = cs.flight_common
	economy = cs.economy
	base = DoctrineResolver.resolve(null, cs.ships, cs.ground_units, cs.structures, cs.weapons, cs.projectiles)
	ship_count = cs.ships.size()
	var _a: int = _resolved.resize(NEUTRAL + 1)
	var _b: int = ship_table.resize((NEUTRAL + 1) * ship_count)
	for p: int in NEUTRAL + 1:
		_bind(p, base)
	var np: int = cs.projectiles.size()
	var e: int = projectile_radius.resize(np) | straight.resize(np) | turn_rad_per_s.resize(cs.weapons.size())
	e |= pad_radius_by_def.resize(DefRanges.STRUCTURE_BASE + cs.structures.size())
	assert(e == OK)
	for i: int in np:
		var pd: ProjectileDef = cs.projectiles[i]
		projectile_radius[i] = pd.radius_m
		straight[i] = 1 if not pd.gravity and not pd.transport else 0
	for w: int in cs.weapons.size():
		turn_rad_per_s[w] = deg_to_rad(cs.weapons[w].turn_rate_dps)
	pad_radius_by_def.fill(0.0)
	for k: int in cs.structures.size():
		var sd: StructureDef = cs.structures[k]
		pad_radius_by_def[DefRanges.STRUCTURE_BASE + k] = sd.pad_radius_m if sd.pads > 0 else 0.0


## Resolves `doctrine` for player `slot`; false (base defs kept) for an unknown doctrine id.
func resolve(slot: int, doctrine: StringName) -> bool:
	var d: DoctrineDef = null
	if doctrine != &"":
		for dd: DoctrineDef in content.doctrines:
			if dd.id == doctrine:
				d = dd
		if d == null:
			_bind(slot, base)
			return false
	var c: ContentSet = content
	_bind(slot, DoctrineResolver.resolve(d, c.ships, c.ground_units, c.structures, c.weapons, c.projectiles))
	return true


func resolved(owner: int) -> ResolvedDefs:
	return _resolved[owner if owner >= 0 and owner < NEUTRAL else NEUTRAL]


## The ShipDef of `def_id` as owner u8 `owner` flies it; null for a non-ship def.
func ship(owner: int, def_id: int) -> ShipDef:
	var i: int = def_id - DefRanges.SHIP_BASE
	if i < 0 or i >= ship_count:
		return null
	return ship_table[(owner if owner >= 0 and owner < NEUTRAL else NEUTRAL) * ship_count + i]


## EntityStore.K_* of an entity def_id; -1 for weapons, projectiles and unknown ids.
func entity_kind(def_id: int) -> int:
	match DefRanges.kind_of(def_id):
		DefRanges.K_SHIP:
			return EntityStore.K_SHIP if def_id - DefRanges.SHIP_BASE < ship_count else -1
		DefRanges.K_GROUND:
			return EntityStore.K_GROUND if base.ground_unit(def_id) != null else -1
		DefRanges.K_STRUCTURE:
			return EntityStore.K_STRUCTURE if base.structure(def_id) != null else -1
	return -1


## Full HP of `def_id` for owner `owner` (doctrine-resolved); 0 when unknown.
func hp_max(owner: int, def_id: int) -> float:
	var r: ResolvedDefs = resolved(owner)
	var s: ShipDef = r.ship(def_id)
	if s != null:
		return float(s.hp)
	var g: GroundUnitDef = r.ground_unit(def_id)
	if g != null:
		return float(g.hp)
	var t: StructureDef = r.structure(def_id)
	return float(t.hp) if t != null else 0.0


## Ore / ice cost of a unit or structure def (doctrine-resolved); (-1, -1) when not buildable as a unit/structure.
func cost(owner: int, def_id: int) -> Vector2i:
	var r: ResolvedDefs = resolved(owner)
	var s: ShipDef = r.ship(def_id)
	if s != null:
		return Vector2i(s.cost_ore, s.cost_ice)
	var g: GroundUnitDef = r.ground_unit(def_id)
	if g != null:
		return Vector2i(g.cost_ore, g.cost_ice)
	var t: StructureDef = r.structure(def_id)
	return Vector2i(t.cost_ore, t.cost_ice) if t != null else Vector2i(-1, -1)


func possessable(def_id: int) -> bool:
	var s: ShipDef = base.ship(def_id)
	if s != null:
		return s.possessable
	var g: GroundUnitDef = base.ground_unit(def_id)
	if g != null:
		return g.possessable
	var t: StructureDef = base.structure(def_id)
	return t != null and t.possessable


## Collision radius at spawn: bounding_radius for units; for structures the footprint half-diagonal on the
## GRID_BUILD grid (interim until Build, TA-19, sizes structures) or the pad radius, whichever is larger.
func radius_of(def_id: int) -> float:
	var s: ShipDef = base.ship(def_id)
	if s != null:
		return s.bounding_radius
	var g: GroundUnitDef = base.ground_unit(def_id)
	if g != null:
		return g.bounding_radius
	var t: StructureDef = base.structure(def_id)
	if t == null:
		return 0.0
	var cell_m: float = build_cell_m()
	var w: int = t.footprint[0] if t.footprint.size() > 0 else 1
	var h: int = t.footprint[1] if t.footprint.size() > 1 else w
	return maxf(Vector2(float(w), float(h)).length() * cell_m * 0.5, pad_radius_by_def[def_id])


## Edge of one GRID_BUILD cell in metres (footprints are counted in these).
static func build_cell_m() -> float:
	return Sphere.PLANET_RADIUS * PI * 0.5 / float(Sphere.GRID_BUILD)


func _bind(slot: int, r: ResolvedDefs) -> void:
	_resolved[slot] = r
	for i: int in ship_count:
		ship_table[slot * ship_count + i] = r.ships[i]
