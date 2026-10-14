extends GdUnitTestSuite
## Unit tests for sim/steer/aim_solver.gd (AI-12; 05 s6.2, s6.8; R0 C1-03): straight-line intercepts against analytic
## solutions and against slugs stepped by `Kinematics.step_projectile`, the flak fuse, the fire cone and purity.

const R: float = Sphere.PLANET_RADIUS
const TOL: float = 0.05

var _rules: RulesDef
var _slug: ProjectileDef
var _flak: ProjectileDef
var _dt: float


func before_test() -> void:
	_rules = FlightTestKit.rules()
	_slug = FlightTestKit.projectile(&"slug_light")
	_flak = FlightTestKit.projectile(&"flak_shell")
	_dt = FlightTestKit.dt(_rules)


# Steps the projectile `def` with the sim's integrator for `t` seconds (whole ticks plus a fractional last one).
func _fly(def: ProjectileDef, p: Vector3, v: Vector3, t: float) -> Vector3:
	var q: Vector3 = p
	var w: Vector3 = v
	var left: float = t
	while left > 0.0:
		var h: float = minf(_dt, left)
		var st: ProjectileState = Kinematics.step_projectile(q, w, def, _rules, h)
		q = st.p
		w = st.v
		left -= h
	return q


func test_coaltitude_slug_hits_at_200_400_650_800() -> void:
	# 03 test_slug_hits_coaltitude_target mirrored for the autopilot: shooter 300 m AGL, stationary co-altitude target.
	var r_alt: float = R + 300.0
	var shooter: Vector3 = Vector3(r_alt, 0, 0)
	for d: float in [200.0, 400.0, 650.0, 800.0]:
		var ang: float = 2.0 * asin(d / (2.0 * r_alt))
		var target: Vector3 = Vector3(cos(ang), sin(ang), 0) * r_alt
		var dir: Vector3 = AimSolver.aim_dir(shooter, Vector3.ZERO, target, Vector3.ZERO, _slug.speed_mps)
		var t: float = AimSolver.intercept_time(target - shooter, Vector3.ZERO, _slug.speed_mps)
		assert_float(t).is_equal_approx(d / _slug.speed_mps, 0.0001)
		var at: Vector3 = _fly(_slug, shooter, dir * _slug.speed_mps, t)
		assert_float(at.distance_to(target)).is_less(TOL)


func test_moving_shooter_and_target_hit_the_lead_point() -> void:
	# Straight-line world-frame target; the slug inherits the shooter velocity (R0 C1-03).
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 12
	for i: int in 200:
		var ps: Vector3 = Vector3(R + 400.0, 0, 0)
		var vs: Vector3 = Vector3(rng.randf_range(-20, 20), rng.randf_range(-250, 250), rng.randf_range(-250, 250))
		var pt: Vector3 = ps + Vector3(rng.randf_range(-100, 100), rng.randf_range(-600, 600), rng.randf_range(-600, 600))
		var vt: Vector3 = Vector3(rng.randf_range(-20, 20), rng.randf_range(-250, 250), rng.randf_range(-250, 250))
		var t: float = AimSolver.intercept_time(pt - ps, vt - vs, _slug.speed_mps)
		assert_bool(is_inf(t)).is_false()
		var dir: Vector3 = AimSolver.aim_dir(ps, vs, pt, vt, _slug.speed_mps)
		var shell: Vector3 = _fly(_slug, ps, vs + dir * _slug.speed_mps, t)
		assert_float(shell.distance_to(pt + vt * t)).is_less(TOL)
		assert_vector(AimSolver.lead_point(ps, vs, pt, vt, _slug.speed_mps)).is_equal_approx(pt + (vt - vs) * t, Vector3.ONE * TOL)


func test_matches_closed_form_head_on() -> void:
	# Head-on, closing speed 300 + 700 = 1000 over 1000 m: t = 1.0 s exactly.
	var t: float = AimSolver.intercept_time(Vector3(1000, 0, 0), Vector3(-300, 0, 0), 700.0)
	assert_float(t).is_equal_approx(1.0, 0.00001)


func test_agrees_with_hud_lead_solver() -> void:
	# UX-17's pip iterates the same equation; its converged flight time must match the closed form.
	var ps: Vector3 = Vector3(R + 300.0, 0, 0)
	var vs: Vector3 = Vector3(0, 120, 0)
	var pt: Vector3 = ps + Vector3(0, 500, 200)
	var vt: Vector3 = Vector3(0, 90, -40)
	var exact: float = AimSolver.intercept_time(pt - ps, vt - vs, 700.0)
	assert_float(LeadSolver.lead_time(ps, vs, pt, vt, 700.0)).is_equal_approx(exact, exact * 0.01)


func test_no_solution_when_target_outruns_projectile() -> void:
	assert_bool(is_inf(AimSolver.intercept_time(Vector3(500, 0, 0), Vector3(900, 0, 0), 700.0))).is_true()
	assert_vector(AimSolver.aim_dir(Vector3.ZERO, Vector3.ZERO, Vector3(500, 0, 0), Vector3(900, 0, 0), 700.0)).is_equal(Vector3.ZERO)
	assert_vector(AimSolver.lead_point(Vector3.ZERO, Vector3.ZERO, Vector3(500, 0, 0), Vector3(900, 0, 0), 700.0)) \
		.is_equal(Vector3(500, 0, 0))
	assert_bool(is_inf(AimSolver.intercept_time(Vector3(1, 0, 0), Vector3.ZERO, 0.0))).is_true()


func test_equal_speed_pursuit_has_a_linear_solution() -> void:
	# |u| = speed: the quadratic degenerates; closing target at u.x = -700 along r.x = 700 -> 0.5 s.
	var t: float = AimSolver.intercept_time(Vector3(700, 0, 0), Vector3(-700, 0, 0), 700.0)
	assert_float(t).is_equal_approx(0.5, 0.0001)


func test_flak_lead_and_fuse() -> void:
	# Flak shell 300 m/s straight, no gravity (B.5): aimed shell meets a crossing target at the fuse time minus the delay.
	var speed: float = _flak.speed_mps
	var ps: Vector3 = Vector3(R + 500.0, 0, 0)
	var pt: Vector3 = ps + Vector3(100, 600, 0)
	var vt: Vector3 = Vector3(0, 0, 150)
	var t: float = AimSolver.intercept_time(pt - ps, vt, speed)
	var dir: Vector3 = AimSolver.aim_dir(ps, Vector3.ZERO, pt, vt, speed)
	assert_float(_fly(_flak, ps, dir * speed, t).distance_to(pt + vt * t)).is_less(TOL)
	var fuse: float = AimSolver.fuse_time(pt - ps, vt, speed, 0.3, _flak.arm_s, _flak.lifetime_s)
	assert_float(fuse).is_equal_approx(t + 0.3, 0.0001)
	# No solution: the shell bursts at the end of its life.
	assert_float(AimSolver.fuse_time(Vector3(900, 0, 0), Vector3(2000, 0, 0), speed, 0.3, _flak.arm_s, _flak.lifetime_s)) \
		.is_equal(_flak.lifetime_s)
	# A target inside the arming time bursts no earlier than arm_s.
	assert_float(AimSolver.fuse_time(Vector3(10, 0, 0), Vector3.ZERO, speed, 0.0, _flak.arm_s, _flak.lifetime_s)) \
		.is_greater_equal(_flak.arm_s)


func test_fire_cone() -> void:
	var aim: Vector3 = Vector3(1, 0, 0)
	var cone: float = atan(2.0 * 6.0 / 400.0)
	assert_bool(AimSolver.in_fire_cone(aim.rotated(Vector3.UP, cone * 0.9), aim, 2.0, 6.0, 400.0)).is_true()
	assert_bool(AimSolver.in_fire_cone(aim.rotated(Vector3.UP, cone * 1.1), aim, 2.0, 6.0, 400.0)).is_false()
	assert_bool(AimSolver.in_fire_cone(aim, Vector3.ZERO, 2.0, 6.0, 400.0)).is_false()


func test_pure_and_deterministic() -> void:
	var a: float = AimSolver.intercept_time(Vector3(300, 40, -9), Vector3(-50, 12, 3), 700.0)
	for i: int in 50:
		assert_float(AimSolver.intercept_time(Vector3(300, 40, -9), Vector3(-50, 12, 3), 700.0)).is_equal(a)
	for path: String in ["res://src/sim/steer/aim_solver.gd", "res://src/sim/steer/ballistics.gd"]:
		var src: String = FileAccess.get_file_as_string(path)
		assert_bool(src.contains("\nvar ")).is_false()
		assert_bool(src.contains("static var")).is_false()
		for line: String in src.split("\n"):
			if line.begins_with("func "):
				fail("non-static func in %s: %s" % [path, line])
			if line.contains("Rng") or line.contains("Time.") or line.contains("randf"):
				fail("clock or RNG in %s: %s" % [path, line])
