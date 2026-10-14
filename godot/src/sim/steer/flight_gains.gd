class_name FlightGains extends RefCounted
## Parameter struct of FlightController (05 s5.2): the autopilot def's `flight` block plus the ship class's rate
## caps (02 s2.2) and the tick. One instance per (autopilot profile, ship class), shared by every ship of that
## class and read-only to the controller. No numeric defaults live here (ADR-09): build it with `from_dict`.
## Angles are stored in radians, rates in rad/s.

## Keys `from_dict` requires in the `flight` block (05 s4.4 plus the AI-05 additions listed in MODULE.md).
const KEYS: PackedStringArray = ["kp_path", "ki_path", "integ_max_rad", "integ_band_deg", "lead_max_deg", "kp_att", "kp_yaw",
	"kp_roll", "kp_bank", "bank_threshold_deg", "bank_max_deg", "t_trim", "kp_speed", "ki_speed", "kp_turn_thrust",
	"brake_overspeed_mps"]

var dt: float = 0.0                    ## 1 / rules.tick_hz
var pitch_rate: float = 0.0            ## ShipDef.pitch_rate_dps (rad/s): full stick
var yaw_rate: float = 0.0              ## ShipDef.yaw_rate_dps (rad/s)
var roll_rate: float = 0.0             ## ShipDef.roll_rate_dps (rad/s)
var rate_accel: float = 0.0            ## ShipDef.rate_accel_dps2 (rad/s^2): the stop-in-time rate profile
var kp_path: float = 0.0               ## nose lead per radian of flight-path error
var ki_path: float = 0.0               ## 1/s: pitch integrator (holds the steady angle of attack)
var integ_max: float = 0.0             ## pitch integrator clamp (rad of nose lead)
var integ_band: float = 0.0            ## flight-path angle error clamp at the pitch integrator input (rad): limits windup
var lead_max: float = 0.0              ## cap of the nose offset from the velocity vector (rad)
var kp_att: float = 0.0                ## 1/s: pitch-axis pointing gain (rate per radian of nose error)
var kp_yaw: float = 0.0                ## 1/s: yaw-axis pointing gain
var kp_roll: float = 0.0               ## 1/s: bank-angle gain
var kp_bank: float = 0.0               ## bank angle per radian of heading error beyond the threshold
var bank_threshold: float = 0.0        ## heading error below which the wings stay level (rad)
var bank_max: float = 0.0              ## bank angle cap (rad)
var t_trim: float = 0.0                ## throttle at zero speed error
var kp_speed: float = 0.0              ## throttle per m/s of speed error
var ki_speed: float = 0.0              ## throttle per m*s of integrated speed error
var kp_turn_thrust: float = 0.0        ## throttle per radian of path error (thrust turns the path under damping_only)
var brake_overspeed: float = 0.0       ## BRAKE when |v| exceeds |v_cmd| by this (m/s)


## Builds the struct from an autopilot def's `flight` dictionary, the ship class and the tick rate. Returns null
## when a key of KEYS is missing or not a number, or tick_hz <= 0 (a broken def is a load error, not a default).
static func from_dict(flight: Dictionary, def: ShipDef, tick_hz: int) -> FlightGains:
	if tick_hz <= 0 or def == null:
		return null
	for k: String in KEYS:
		var x: Variant = flight.get(k)
		if not (x is float or x is int):
			return null
	var g: FlightGains = FlightGains.new()
	g.dt = 1.0 / float(tick_hz)
	g.pitch_rate = deg_to_rad(def.pitch_rate_dps)
	g.yaw_rate = deg_to_rad(def.yaw_rate_dps)
	g.roll_rate = deg_to_rad(def.roll_rate_dps)
	g.rate_accel = deg_to_rad(def.rate_accel_dps2)
	g.kp_path = _f(flight, "kp_path")
	g.ki_path = _f(flight, "ki_path")
	g.integ_max = _f(flight, "integ_max_rad")
	g.integ_band = deg_to_rad(_f(flight, "integ_band_deg"))
	g.lead_max = deg_to_rad(_f(flight, "lead_max_deg"))
	g.kp_att = _f(flight, "kp_att")
	g.kp_yaw = _f(flight, "kp_yaw")
	g.kp_roll = _f(flight, "kp_roll")
	g.kp_bank = _f(flight, "kp_bank")
	g.bank_threshold = deg_to_rad(_f(flight, "bank_threshold_deg"))
	g.bank_max = deg_to_rad(_f(flight, "bank_max_deg"))
	g.t_trim = _f(flight, "t_trim")
	g.kp_speed = _f(flight, "kp_speed")
	g.ki_speed = _f(flight, "ki_speed")
	g.kp_turn_thrust = _f(flight, "kp_turn_thrust")
	g.brake_overspeed = _f(flight, "brake_overspeed_mps")
	return g


static func _f(d: Dictionary, k: String) -> float:
	var x: Variant = d[k]
	if x is int:
		var i: int = x
		return float(i)
	var f: float = x
	return f
