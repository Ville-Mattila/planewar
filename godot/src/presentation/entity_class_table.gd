class_name EntityClassTable
extends RefCounted
## def_id -> view class (03 s10.1). A class is a far-pool group: a def's `presentation.far_mesh_node` when it has one,
## else its kind plus a size bucket (ships: "ship"; ground units: "ground"; structures: "structure_s" / "structure_l"
## by footprint). Placeholder primitives stand in per kind until ART-04/05 deliver the GLBs. Packed lookup, no
## Dictionary on the sync path.

const BIG_FOOTPRINT_CELLS: int = 3

var _group_of_def: PackedInt32Array = PackedInt32Array()
var _names: Array[StringName] = []
var _kinds: PackedInt32Array = PackedInt32Array()   ## DefRanges.K_* per group


static func from_content(c: ContentSet) -> EntityClassTable:
	var t: EntityClassTable = EntityClassTable.new()
	var _r1: int = t._group_of_def.resize(DefRanges.END)
	t._group_of_def.fill(-1)
	for d: ShipDef in c.ships:
		t._add(d, DefRanges.K_SHIP, &"ship")
	for d: GroundUnitDef in c.ground_units:
		t._add(d, DefRanges.K_GROUND, &"ground")
	for d: StructureDef in c.structures:
		var big: bool = not d.footprint.is_empty() and maxi(d.footprint[0], d.footprint[d.footprint.size() - 1]) >= BIG_FOOTPRINT_CELLS
		t._add(d, DefRanges.K_STRUCTURE, &"structure_l" if big else &"structure_s")
	return t


func group_count() -> int:
	return _names.size()


func group_name(group: int) -> StringName:
	return _names[group]


## DefRanges.K_SHIP / K_GROUND / K_STRUCTURE of the group (picks the placeholder mesh and the icon glyph).
func group_kind(group: int) -> int:
	return _kinds[group]


## The group of a def id; -1 for an unknown id.
func group_of(def_id: int) -> int:
	return _group_of_def[def_id] if def_id >= 0 and def_id < _group_of_def.size() else -1


func _add(d: Def, kind: int, fallback: StringName) -> void:
	var key: StringName = d.presentation.far_mesh_node if d.presentation != null and d.presentation.far_mesh_node != &"" else fallback
	var g: int = _names.find(key)
	if g < 0:
		g = _names.size()
		_names.append(key)
		var _a: bool = _kinds.push_back(kind)
	if d.def_id >= 0 and d.def_id < _group_of_def.size():
		_group_of_def[d.def_id] = g
