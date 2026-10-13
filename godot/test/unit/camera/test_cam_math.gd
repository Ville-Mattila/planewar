extends GdUnitTestSuite
## Unit tests for camera/cam_math.gd: crit_damp, bank angle, up reference, view basis, near plane (R0 C2-28).

const EPS: float = 1e-4


func _assert_orthonormal(b: Basis) -> void:
	assert_float(b.x.length()).is_equal_approx(1.0, EPS)
	assert_float(b.y.length()).is_equal_approx(1.0, EPS)
	assert_float(b.z.length()).is_equal_approx(1.0, EPS)
	assert_float(b.x.dot(b.y)).is_equal_approx(0.0, EPS)
	assert_float(b.y.dot(b.z)).is_equal_approx(0.0, EPS)
	assert_float(b.x.dot(b.z)).is_equal_approx(0.0, EPS)
	assert_float(b.determinant()).is_equal_approx(1.0, EPS)


# --- crit_damp ---------------------------------------------------------------

func test_crit_damp_converges() -> void:
	var x: Vector3 = Vector3(10, -4, 7)
	var v: Vector3 = Vector3(3, 2, -5)
	var target: Vector3 = Vector3(1, 2, 3)
	for i in 120:
		var r: PackedVector3Array = CamMath.crit_damp(x, v, target, 12.0, 1.0 / 60.0)
		x = r[0]
		v = r[1]
	assert_float(x.distance_to(target)).is_less(1e-3)
	assert_float(v.length()).is_less(1e-2)


func test_crit_damp_no_overshoot_from_rest() -> void:
	var x: Vector3 = Vector3(100, 0, 0)
	var v: Vector3 = Vector3.ZERO
	var target: Vector3 = Vector3.ZERO
	for i in 300:
		var r: PackedVector3Array = CamMath.crit_damp(x, v, target, 12.0, 1.0 / 60.0)
		x = r[0]
		v = r[1]
		assert_float(x.x).is_greater_equal(-1e-6)
		assert_float(x.x).is_less_equal(100.0)


func test_crit_damp_step_independent() -> void:
	# Exact solution: one step of dt equals two steps of dt / 2.
	var x: Vector3 = Vector3(5, 1, -2)
	var v: Vector3 = Vector3(-1, 4, 0)
	var t: Vector3 = Vector3(0, 0, 1)
	var one: PackedVector3Array = CamMath.crit_damp(x, v, t, 12.0, 0.1)
	var h1: PackedVector3Array = CamMath.crit_damp(x, v, t, 12.0, 0.05)
	var h2: PackedVector3Array = CamMath.crit_damp(h1[0], h1[1], t, 12.0, 0.05)
	assert_float(one[0].distance_to(h2[0])).is_less(1e-4)
	assert_float(one[1].distance_to(h2[1])).is_less(1e-4)


func test_crit_damp_at_target_stays() -> void:
	var r: PackedVector3Array = CamMath.crit_damp(Vector3(1, 2, 3), Vector3.ZERO, Vector3(1, 2, 3), 12.0, 0.016)
	assert_float(r[0].distance_to(Vector3(1, 2, 3))).is_less(1e-6)
	assert_float(r[1].length()).is_less(1e-6)


func test_crit_damp_f_matches_vector_form() -> void:
	var s: Vector2 = CamMath.crit_damp_f(4.0, 2.0, -1.0, 8.0, 0.03)
	var r: PackedVector3Array = CamMath.crit_damp(Vector3(4, 0, 0), Vector3(2, 0, 0), Vector3(-1, 0, 0), 8.0, 0.03)
	assert_float(s.x).is_equal_approx(r[0].x, 1e-6)
	assert_float(s.y).is_equal_approx(r[1].x, 1e-6)


# --- bank, up reference, view basis ----------------------------------------------

func test_bank_angle_level_and_banked() -> void:
	var n: Vector3 = Vector3.UP
	assert_float(CamMath.bank_angle(Basis.IDENTITY, n)).is_equal_approx(0.0, EPS)
	# Roll about forward (-z) by +30 deg: right wing down is positive.
	var banked: Basis = Basis(Vector3(0, 0, -1), deg_to_rad(30.0)) * Basis.IDENTITY
	assert_float(absf(CamMath.bank_angle(banked, n))).is_equal_approx(deg_to_rad(30.0), EPS)
	var other: Basis = Basis(Vector3(0, 0, -1), deg_to_rad(-30.0)) * Basis.IDENTITY
	assert_float(CamMath.bank_angle(banked, n) * CamMath.bank_angle(other, n)).is_less(0.0)


func test_bank_angle_vertical_is_zero() -> void:
	var b: Basis = Basis.looking_at(Vector3.UP, Vector3.BACK)
	assert_float(CamMath.bank_angle(b, Vector3.UP)).is_equal(0.0)


func test_up_reference_unit_and_perpendicular() -> void:
	var rng: Rng = Rng.new(7)
	for i in 500:
		var d: Vector3 = Vector3(rng.range_f(-1, 1), rng.range_f(-1, 1), rng.range_f(-1, 1)).normalized()
		var n: Vector3 = Vector3(rng.range_f(-1, 1), rng.range_f(-1, 1), rng.range_f(-1, 1)).normalized()
		var u: Vector3 = CamMath.perp(Vector3(rng.range_f(-1, 1), rng.range_f(-1, 1), rng.range_f(-1, 1)), d).normalized()
		var r: Vector3 = CamMath.up_reference(d, n, u)
		assert_float(r.length()).is_equal_approx(1.0, EPS)
		assert_float(r.dot(d)).is_equal_approx(0.0, EPS)


func test_up_reference_degenerate_inputs_do_not_nan() -> void:
	var d: Vector3 = Vector3(0, 0, 1)
	var r: Vector3 = CamMath.up_reference(d, d, d)
	assert_bool(is_nan(r.x) or is_nan(r.y) or is_nan(r.z)).is_false()
	assert_float(r.length()).is_equal_approx(1.0, EPS)


func test_view_basis_orthonormal() -> void:
	var d: Vector3 = Vector3(0.3, -0.5, 0.8).normalized()
	var b: Basis = CamMath.view_basis(d, Vector3.UP)
	_assert_orthonormal(b)
	assert_float((-b.z).distance_to(d)).is_less(EPS)
	var straight: Basis = CamMath.view_basis(Vector3.UP, Vector3.UP)
	_assert_orthonormal(straight)


func test_roll_target_clamps_and_fades_when_inverted() -> void:
	assert_float(CamMath.roll_target(deg_to_rad(10.0), 0.35)).is_equal_approx(deg_to_rad(3.5), EPS)
	assert_float(CamMath.roll_target(deg_to_rad(80.0), 1.0)).is_equal_approx(deg_to_rad(30.0), EPS)
	assert_float(CamMath.roll_target(deg_to_rad(170.0), 1.0)).is_equal_approx(0.0, EPS)
	assert_float(CamMath.roll_target(deg_to_rad(-60.0), 0.0)).is_equal(0.0)


func test_smootherstep_endpoints_and_monotonic() -> void:
	assert_float(CamMath.smootherstep(-1.0)).is_equal(0.0)
	assert_float(CamMath.smootherstep(2.0)).is_equal(1.0)
	assert_float(CamMath.smootherstep(0.5)).is_equal_approx(0.5, EPS)
	var prev: float = 0.0
	for i in 101:
		var e: float = CamMath.smootherstep(float(i) / 100.0)
		assert_float(e).is_greater_equal(prev)
		prev = e


# --- near plane (R0 C2-28) -----------------------------------------------------

func test_near_plane_default_formula() -> void:
	assert_float(CamMath.near_plane(0.0)).is_equal_approx(0.3, 1e-6)
	assert_float(CamMath.near_plane(-50.0)).is_equal_approx(0.3, 1e-6)
	assert_float(CamMath.near_plane(100.0)).is_equal_approx(0.7, 1e-6)
	assert_float(CamMath.near_plane(1000.0)).is_equal_approx(4.3, 1e-6)
	assert_float(CamMath.near_plane(14000.0)).is_equal_approx(20.0, 1e-6)


func test_near_plane_continuous_and_monotonic() -> void:
	var prev: float = CamMath.near_plane(0.0)
	for i in range(1, 2000):
		var cur: float = CamMath.near_plane(float(i) * 10.0)
		assert_float(cur).is_greater_equal(prev)
		assert_float(cur - prev).is_less(0.05 + 1e-6)
		prev = cur


func test_near_plane_orbit_alt_formula() -> void:
	assert_float(CamMath.near_plane_orbit_alt(300.0)).is_equal_approx(4.0, 1e-6)
	assert_float(CamMath.near_plane_orbit_alt(2500.0)).is_equal_approx(20.0, 1e-6)
	assert_float(CamMath.near_plane_orbit_alt(1400.0)).is_equal_approx(12.0, 1e-6)
	assert_float(CamMath.near_plane_orbit_alt(14000.0)).is_equal_approx(20.0, 1e-6)
	assert_float(CamMath.near_plane_orbit_alt(0.0)).is_equal_approx(4.0, 1e-6)


func test_near_lerp_is_log_space() -> void:
	assert_float(CamMath.near_lerp(0.3, 20.0, 0.0)).is_equal_approx(0.3, 1e-6)
	assert_float(CamMath.near_lerp(0.3, 20.0, 1.0)).is_equal_approx(20.0, 1e-4)
	assert_float(CamMath.near_lerp(1.0, 16.0, 0.5)).is_equal_approx(4.0, 1e-5)


func test_far_plane_constant() -> void:
	assert_float(CamMath.FAR_PLANE).is_equal(40000.0)
