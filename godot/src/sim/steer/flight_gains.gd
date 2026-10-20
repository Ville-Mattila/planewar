class_name FlightGains extends RefCounted
## Parameter struct of FlightController (05 s5.2): the autopilot def's `flight` block plus the ship class's rate
## caps (02 s2.2), the tick, and the lift law the ship flies under (ship def, world rules, flight_common: the
## weight-support floor and the pull-up attitude read `Kinematics` with them, AI-38). One instance per (autopilot
## profile, ship class), shared by every ship of that class and read-only to the controller. No numeric defaults
## live here (ADR-09): build it with `from_dict`. Angles are stored in radians, rates in rad/s.

## Keys `from_dict` requires in the `flight` block (05 s4.4 plus the AI-05 additions listed in MODULE.md).
const KEYS: PackedStringArray = ["kp_path", "ki_path", "integ_max_rad", "integ_band_deg", "lead_max_deg", "kp_att", "kp_yaw",
	"kp_roll", "kp_bank", "bank_threshold_deg", "bank_max_deg", "t_trim", "kp_speed", "ki_speed", "kp_turn_thrust",
	"brake_overspeed_mps"]
## Numerical resolution of the `lead_best` table (AI-38), not tuning: speeds 0..v_dive_max, path errors 0..180
## degrees, AoA search on a 5 degree grid over 0..180 refined by a parabola through the best sample.
const LEAD_TABLE_SIZE: int = 17
const LEAD_ERR_SIZE: int = 9
const LEAD_SEARCH_STEPS: int = 36

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
var ship: ShipDef = null               ## a_thrust, v_cruise, k_up / k_up_flight / k_side (Kinematics lift law)
var rules: RulesDef = null             ## gravity, lift_model
var common: FlightCommonDef = null     ## eff_fade_start (Kinematics.thrust_efficiency)
var stop_angle: float = 0.0            ## pitch_rate^2 / (2 rate_accel) (rad): the pitch a full-rate stop takes
var lead_best: PackedFloat32Array = PackedFloat32Array()   ## AoA of the largest `turn_accel` (rad), [speed][error]
var lead_du: float = 0.0               ## speed step of `lead_best` (m/s): v_dive_max / (LEAD_TABLE_SIZE - 1)
var lead_de: float = 0.0               ## path-error step of `lead_best` (rad): PI / (LEAD_ERR_SIZE - 1)
var lift_best: PackedFloat32Array = PackedFloat32Array()   ## best wing lift k_up_eff u sin cos per speed (m/s^2)


## Builds the struct from an autopilot def's `flight` dictionary, the ship class, the tick rate, the world rules
## and flight_common. Returns null when a key of KEYS is missing or not a number, tick_hz <= 0, or a def is null
## (a broken def is a load error, not a default).
static func from_dict(flight: Dictionary, def: ShipDef, tick_hz: int, rules_def: RulesDef,
		flight_common: FlightCommonDef) -> FlightGains:
	if tick_hz <= 0 or def == null or rules_def == null or flight_common == null:
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
	g.ship = def
	g.rules = rules_def
	g.common = flight_common
	g.stop_angle = g.pitch_rate * g.pitch_rate / (2.0 * g.rate_accel) if g.rate_accel > 0.0 else 0.0
	g.lead_du = def.v_dive_max / float(LEAD_TABLE_SIZE - 1)
	g.lead_de = PI / float(LEAD_ERR_SIZE - 1)
	var _r: int = g.lead_best.resize(LEAD_TABLE_SIZE * LEAD_ERR_SIZE)
	var _l: int = g.lift_best.resize(LEAD_TABLE_SIZE)
	for i: int in LEAD_TABLE_SIZE:
		g.lift_best[i] = _max_lift(float(i) * g.lead_du, g)
		for j: int in LEAD_ERR_SIZE:
			g.lead_best[i * LEAD_ERR_SIZE + j] = _argmax_turn(float(i) * g.lead_du, float(j) * g.lead_de, g)
	return g


# Largest body-up damping lift k_up_effective(u cos a) u sin(a) cos(a) over a in [0, 90] degrees (LEAD_SEARCH_STEPS
# grid, 2.5 degrees).
static func _max_lift(u: float, g: FlightGains) -> float:
	var best: float = 0.0
	for j: int in LEAD_SEARCH_STEPS + 1:
		var alpha: float = PI * 0.5 * float(j) / float(LEAD_SEARCH_STEPS)
		var c: float = cos(alpha)
		best = maxf(best, Kinematics.k_up_effective(u * c, g.ship, g.rules) * u * sin(alpha) * c)
	return best


# AoA in [0, 180] degrees with the largest `FlightController.turn_accel` at speed `u` and path error `err`: the best
# sample of a LEAD_SEARCH_STEPS grid, moved to the vertex of the parabola through it and its neighbours.
static func _argmax_turn(u: float, err: float, g: FlightGains) -> float:
	var step: float = PI / float(LEAD_SEARCH_STEPS)
	var best: int = 0
	var f: PackedFloat32Array = PackedFloat32Array()
	var _r: int = f.resize(LEAD_SEARCH_STEPS + 1)
	for j: int in LEAD_SEARCH_STEPS + 1:
		f[j] = FlightController.turn_accel(u, step * float(j), err, g)
		if f[j] > f[best]:
			best = j
	if best == 0 or best == LEAD_SEARCH_STEPS:
		return step * float(best)
	var curv: float = f[best + 1] + f[best - 1] - 2.0 * f[best]
	var off: float = -0.5 * (f[best + 1] - f[best - 1]) / curv if curv < 0.0 else 0.0
	return step * (float(best) + clampf(off, -0.5, 0.5))


static func _f(d: Dictionary, k: String) -> float:
	var x: Variant = d[k]
	if x is int:
		var i: int = x
		return float(i)
	var f: float = x
	return f
