class_name FlightControllerRefAi38 extends RefCounted
## AI-41 reference: `FlightController.track_velocity`, `lead_cap` and `weight_support_throttle` exactly as at
## ded8b4e (the AI-38 code the committed `test/tuning/reports/ai38` CSVs were first generated with), before the
## review-round rework (5961ff9: cap / floor skips, inlined lookup, cached FlightGains constants; 94c0272: floor
## guard for integ_band 0). The unchanged helpers (`_point`, `_bank`, `_throttle`, `best_lead`, `lift_best`) are
## called on FlightController. Test code only: the equivalence test compares the shipped law against this.


static func track_velocity(b: Basis, v: Vector3, v_cmd: Vector3, up_local: Vector3,
		g: FlightGains, integ: Vector2, out: PilotInput) -> Vector2:
	var fwd: Vector3 = -b.z
	var u: float = v.length()
	var vhat: Vector3 = v / u if u >= 1.0 else fwd
	var s_cmd: float = v_cmd.length()
	var d: Vector3 = v_cmd / s_cmd if s_cmd > 0.0 else vhat
	var hr: Vector3 = b.x - vhat * b.x.dot(vhat)
	hr = hr.normalized() if hr.length_squared() > 0.0 else vhat.cross(up_local).normalized()
	var vu: Vector3 = hr.cross(vhat)
	var dl: float = d.dot(vhat)
	var e_p: float = atan2(d.dot(vu), Vector2(dl, d.dot(hr)).length())
	var e_l: float = atan2(d.dot(hr), dl)
	var e_gamma: float = d.dot(up_local) - vhat.dot(up_local)
	var vn: Vector3 = (up_local - vhat * vhat.dot(up_local)).normalized()
	var lead: Vector3 = vu * (g.kp_path * e_p) + hr * (g.kp_path * e_l) + vn * integ.x
	var la: float = lead.length()
	var ix: float = integ.x
	var cap: float = lead_cap(u, Vector2(e_p, e_l).length(), s_cmd - u, g)
	if la < cap:
		var e_i: float = clampf(e_gamma, -g.integ_band, g.integ_band)
		ix = clampf(ix + g.ki_path * e_i * g.dt, -g.integ_max, g.integ_max)
	la = minf(la, cap)
	var nose: Vector3 = vhat
	if la > 0.0:
		nose = vhat * cos(la) + lead.normalized() * sin(la)
	FlightController._point(b, nose, b.x, g, out)
	out.roll = FlightController._bank(b, vhat, d, up_local, g)
	var turn: float = g.kp_turn_thrust * Vector2(e_p, e_l).length()
	var iy: float = FlightController._throttle(s_cmd - u, integ.y, maxf(fwd.dot(vhat), 0.5), turn, g, out)
	var w: float = clampf(1.0 + e_gamma / g.integ_band, 0.0, 1.0) if g.integ_band > 0.0 else 1.0
	var floor_t: float = weight_support_throttle(b, v, up_local, g) * w
	if floor_t > out.thrust:
		out.thrust = floor_t
		iy = integ.y
	return Vector2(ix, iy)


static func lead_cap(u: float, err: float, e_s: float, g: FlightGains) -> float:
	var best: float = FlightController.best_lead(u, err, g)
	if best >= g.lead_max:
		return g.lead_max
	var w: float = clampf(-e_s / g.brake_overspeed, 0.0, 1.0) if g.brake_overspeed > 0.0 else 0.0
	return best + (g.lead_max - best) * w


static func weight_support_throttle(b: Basis, v: Vector3, up_local: Vector3, g: FlightGains) -> float:
	var fwd: Vector3 = -b.z
	var s_n: float = fwd.dot(up_local)
	if s_n <= 0.0:
		return 0.0
	var deficit: float = g.rules.gravity - FlightController.lift_best(v.length(), g)
	if deficit <= 0.0:
		return 0.0
	var eff: float = Kinematics.thrust_efficiency(v.dot(fwd), g.ship.v_cruise, g.common.eff_fade_start)
	var a: float = g.ship.a_thrust * eff * s_n
	return minf(deficit / a, 1.0) if a > 0.0 else 1.0
