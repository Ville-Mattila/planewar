class_name SupplyCanisterDef extends Def
## commander_verbs.json entry `supply_canister` (08 SL-5, FEAT-01). status stays `candidate` until the C1-13 gate.

var cost_ore: int = 0
var cost_ice: int = 0
var team_max_in_flight: int = 0
var hp: int = 0
var launch_range_m: float = 0.0
var pad_cooldown_s: float = 0.0
var boost_mps: float = 0.0
var boost_s: float = 0.0
var max_speed_mps: float = 0.0
var max_accel_mps2: float = 0.0
var lead_m: float = 0.0
var slow_target_mps: float = 0.0
var hover_above_m: float = 0.0
var min_agl_m: float = 0.0
var max_alt_m: float = 0.0
var deploy_radius_m: float = 0.0
var max_flight_s: float = 0.0
var loiter_s: float = 0.0
var pickup_radius_m: float = 0.0
var fuel_frac: float = 0.0
var ammo_frac: float = 0.0
var divert_radius_m: float = 0.0
var divert_safe_radius_m: float = 0.0
var opportunist_radius_m: float = 0.0

const SPEC: Dictionary = {
	"i": "cost_ore cost_ice team_max_in_flight hp",
	"f": "launch_range_m pad_cooldown_s boost_mps boost_s max_speed_mps max_accel_mps2 lead_m slow_target_mps hover_above_m min_agl_m max_alt_m deploy_radius_m max_flight_s loiter_s pickup_radius_m fuel_frac ammo_frac divert_radius_m divert_safe_radius_m opportunist_radius_m",
	"req": "cost_ore cost_ice team_max_in_flight hp launch_range_m pad_cooldown_s boost_mps boost_s max_speed_mps max_accel_mps2 lead_m slow_target_mps hover_above_m min_agl_m max_alt_m deploy_radius_m max_flight_s loiter_s pickup_radius_m fuel_frac ammo_frac divert_radius_m divert_safe_radius_m opportunist_radius_m",
}


static func from_dict(d: Dictionary) -> SupplyCanisterDef:
	var s: SupplyCanisterDef = SupplyCanisterDef.new()
	s._read_common(d)
	s._fill(d, SPEC)
	return s
