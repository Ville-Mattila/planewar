class_name GroundUnitDef extends Def
## ground_units.json entry (R0 B.1, 02 s3).

var hp: int = 0
var cost_ore: int = 0
var cost_ice: int = 0
var build_time_s: float = 0.0
var produced_at: StringName = &""
var requires: PackedStringArray = PackedStringArray()
var ground_speed: float = 0.0
var ground_speed_loaded: float = 0.0  ## 0 when absent
var max_slope_deg: float = 0.0
var cargo_ore: int = 0
var mine_rate: float = 0.0
var unload_time_s: float = 0.0
var weapon: StringName = &""  ## empty = none (null in JSON)
var ammo: int = 0
var sensor_radius: float = 0.0
var bounding_radius: float = 0.0
var score_value: int = 0
var possessable: bool = false
var autopilot: StringName = &""

const SPEC: Dictionary = {
	"f": "build_time_s ground_speed ground_speed_loaded max_slope_deg mine_rate unload_time_s sensor_radius bounding_radius",
	"i": "hp cost_ore cost_ice cargo_ore ammo score_value",
	"b": "possessable",
	"n": "produced_at autopilot",
	"a": "requires",
	"extra": "weapon",
	"req": "hp cost_ore cost_ice build_time_s produced_at requires ground_speed max_slope_deg weapon sensor_radius bounding_radius score_value possessable autopilot",
}


static func from_dict(d: Dictionary) -> GroundUnitDef:
	var g: GroundUnitDef = GroundUnitDef.new()
	g._read_common(d)
	g._fill(d, SPEC)
	var w: Variant = d.get("weapon")
	if typeof(w) == TYPE_STRING:
		g.weapon = StringName(str(w))
	return g
