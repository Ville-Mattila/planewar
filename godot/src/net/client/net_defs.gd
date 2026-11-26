class_name NetDefs extends RefCounted
## Per-def tables NetSimView needs, built once from a ContentSet (base defs; doctrine modifiers are not replicated).
## Indexed by def_id (0 .. DefRanges.END); projectile defs carry gravity_def and radius (radius_m) only, kind -1. Mirrors the sim's spawn rules (WorldDefs.radius_of / possessable / hp_max,
## PadQueries.serves, TeamStats.tech_available's `requires`) without naming sim types; test_net_sim_view.gd pins every
## table to the sim's answer for the content set. `kind_of` uses the EntityStore kind ordinals (NetSimView.K_*).

var tick_hz: int = 30
var gravity: float = 0.0
var hp: PackedFloat32Array = PackedFloat32Array()
var fuel_s: PackedFloat32Array = PackedFloat32Array()
var radius: PackedFloat32Array = PackedFloat32Array()
var possessable: PackedByteArray = PackedByteArray()
var pad: PackedByteArray = PackedByteArray()              ## 1 = structure with a service pad (pads > 0 and pad_radius_m > 0)
var gravity_def: PackedByteArray = PackedByteArray()      ## 1 = projectile def with gravity (SnapshotDecoder.gravity_def)
var kind: PackedInt32Array = PackedInt32Array()           ## NetSimView.K_* or -1
## Ground barrel (NET-61, R0 B.31 A-151 / A-152), BarrelSlew's rule from the raw `barrel_*` keys: 1 = the def has a barrel
## (slew > 0 or a non-zero limit; SnapshotDecoder.barrel_def), limits in radians with min <= max.
var barrel_def: PackedByteArray = PackedByteArray()
var barrel_lo: PackedFloat64Array = PackedFloat64Array()
var barrel_hi: PackedFloat64Array = PackedFloat64Array()
var _requires: Array[PackedInt32Array] = []


func _init(content: ContentSet = null) -> void:
	var n: int = DefRanges.END
	var _a: int = hp.resize(n)
	var _b: int = fuel_s.resize(n)
	var _c: int = radius.resize(n)
	var _d: int = possessable.resize(n)
	var _e: int = pad.resize(n)
	var _f: int = gravity_def.resize(n)
	var _g: int = kind.resize(n)
	var e: int = barrel_def.resize(n) | barrel_lo.resize(n) | barrel_hi.resize(n)
	assert(e == OK)
	kind.fill(-1)
	var _h: int = _requires.resize(n)
	for i: int in n:
		_requires[i] = PackedInt32Array()
	if content == null:
		return
	if content.rules != null:
		tick_hz = maxi(content.rules.tick_hz, 1)
		gravity = content.rules.gravity
	for k: int in content.ships.size():
		var s: ShipDef = content.ships[k]
		_unit(content, DefRanges.SHIP_BASE + k, NetSimView.K_SHIP, float(s.hp), s.bounding_radius, s.possessable, s.requires)
		fuel_s[DefRanges.SHIP_BASE + k] = s.fuel_s
	for k: int in content.ground_units.size():
		var g: GroundUnitDef = content.ground_units[k]
		_unit(content, DefRanges.GROUND_BASE + k, NetSimView.K_GROUND, float(g.hp), g.bounding_radius, g.possessable, g.requires)
		_barrel(DefRanges.GROUND_BASE + k, g.raw)
	for k: int in content.structures.size():
		_structure(content, DefRanges.STRUCTURE_BASE + k, content.structures[k])
	for k: int in content.projectiles.size():
		gravity_def[DefRanges.PROJECTILE_BASE + k] = 1 if content.projectiles[k].gravity else 0
		radius[DefRanges.PROJECTILE_BASE + k] = content.projectiles[k].radius_m     # projectile entities (A-112)


func _unit(content: ContentSet, d: int, k: int, hp_max: float, r: float, poss: bool, req: PackedStringArray) -> void:
	kind[d] = k
	hp[d] = hp_max
	radius[d] = r
	possessable[d] = 1 if poss else 0
	_requires[d] = _resolve(content, req)


func _barrel(d: int, r: Dictionary) -> void:
	var lo: float = deg_to_rad(Def.num(r.get("barrel_min_deg", 0.0)))
	var hi: float = deg_to_rad(Def.num(r.get("barrel_max_deg", 0.0)))
	barrel_lo[d] = minf(lo, hi)
	barrel_hi[d] = maxf(lo, hi)
	barrel_def[d] = 1 if Def.num(r.get("barrel_slew_dps", 0.0)) > 0.0 or lo != 0.0 or hi != 0.0 else 0


func _structure(content: ContentSet, d: int, sd: StructureDef) -> void:
	var pad_r: float = sd.pad_radius_m if sd.pads > 0 else 0.0
	var w: int = sd.footprint[0] if sd.footprint.size() > 0 else 1
	var h: int = sd.footprint[1] if sd.footprint.size() > 1 else w
	var cell_m: float = Sphere.PLANET_RADIUS * PI * 0.5 / float(Sphere.GRID_BUILD)
	_unit(content, d, NetSimView.K_STRUCTURE, float(sd.hp), maxf(Vector2(float(w), float(h)).length() * cell_m * 0.5, pad_r),
			sd.possessable, sd.requires)
	pad[d] = 1 if pad_r > 0.0 else 0


static func _resolve(content: ContentSet, req: PackedStringArray) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for need: String in req:
		var d: int = content.entity_index.get(StringName(need), -1)
		var _a: bool = out.push_back(d)
	return out


func valid(def_id: int) -> bool:
	return def_id >= 0 and def_id < DefRanges.END


## NetSimView.K_* for a roster entry: K_WRECK for a wreck slot (EntityId.WRECK_SLOT_MIN ..), else the def's kind.
func kind_of(def_id: int, slot: int) -> int:
	if slot >= EntityId.WRECK_SLOT_MIN and slot < EntityId.WRECK_SLOT_END:
		return NetSimView.K_WRECK
	return kind[def_id] if valid(def_id) else -1


## The barrel wire byte for elevation `e` (radians) of def `def_id` (Codec.quantize_barrel), -1 for a def without a
## barrel (SnapshotFrame.set_barrel takes either).
func barrel_byte(def_id: int, e: float) -> int:
	if not valid(def_id) or barrel_def[def_id] == 0:
		return -1
	return Codec.quantize_barrel(e, barrel_lo[def_id], barrel_hi[def_id])


## The elevation (radians) a held barrel value (BaselineFrame.barrel) of def `def_id` decodes to; 0.0 when not held.
func barrel_rad(def_id: int, held: int) -> float:
	if held == 0 or not valid(def_id) or barrel_def[def_id] == 0:
		return 0.0
	return Codec.dequantize_barrel(held, barrel_lo[def_id], barrel_hi[def_id])


## The def ids a unit or structure def requires (resolved `requires[]`; -1 for an unknown name).
func requires_of(def_id: int) -> PackedInt32Array:
	return _requires[def_id] if valid(def_id) else PackedInt32Array()
