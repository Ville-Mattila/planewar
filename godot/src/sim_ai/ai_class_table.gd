class_name AiClassTable extends RefCounted
## def id -> AI class batch (05 s4.3, R0 B.12 A-71): what `AiDriver.on_event` uses to register a spawned unit. A class is
## the unit def itself: ships in `ships.json` order, then ground units in `ground_units.json` order (7 shipped, at most
## `AiDriver.MAX_CLASSES`). Structures (towers fire inside the sim) and anything else are `NONE`. Built once from the
## `ContentSet`, read-only afterwards; one byte read per SPAWN.

const NONE: int = 255


## One byte per def id below `DefRanges.STRUCTURE_BASE` (ships, ground units); defs beyond `AiDriver.MAX_CLASSES`
## stay `NONE`.
static func from_content(c: ContentSet) -> PackedByteArray:
	var t: PackedByteArray = PackedByteArray()
	var _r: int = t.resize(DefRanges.STRUCTURE_BASE)
	t.fill(NONE)
	var cls: int = 0
	for sd: ShipDef in c.ships:
		cls = _put(t, c, sd.id, cls)
	for gd: GroundUnitDef in c.ground_units:
		cls = _put(t, c, gd.id, cls)
	return t


## Class of `def_id` in `table` (`NONE` when out of range or not AI-driven).
static func class_of(table: PackedByteArray, def_id: int) -> int:
	return table[def_id] if def_id >= 0 and def_id < table.size() else NONE


static func _put(t: PackedByteArray, c: ContentSet, id: StringName, cls: int) -> int:
	var d: int = c.entity_index.get(id, -1)
	if d < 0 or d >= t.size() or cls >= AiDriver.MAX_CLASSES:
		return cls
	t[d] = cls
	return cls + 1
