class_name ShipDef extends Def
## ships.json entry (R0 B.1, 02 s2). Read by sim Kinematics.

var hp: int = 0
var cost_ore: int = 0
var cost_ice: int = 0
var build_time_s: float = 0.0
var produced_at: StringName = &""
var requires: PackedStringArray = PackedStringArray()
var sensor_radius: float = 0.0
var bounding_radius: float = 0.0
var score_value: int = 0
var v_cruise: float = 0.0
var v_cruise_loaded: float = 0.0  ## 0 when absent (Hauler only)
var v_boost: float = 0.0
var boost_duration_s: float = 0.0
var boost_cooldown_s: float = 0.0
var v_dive_max: float = 0.0
var a_thrust: float = 0.0
var pitch_rate_dps: float = 0.0
var yaw_rate_dps: float = 0.0
var roll_rate_dps: float = 0.0
var rate_accel_dps2: float = 0.0
var flip_cooldown_s: float = 0.0
var flip_duration_s: float = 0.0
var k_side: float = 0.0
var k_up: float = 0.0
var k_up_flight: float = 0.0
var primary_weapon: StringName = &""  ## empty = none
var primary_ammo: int = 0
var secondary_weapon: StringName = &""
var secondary_count: int = 0
var fuel_s: float = 0.0
var refuel_ice: int = 0
var refuel_time_s: float = 0.0
var rearm_time_s: float = 0.0
var repair_time_s: float = 0.0
var cargo_ice: int = 0
var tow_slots: int = 0
var possessable: bool = false
var autopilot: StringName = &""

const SPEC: Dictionary = {
	"f": "build_time_s sensor_radius bounding_radius v_cruise v_cruise_loaded v_boost boost_duration_s boost_cooldown_s v_dive_max a_thrust pitch_rate_dps yaw_rate_dps roll_rate_dps rate_accel_dps2 flip_cooldown_s flip_duration_s k_side k_up k_up_flight fuel_s refuel_time_s rearm_time_s repair_time_s",
	"i": "hp cost_ore cost_ice refuel_ice cargo_ice score_value tow_slots",
	"b": "possessable",
	"n": "produced_at autopilot",
	"a": "requires",
	"extra": "primary secondary",
	"req": "hp cost_ore cost_ice build_time_s produced_at requires sensor_radius bounding_radius score_value v_cruise v_boost boost_duration_s boost_cooldown_s v_dive_max a_thrust pitch_rate_dps yaw_rate_dps roll_rate_dps rate_accel_dps2 flip_cooldown_s flip_duration_s k_side k_up k_up_flight primary secondary fuel_s refuel_time_s rearm_time_s repair_time_s cargo_ice tow_slots possessable autopilot",
}


static func from_dict(d: Dictionary) -> ShipDef:
	var s: ShipDef = ShipDef.new()
	s._read_common(d)
	s._fill(d, SPEC)
	var p: Array = Def._weapon_slot(d.get("primary"), "ammo")
	s.primary_weapon = p[0]
	s.primary_ammo = p[1]
	var q: Array = Def._weapon_slot(d.get("secondary"), "count")
	s.secondary_weapon = q[0]
	s.secondary_count = q[1]
	return s
