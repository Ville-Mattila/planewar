extends GdUnitTestSuite
## Unit tests for ui/hud/bomb_sight.gd and lead_solver.gd (UX-17; docs/06 s6.3, R0 C2-11).

const R: float = Sphere.PLANET_RADIUS
const EJECT: float = 40.0
const SLUG_SPEED: float = 700.0
const SLUG_RANGE: float = 800.0


func _step_fn() -> Callable:
	var d: ProjectileDef = ProjectileDef.new()
	d.gravity = true
	d.transport = true
	var rules: RulesDef = RulesDef.new()
	rules.gravity = 6.0
	return func(p: Vector3, v: Vector3, dt: float) -> PackedVector3Array:
		var s: ProjectileState = Kinematics.step_projectile(p, v, d, rules, dt)
		return PackedVector3Array([s.p, s.v])


func _ground() -> Callable:
	return func(_dir: Vector3) -> float: return R


func _predict(alt: float, spd: float, dt: float = 0.0) -> Vector4:
	var n: Vector3 = Vector3(0, 0, 1)
	return BombSight.predict(n * (R + alt), Vector3(spd, 0, 0), n, EJECT, _step_fn(), _ground(), dt)


func test_impact_matches_fine_reference_within_2m() -> void:
	for alt: float in [100.0, 200.0, 300.0, 400.0, 500.0]:
		for spd: float in [0.0, 120.0, 250.0]:
			var coarse: Vector4 = _predict(alt, spd)
			var ref: Vector4 = _predict(alt, spd, 1.0 / 30.0)
			assert_bool(BombSight.has_impact(coarse)).is_true()
			var dp: float = Vector3(coarse.x, coarse.y, coarse.z).distance_to(Vector3(ref.x, ref.y, ref.z))
			assert_float(dp).is_less(2.0)
			assert_float(absf(coarse.w - ref.w)).is_less(0.1)


func test_time_to_impact_vertical_drop_matches_closed_form() -> void:
	# 200 = 40 t + 3 t^2 with g = 6.
	var t: float = (-40.0 + sqrt(1600.0 + 4.0 * 3.0 * 200.0)) / 6.0
	assert_float(_predict(200.0, 0.0, 1.0 / 30.0).w).is_equal_approx(t, 0.1)


func test_high_altitude_beyond_horizon_hides_sight() -> void:
	assert_bool(BombSight.has_impact(_predict(800.0, 100.0))).is_false()


func test_horizon_edge_altitude() -> void:
	# 8 s drop = 40 * 8 + 3 * 64 = 512 m.
	assert_bool(BombSight.has_impact(_predict(505.0, 0.0))).is_true()
	assert_bool(BombSight.has_impact(_predict(520.0, 0.0))).is_false()


func test_at_or_near_ground_impacts_immediately() -> void:
	var r: Vector4 = _predict(0.0, 50.0)
	assert_bool(BombSight.has_impact(r)).is_true()
	assert_float(r.w).is_equal(0.0)
	assert_float(_predict(2.0, 0.0).w).is_less(0.1)


func test_hit_predicate_uses_radius() -> void:
	var imp: Vector4 = Vector4(0.0, 0.0, R, 3.0)
	var near: PackedVector3Array = PackedVector3Array([Vector3(14.0, 0.0, R)])
	var far: PackedVector3Array = PackedVector3Array([Vector3(16.0, 0.0, R)])
	assert_bool(BombSight.hit_predicted(imp, near)).is_true()
	assert_bool(BombSight.hit_predicted(imp, far)).is_false()
	assert_bool(BombSight.hit_predicted(BombSight.NO_IMPACT, near)).is_false()


func test_lead_matches_analytic_intercept() -> void:
	# Stationary shooter, target crossing at 100 m/s: |p_t + v t| = speed * t has a closed form.
	var p_t: Vector3 = Vector3(300.0, 0.0, 0.0)
	var v_t: Vector3 = Vector3(0.0, 100.0, 0.0)
	var t_exact: float = 300.0 / sqrt(SLUG_SPEED * SLUG_SPEED - 100.0 * 100.0)
	var t: float = LeadSolver.lead_time(Vector3.ZERO, Vector3.ZERO, p_t, v_t, SLUG_SPEED)
	assert_float(t).is_equal_approx(t_exact, 0.002)
	var lp: Vector3 = LeadSolver.lead_point(Vector3.ZERO, Vector3.ZERO, p_t, v_t, SLUG_SPEED)
	assert_float(lp.distance_to(p_t + v_t * t_exact)).is_less(1.0)


func test_lead_stationary_target_is_target() -> void:
	var p_t: Vector3 = Vector3(0.0, 400.0, 0.0)
	var lp: Vector3 = LeadSolver.lead_point(Vector3.ZERO, Vector3.ZERO, p_t, Vector3.ZERO, SLUG_SPEED)
	assert_float(lp.distance_to(p_t)).is_less(0.001)


func test_slug_hits_coaltitude_target() -> void:
	var slug_def: ProjectileDef = ProjectileDef.new()
	var rules: RulesDef = RulesDef.new()
	var p_s: Vector3 = Vector3(0, 0, R + 300.0)
	var v_s: Vector3 = Vector3(150.0, 0.0, 0.0)
	var v_t: Vector3 = Vector3(-60.0, 90.0, 0.0)
	for dist: float in [200.0, 400.0, 650.0, 800.0]:
		var p_t: Vector3 = p_s + Vector3(0.0, dist, 0.0)
		var dir: Vector3 = LeadSolver.aim_dir(p_s, v_s, p_t, v_t, SLUG_SPEED)
		var t: float = LeadSolver.lead_time(p_s, v_s, p_t, v_t, SLUG_SPEED)
		var q: Vector3 = p_s
		var w: Vector3 = v_s + dir * SLUG_SPEED
		var n: int = 60
		for _i in n:
			q = Kinematics.step_projectile(q, w, slug_def, rules, t / float(n)).p
		assert_float(q.distance_to(p_t + v_t * t)).is_less(1.5)


func test_pip_hidden_beyond_range() -> void:
	var s: Vector3 = Vector3.ZERO
	assert_bool(LeadSolver.pip_visible(s, s, Vector3(0, 800.0, 0), s, SLUG_SPEED, SLUG_RANGE)).is_true()
	assert_bool(LeadSolver.pip_visible(s, s, Vector3(0, 820.0, 0), s, SLUG_SPEED, SLUG_RANGE)).is_false()
	assert_bool(LeadSolver.pip_visible(s, s, Vector3(0, 100.0, 0), s, 0.0, SLUG_RANGE)).is_false()
