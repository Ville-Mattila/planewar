class_name FlightController extends RefCounted
## Inner-loop flight controller of 05 s5.2 (AI-05): turns a guidance target into one `PilotInput` per tick
## through the same rate-capped stick a human has (P1). Pure (S8, 03 s5.6): static functions of their arguments,
## no state; the only writes are to `out` and the returned integrators. Shared by autopilots (`sim_ai` act layer)
## and, through `Assist`, by client prediction (ADR-07), so a change here is reviewed for `sim_ai` and `net`.
##
## `track_velocity` flies the flight-path vector: the nose is pointed at the velocity direction rotated toward
## the command by `kp_path` times the path error (plus the pitch integrator, which carries the steady angle of
## attack under either lift model), capped at `lead_max`; the wings bank toward large heading errors and stay
## level below `bank_threshold`. Rates follow a stop-in-time profile, min(kp e, sqrt(2 rate_accel e)), so the
## autopilot never overshoots a pointing target it can see, without needing the body rates (SimView has none).
## The throttle divides the speed loop by cos(AoA) and adds `kp_turn_thrust` per radian of path error: under the
## damping_only lift model thrust is most of the turning force (TA-30: 27-33 degrees of AoA in level flight).
## `b` is the entity basis as SimView returns it: x = right, y = up, z = -forward (Godot's -Z forward).


## Velocity mode (cruise, intercept, patrol, egress). `integ` = (pitch integrator in rad of nose lead, throttle
## integrator); the caller stores the returned value and resets it to Vector2.ZERO on a mode change. Writes thrust,
## pitch, yaw, roll and the BRAKE bit of `out.buttons`; every other button is left as the caller set it.
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
	var e_gamma: float = d.dot(up_local) - vhat.dot(up_local)   # sin difference: monotone, and clamped to the band below
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
	_point(b, nose, b.x, g, out)
	out.roll = _bank(b, vhat, d, up_local, g)
	var turn: float = g.kp_turn_thrust * Vector2(e_p, e_l).length()
	var iy: float = _throttle(s_cmd - u, integ.y, maxf(fwd.dot(vhat), 0.5), turn, g, out)
	var w: float = clampf(1.0 + e_gamma / g.integ_band, 0.0, 1.0) if g.integ_band > 0.0 else 1.0
	var floor_t: float = weight_support_throttle(b, v, up_local, g) * w
	if floor_t > out.thrust:   # the floor flies, not the speed loop: its integrator holds (no wind-down)
		out.thrust = floor_t
		iy = integ.y
	return Vector2(ix, iy)


## Thrust-vector mode (landing L4-L6 and hover, 05 s5.5): points the thrust axis (body forward) along `t_dir`
## and sets the throttle to `t_mag01` times the projection of the current axis on `t_dir` (no thrust while the
## nose points away). The roll rate is commanded to zero; `up_local` picks the pitch-up axis when `t_dir` is
## exactly behind the nose. Clears the BRAKE bit (the landing law sets it after this call if it wants it).
static func track_thrust_vector(b: Basis, t_dir: Vector3, t_mag01: float, up_local: Vector3,
		g: FlightGains, out: PilotInput) -> void:
	var fwd: Vector3 = -b.z
	var td: Vector3 = t_dir.normalized() if t_dir.length_squared() > 0.0 else up_local
	var pitch_axis: Vector3 = fwd.cross(up_local)
	pitch_axis = pitch_axis.normalized() if pitch_axis.length_squared() > 0.0 else b.x
	_point(b, td, pitch_axis, g, out)
	out.roll = 0.0
	out.thrust = clampf(t_mag01 * maxf(fwd.dot(td), 0.0), 0.0, 1.0)
	out.buttons &= ~PilotInput.BRAKE


## Nose-lead cap (AI-38): `lead_max`, but no further than `best_lead`, the AoA that turns the velocity fastest
## toward the command at speed `u` and path error `err` (rad) under the ship's lift law (past it the speed-dependent
## lift falls faster than the thrust adds), unless the speed loop wants to brake: the cap opens linearly to
## `lead_max` as the overspeed `-e_s` reaches `brake_overspeed`.
static func lead_cap(u: float, err: float, e_s: float, g: FlightGains) -> float:
	var best: float = best_lead(u, err, g)
	if best >= g.lead_max:
		return g.lead_max
	var w: float = clampf(-e_s / g.brake_overspeed, 0.0, 1.0) if g.brake_overspeed > 0.0 else 0.0
	return best + (g.lead_max - best) * w


## AoA (rad) of the largest `turn_accel` at speed `u` and path error `err`: bilinear in FlightGains' `lead_best`
## table, clamped at its edges.
static func best_lead(u: float, err: float, g: FlightGains) -> float:
	var n: int = FlightGains.LEAD_ERR_SIZE
	var x: float = clampf(u / g.lead_du, 0.0, float(FlightGains.LEAD_TABLE_SIZE - 1))
	var y: float = clampf(err / g.lead_de, 0.0, float(n - 1))
	var i: int = mini(int(x), FlightGains.LEAD_TABLE_SIZE - 2)
	var j: int = mini(int(y), n - 2)
	var t: PackedFloat32Array = g.lead_best
	var a: float = lerpf(t[i * n + j], t[i * n + j + 1], y - float(j))
	var b: float = lerpf(t[(i + 1) * n + j], t[(i + 1) * n + j + 1], y - float(j))
	return lerpf(a, b, x - float(i))


## Rate (m/s^2) at which full thrust and the lift at AoA `alpha` turn a velocity of speed `u` toward a command
## `err` (rad) off it, wings level, gravity aside: the acceleration along the chord direction (the path normal
## rotated back by err / 2), A eff sin(alpha - err/2) + k u sin(alpha) cos(alpha - err/2), with
## `Kinematics.thrust_efficiency` and `Kinematics.k_up_effective` at the forward speed u cos(alpha). At err 0 it
## peaks near 40 degrees at a Dart's cruise under speed_scaled (the lift collapses with the forward speed), near
## 70 under damping_only (thrust is the lift).
static func turn_accel(u: float, alpha: float, err: float, g: FlightGains) -> float:
	var c: float = cos(alpha)
	var s: float = sin(alpha)
	var v_fwd: float = u * c
	var eff: float = Kinematics.thrust_efficiency(v_fwd, g.ship.v_cruise, g.common.eff_fade_start)
	var h: float = alpha - err * 0.5
	return g.ship.a_thrust * eff * sin(h) + Kinematics.k_up_effective(v_fwd, g.ship, g.rules) * u * s * cos(h)


## Weight-support throttle (AI-38): the throttle whose radial thrust carries the part of gravity that the body-up
## damping lift cannot carry at ANY angle of attack at the current speed (`lift_best`, the best of
## `Kinematics.k_up_effective` u sin(a) cos(a); what the wing can carry is the pitch loop's job, so under
## `speed_scaled` in flight it is 0), at the current nose elevation and `Kinematics.thrust_efficiency` (the ceiling
## fade is not modelled). 0 with the nose at or below the horizon; 1 when full thrust cannot. Under `damping_only`
## (wing lift k_up u / 2) it keeps the speed loop from cutting the thrust that is the lift while decelerating.
static func weight_support_throttle(b: Basis, v: Vector3, up_local: Vector3, g: FlightGains) -> float:
	var fwd: Vector3 = -b.z
	var s_n: float = fwd.dot(up_local)
	if s_n <= 0.0:
		return 0.0
	var deficit: float = g.rules.gravity - lift_best(v.length(), g)
	if deficit <= 0.0:
		return 0.0
	var eff: float = Kinematics.thrust_efficiency(v.dot(fwd), g.ship.v_cruise, g.common.eff_fade_start)
	var a: float = g.ship.a_thrust * eff * s_n
	return minf(deficit / a, 1.0) if a > 0.0 else 1.0


## Largest body-up damping lift (m/s^2) over angles of attack at speed `u`: linear in FlightGains' `lift_best`.
static func lift_best(u: float, g: FlightGains) -> float:
	var x: float = clampf(u / g.lead_du, 0.0, float(FlightGains.LEAD_TABLE_SIZE - 1))
	var i: int = mini(int(x), FlightGains.LEAD_TABLE_SIZE - 2)
	return lerpf(g.lift_best[i], g.lift_best[i + 1], x - float(i))


## PULL_UP attitude law (05 s5.3 as amended by AI-38): the nose goes, at the ship's own rates, to the elevation in
## the vertical plane of the velocity that maximises `climb_accel` now (`pull_up_elevation`: the speed-dependent
## lift of the lift law plus thrust, not "nose to local up", which kills the speed_scaled lift); the wings roll
## level; thrust 1 while the nose is above the horizon and 0 below it (there it would only steepen the dive).
## Writes the axes and thrust; buttons are the caller's.
static func pull_up(b: Basis, v: Vector3, up_local: Vector3, g: FlightGains, out: PilotInput) -> void:
	var fwd: Vector3 = -b.z
	var h: Vector3 = pull_up_plane(b, v, up_local)
	var th: float = pull_up_elevation(v, h, up_local, atan2(fwd.dot(up_local), fwd.dot(h)), g)
	_point(b, h * cos(th) + up_local * sin(th), b.x, g, out)
	out.roll = _bank(b, h, h, up_local, g)
	out.thrust = 1.0 if fwd.dot(up_local) > 0.0 else 0.0


## Height (m) a ship loses before PULL_UP arrests its sink, from now (AI-38 pull-up budget; 0 while climbing): the
## nose turns from its elevation to `pull_up_elevation` at the pitch rate cap (plus one rate ramp, pitch_rate /
## rate_accel) while gravity alone acts, then `climb_accel` there (the speed-dependent lift) stops the sink. INF
## when no climb acceleration is available. A caller pulls up when the clearance it can see is below this.
static func pull_up_loss(b: Basis, v: Vector3, up_local: Vector3, g: FlightGains) -> float:
	var vz: float = v.dot(up_local)
	if vz >= 0.0:
		return 0.0
	var fwd: Vector3 = -b.z
	var h: Vector3 = pull_up_plane(b, v, up_local)
	var th0: float = atan2(fwd.dot(up_local), fwd.dot(h))
	var th: float = pull_up_elevation(v, h, up_local, th0, g)
	var tau: float = absf(th - th0) / g.pitch_rate + g.pitch_rate / g.rate_accel
	var a: float = climb_accel(v, h, up_local, th, g)
	if a <= 0.0:
		return INF
	var vz1: float = vz - g.rules.gravity * tau
	return -vz * tau + 0.5 * g.rules.gravity * tau * tau + vz1 * vz1 / (2.0 * a)


## Unit horizontal direction of the PULL_UP plane: the velocity's, below 1 m/s of ground speed the nose's, with
## the nose vertical the body up's.
static func pull_up_plane(b: Basis, v: Vector3, up_local: Vector3) -> Vector3:
	var h: Vector3 = v - up_local * v.dot(up_local)
	if h.length_squared() < 1.0:
		h = -b.z - up_local * (-b.z).dot(up_local)
		if h.length_squared() <= 0.0:
			h = b.y - up_local * b.y.dot(up_local)
	return h.normalized()


## Target nose elevation (rad, [0, 90] degrees) of PULL_UP in the plane of `h` from the nose elevation `th0`: a
## Newton step on three `climb_accel` samples `stop_angle` apart around th0 (the centre kept inside the range, so
## a nose below the horizon, where thrust is off, does not bend the samples); with no maximum in reach (convex
## samples) the end the slope points to. Re-evaluated every tick, it tracks the optimum as the nose turns.
static func pull_up_elevation(v: Vector3, h: Vector3, up_local: Vector3, th0: float, g: FlightGains) -> float:
	var d: float = minf(g.stop_angle, PI * 0.25)
	var c: float = clampf(th0, d, PI * 0.5 - d)
	var f_m: float = climb_accel(v, h, up_local, c - d, g)
	var f_0: float = climb_accel(v, h, up_local, c, g)
	var f_p: float = climb_accel(v, h, up_local, c + d, g)
	var curv: float = f_p + f_m - 2.0 * f_0
	var th: float = PI if f_p > f_m else -PI
	if curv < 0.0:
		th = c - d * (f_p - f_m) / (2.0 * curv)
	return clampf(th, 0.0, PI * 0.5)


## Radial (climb) acceleration of a ship with velocity `v` if its nose were at elevation `theta` (rad) in the
## vertical plane of the unit horizontal `h`, wings level, thrust 1 above the horizon: thrust times
## `Kinematics.thrust_efficiency`, plus the body-up damping lift (`Kinematics.k_up_effective`), minus gravity.
static func climb_accel(v: Vector3, h: Vector3, up_local: Vector3, theta: float, g: FlightGains) -> float:
	var c: float = cos(theta)
	var s: float = sin(theta)
	var v_fwd: float = v.dot(h * c + up_local * s)
	var v_up: float = v.dot(up_local * c - h * s)
	var eff: float = Kinematics.thrust_efficiency(v_fwd, g.ship.v_cruise, g.common.eff_fade_start)
	var lift: float = Kinematics.k_up_effective(v_fwd, g.ship, g.rules) * v_up * c
	return g.ship.a_thrust * eff * maxf(s, 0.0) - lift - g.rules.gravity


## Stop-in-time rate for an angle error `e` (rad): proportional near the target, never faster than a rate that
## `accel` can still stop within `e`.
static func shape_rate(e: float, kp: float, accel: float) -> float:
	var m: float = absf(e)
	return signf(e) * minf(kp * m, sqrt(2.0 * accel * m))


# Pitch and yaw stick to turn the nose toward `target` (unit). `fallback` is the rotation axis when the target is
# exactly behind the nose (the cross product vanishes).
static func _point(b: Basis, target: Vector3, fallback: Vector3, g: FlightGains, out: PilotInput) -> void:
	var fwd: Vector3 = -b.z
	var axis: Vector3 = fwd.cross(target)
	var s: float = axis.length()
	var c: float = fwd.dot(target)
	var e: Vector3 = Vector3.ZERO
	if s > 0.0:
		e = axis * (atan2(s, c) / s)
	elif c < 0.0:
		e = fallback * PI
	var ep: float = e.dot(b.x)   # shape_rate inlined (hot path, 05 s10 act row)
	var ey: float = e.dot(b.y)
	var mp: float = absf(ep)
	var my: float = absf(ey)
	out.pitch = clampf(signf(ep) * minf(g.kp_att * mp, sqrt(2.0 * g.rate_accel * mp)) / g.pitch_rate, -1.0, 1.0)
	out.yaw = clampf(signf(ey) * minf(g.kp_yaw * my, sqrt(2.0 * g.rate_accel * my)) / g.yaw_rate, -1.0, 1.0)


# Roll stick: bank toward the horizontal heading error beyond bank_threshold (wings level below it, so released
# ships settle head-up, 01 s4.1), faded out when the path or the command is near vertical (no heading) and when
# the nose is near vertical (bank undefined).
static func _bank(b: Basis, vhat: Vector3, d: Vector3, n: Vector3, g: FlightGains) -> float:
	var vh: Vector3 = vhat - n * vhat.dot(n)
	var dh: Vector3 = d - n * d.dot(n)
	var psi: float = atan2(dh.cross(vh).dot(n), vh.dot(dh))
	var w: float = clampf(2.0 * minf(vh.length(), dh.length()), 0.0, 1.0)
	var phi_cmd: float = signf(psi) * clampf(g.kp_bank * (absf(psi) - g.bank_threshold), 0.0, g.bank_max) * w
	var phi: float = atan2(-b.x.dot(n), b.y.dot(n))
	var fwd_h: float = clampf(2.0 * (-b.z).cross(n).length(), 0.0, 1.0)
	var rate: float = shape_rate(wrapf(phi_cmd - phi, -PI, PI), g.kp_roll, g.rate_accel) * fwd_h
	return clampf(rate / g.roll_rate, -1.0, 1.0)


# Throttle: (t_trim + kp_speed e + integrator) / cos_aoa, so the speed loop sets the thrust component along the
# path whatever the nose offset (cos_aoa floored at 0.5); the integrator runs only while it does not deepen a
# saturation. BRAKE when the speed exceeds the command by brake_overspeed. Returns the throttle integrator.
static func _throttle(e_s: float, iy: float, cos_aoa: float, turn: float, g: FlightGains, out: PilotInput) -> float:
	var t: float = (g.t_trim + g.kp_speed * e_s + iy) / cos_aoa + turn
	var i: float = iy
	if (t < 1.0 or e_s < 0.0) and (t > 0.0 or e_s > 0.0):
		i = clampf(iy + g.ki_speed * e_s * g.dt, -1.0, 1.0)
	out.thrust = clampf(t, 0.0, 1.0)
	if -e_s > g.brake_overspeed:
		out.buttons |= PilotInput.BRAKE
	else:
		out.buttons &= ~PilotInput.BRAKE
	return i
