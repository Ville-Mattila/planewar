class_name LandingController extends RefCounted
## Tail-down powered landing of 05 s5.5 (owner decision O-2, R0 B.5), AI-09. Static and pure (S8): every function
## reads only its arguments and writes only `st` (the caller's per-landing memory) and `out`. The sub-machine:
## L1 TRANSIT -> L2 APPROACH (bearing, glide slope, speed schedule) -> L4 TRANSITION -> L5 HOVER -> L6 FLARE, with
## L2b HOLD for a busy pad and L3 GO_AROUND on any abort. L1-L3 fly a guidance velocity through
## FlightController.track_velocity; L4-L6 fly the 05 position law through track_thrust_vector, with two AI-09
## additions: a height floor while the ship is not over the pad, and vertical-first thrust allocation (horizontal
## authority is what is left of the thrust once the vertical demand is met), so a fast entry never trades height
## for braking. `Assist.auto_dock` (AI-10) runs the same `thrust_law` for a possessed ship.
## The caller owns pad selection and the DONE transition (it sees the sim's DOCKED state); after an abort it reads
## `st.abort_reason` (PAD_INVALID: select another pad) and `st.attempts` (> max_attempts: select another pad).

enum Phase { TRANSIT, APPROACH, HOLD, GO_AROUND, TRANSITION, HOVER, FLARE, DONE }
enum Abort { NONE, HORIZ_ERR, SINK, PAD_INVALID, PAD_BUSY, PAD_THREAT, TTI, GLIDE }


## One tick: abort rules, phase transitions, then the control output for the (new) phase into `out` (axes, thrust,
## BRAKE bit; the caller sets DOCK and every other button). Returns `st.phase`.
static func step(st: LandingState, ship: ShipSnapshot, pad: PadSnapshot, prm: LandingParams, g: FlightGains,
		out: PilotInput) -> int:
	var ab: int = should_abort(st, ship, pad, prm)
	if ab != Abort.NONE:
		go_around(st, ship, pad, ab)
	_advance(st, ship, pad, prm)
	if st.phase == Phase.DONE:
		out.thrust = 0.0
		out.pitch = 0.0
		out.yaw = 0.0
		out.roll = 0.0
		out.buttons &= ~PilotInput.BRAKE
	elif st.phase >= Phase.TRANSITION:
		thrust_law(st.phase, ship, pad, prm, g, out)
	else:
		var v_cmd: Vector3 = guidance(st, ship, pad, prm)
		st.integ = FlightController.track_velocity(ship.b, ship.v, v_cmd, ship.p.normalized(), g, st.integ, out)
	return st.phase


## The 05 s5.5 abort rules for the current phase; Abort.NONE when none applies. TRANSIT and HOLD abort only on an
## invalid pad; GO_AROUND and DONE never.
static func should_abort(st: LandingState, ship: ShipSnapshot, pad: PadSnapshot, prm: LandingParams) -> int:
	var ph: int = st.phase
	if ph == Phase.DONE or ph == Phase.GO_AROUND:
		return Abort.NONE
	if not pad.valid:
		return Abort.PAD_INVALID
	if ph == Phase.TRANSIT or ph == Phase.HOLD:
		return Abort.NONE
	if pad.threat:
		return Abort.PAD_THREAT
	var rel: Vector3 = ship.p - pad.p
	var hc: float = rel.dot(pad.n)
	var h: float = hc - ship.bounding_radius
	var w: Vector3 = ship.v - pad.n * ship.v.dot(pad.n)
	if ph >= Phase.TRANSITION:
		if pad.busy:
			return Abort.PAD_BUSY
		if h < prm.abort_vz_agl_m and -ship.v.dot(pad.n) > prm.abort_vz:
			return Abort.SINK
		if ph >= Phase.HOVER and h < prm.abort_horiz_agl_m \
				and (rel - pad.n * hc).length() > prm.abort_horiz_err_m:
			return Abort.HORIZ_ERR
	if ship.tti_s < prm.abort_tti_s:
		var impact: Vector3 = rel + w * ship.tti_s
		if (impact - pad.n * impact.dot(pad.n)).length() > pad.radius_m:
			return Abort.TTI
	return Abort.NONE


## Enters L3 GO_AROUND for `reason`: the climb-out extends from here along the approach course (opposite the
## bearing; the current track, else the line to the pad, when no bearing was chosen). Attempts count at its end.
static func go_around(st: LandingState, ship: ShipSnapshot, pad: PadSnapshot, reason: int) -> void:
	var np: Vector3 = pad.p.normalized()
	var dir: Vector3 = -st.bearing
	if dir.length_squared() == 0.0:
		dir = ship.v - np * ship.v.dot(np)
		if dir.length_squared() < 1.0:
			dir = pad.p - ship.p
		dir = dir - np * dir.dot(np)
	st.ga_dir = dir.normalized() if dir.length_squared() > 0.0 else Sphere.tangent_frame(np).y
	st.mark = ship.p.normalized()
	st.abort_reason = reason
	_set_phase(st, Phase.GO_AROUND)


## Phase transitions that are not aborts (05 s5.5 table).
static func _advance(st: LandingState, ship: ShipSnapshot, pad: PadSnapshot, prm: LandingParams) -> void:
	var np: Vector3 = pad.p.normalized()
	var r_pad: float = pad.p.length()
	var d: float = np.angle_to(ship.p) * r_pad
	match st.phase:
		Phase.TRANSIT:
			if d < prm.gate_dist_m and pad.busy:
				_set_phase(st, Phase.HOLD)
			elif d < prm.gate_dist_m and st.bearing.length_squared() > 0.0:
				_set_phase(st, Phase.APPROACH)
		Phase.APPROACH:
			if pad.busy:
				_set_phase(st, Phase.HOLD)
			elif d < prm.transition_dist_m and _established(_line(st, ship, pad), ship, pad, prm):
				var h: float = ship.p.length() - r_pad - ship.bounding_radius
				if absf(h - d * prm.tan_glide) <= prm.glide_tol_m:
					_set_phase(st, Phase.TRANSITION)
				else:
					go_around(st, ship, pad, Abort.GLIDE)
		Phase.HOLD:
			if not pad.busy:
				st.bearing = Vector3.ZERO
				_set_phase(st, Phase.TRANSIT)
		Phase.GO_AROUND:
			var agl: float = ship.p.length() - Sphere.PLANET_RADIUS - ship.ground_h - ship.bounding_radius
			if st.mark.angle_to(ship.p) * r_pad >= prm.goaround_extend_m \
					and agl >= prm.goaround_agl_m - prm.glide_tol_m:
				st.attempts += 1
				st.bearing = Vector3.ZERO
				_set_phase(st, Phase.TRANSIT)
		_:
			_advance_thrust(st, ship, pad, prm)


static func _advance_thrust(st: LandingState, ship: ShipSnapshot, pad: PadSnapshot, prm: LandingParams) -> void:
	var rel: Vector3 = pad.p - ship.p
	var hc: float = -rel.dot(pad.n)
	var e: float = (rel + pad.n * hc).length()
	if st.phase == Phase.TRANSITION:
		# L4 -> L5 also needs the ship to stay outside the L5 horizontal abort envelope (low and off-centre): a low
		# entry climbs to the floor or centres in L4 first (offset plus the drift of one 1 / kd_pos time constant)
		# instead of aborting in L5 under L5's smaller tilt limit.
		var ws: float = (ship.v - pad.n * ship.v.dot(pad.n)).length()
		var clear: bool = e + ws / prm.kd_pos <= prm.abort_horiz_err_m \
			or hc - ship.bounding_radius >= prm.abort_horiz_agl_m
		var upright: bool = (-ship.b.z).dot(pad.n) >= prm.cos_transition_nose
		if ws < prm.transition_exit_hspeed and e < prm.transition_exit_dist_m and clear and upright:
			_set_phase(st, Phase.HOVER)
	elif st.phase == Phase.HOVER:
		var drift: float = (ship.v - pad.n * ship.v.dot(pad.n)).length() / prm.kd_pos
		if hc - ship.bounding_radius < prm.flare_agl_m and e + drift < pad.radius_m * 0.5:
			_set_phase(st, Phase.FLARE)


static func _set_phase(st: LandingState, ph: int) -> void:
	if st.phase != ph:
		st.phase = ph
		st.integ = Vector2.ZERO


## Guidance velocity of the velocity phases (L1 TRANSIT, L2 APPROACH, L2b HOLD, L3 GO_AROUND); ZERO otherwise.
static func guidance(st: LandingState, ship: ShipSnapshot, pad: PadSnapshot, prm: LandingParams) -> Vector3:
	var n: Vector3 = ship.p.normalized()
	var np: Vector3 = pad.p.normalized()
	var agl: float = ship.p.length() - Sphere.PLANET_RADIUS - ship.ground_h - ship.bounding_radius
	match st.phase:
		Phase.TRANSIT:   # cruise height, but never above the glide slope extended past the gate
			var dh: float = np.angle_to(n) * pad.p.length() * prm.tan_glide 				- (ship.p.length() - pad.p.length() - ship.bounding_radius)
			var vz: float = prm.kp_alt * minf(prm.cruise_alt_agl_m - agl, dh)
			return _v_cmd(ship, _toward(n, np), ship.v_cruise, vz, prm)
		Phase.APPROACH:
			return _approach(st, ship, pad, prm, agl)
		Phase.HOLD:
			return _hold(ship, np, prm, agl)
		Phase.GO_AROUND:
			var aim: Vector3 = _along(np, st.ga_dir, prm.goaround_extend_m / pad.p.length())
			return _v_cmd(ship, _toward(n, aim), ship.v_cruise, prm.kp_alt * (prm.goaround_agl_m - agl), prm)
	return Vector3.ZERO


# L2: pure pursuit of the approach line (bearing b, from the gate fix to the pad) at the 05 speed schedule. Until
# the ship is established (on the approach side, cross track <= along track * tan_capture) it flies to the gate
# fix at v_cruise; established, it holds the glide slope h(d) = d tan(glide) above the pad.
static func _approach(st: LandingState, ship: ShipSnapshot, pad: PadSnapshot, prm: LandingParams, agl: float) -> Vector3:
	var n: Vector3 = ship.p.normalized()
	var np: Vector3 = pad.p.normalized()
	var r_pad: float = pad.p.length()
	var ln: Vector3 = _line(st, ship, pad)
	var h: float = ship.p.length() - r_pad - ship.bounding_radius
	if not _established(ln, ship, pad, prm):
		# to the gate fix at the glide height of the gate, at least hold_agl_m above the terrain; within one
		# lookahead of the fix (or beyond it) pursue the line inbound, which turns the ship onto it
		var aim: Vector3 = _along(np, st.bearing, prm.gate_dist_m / r_pad)
		if ln.y >= prm.gate_dist_m - prm.approach_lookahead_m and ln.z <= ln.y * prm.tan_capture:
			aim = _along(np, st.bearing, clampf(ln.y - prm.approach_lookahead_m, 0.0, prm.gate_dist_m) / r_pad)
		var vz_fix: float = prm.kp_alt * maxf(prm.gate_dist_m * prm.tan_glide - h, prm.hold_agl_m - agl)
		return _v_cmd(ship, _toward(n, aim), ship.v_cruise, vz_fix, prm)
	var span: float = maxf(prm.gate_dist_m - prm.transition_dist_m, 1.0)
	var s: float = clampf(prm.approach_min_speed + (ship.v_cruise - prm.approach_min_speed)
		* (ln.x - prm.transition_dist_m) / span, prm.approach_min_speed, ship.v_cruise)
	var a_aim: float = clampf(ln.y - prm.approach_lookahead_m, 0.0, prm.gate_dist_m)
	var vz: float = maxf(prm.kp_alt * (ln.x * prm.tan_glide - h) - s * prm.tan_glide, -2.0 * s * prm.tan_glide)
	return _v_cmd(ship, _toward(n, _along(np, st.bearing, a_aim / r_pad)), s, vz, prm)


# (great-circle distance to the pad, along-track, cross-track) of the ship relative to the approach line, in the
# pad's azimuthal-equidistant frame.
static func _line(st: LandingState, ship: ShipSnapshot, pad: PadSnapshot) -> Vector3:
	var n: Vector3 = ship.p.normalized()
	var np: Vector3 = pad.p.normalized()
	var d: float = np.angle_to(n) * pad.p.length()
	var u: Vector3 = n - np * n.dot(np)
	var r: Vector3 = u.normalized() * d if u.length_squared() > 0.0 else Vector3.ZERO
	var along: float = r.dot(st.bearing)
	return Vector3(d, along, (r - st.bearing * along).length())


# On the approach side of the pad, within approach_capture_deg of the line seen from the pad, and inbound (the
# ground track closes on the pad: a ship crossing the pad on its way to the gate fix is not established).
static func _established(ln: Vector3, ship: ShipSnapshot, pad: PadSnapshot, prm: LandingParams) -> bool:
	if ln.y <= 0.0 or ln.z > ln.y * prm.tan_capture:
		return false
	var n: Vector3 = ship.p.normalized()
	return ship.v.dot(_toward(n, pad.p.normalized())) > 0.0


# L2b: orbit the pad at hold_radius_m (counter-clockwise seen from above) and hold_agl_m.
static func _hold(ship: ShipSnapshot, np: Vector3, prm: LandingParams, agl: float) -> Vector3:
	var n: Vector3 = ship.p.normalized()
	var d: float = np.angle_to(n) * Sphere.PLANET_RADIUS
	var out_dir: Vector3 = -_toward(n, np)
	var tang: Vector3 = n.cross(out_dir)
	var radial: float = clampf((prm.hold_radius_m - d) / prm.hold_radius_m * 2.0, -1.0, 1.0)
	var dir: Vector3 = (tang + out_dir * radial).normalized()
	return _v_cmd(ship, dir, prm.hold_speed, prm.kp_alt * (prm.hold_agl_m - agl), prm)


# Direction from the speed (the vertical rate is met while the speed loop converges) and the commanded speed; the
# terrain lift of the last think raises the vertical rate (05 s5.3), the clamp bounds it.
# The horizontal direction is limited to turn_cmd_max_deg off the current track (bank-to-turn instead of a loop
# when the target is behind; below 1 m/s of ground speed any direction goes).
static func _v_cmd(ship: ShipSnapshot, to: Vector3, speed: float, vz: float, prm: LandingParams) -> Vector3:
	var n: Vector3 = ship.p.normalized()
	var z: float = clampf(vz, -prm.vz_max, prm.vz_max)
	if ship.lift_mps > 0.0:
		z = maxf(z, ship.v.dot(n) + ship.lift_mps)
	var track: Vector3 = ship.v - n * ship.v.dot(n)
	var dir: Vector3 = to
	if track.length_squared() >= 1.0:
		track = track.normalized()
		var ang: float = atan2(track.cross(to).dot(n), track.dot(to))
		if absf(ang) > prm.turn_cmd_max:
			dir = track.rotated(n, signf(ang) * prm.turn_cmd_max)
	var u: float = maxf(ship.v.length(), 1.0)
	return (dir * u + n * z).normalized() * speed


# Unit tangent at `n` toward the direction `to` (any tangent when they coincide).
static func _toward(n: Vector3, to: Vector3) -> Vector3:
	var t: Vector3 = to - n * to.dot(n)
	return t.normalized() if t.length_squared() > 0.0 else Sphere.tangent_frame(n).y


# The unit direction `ang` radians from `np` along the tangent `b`.
static func _along(np: Vector3, b: Vector3, ang: float) -> Vector3:
	return np * cos(ang) + b * sin(ang)


## L4-L6 output (05 s5.5, R0 B.5 tail-down): the thrust vector of `thrust_vector` through
## FlightController.track_thrust_vector, throttle |T| / available thrust; BRAKE in L4 while the nose is further than
## transition_nose_deg from the pad normal and still moving forward.
static func thrust_law(phase: int, ship: ShipSnapshot, pad: PadSnapshot, prm: LandingParams, g: FlightGains,
		out: PilotInput) -> void:
	var t: Vector3 = thrust_vector(phase, ship, pad, prm)
	var fwd: Vector3 = -ship.b.z
	var a_max: float = ship.a_thrust * Kinematics.thrust_efficiency(ship.v.dot(fwd), ship.v_cruise, ship.eff_fade_start)
	FlightController.track_thrust_vector(ship.b, t, t.length() / maxf(a_max, prm.gravity), ship.p.normalized(), g, out)
	if phase == Phase.TRANSITION and fwd.dot(pad.n) < prm.cos_transition_nose and ship.v.dot(fwd) > 0.0:
		out.buttons |= PilotInput.BRAKE


## The 05 s5.5 position law's thrust acceleration T = a_h + a_v n + g n (m/s^2, world), for L4-L6 `phase`: the
## horizontal part is limited to the phase's tilt and to what the thrust has left after the vertical demand
## (vertical first); below floor_agl_m (pad plane or terrain) and outside the pad radius the vertical command climbs
## back to the floor and the tilt is limited to floor_tilt_deg (AI-09). |T| <= the thrust available along T.
static func thrust_vector(phase: int, ship: ShipSnapshot, pad: PadSnapshot, prm: LandingParams) -> Vector3:
	var n: Vector3 = pad.n
	var rel: Vector3 = pad.p - ship.p
	var hc: float = -rel.dot(n)
	var h: float = hc - ship.bounding_radius
	var e: Vector3 = rel + n * hc
	var ed: float = e.length()
	var vz: float = ship.v.dot(n)
	var w: Vector3 = ship.v - n * vz
	# centred: the offset plus the drift of one 1 / kd_pos time constant, so a ship sliding across the pad does
	# not sink while it still has to stop
	var centred: float = clampf(1.0 - (ed + w.length() / prm.kd_pos) / pad.radius_m, 0.0, 1.0)
	var vz_cmd: float = _sink_cmd(phase, h, centred, prm)
	var tan_lim: float = prm.tan_tilt
	if phase == Phase.TRANSITION:
		tan_lim = prm.tan_transition_tilt
	elif phase == Phase.FLARE:
		tan_lim = prm.tan_flare_tilt
	if phase != Phase.FLARE and ed > pad.radius_m:
		var hf: float = minf(h, ship.p.length() - Sphere.PLANET_RADIUS - ship.ground_h - ship.bounding_radius)
		if hf < prm.floor_agl_m:
			vz_cmd = maxf(vz_cmd, prm.kp_floor * (prm.floor_agl_m - hf))
			tan_lim = minf(tan_lim, prm.tan_floor_tilt)
	# thrust available once the nose is near the pad normal (efficiency at the speed along it), never less than now
	var fwd: Vector3 = -ship.b.z
	var a_cap: float = ship.a_thrust * maxf(Kinematics.thrust_efficiency(maxf(vz, 0.0), ship.v_cruise,
		ship.eff_fade_start), Kinematics.thrust_efficiency(ship.v.dot(fwd), ship.v_cruise, ship.eff_fade_start))
	var a_v: float = clampf(prm.kp_vz * (vz_cmd - vz) + prm.gravity, 0.0, a_cap)
	var w_cmd: Vector3 = (e * (prm.kp_pos / prm.kd_pos)).limit_length(prm.transition_speed_cap)
	var h_lim: float = minf(a_v * tan_lim, sqrt(maxf(a_cap * a_cap - a_v * a_v, 0.0)))
	return ((w_cmd - w) * prm.kd_pos).limit_length(h_lim) + n * a_v


# 05 s5.5 vertical speed command along the pad normal: L4 holds height, L5 sinks with height (scaled by how well
# the ship is centred; off-centre below the flare height it climbs back), L6 touches down at touch_vz.
static func _sink_cmd(phase: int, h: float, centred: float, prm: LandingParams) -> float:
	if phase == Phase.TRANSITION:
		return 0.0
	if phase == Phase.FLARE:
		return -prm.touch_vz * centred
	if centred <= 0.5 and h < prm.flare_agl_m:
		return minf(prm.sink_gain * (prm.flare_agl_m - h), prm.sink_min)
	return -clampf(prm.sink_gain * h, prm.sink_min, prm.sink_max) * centred


## Approach bearing (05 s5.5 L2): of `prm.bearing_count` candidates in equal steps from the pad's north, the one
## with the best score = alignment of the approach course with the ship's track (cos) - bearing_terrain_weight x
## the worst shortfall of the glide path below terrain + bearing_clear_m along the line (bearing_samples samples
## from transition_dist_m to gate_dist_m) - `threat[k]` (caller's per-candidate threat penalty; empty = none).
## Ties keep the lowest index. Returns the unit tangent at the pad pointing to the approach side.
static func choose_bearing(terrain: Terrain, pad: PadSnapshot, ship: ShipSnapshot, threat: PackedFloat32Array,
		prm: LandingParams) -> Vector3:
	var np: Vector3 = pad.p.normalized()
	var r_pad: float = pad.p.length()
	var f: Basis = Sphere.tangent_frame(np)
	var n: Vector3 = ship.p.normalized()
	var track: Vector3 = ship.v - n * ship.v.dot(n)
	if track.length_squared() < 1.0:
		track = pad.p - ship.p
	track = (track - np * track.dot(np)).normalized()
	var best: Vector3 = f.y
	var best_score: float = -INF
	var span: float = prm.gate_dist_m - prm.transition_dist_m
	for k: int in prm.bearing_count:
		var ang: float = TAU * float(k) / float(prm.bearing_count)
		var b: Vector3 = f.y * cos(ang) + f.x * sin(ang)
		var short: float = 0.0
		for j: int in prm.bearing_samples:
			var d: float = prm.transition_dist_m + span * float(j + 1) / float(prm.bearing_samples)
			var ground: float = Sphere.PLANET_RADIUS + terrain.height_at(_along(np, b, d / r_pad))
			short = maxf(short, ground + prm.bearing_clear_m - (r_pad + d * prm.tan_glide))
		var score: float = -b.dot(track) - prm.bearing_terrain_weight * short
		if k < threat.size():
			score -= threat[k]
		if score > best_score:
			best_score = score
			best = b
	return best
