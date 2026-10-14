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
	if la < g.lead_max:
		var e_i: float = clampf(e_gamma, -g.integ_band, g.integ_band)
		ix = clampf(ix + g.ki_path * e_i * g.dt, -g.integ_max, g.integ_max)
	la = minf(la, g.lead_max)
	var nose: Vector3 = vhat
	if la > 0.0:
		nose = vhat * cos(la) + lead.normalized() * sin(la)
	_point(b, nose, b.x, g, out)
	out.roll = _bank(b, vhat, d, up_local, g)
	var turn: float = g.kp_turn_thrust * Vector2(e_p, e_l).length()
	var iy: float = _throttle(s_cmd - u, integ.y, maxf(fwd.dot(vhat), 0.5), turn, g, out)
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
