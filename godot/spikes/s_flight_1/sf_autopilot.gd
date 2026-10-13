class_name SfAutopilot extends RefCounted
## Spike stand-in for 05's `sim/steer/` controllers (LandingController L4-L6 behind `Assist.auto_dock`, and a
## reduced L1/L2 approach for the automated-landing measurement). Produces `PilotInput` only, through the same
## `Kinematics.step_ship` a human flies (05 s5.5). Gains from spike_flight.json (05 s5.5 values). Not a contract:
## the real controllers are AI-05 / AI-09 and will be tuned against this spike's numbers.

enum Phase { TRANSIT, APPROACH, TRANSITION, HOVER, FLARE }

var phase: Phase = Phase.TRANSIT
var _d: SfDefs
var _kp_pos: float
var _kd_pos: float
var _kp_vz: float
var _tan_tilt: float
var _tan_tilt_tr: float
var _cos_nose: float
var _exit_hs: float
var _exit_dist: float
var _speed_cap: float
var _flare_agl: float
var _touch_vz: float
var _sink_gain: float
var _sink_min: float
var _sink_max: float
var _tan_flare: float
var _att_kp: float
var _att_kd: float


func _init(d: SfDefs) -> void:
	_d = d
	var l: Dictionary = d.landing
	_kp_pos = SfDefs.num(l, "kp_pos")
	_kd_pos = SfDefs.num(l, "kd_pos")
	_kp_vz = SfDefs.num(l, "kp_vz")
	_tan_tilt = tan(deg_to_rad(SfDefs.num(l, "max_tilt_deg")))
	_tan_tilt_tr = tan(deg_to_rad(SfDefs.num(l, "transition_max_tilt_deg")))
	_cos_nose = cos(deg_to_rad(SfDefs.num(l, "transition_nose_deg")))
	_exit_hs = SfDefs.num(l, "transition_exit_hspeed_mps")
	_exit_dist = SfDefs.num(l, "transition_exit_dist_m")
	_speed_cap = SfDefs.num(l, "transition_speed_cap_mps")
	_flare_agl = SfDefs.num(l, "flare_agl_m")
	_touch_vz = SfDefs.num(l, "touch_vz_mps")
	_sink_gain = SfDefs.num(l, "sink_gain")
	_sink_min = SfDefs.num(l, "sink_min_mps")
	_sink_max = SfDefs.num(l, "sink_max_mps")
	_tan_flare = tan(deg_to_rad(SfDefs.num(l, "flare_tilt_deg")))
	_att_kp = SfDefs.num(l, "att_kp")
	_att_kd = SfDefs.num(l, "att_kd")


func reset(start: Phase) -> void:
	phase = start


## Auto-dock assist: L4 TRANSITION -> L5 HOVER-DESCENT -> L6 FLARE over the pad (05 s5.5).
func dock_step(s: ShipState, def: ShipDef, pad_p: Vector3, pad_n: Vector3, out: PilotInput) -> void:
	if phase < Phase.TRANSITION:
		phase = Phase.TRANSITION
	var rel: Vector3 = pad_p - s.p
	var e: Vector3 = rel - pad_n * rel.dot(pad_n)
	var w: Vector3 = s.v - pad_n * s.v.dot(pad_n)
	var agl: float = -rel.dot(pad_n) - def.bounding_radius
	var vz: float = s.v.dot(pad_n)
	if phase == Phase.TRANSITION and w.length() < _exit_hs and e.length() < _exit_dist:
		phase = Phase.HOVER
	var centred: float = clampf(1.0 - e.length() / _d.pad_radius_m, 0.0, 1.0)
	if phase == Phase.HOVER and agl < _flare_agl and centred > 0.5:
		phase = Phase.FLARE
	var vz_cmd: float = 0.0
	var tan_lim: float = _tan_tilt
	if phase == Phase.TRANSITION:
		tan_lim = _tan_tilt_tr
	elif phase == Phase.HOVER:
		vz_cmd = -clampf(_sink_gain * agl, _sink_min, _sink_max) * centred
		if centred <= 0.5 and agl < _flare_agl:   # low and off-centre: climb back to flare height first
			vz_cmd = minf(_sink_gain * (_flare_agl - agl), _sink_min)
	else:
		vz_cmd = -_touch_vz * centred
		tan_lim = _tan_flare
	var w_cmd: Vector3 = (e * (_kp_pos / _kd_pos)).limit_length(_speed_cap)
	var a_h: Vector3 = (w_cmd - w) * _kd_pos
	var a_v: float = _kp_vz * (vz_cmd - vz) + _d.rules.gravity
	var t: Vector3 = a_h.limit_length(maxf(a_v, 0.0) * tan_lim) + pad_n * a_v
	thrust_vector(s, def, t, out)
	out.buttons = PilotInput.DOCK
	if phase == Phase.TRANSITION and s.fwd.dot(pad_n) < _cos_nose and s.v.dot(s.fwd) > 0.0:
		out.buttons |= PilotInput.BRAKE


## Point the thrust axis along `t` (desired acceleration from thrust, m/s^2) and set the throttle to the
## projection of `t` on the current axis (05 track_thrust_vector, simplified). Roll rate is damped to zero.
func thrust_vector(s: ShipState, def: ShipDef, t: Vector3, out: PilotInput) -> void:
	var t_dir: Vector3 = t.normalized() if t.length_squared() > 0.0 else s.p.normalized()
	var err: Vector3 = s.fwd.cross(t_dir)
	if s.fwd.dot(t_dir) < 0.0 and err.length_squared() < 0.25:
		err = s.fwd.cross(s.up)          # nearly opposite: pitch nose-up first
	var right: Vector3 = s.fwd.cross(s.up)
	out.pitch = clampf((_att_kp * err.dot(right) - _att_kd * s.rates.x) / deg_to_rad(def.pitch_rate_dps), -1.0, 1.0)
	out.yaw = clampf((_att_kp * err.dot(s.up) - _att_kd * s.rates.y) / deg_to_rad(def.yaw_rate_dps), -1.0, 1.0)
	out.roll = clampf(-_att_kd * s.rates.z / deg_to_rad(def.roll_rate_dps), -1.0, 1.0)
	var eff: float = Kinematics.thrust_efficiency(s.v.dot(s.fwd), def.v_cruise, _d.common.eff_fade_start)
	var alt: float = s.p.length() - Sphere.PLANET_RADIUS
	eff *= Kinematics.ceiling_efficiency(alt, _d.rules)
	out.thrust = clampf(maxf(t.dot(s.fwd), 0.0) / maxf(def.a_thrust * eff, 0.001), 0.0, 1.0)


## Harness autopilot: L1 TRANSIT at cruise altitude, L2 glide slope with the 05 speed schedule, then dock_step
## from transition_dist_m. Wings level, heading by yaw (k_side drags the velocity onto the nose).
func approach_step(s: ShipState, def: ShipDef, pad_p: Vector3, pad_n: Vector3, out: PilotInput) -> void:
	var a: Dictionary = _d.approach
	var dist: float = Sphere.great_circle(s.p, pad_p)
	if phase >= Phase.TRANSITION or dist < SfDefs.num(a, "transition_dist_m"):
		dock_step(s, def, pad_p, pad_n, out)
		return
	var gate: float = SfDefs.num(a, "gate_dist_m")
	var tr: float = SfDefs.num(a, "transition_dist_m")
	var s_min: float = SfDefs.num(a, "min_speed_mps")
	phase = Phase.APPROACH if dist < gate else Phase.TRANSIT
	var h_cmd: float = SfDefs.num(a, "cruise_alt_agl_m")
	var s_cmd: float = def.v_cruise
	if phase == Phase.APPROACH:
		h_cmd = minf(h_cmd, dist * tan(deg_to_rad(SfDefs.num(a, "glide_deg"))))
		s_cmd = s_min + (def.v_cruise - s_min) * clampf((dist - tr) / (gate - tr), 0.0, 1.0)
	var n: Vector3 = s.p.normalized()
	var to_pad: Vector3 = pad_p - s.p
	to_pad = (to_pad - n * to_pad.dot(n)).normalized()
	hold(s, def, h_cmd, s_cmd, to_pad, out)


## Level hold at altitude `h0` (datum = pad level on the flat stub), forward speed `v_target`, heading `dir`
## (tangent unit vector; zero keeps the current heading). Also used for the forced-release descent and AoA runs.
func hold(s: ShipState, def: ShipDef, h0: float, v_target: float, dir: Vector3, out: PilotInput) -> void:
	var a: Dictionary = _d.approach
	var n: Vector3 = s.p.normalized()
	var v_fwd: float = s.v.dot(s.fwd)
	var vz: float = s.v.dot(n)
	var alt: float = s.p.length() - Sphere.PLANET_RADIUS - def.bounding_radius
	var k_eff: float = Kinematics.k_up_effective(v_fwd, def, _d.rules)
	var trim: float = _d.rules.gravity / (maxf(v_fwd, 1.0) * maxf(k_eff, 0.01))
	var vz_lim: float = SfDefs.num(a, "vz_limit_mps")
	var vz_cmd: float = clampf(SfDefs.num(a, "kp_alt") * (h0 - alt), -vz_lim, vz_lim)
	var theta_cmd: float = minf(trim, deg_to_rad(SfDefs.num(a, "bank_limit_deg"))) \
		+ SfDefs.num(a, "theta_gain") * (vz_cmd - vz)
	var theta: float = asin(clampf(s.fwd.dot(n), -1.0, 1.0))
	var right: Vector3 = s.fwd.cross(s.up)
	var kp: float = SfDefs.num(a, "kp_path")
	var kd: float = SfDefs.num(a, "kd_rate")
	out.pitch = clampf((kp * (theta_cmd - theta) - kd * s.rates.x) / deg_to_rad(def.pitch_rate_dps), -1.0, 1.0)
	out.roll = clampf((kp * right.dot(n) - kd * s.rates.z) / deg_to_rad(def.roll_rate_dps), -1.0, 1.0)
	var e_lat: float = 0.0
	if dir.length_squared() > 0.0:
		var f_t: Vector3 = (s.fwd - n * s.fwd.dot(n)).normalized()
		e_lat = atan2(dir.dot(f_t.cross(n)), dir.dot(f_t))   # + = target to the right; yaw + = nose left
	out.yaw = clampf((-SfDefs.num(a, "kp_heading") * e_lat - kd * s.rates.y) / deg_to_rad(def.yaw_rate_dps),
		-1.0, 1.0)
	out.thrust = clampf(SfDefs.num(a, "kp_speed") * (v_target - v_fwd) + 0.1, 0.0, 1.0)
	out.buttons = 0
	if v_fwd - v_target > SfDefs.num(_d.assist, "auto_throttle_brake_mps"):
		out.buttons = PilotInput.BRAKE
