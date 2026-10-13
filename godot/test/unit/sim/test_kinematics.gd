extends GdUnitTestSuite
## Unit tests for sim/kinematics.gd (TA-12; 03 s5.3-5.4, R0 B.5, C1-03, C1-04).
## Def values: canonical fixture via FlightTestKit (R0 B.1 Dart / Bomber, rules.json, projectiles.json).

const DEG_TOL: float = 0.0001

var _dart: ShipDef
var _bomber: ShipDef
var _common: FlightCommonDef
var _rules: RulesDef
var _flat: Terrain
var _dt: float
var _idle: PilotInput


class RaisedTerrain extends Terrain:
	var h: float = 0.0

	func height_at(_dir: Vector3) -> float:
		return h


func before_test() -> void:
	_dart = FlightTestKit.ship(&"dart")
	_bomber = FlightTestKit.ship(&"bomber")
	_common = FlightTestKit.common()
	_rules = FlightTestKit.rules()
	_flat = Terrain.new()
	_dt = FlightTestKit.dt(_rules)
	_idle = FlightTestKit.input(0.0, 0.0, 0.0, 0.0, 0)


func _step(s: ShipState, inp: PilotInput, def: ShipDef, rules: RulesDef, terrain: Terrain) -> void:
	var _r: ShipState = Kinematics.step_ship(s, inp, def, _common, rules, terrain, _dt)


# --- efficiency curves and the lift law ---------------------------------------------------------------

func test_thrust_efficiency_knee_and_fade() -> void:
	var cruise: float = _dart.v_cruise
	var fade: float = _common.eff_fade_start
	assert_float(Kinematics.thrust_efficiency(0.0, cruise, fade)).is_equal(1.0)
	assert_float(Kinematics.thrust_efficiency(fade * cruise, cruise, fade)).is_equal(1.0)
	var mid: float = (fade * cruise + cruise) * 0.5
	assert_float(Kinematics.thrust_efficiency(mid, cruise, fade)).is_equal_approx(0.5, DEG_TOL)
	assert_float(Kinematics.thrust_efficiency(cruise, cruise, fade)).is_equal(0.0)
	assert_float(Kinematics.thrust_efficiency(cruise * 2.0, cruise, fade)).is_equal(0.0)
	assert_float(Kinematics.thrust_efficiency(-cruise, cruise, fade)).is_equal(1.0)


func test_ceiling_efficiency_soft_to_hard() -> void:
	var soft: float = _rules.ceiling_soft_m
	var hard: float = _rules.ceiling_hard_m
	assert_float(Kinematics.ceiling_efficiency(0.0, _rules)).is_equal(1.0)
	assert_float(Kinematics.ceiling_efficiency(soft, _rules)).is_equal(1.0)
	assert_float(Kinematics.ceiling_efficiency((soft + hard) * 0.5, _rules)).is_equal_approx(0.5, DEG_TOL)
	assert_float(Kinematics.ceiling_efficiency(hard, _rules)).is_equal(0.0)
	assert_float(Kinematics.ceiling_efficiency(hard + 100.0, _rules)).is_equal(0.0)


func test_k_up_effective_speed_scaled_at_reference_speeds() -> void:
	var d: ShipDef = _dart
	var span: float = d.k_up_flight - d.k_up
	assert_float(Kinematics.k_up_effective(0.0, d, _rules)).is_equal_approx(d.k_up, DEG_TOL)
	assert_float(Kinematics.k_up_effective(-d.v_cruise, d, _rules)).is_equal_approx(d.k_up, DEG_TOL)
	assert_float(Kinematics.k_up_effective(0.5 * d.v_cruise, d, _rules)).is_equal_approx(d.k_up + span * 0.25, DEG_TOL)
	# 03 s5.3 lift law check: Dart at 0.9 x v_cruise -> 0.10 + 0.90 x 0.81 = 0.829 /s
	assert_float(Kinematics.k_up_effective(0.9 * d.v_cruise, d, _rules)).is_equal_approx(d.k_up + span * 0.81, DEG_TOL)
	assert_float(Kinematics.k_up_effective(d.v_cruise, d, _rules)).is_equal_approx(d.k_up_flight, DEG_TOL)
	assert_float(Kinematics.k_up_effective(d.v_boost, d, _rules)).is_equal_approx(d.k_up_flight, DEG_TOL)


func test_k_up_effective_damping_only_is_glide_value() -> void:
	var r: RulesDef = FlightTestKit.rules(RulesDef.LIFT_DAMPING_ONLY)
	for frac: float in [0.0, 0.5, 0.9, 1.0, 1.5]:
		assert_float(Kinematics.k_up_effective(frac * _dart.v_cruise, _dart, r)).is_equal(_dart.k_up)


func test_lift_model_switch_changes_lift_at_cruise_aoa() -> void:
	# Same state, nose 4.5 degrees above a 0.9 x v_cruise velocity, engines cut: speed_scaled is near level,
	# damping_only sinks at almost g (the C1-04 problem the switch A/Bs).
	var v: float = 0.9 * _dart.v_cruise
	var aoa: float = deg_to_rad(4.5)
	var a: ShipState = FlightTestKit.level(_dart, 300.0, v, aoa)
	var b: ShipState = FlightTestKit.level(_dart, 300.0, v, aoa)
	_step(a, _idle, _dart, _rules, _flat)
	_step(b, _idle, _dart, FlightTestKit.rules(RulesDef.LIFT_DAMPING_ONLY), _flat)
	var g: float = _rules.gravity
	var az_scaled: float = a.v.dot(a.p.normalized()) / _dt
	var az_damping: float = b.v.dot(b.p.normalized()) / _dt
	assert_float(absf(az_scaled)).is_less_equal(0.15 * g)
	assert_float(az_damping).is_less_equal(-0.6 * g)


func test_level_flight_at_0_9_cruise_holds_altitude_with_small_aoa() -> void:
	# 03 s5.3 lift law check / TA-12: test PD autopilot, 0.9 x v_cruise, 60 s: altitude +-1 m, AoA <= 6 deg.
	var v: float = 0.9 * _dart.v_cruise
	var trim: float = _rules.gravity / (v * Kinematics.k_up_effective(v, _dart, _rules))
	var s: ShipState = FlightTestKit.level(_dart, 300.0, v, trim)
	var inp: PilotInput = PilotInput.new()
	var aoa_sum: float = 0.0
	var aoa_max: float = 0.0
	var h_err: float = 0.0
	var n_ticks: int = 60 * _rules.tick_hz
	for i: int in n_ticks:
		var _i: PilotInput = FlightTestKit.level_hold(s, _dart, _rules, 300.0, v, inp)
		_step(s, inp, _dart, _rules, _flat)
		var aoa: float = rad_to_deg(FlightTestKit.aoa(s))
		aoa_sum += aoa
		aoa_max = maxf(aoa_max, absf(aoa))
		h_err = maxf(h_err, absf(FlightTestKit.altitude(s) - 300.0))
	var aoa_mean: float = aoa_sum / n_ticks
	print("TA-12 level flight 0.9 v_cruise speed_scaled: steady AoA %.2f deg (max %.2f), max |dh| %.3f m" % [
		aoa_mean, aoa_max, h_err])
	assert_float(h_err).is_less_equal(1.0)
	assert_float(aoa_max).is_less_equal(6.0)
	assert_float(aoa_mean).is_greater(0.0)


# --- free fall, energy, envelope ---------------------------------------------------------------------

func test_free_fall_from_100m_lands_in_5_8_to_6_2_s() -> void:
	var s: ShipState = FlightTestKit.level(_dart, 100.0, 0.0, 0.0)
	var ticks: int = 0
	while not s.terrain_hit and ticks < 1000:
		_step(s, _idle, _dart, _rules, _flat)
		ticks += 1
	assert_bool(s.terrain_hit).is_true()
	assert_float(ticks * _dt).is_between(5.8, 6.2)
	# engines cut at 100 m is a crash: faster than the terrain kill speed
	assert_float(s.hit_normal_speed).is_greater(_common.terrain_kill_speed)


func test_free_fall_sink_follows_terminal_g_over_k_up() -> void:
	# k_up_eff = k_up at zero forward speed: v_sink(t) = g / k_up * (1 - exp(-k_up t)) (01 s3.1.1 numbers).
	var s: ShipState = FlightTestKit.level(_dart, 1900.0, 0.0, 0.0)
	var n_ticks: int = 20 * _rules.tick_hz
	for i: int in n_ticks:
		_step(s, _idle, _dart, _rules, _flat)
	var t: float = n_ticks * _dt
	var expect: float = _rules.gravity / _dart.k_up * (1.0 - exp(-_dart.k_up * t))
	var sink: float = -s.v.dot(s.p.normalized())
	assert_float(sink).is_equal_approx(expect, expect * 0.01)


func test_unpowered_flight_never_gains_energy() -> void:
	# Damping only removes energy: specific energy 0.5 v^2 + g r never rises by more than integration noise.
	var s: ShipState = FlightTestKit.level(_dart, 800.0, _dart.v_cruise, deg_to_rad(20.0))
	var inp: PilotInput = FlightTestKit.input(0.0, 0.4, 0.2, 0.3, 0)
	var e0: float = _energy(s)
	var e_prev: float = e0
	for i: int in 300:
		_step(s, inp, _dart, _rules, _flat)
		var e: float = _energy(s)
		assert_float(e - e_prev).is_less_equal(0.05)
		e_prev = e
	assert_float(e_prev).is_less(e0)


func _energy(s: ShipState) -> float:
	return 0.5 * s.v.length_squared() + _rules.gravity * s.p.length()


func test_dive_clamp_reports_excess_and_caps_speed() -> void:
	var s: ShipState = FlightTestKit.level(_dart, 800.0, _dart.v_dive_max + 30.0, 0.0)
	_step(s, _idle, _dart, _rules, _flat)
	assert_float(s.over_dive_excess).is_greater(29.0)
	assert_float(s.v.length()).is_equal_approx(_dart.v_dive_max, 0.001)
	_step(s, _idle, _dart, _rules, _flat)
	assert_float(s.over_dive_excess).is_less(1.0)


func test_ceiling_forced_at_hard_ceiling_and_thrust_fades() -> void:
	var s: ShipState = FlightTestKit.level(_dart, _rules.ceiling_hard_m + 1.0, 0.0, 0.0)
	var full: PilotInput = FlightTestKit.input(1.0, 0.0, 0.0, 0.0, 0)
	_step(s, full, _dart, _rules, _flat)
	assert_bool(s.ceiling_forced).is_true()
	assert_float(s.v.dot(s.fwd)).is_equal_approx(0.0, 0.0001)    # no thrust above the hard ceiling
	var low: ShipState = FlightTestKit.level(_dart, 300.0, 0.0, 0.0)
	_step(low, full, _dart, _rules, _flat)
	assert_bool(low.ceiling_forced).is_false()
	assert_float(low.v.dot(low.fwd)).is_equal_approx(_dart.a_thrust * _dt, 0.0001)


func test_fuel_burns_with_thrust_and_cuts_engine_when_empty() -> void:
	var s: ShipState = FlightTestKit.level(_dart, 300.0, 0.0, 0.0)
	s.fuel = 2.5 * _dt
	var full: PilotInput = FlightTestKit.input(1.0, 0.0, 0.0, 0.0, 0)
	for i: int in 3:
		_step(s, full, _dart, _rules, _flat)
	assert_float(s.fuel).is_equal(0.0)
	var v_fwd: float = s.v.dot(s.fwd)
	_step(s, full, _dart, _rules, _flat)
	assert_float(s.v.dot(s.fwd)).is_equal_approx(v_fwd, 0.0001)


func test_brake_slows_but_never_reverses() -> void:
	var brake: PilotInput = FlightTestKit.input(0.0, 0.0, 0.0, 0.0, PilotInput.BRAKE)
	var s: ShipState = FlightTestKit.level(_dart, 300.0, 50.0, 0.0)
	_step(s, brake, _dart, _rules, _flat)
	var dv: float = 50.0 - s.v.dot(s.fwd)
	assert_float(dv).is_equal_approx(_common.brake_factor * _dart.a_thrust * _dt, 0.001)
	var still: ShipState = FlightTestKit.level(_dart, 300.0, 0.0, 0.0)
	_step(still, brake, _dart, _rules, _flat)
	assert_float(still.v.dot(still.fwd)).is_equal_approx(0.0, 0.0001)


func test_brake_ramp_reads_flight_common_brake_fade_mps() -> void:
	# 03 s5.3 / R0 B.9 A-13: brake decel = brake_factor * a_thrust * clamp(v_fwd / brake_fade_mps, 0, 1).
	var brake: PilotInput = FlightTestKit.input(0.0, 0.0, 0.0, 0.0, PilotInput.BRAKE)
	var full: float = _common.brake_factor * _dart.a_thrust * _dt
	var v0: float = _common.brake_fade_mps * 0.5
	var s: ShipState = FlightTestKit.level(_dart, 300.0, v0, 0.0)
	_step(s, brake, _dart, _rules, _flat)
	assert_float(v0 - s.v.dot(s.fwd)).is_equal_approx(full * 0.5, 0.001)
	_common.brake_fade_mps *= 2.0                                     # the def field, not a constant, sets the ramp
	var s2: ShipState = FlightTestKit.level(_dart, 300.0, v0, 0.0)
	_step(s2, brake, _dart, _rules, _flat)
	assert_float(v0 - s2.v.dot(s2.fwd)).is_equal_approx(full * 0.25, 0.001)


func test_boost_lasts_duration_then_cools_down() -> void:
	var boost: PilotInput = FlightTestKit.input(1.0, 0.0, 0.0, 0.0, PilotInput.BOOST)
	var s: ShipState = FlightTestKit.level(_dart, 300.0, 0.0, 0.0)
	_step(s, boost, _dart, _rules, _flat)
	assert_float(s.boost_time).is_equal(_dart.boost_duration_s)
	_step(s, boost, _dart, _rules, _flat)       # boosting: thrust x boost_thrust_mult
	assert_float(s.v.dot(s.fwd) - _dart.a_thrust * _dt).is_equal_approx(
		_dart.a_thrust * _common.boost_thrust_mult * _dt, 0.001)
	# Holding BOOST re-triggers only once duration + cooldown have elapsed since the first trigger.
	var ticks: int = 1
	while s.boost_time != _dart.boost_duration_s and ticks < 2000:
		_step(s, boost, _dart, _rules, _flat)
		ticks += 1
	var cycle: int = roundi((_dart.boost_duration_s + _dart.boost_cooldown_s) / _dt)
	assert_int(ticks).is_between(cycle, cycle + 1)


# --- attitude ------------------------------------------------------------------------------------------

func test_rates_accelerate_at_rate_accel_and_cap_at_stick_rate() -> void:
	var s: ShipState = FlightTestKit.level(_dart, 300.0, 0.0, 0.0)
	var stick: PilotInput = FlightTestKit.input(0.0, 1.0, -1.0, 0.5, 0)
	_step(s, stick, _dart, _rules, _flat)
	var step: float = deg_to_rad(_dart.rate_accel_dps2) * _dt
	assert_vector(s.rates).is_equal_approx(Vector3(step, -step, step), Vector3.ONE * DEG_TOL)
	for i: int in 30:
		_step(s, stick, _dart, _rules, _flat)
	var want: Vector3 = Vector3(deg_to_rad(_dart.pitch_rate_dps), -deg_to_rad(_dart.yaw_rate_dps),
		0.5 * deg_to_rad(_dart.roll_rate_dps))
	assert_vector(s.rates).is_equal_approx(want, Vector3.ONE * DEG_TOL)
	assert_float(s.fwd.dot(s.up)).is_equal_approx(0.0, 0.00001)
	assert_float(s.up.length()).is_equal_approx(1.0, 0.00001)


func test_axis_sign_conventions() -> void:
	# pitch + nose up, yaw + nose left, roll + right wing down (PilotInput doc).
	var n: Vector3 = Vector3(1, 0, 0)
	for case: Array in [[1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 1.0]]:
		var s: ShipState = FlightTestKit.level(_dart, 300.0, 0.0, 0.0)
		var right0: Vector3 = s.fwd.cross(s.up)
		var inp: PilotInput = FlightTestKit.input(0.0, case[0], case[1], case[2], 0)
		for i: int in 5:
			_step(s, inp, _dart, _rules, _flat)
		if case[0] > 0.0:
			assert_float(s.fwd.dot(n)).is_greater(0.0)
		elif case[1] > 0.0:
			assert_float(s.fwd.dot(right0)).is_less(0.0)
		else:
			assert_float(s.fwd.cross(s.up).dot(n)).is_less(0.0)


func test_flip_reverses_heading_in_flip_duration() -> void:
	for def: ShipDef in [_dart, _bomber]:
		var s: ShipState = FlightTestKit.level(def, 300.0, def.v_cruise, 0.0)
		var flip: PilotInput = FlightTestKit.input(0.0, 0.0, 0.0, 0.0, PilotInput.FLIP)
		var ticks: int = roundi(def.flip_duration_s / _dt)
		_step(s, flip, def, _rules, _flat)
		for i: int in ticks - 1:
			_step(s, _idle, def, _rules, _flat)
		var east: Vector3 = Sphere.tangent_frame(s.p).x
		assert_float(s.fwd.dot(east)).is_less(-0.999)                       # heading reversed
		assert_float(s.up.dot(s.p.normalized())).is_greater(0.999)          # upright
		assert_float(s.flip_time).is_equal(0.0)
		assert_vector(s.rates).is_equal(Vector3.ZERO)
		_step(s, flip, def, _rules, _flat)                                  # cooling: FLIP ignored
		assert_float(s.flip_time).is_less(0.0)


# --- terrain probe and landing-rule inputs --------------------------------------------------------------

func test_terrain_hit_pushes_out_and_reports_normal_speed() -> void:
	var t: RaisedTerrain = RaisedTerrain.new()
	t.h = 50.0
	var s: ShipState = FlightTestKit.level(_dart, 50.0 + _dart.bounding_radius + 0.1, 0.0, 0.0)
	s.v = -s.p.normalized() * 5.0 + Vector3(0, 3, 0)
	_step(s, _idle, _dart, _rules, t)
	assert_bool(s.terrain_hit).is_true()
	var k: float = Kinematics.k_up_effective(3.0, _dart, _rules)          # belly-down: body up is radial
	assert_float(s.hit_normal_speed).is_equal_approx(5.0 + (_rules.gravity - 5.0 * k) * _dt, 0.001)
	assert_float(FlightTestKit.altitude(s)).is_equal_approx(50.0 + _dart.bounding_radius, 0.001)
	assert_float(s.v.dot(s.p.normalized())).is_equal_approx(0.0, 0.0001)   # into-ground component removed
	assert_float(s.v.length()).is_greater(2.9)                              # tangential speed kept
	_step(s, _idle, _dart, _rules, _flat)
	assert_bool(s.terrain_hit).is_false()                                   # reported per step only


func test_tail_down_touchdown_inputs_are_inside_the_landing_envelope() -> void:
	# A Dart settling tail-down at 3 m/s: the probe reports what the landing rule (03 s6.4, R0 B.5) tests.
	var n: Vector3 = Vector3(1, 0, 0)
	var s: ShipState = FlightTestKit.spawn(_dart, n * (Sphere.PLANET_RADIUS + 30.0), n, Vector3(0, 0, 1),
		Vector3.ZERO)
	var inp: PilotInput = PilotInput.new()
	var ticks: int = 0
	while not s.terrain_hit and ticks < 600:
		var _i: PilotInput = FlightTestKit.hover_hold(s, _dart, _rules, s.p.normalized(), 0.0, -3.0, false, inp)
		_step(s, inp, _dart, _rules, _flat)
		ticks += 1
	assert_bool(s.terrain_hit).is_true()
	var up_pad: Vector3 = s.p.normalized()
	var horiz: float = (s.v - up_pad * s.v.dot(up_pad)).length()
	assert_float(s.hit_normal_speed).is_less_equal(_common.landing_safe_v_vert)
	assert_float(horiz).is_less_equal(_common.landing_safe_v_hor)
	assert_float(s.fwd.dot(up_pad)).is_greater_equal(cos(deg_to_rad(_common.landing_safe_pitch_deg)))


# --- projectiles (03 s5.4, C1-03) -------------------------------------------------------------------------

func test_step_projectile_straight_is_world_frame_line() -> void:
	var slug: ProjectileDef = FlightTestKit.projectile(&"slug_light")
	var p: Vector3 = Vector3(Sphere.PLANET_RADIUS + 300.0, 0, 0)
	var v: Vector3 = Vector3(0, slug.speed_mps, 0)
	var ps: ProjectileState = Kinematics.step_projectile(p, v, slug, _rules, _dt)
	assert_vector(ps.p).is_equal(p + v * _dt)
	assert_vector(ps.v).is_equal(v)


func test_slug_hits_coaltitude_target() -> void:
	# Shooter 300 m AGL, co-altitude target at 200/400/650/800 m range, fired along the line of
	# sight: every slug passes within the hit radius (C1-03; a transported slug would miss low by d^2 / 2R).
	var slug: ProjectileDef = FlightTestKit.projectile(&"slug_light")
	var r_alt: float = Sphere.PLANET_RADIUS + 300.0
	var shooter: Vector3 = Vector3(r_alt, 0, 0)
	for d: float in [200.0, 400.0, 650.0, 800.0]:
		var ang: float = 2.0 * asin(d / (2.0 * r_alt))                     # d = straight-line range
		var target: Vector3 = Vector3(cos(ang), sin(ang), 0) * r_alt
		var v: Vector3 = (target - shooter).normalized() * slug.speed_mps
		var best: float = _closest_approach(slug, shooter, v, target)
		assert_float(best).is_less(slug.radius_m + _dart.bounding_radius)
		assert_float(best).is_less(0.01)
	# Control: the same shot with parallel transport switched on misses the 800 m target by tens of metres.
	var transported: ProjectileDef = FlightTestKit.projectile(&"slug_light")
	transported.transport = true
	var ang8: float = 2.0 * asin(800.0 / (2.0 * r_alt))
	var target8: Vector3 = Vector3(cos(ang8), sin(ang8), 0) * r_alt
	var v8: Vector3 = (target8 - shooter).normalized() * slug.speed_mps
	assert_float(_closest_approach(transported, shooter, v8, target8)).is_greater(20.0)


func _closest_approach(def: ProjectileDef, p0: Vector3, v0: Vector3, target: Vector3) -> float:
	var p: Vector3 = p0
	var v: Vector3 = v0
	var best: float = INF
	for i: int in ceili(def.lifetime_s / _dt):
		var ps: ProjectileState = Kinematics.step_projectile(p, v, def, _rules, _dt)
		best = minf(best, Geometry3D.get_closest_point_to_segment(target, p, ps.p).distance_to(target))
		p = ps.p
		v = ps.v
	return best


func test_bomb_falls_under_gravity_and_is_transported() -> void:
	var bomb: ProjectileDef = FlightTestKit.projectile(&"bomb")
	var p: Vector3 = Vector3(Sphere.PLANET_RADIUS + 300.0, 0, 0)
	var v: Vector3 = Vector3(0, 100.0, 0)
	var n_ticks: int = _rules.tick_hz
	for i: int in n_ticks:
		var ps: ProjectileState = Kinematics.step_projectile(p, v, bomb, _rules, _dt)
		p = ps.p
		v = ps.v
	var t: float = n_ticks * _dt
	var n: Vector3 = p.normalized()
	assert_float(v.dot(n)).is_equal_approx(-_rules.gravity * t, 0.05)
	assert_float((v - n * v.dot(n)).length()).is_equal_approx(100.0, 0.05)   # tangential speed kept
	var drop: float = 300.0 - (p.length() - Sphere.PLANET_RADIUS)
	assert_float(drop).is_equal_approx(0.5 * _rules.gravity * t * t, 0.2)


func test_rocket_is_transported_at_constant_speed() -> void:
	var rocket: ProjectileDef = FlightTestKit.projectile(&"rocket")
	var p: Vector3 = Vector3(Sphere.PLANET_RADIUS + 300.0, 0, 0)
	var v: Vector3 = Vector3(0, rocket.speed_mps, 0)
	for i: int in ceili(rocket.lifetime_s / _dt):
		var ps: ProjectileState = Kinematics.step_projectile(p, v, rocket, _rules, _dt)
		p = ps.p
		v = ps.v
	assert_float(v.length()).is_equal_approx(rocket.speed_mps, 0.001)
	assert_float(v.dot(p.normalized())).is_equal_approx(0.0, 0.01)
