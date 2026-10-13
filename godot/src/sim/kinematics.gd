class_name Kinematics
## CF kinematics (03 s5.2-5.4, R0 B.5). All static and pure: no Node, autoload, RNG, Time or static var (S8).
## `step_ship` mutates and returns the `ShipState` scratch it is given; the same call runs on the server and in
## client prediction (ADR-07). Every constant comes from content's `*Def`s; `dt` is the caller's tick (1 / rules.tick_hz).


## One tick of one ship, in the normative order of 03 s5.3. Returns `s`.
static func step_ship(s: ShipState, input: PilotInput, def: ShipDef, common: FlightCommonDef,
		rules: RulesDef, terrain: Terrain, dt: float) -> ShipState:
	var alt0: float = s.p.length() - Sphere.PLANET_RADIUS
	s.terrain_hit = false
	s.hit_normal_speed = 0.0
	_step_attitude(s, input, def, common, dt)
	var a: Vector3 = _acceleration(s, input, def, common, rules, alt0, dt)
	_integrate(s, a, def, dt)
	_probe_terrain(s, def, terrain)
	s.ceiling_forced = alt0 >= rules.ceiling_hard_m
	s.boost_time = maxf(s.boost_time - dt, -def.boost_cooldown_s)
	if (input.buttons & PilotInput.BOOST) != 0 and s.boost_time <= -def.boost_cooldown_s and s.fuel > 0.0:
		s.boost_time = def.boost_duration_s
	return s


## One tick of one projectile (03 s5.4, R0 B.5). Straight kinds (`gravity` and `transport` false) move
## `p += v * dt` in the world frame; ballistic kinds fall under `-g n` and are transported; guided kinds are
## transported at constant speed (their re-aim is ProjectileMotion's).
## `out` (R0 B.9 A-12): when given, it is filled and returned, so a caller holding one reused scratch (ProjectileMotion,
## 2,000 projectiles per tick) allocates nothing; when null a new ProjectileState is returned. `p` / `v` are values,
## so `out.p` / `out.v` may be passed back in.
static func step_projectile(p: Vector3, v: Vector3, def: ProjectileDef, rules: RulesDef,
		dt: float, out: ProjectileState = null) -> ProjectileState:
	var r: ProjectileState = out if out != null else ProjectileState.new()
	if not def.gravity and not def.transport:
		r.p = p + v * dt
		r.v = v
		return r
	var n0: Vector3 = p.normalized()
	var vel: Vector3 = v
	if def.gravity:
		vel -= n0 * (rules.gravity * dt)
	var p_new: Vector3 = p + vel * dt
	if def.transport:
		vel = Sphere.transport(n0, p_new.normalized()) * vel
	r.p = p_new
	r.v = vel
	return r


## 1.0 up to `fade_start * cruise`, then linear to 0.0 at `cruise` (03 s5.3).
static func thrust_efficiency(v_fwd: float, cruise: float, fade_start: float) -> float:
	var knee: float = fade_start * cruise
	if v_fwd <= knee:
		return 1.0
	var span: float = cruise - knee
	if span <= 0.0:
		return 0.0
	return clampf((cruise - v_fwd) / span, 0.0, 1.0)


## 1.0 below `ceiling_soft_m`, linear to 0.0 at `ceiling_hard_m`, 0.0 above (01 s3.1.5).
static func ceiling_efficiency(altitude: float, rules: RulesDef) -> float:
	if altitude <= rules.ceiling_soft_m:
		return 1.0
	if altitude >= rules.ceiling_hard_m:
		return 0.0
	return (rules.ceiling_hard_m - altitude) / (rules.ceiling_hard_m - rules.ceiling_soft_m)


## Body-up damping (R0 C1-04a): `speed_scaled` = k_up + (k_up_flight - k_up) * clamp(v_fwd / v_cruise, 0, 1)^2;
## `damping_only` = k_up.
static func k_up_effective(v_fwd: float, def: ShipDef, rules: RulesDef) -> float:
	if rules.lift_model != RulesDef.LIFT_SPEED_SCALED:
		return def.k_up
	var x: float = clampf(v_fwd / def.v_cruise, 0.0, 1.0)
	return def.k_up + (def.k_up_flight - def.k_up) * x * x


# 03 s5.3 steps 1-2: flip trigger, rates, body rotation, re-orthonormalisation, flip timer.
static func _step_attitude(s: ShipState, input: PilotInput, def: ShipDef, common: FlightCommonDef, dt: float) -> void:
	if (input.buttons & PilotInput.FLIP) != 0 and s.flip_time <= -def.flip_cooldown_s:
		s.flip_time = def.flip_duration_s
		s.rates = Vector3(0.0, 0.0, -1.0 if input.roll < 0.0 else 1.0)   # roll sign carrier for the flip
	if s.flip_time > 0.0:
		if _flip_tick(s, def.flip_duration_s, common.flip_speed_retain, dt):
			s.flip_time = dt                                              # ends this tick: 0 after the decrement
	else:
		_stick_tick(s, input, def, dt)
	var f: Vector3 = s.fwd.normalized()
	s.fwd = f
	s.up = (s.up - f * s.up.dot(f)).normalized()
	s.flip_time = maxf(s.flip_time - dt, -def.flip_cooldown_s)


# Stick: rates move toward the commanded rates per component at rate_accel_dps2, then rotate in the body frame.
static func _stick_tick(s: ShipState, input: PilotInput, def: ShipDef, dt: float) -> void:
	var step: float = deg_to_rad(def.rate_accel_dps2) * dt
	var r: Vector3 = s.rates
	r.x = move_toward(r.x, clampf(input.pitch, -1.0, 1.0) * deg_to_rad(def.pitch_rate_dps), step)
	r.y = move_toward(r.y, clampf(input.yaw, -1.0, 1.0) * deg_to_rad(def.yaw_rate_dps), step)
	r.z = move_toward(r.z, clampf(input.roll, -1.0, 1.0) * deg_to_rad(def.roll_rate_dps), step)
	s.rates = r
	if r == Vector3.ZERO:
		return
	var fwd: Vector3 = s.fwd
	var up: Vector3 = s.up
	var q: Quaternion = Quaternion(fwd.cross(up), r.x * dt) * Quaternion(up, r.y * dt) * Quaternion(fwd, r.z * dt)
	s.fwd = q * fwd
	s.up = q * up


# Flip (scripted, rates forced): a half roll over the first half of flip_duration_s, then a half loop over the
# second half, so the ship ends upright with heading reversed. Each tick turns exactly its share of each phase
# (a remainder under half a tick is folded into the last tick); rates are zero when the flip ends. Returns true
# on the last tick. See the TA-12 PR for why the phases are sequential. Velocity redirect (R0 B.9 A-29): `v` turns
# with the body every tick and is scaled by `retain` (flight_common.flip_speed_retain) on the last, so the ship
# leaves the flip flying nose-first on the reversed heading.
static func _flip_tick(s: ShipState, duration: float, retain: float, dt: float) -> bool:
	var half: float = duration * 0.5
	var w: float = PI / half
	var t1: float = s.flip_time
	var t0: float = t1 - dt
	var ended: bool = t0 < dt * 0.5
	if ended:
		t0 = 0.0
	var roll_a: float = w * maxf(t1 - maxf(t0, half), 0.0) * signf(s.rates.z)
	var pitch_a: float = w * maxf(minf(t1, half) - t0, 0.0)
	var fwd: Vector3 = s.fwd
	var up: Vector3 = s.up
	var v: Vector3 = s.v
	if roll_a != 0.0:
		var qr: Quaternion = Quaternion(fwd, roll_a)
		up = qr * up
		v = qr * v
	if pitch_a != 0.0:
		var q: Quaternion = Quaternion(fwd.cross(up), pitch_a)
		fwd = q * fwd
		up = q * up
		v = q * v
	s.fwd = fwd
	s.up = up
	s.v = v * retain if ended else v
	s.rates = Vector3.ZERO if ended else Vector3(pitch_a / dt, 0.0, roll_a / dt)
	return ended


# 03 s5.3 step 3: gravity, thrust (fuel, efficiency, boost), brake, fuel burn, body-frame damping with the lift law.
# An empty tank (fuel at step start <= 0) means no thrust, no boost and no brake: the ship glides (02 s2.3).
static func _acceleration(s: ShipState, input: PilotInput, def: ShipDef, common: FlightCommonDef,
		rules: RulesDef, alt: float, dt: float) -> Vector3:
	var fwd: Vector3 = s.fwd
	var up: Vector3 = s.up
	var right: Vector3 = fwd.cross(up)
	var v: Vector3 = s.v
	var v_fwd: float = v.dot(fwd)
	var a: Vector3 = s.p.normalized() * -rules.gravity
	var fuelled: bool = s.fuel > 0.0
	var thr: float = clampf(input.thrust, 0.0, 1.0) if fuelled else 0.0
	var boosting: bool = fuelled and s.boost_time > 0.0
	var braking: bool = fuelled and (input.buttons & PilotInput.BRAKE) != 0
	if thr > 0.0:
		var cruise: float = def.v_boost if boosting else def.v_cruise
		var a_t: float = def.a_thrust * (common.boost_thrust_mult if boosting else 1.0)
		var eff: float = thrust_efficiency(v_fwd, cruise, common.eff_fade_start) * ceiling_efficiency(alt, rules)
		a += fwd * (a_t * thr * eff)
	if braking:
		a -= fwd * (common.brake_factor * def.a_thrust * clampf(v_fwd / common.brake_fade_mps, 0.0, 1.0))
	if fuelled:
		_burn_fuel(s, thr, boosting, braking, common, dt)
	a -= right * (v.dot(right) * def.k_side)
	a -= up * (v.dot(up) * k_up_effective(v_fwd, def, rules))
	return a


# Fuel burn per second (02 s2.3, R0 B.9 A-32): thrust input + fuel_burn_boost_per_s while boosting
# + fuel_burn_brake_per_s while braking + fuel_burn_idle_per_s (attitude jets). The tick that empties the tank
# ends an active boost (its cooldown starts), so a refuelled ship cannot resume a stale boost.
static func _burn_fuel(s: ShipState, thr: float, boosting: bool, braking: bool, common: FlightCommonDef,
		dt: float) -> void:
	var rate: float = thr + common.fuel_burn_idle_per_s
	if boosting:
		rate += common.fuel_burn_boost_per_s
	if braking:
		rate += common.fuel_burn_brake_per_s
	s.fuel = maxf(s.fuel - rate * dt, 0.0)
	if s.fuel <= 0.0:
		s.boost_time = minf(s.boost_time, 0.0)


# 03 s5.3 steps 4-5: semi-implicit Euler, dive clamp, parallel transport of v, fwd, up.
static func _integrate(s: ShipState, a: Vector3, def: ShipDef, dt: float) -> void:
	var v: Vector3 = s.v + a * dt
	var speed: float = v.length()
	s.over_dive_excess = maxf(speed - def.v_dive_max, 0.0)
	if s.over_dive_excess > 0.0:
		v *= def.v_dive_max / speed
	var p_old: Vector3 = s.p
	var p_new: Vector3 = p_old + v * dt
	var q: Quaternion = Sphere.transport(p_old.normalized(), p_new.normalized())
	s.v = q * v
	s.fwd = q * s.fwd
	s.up = q * s.up
	s.p = p_new


# 03 s5.3 step 6: terrain probe. Reports and pushes out; Collision classifies (03 s6.1).
static func _probe_terrain(s: ShipState, def: ShipDef, terrain: Terrain) -> void:
	var n: Vector3 = s.p.normalized()
	var r_min: float = Sphere.PLANET_RADIUS + terrain.height_at(n) + def.bounding_radius
	if s.p.length() >= r_min:
		return
	var gn: Vector3 = terrain.normal_at(n)
	var vn: float = s.v.dot(gn)
	s.terrain_hit = true
	s.hit_normal_speed = -vn
	s.p = n * r_min
	if vn < 0.0:
		s.v -= gn * vn
