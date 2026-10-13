class_name ResolvedDefs extends RefCounted
## Doctrine-resolved view of the gameplay defs (02 s7, R0 C2-01): copies, never the base defs (N4).
## Produced by ContentDB.resolve_for_doctrine; arrays are indexed like the def_id ranges (def_id - base).

var doctrine_id: StringName = &""
var ships: Array[ShipDef] = []
var ground_units: Array[GroundUnitDef] = []
var structures: Array[StructureDef] = []  ## structures then towers
var weapons: Array[WeaponDef] = []
var projectiles: Array[ProjectileDef] = []  ## never modified by doctrines: shared with the base set
## The doctrine's `rules {}` block, verbatim.
var rules: Dictionary = {}
var flip_cooldown_s_override: float = 0.0  ## > 0: already applied to every resolved ship
var hangar_blocks_rockets: bool = false
var reactor_unlock_s: float = 0.0


func ship(def_id: int) -> ShipDef:
	var i: int = def_id - DefRanges.SHIP_BASE
	return ships[i] if i >= 0 and i < ships.size() else null


func ground_unit(def_id: int) -> GroundUnitDef:
	var i: int = def_id - DefRanges.GROUND_BASE
	return ground_units[i] if i >= 0 and i < ground_units.size() else null


func structure(def_id: int) -> StructureDef:
	var i: int = def_id - DefRanges.STRUCTURE_BASE
	return structures[i] if i >= 0 and i < structures.size() else null


func weapon(def_id: int) -> WeaponDef:
	var i: int = def_id - DefRanges.WEAPON_BASE
	return weapons[i] if i >= 0 and i < weapons.size() else null


func projectile(def_id: int) -> ProjectileDef:
	var i: int = def_id - DefRanges.PROJECTILE_BASE
	return projectiles[i] if i >= 0 and i < projectiles.size() else null


## Canonical text of every resolved def (N7: same input, byte-identical output).
func serialise() -> String:
	var all: Array = []
	for group: Array in [ships, ground_units, structures, weapons]:
		for d: Def in group:
			all.append(d.raw)
	all.append(rules)
	return ContentHash.canonical(all)

