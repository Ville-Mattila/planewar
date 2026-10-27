class_name TeamStateWire extends RefCounted
## One TEAM_STATE (0x85) message as wire integers (04 s2.3): the receiving client's own team. `flags` uses the
## TeamStateView bits (Protocol.TEAM_CORE_EXPOSURE 1, TEAM_LOW_POWER 2, TEAM_CORE_SHIELD_UP 4, TEAM_SPEND_LOCK_ACTIVE 8;
## R0 B.8 A-8, GD-38). `tick` 0 = nothing received yet.

var tick: int = 0
var ore: int = 0
var ice: int = 0
var ore_cap: int = 0
var ice_cap: int = 0
var power_supply: int = 0
var power_demand: int = 0
var unit_cap: int = 0
var structure_cap: int = 0
var flags: int = 0
var member_slot: PackedInt32Array = PackedInt32Array()
var member_units: PackedInt32Array = PackedInt32Array()
var member_structures: PackedInt32Array = PackedInt32Array()


func copy_from(o: TeamStateWire) -> void:
	tick = o.tick
	ore = o.ore
	ice = o.ice
	ore_cap = o.ore_cap
	ice_cap = o.ice_cap
	power_supply = o.power_supply
	power_demand = o.power_demand
	unit_cap = o.unit_cap
	structure_cap = o.structure_cap
	flags = o.flags
	member_slot = o.member_slot.duplicate()
	member_units = o.member_units.duplicate()
	member_structures = o.member_structures.duplicate()


## Index of player `slot` among the members, or -1.
func member_index(slot: int) -> int:
	for k: int in member_slot.size():
		if member_slot[k] == slot:
			return k
	return -1


func add_member(slot: int, units: int, structures: int) -> void:
	var _a: bool = member_slot.push_back(slot)
	var _b: bool = member_units.push_back(units)
	var _c: bool = member_structures.push_back(structures)
