class_name ShieldTables extends RefCounted
## The flat per-def numbers of the shield domes (02 s5.1, s5.2), read once from the structure defs when `ShieldDomes` is
## built: by `EntityStore.def_id` the dome kind (`K_PROJECTOR` from a `shield` block, `K_CORE` from an `integrated_shield`
## block), dome radius, charge cap, recharge per second, Exposure multipliers, recharge points per Ice (0 = free), recharge
## delay and collapse length in ticks; by projectile local def whether the dome takes it; and the first tick without the
## Core shield. Optional keys `dome_radius` and `collapse_s` of `integrated_shield` are read when present; the Core's
## radius is otherwise its footprint half-diagonal plus the largest structure blast of an absorbed projectile, its
## collapse the Projector's. Lane-internal, immutable after `_init`.

const K_PROJECTOR: int = 1
const K_CORE: int = 2

var kind: PackedByteArray = PackedByteArray()
var radius: PackedFloat64Array = PackedFloat64Array()
var cmax: PackedFloat64Array = PackedFloat64Array()
var rate: PackedFloat64Array = PackedFloat64Array()
var xc: PackedFloat64Array = PackedFloat64Array()
var xr: PackedFloat64Array = PackedFloat64Array()
var pts_per_ice: PackedFloat64Array = PackedFloat64Array()
var delay: PackedInt32Array = PackedInt32Array()
var collapse: PackedInt32Array = PackedInt32Array()
var absorbs: PackedByteArray = PackedByteArray()
var core_until: int = 0


func _init(defs: WorldDefs, hz: int) -> void:
	_fill(defs, maxi(hz, 1))


func _fill(defs: WorldDefs, hz: int) -> void:
	var c: ContentSet = defs.content
	var n: int = DefRanges.WEAPON_BASE
	var e: int = kind.resize(n) | radius.resize(n) | cmax.resize(n) | rate.resize(n) | xc.resize(n) | xr.resize(n)
	e |= pts_per_ice.resize(n) | delay.resize(n) | collapse.resize(n) | absorbs.resize(c.projectiles.size())
	assert(e == OK)
	kind.fill(0)
	xc.fill(1.0)
	xr.fill(1.0)
	delay.fill(0)
	collapse.fill(0)
	pts_per_ice.fill(0.0)
	var proj_collapse: float = 0.0
	for sd: StructureDef in c.structures:
		proj_collapse = maxf(proj_collapse, Def.num(sd.shield.get("collapse_s", 0.0)))
	var reach: float = 0.0   # the Core dome covers every point whose blast could still reach the footprint
	for k: int in c.projectiles.size():
		absorbs[k] = 1 if c.projectiles[k].shield_absorbed else 0
		reach = maxf(reach, c.projectiles[k].blast_radius_structure_m if c.projectiles[k].shield_absorbed else 0.0)
	var cell: float = WorldDefs.build_cell_m()
	for sd: StructureDef in c.structures:
		var d: int = c.entity_index.get(sd.id, -1)
		if d < 0 or d >= n or (sd.shield.is_empty() and sd.integrated_shield.is_empty()):
			continue
		var core: bool = sd.shield.is_empty()
		var b: Dictionary = sd.integrated_shield if core else sd.shield
		kind[d] = K_CORE if core else K_PROJECTOR
		var diag: float = Vector2(float(sd.footprint[0]), float(sd.footprint[1])).length() * cell * 0.5 + reach if sd.footprint.size() > 1 else 0.0
		radius[d] = Def.num(b.get("dome_radius", diag))
		cmax[d] = Def.num(b.get("charge_max", 0.0))
		rate[d] = Def.num(b.get("recharge_per_s", 0.0))
		delay[d] = roundi(Def.num(b.get("recharge_delay_s", 0.0)) * float(hz))
		collapse[d] = roundi(Def.num(b.get("collapse_s", proj_collapse)) * float(hz))
		xc[d] = Def.num(b.get("exposure_charge_mult", 1.0))
		xr[d] = Def.num(b.get("exposure_recharge_mult", 1.0))
		var per_point: float = Def.num(b.get("recharge_ice_per_point", 0.0))
		pts_per_ice[d] = 1.0 / per_point if per_point > 0.0 else 0.0
	var mr: MatchRulesDef = c.match_rules
	core_until = roundi(mr.core_shield_until_s * float(hz)) if mr != null else 0
