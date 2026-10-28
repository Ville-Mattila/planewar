class_name FlightCommonDef extends RefCounted
## Top-level `flight_common` object of ships.json (R0 B.1, B.9 A-13, A-29..A-35). Read by sim Kinematics.

var eff_fade_start: float = 0.0
var brake_factor: float = 0.0
var brake_fade_mps: float = 0.0  ## brake ramp clamp(v_fwd / brake_fade_mps, 0, 1) (R0 B.9 A-13)
var boost_thrust_mult: float = 0.0
var overspeed_dps: float = 0.0
var terrain_kill_speed: float = 0.0
var terrain_damage_speed: float = 0.0
var landing_safe_v_vert: float = 0.0
var landing_safe_v_hor: float = 0.0
var landing_safe_pitch_deg: float = 0.0
var landing_damage_v_vert: float = 0.0
var landing_damage_v_hor: float = 0.0
var launch_speed_mps: float = 0.0
var tether_len_m: float = 0.0
var tether_drop_m: float = 0.0
var tether_tau_s: float = 0.0
var tow_turn_rate_mult: float = 0.0
var auto_dock_radius_m: float = 0.0
var flip_speed_retain: float = 0.0  ## flip ends flying the reversed heading at this fraction of its speed (A-29)
var scrape_clear_s: float = 0.0  ## a terrain contact episode ends after this long clear of the ground (A-30)
var fuel_burn_boost_per_s: float = 0.0  ## extra fuel per second while boosting (A-32, 02 s2.3)
var fuel_burn_brake_per_s: float = 0.0  ## extra fuel per second while braking (A-32, 02 s2.3)
var fuel_burn_idle_per_s: float = 0.0  ## attitude-jet idle burn per second (A-32, 02 s2.3)
var landing_damage_tilt_deg: float = 0.0  ## tilt up to this lands with damage, beyond destroys (A-35)
var auto_dock_latch_mult: float = 0.0  ## auto-dock holds out to auto_dock_radius_m * this while DOCK is held (A-34)
var crash_pad_damage: float = 0.0  ## pad HP lost to a crash landing (02 s2.2, A-120)
var raw: Dictionary = {}
var errors: Array[String] = []
var unknown: Array[String] = []

const KEYS: PackedStringArray = [
	"eff_fade_start", "brake_factor", "brake_fade_mps", "boost_thrust_mult", "overspeed_dps", "terrain_kill_speed",
	"terrain_damage_speed", "landing_safe_v_vert", "landing_safe_v_hor", "landing_safe_pitch_deg",
	"landing_damage_v_vert", "landing_damage_v_hor", "launch_speed_mps", "tether_len_m", "tether_drop_m",
	"tether_tau_s", "tow_turn_rate_mult", "auto_dock_radius_m", "flip_speed_retain", "scrape_clear_s",
	"fuel_burn_boost_per_s", "fuel_burn_brake_per_s", "fuel_burn_idle_per_s", "landing_damage_tilt_deg",
	"auto_dock_latch_mult", "crash_pad_damage",
]


static func from_dict(d: Dictionary) -> FlightCommonDef:
	var c: FlightCommonDef = FlightCommonDef.new()
	c.raw = d.duplicate(true)
	for key: String in KEYS:
		var v: Variant = d.get(key)
		if typeof(v) != TYPE_FLOAT and typeof(v) != TYPE_INT:
			c.errors.append("flight_common.%s missing or not a number" % key)
			continue
		c.set(key, Def.num(v))
	for k: Variant in d.keys():
		if not KEYS.has(str(k)):
			c.unknown.append(str(k))
	return c
