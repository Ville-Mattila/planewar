class_name CapsDef extends RefCounted
## One caps profile of match_rules.json (R0 B.7, B.8 A-8): standard | reduced | lite.

var id: StringName = &""
var units: int = 0
var structures: int = 0  ## per player
var projectiles: int = 0
var wrecks: int = 0
var slots: int = 0


static func from_dict(profile: StringName, d: Dictionary) -> CapsDef:
	var c: CapsDef = CapsDef.new()
	c.id = profile
	c.units = roundi(Def.num(d.get("units", 0)))
	c.structures = roundi(Def.num(d.get("structures", 0)))
	c.projectiles = roundi(Def.num(d.get("projectiles", 0)))
	c.wrecks = roundi(Def.num(d.get("wrecks", 0)))
	c.slots = roundi(Def.num(d.get("slots", 0)))
	return c
