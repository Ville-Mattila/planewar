extends GdUnitTestSuite
## Unit tests for camera/orbit_math.gd (UX-10): closed-form D vs iterative solve, 1 deg pole sweep,
## cube edges, heading transport, grab pan, zoom mapping.

const EPS: float = 1e-4
const R: float = Sphere.PLANET_RADIUS


func _tangent_heading(d: Vector3, seed_dir: Vector3) -> Vector3:
	return CamMath.perp(seed_dir, d).normalized()


func _is_nan3(v: Vector3) -> bool:
	return is_nan(v.x) or is_nan(v.y) or is_nan(v.z)


func _assert_pose_ok(t: Transform3D) -> void:
	var b: Basis = t.basis
	assert_bool(_is_nan3(t.origin) or _is_nan3(b.x) or _is_nan3(b.y) or _is_nan3(b.z)).is_false()
	assert_float(b.x.length()).is_equal_approx(1.0, EPS)
	assert_float(b.y.length()).is_equal_approx(1.0, EPS)
	assert_float(b.z.length()).is_equal_approx(1.0, EPS)
	assert_float(b.x.dot(b.y)).is_equal_approx(0.0, EPS)
	assert_float(b.y.dot(b.z)).is_equal_approx(0.0, EPS)
	assert_float(b.x.dot(b.z)).is_equal_approx(0.0, EPS)


## Bisection on |F + D w| = R + A, independent of the closed form. Scalar (64-bit) arithmetic: Vector3
## is 32-bit, whose ulp at 20 km is ~2 mm and would swamp a 1 mm check. F.w = |F| sin(theta), |w| = 1.
func _iterative_d(f_len: float, theta: float, a: float) -> float:
	var lo: float = 0.0
	var hi: float = 40000.0
	for i in 100:
		var mid: float = 0.5 * (lo + hi)
		var dist2: float = f_len * f_len + 2.0 * f_len * mid * sin(theta) + mid * mid
		if dist2 < (R + a) * (R + a):
			lo = mid
		else:
			hi = mid
	return 0.5 * (lo + hi)


# --- closed-form D (acceptance: < 1 mm) ------------------------------------------

func test_closed_form_d_matches_iterative_solve() -> void:
	var rng: Rng = Rng.new(11)
	for i in 400:
		var d_f: Vector3 = Vector3(rng.range_f(-1, 1), rng.range_f(-1, 1), rng.range_f(-1, 1)).normalized()
		var h: Vector3 = _tangent_heading(d_f, Vector3(rng.range_f(-1, 1), rng.range_f(-1, 1), rng.range_f(-1, 1)))
		var f_len: float = R + rng.range_f(Sphere.RELIEF_MIN, Sphere.RELIEF_MAX)
		var g_f: float = f_len - R
		var a: float = rng.range_f(OrbitMath.altitude_min(g_f), OrbitMath.A_MAX)
		var theta: float = deg_to_rad(rng.range_f(OrbitMath.THETA_MIN_DEG, OrbitMath.THETA_MAX_DEG))
		var closed: float = OrbitMath.solve_distance(f_len, theta, a)
		var iter: float = _iterative_d(f_len, theta, a)
		assert_float(absf(closed - iter)).is_less(1e-3)


func test_pose_puts_camera_at_requested_altitude() -> void:
	var d_f: Vector3 = Vector3(0.6, 0.0, 0.8)
	var h: Vector3 = Sphere.tangent_frame(d_f).y
	for a in [300.0, 1800.0, 2499.0, 8000.0, OrbitMath.A_MAX]:
		var z: float = OrbitMath.zoom_z(a)
		var t: Transform3D = OrbitMath.pose(d_f, h, R, a, OrbitMath.theta_of(z, 0.0))
		assert_float(t.origin.length()).is_equal_approx(R + a, 1e-2)
		_assert_pose_ok(t)


func test_camera_looks_at_focus() -> void:
	var d_f: Vector3 = Vector3(1, 0, 0)
	var h: Vector3 = Vector3(0, 0, 1)
	var t: Transform3D = OrbitMath.pose(d_f, h, R, 1800.0, deg_to_rad(40.0))
	var to_f: Vector3 = (d_f * R - t.origin).normalized()
	assert_float(to_f.distance_to(-t.basis.z)).is_less(EPS)


# --- zoom and tilt ----------------------------------------------------------------

func test_zoom_roundtrip_and_tactical_split() -> void:
	for a in [300.0, 777.0, 2499.0, 9000.0, 14000.0]:
		assert_float(OrbitMath.altitude_of_z(OrbitMath.zoom_z(a))).is_equal_approx(a, 1e-2)
	assert_float(OrbitMath.zoom_z(OrbitMath.TACTICAL_A_MAX)).is_equal_approx(0.552, 1e-3)
	assert_bool(OrbitMath.is_tactical(2499.0)).is_true()
	assert_bool(OrbitMath.is_tactical(2500.0)).is_false()


func test_altitude_min() -> void:
	assert_float(OrbitMath.altitude_min(-400.0)).is_equal(300.0)
	assert_float(OrbitMath.altitude_min(700.0)).is_equal(900.0)


func test_theta_range_and_delta_fade() -> void:
	assert_float(rad_to_deg(OrbitMath.theta_of(0.0, 0.0))).is_equal_approx(40.0, 1e-3)
	assert_float(rad_to_deg(OrbitMath.theta_of(1.0, 0.0))).is_equal_approx(90.0, 1e-3)
	assert_float(rad_to_deg(OrbitMath.theta_of(0.0, 99.0))).is_equal_approx(70.0, 1e-3)
	assert_float(rad_to_deg(OrbitMath.theta_of(0.0, -99.0))).is_equal_approx(25.0, 1e-3)
	assert_float(rad_to_deg(OrbitMath.theta_of(0.7, 30.0))).is_equal_approx(rad_to_deg(OrbitMath.theta_of(0.7, 0.0)), 1e-3)
	for i in 101:
		var th: float = rad_to_deg(OrbitMath.theta_of(float(i) / 100.0, 30.0))
		assert_float(th).is_between(25.0, 90.0)


func test_pan_speed() -> void:
	assert_float(OrbitMath.pan_speed(1000.0, 0.0)).is_equal_approx(600.0, 1e-6)


# --- poles and cube edges (acceptance: 1 deg sweep) -----------------------------------

func test_one_degree_sweep_through_pole() -> void:
	# Fly the focus over the Noon Pole along a meridian in 1 deg steps, transporting the heading.
	var theta: float = deg_to_rad(55.0)
	var d: Vector3 = Vector3(cos(deg_to_rad(-60.0)), 0, sin(deg_to_rad(-60.0)))
	var h: Vector3 = Sphere.tangent_frame(d).y
	var prev_y: Vector3 = Vector3.ZERO
	var prev_h: Vector3 = h
	for i in range(0, 241):
		var lat: float = deg_to_rad(-60.0 + float(i))
		var nd: Vector3 = Vector3(cos(lat), 0, sin(lat))
		h = OrbitMath.transport_heading(h, d, nd)
		d = nd
		var t: Transform3D = OrbitMath.pose(d, h, R, 1800.0, theta)
		_assert_pose_ok(t)
		assert_float(h.dot(d)).is_equal_approx(0.0, EPS)
		assert_float(h.length()).is_equal_approx(1.0, EPS)
		# Heading step: the world-space tangent rotates with the great circle (1 deg) and no more.
		assert_float(rad_to_deg(h.angle_to(prev_h))).is_less(2.0)
		if i > 0:
			assert_float(rad_to_deg(t.basis.y.angle_to(prev_y))).is_less(2.0)
		prev_y = t.basis.y
		prev_h = h


func test_sweep_across_pole_keeps_heading_continuous_in_local_frame() -> void:
	# Heading relative to the transported frame of the great circle stays constant: always "forward".
	var d: Vector3 = Vector3(cos(deg_to_rad(80.0)), 0, sin(deg_to_rad(80.0)))
	var h: Vector3 = Sphere.tangent_frame(d).y   # toward the pole
	for i in range(1, 41):
		var lat: float = deg_to_rad(80.0 + float(i))
		var nd: Vector3 = Vector3(cos(lat), 0, sin(lat))
		var travel: Vector3 = (nd - d).normalized()
		h = OrbitMath.transport_heading(h, d, nd)
		d = nd
		var fwd: Vector3 = CamMath.perp(travel, d).normalized()
		assert_float(rad_to_deg(h.angle_to(fwd))).is_less(1.0)


func test_poses_valid_at_exact_poles_and_cube_edges() -> void:
	var dirs: Array[Vector3] = [
		Vector3(0, 0, 1), Vector3(0, 0, -1),
		Vector3(1, 1, 0).normalized(), Vector3(1, 0, 1).normalized(), Vector3(0, -1, 1).normalized(),
		Vector3(1, 1, 1).normalized(), Vector3(-1, -1, 1).normalized(),
		Sphere.face_uv_to_dir(0, 0.0, 0.5), Sphere.face_uv_to_dir(2, 1.0, 1.0),
	]
	for d in dirs:
		var h: Vector3 = OrbitMath.north_heading(d)
		assert_float(h.dot(d)).is_equal_approx(0.0, EPS)
		for a in [300.0, 2000.0, OrbitMath.A_MAX]:
			for th_deg in [25.0, 55.0, 90.0]:
				_assert_pose_ok(OrbitMath.pose(d, h, R, a, deg_to_rad(th_deg)))


func test_sweep_across_cube_edge_is_smooth() -> void:
	# Equator across the face 0 / face 2 edge (lon 45 deg): consecutive poses move smoothly.
	var d: Vector3 = Vector3(cos(deg_to_rad(35.0)), sin(deg_to_rad(35.0)), 0)
	var h: Vector3 = Vector3(0, 0, 1)
	var prev: Transform3D = OrbitMath.pose(d, h, R, 1800.0, deg_to_rad(40.0))
	for i in range(1, 21):
		var lon: float = deg_to_rad(35.0 + float(i))
		var nd: Vector3 = Vector3(cos(lon), sin(lon), 0)
		h = OrbitMath.transport_heading(h, d, nd)
		d = nd
		var t: Transform3D = OrbitMath.pose(d, h, R, 1800.0, deg_to_rad(40.0))
		_assert_pose_ok(t)
		assert_float(rad_to_deg(t.basis.y.angle_to(prev.basis.y))).is_less(1.01 + 0.1)
		assert_float(t.origin.distance_to(prev.origin)).is_less((R + 1800.0) * deg_to_rad(1.0) * 1.1)
		prev = t


# --- frame continuity and transport --------------------------------------------------

func test_pose_continuous_in_altitude_and_theta() -> void:
	var d_f: Vector3 = Vector3(0, 0, 1)
	var h: Vector3 = Vector3(1, 0, 0)
	var prev: Transform3D = OrbitMath.pose(d_f, h, R, 300.0, OrbitMath.theta_of(0.0, 15.0))
	for i in range(1, 1001):
		var z: float = float(i) / 1000.0
		var t: Transform3D = OrbitMath.pose(d_f, h, R, OrbitMath.altitude_of_z(z), OrbitMath.theta_of(z, 15.0))
		_assert_pose_ok(t)
		assert_float(rad_to_deg(t.basis.y.angle_to(prev.basis.y))).is_less(0.5)
		prev = t


func test_transport_heading_keeps_tangent_unit_and_identity() -> void:
	var d: Vector3 = Vector3(1, 0, 0)
	var h: Vector3 = Vector3(0, 0, 1)
	assert_float(OrbitMath.transport_heading(h, d, d).distance_to(h)).is_less(1e-6)
	var rng: Rng = Rng.new(5)
	for i in 300:
		var nd: Vector3 = Vector3(rng.range_f(-1, 1), rng.range_f(-1, 1), rng.range_f(-1, 1)).normalized()
		var hh: Vector3 = OrbitMath.transport_heading(h, d, nd)
		assert_float(hh.length()).is_equal_approx(1.0, EPS)
		assert_float(hh.dot(nd)).is_equal_approx(0.0, EPS)


func test_transport_heading_matches_sphere_transport() -> void:
	var d0: Vector3 = Vector3(1, 0, 0)
	var d1: Vector3 = Vector3(0.6, 0.3, 0.74).normalized()
	var h: Vector3 = Vector3(0, 0, 1)
	var expect: Vector3 = Sphere.transport(d0, d1) * h
	assert_float(OrbitMath.transport_heading(h, d0, d1).distance_to(expect)).is_less(1e-5)


func test_north_heading_and_error() -> void:
	var d: Vector3 = Sphere.from_lat_lon(deg_to_rad(30.0), deg_to_rad(20.0), 1.0)
	var north: Vector3 = OrbitMath.north_heading(d)
	assert_float(north.dot(d)).is_equal_approx(0.0, EPS)
	assert_float(north.z).is_greater(0.0)
	assert_float(OrbitMath.heading_error(north, north, d)).is_equal_approx(0.0, EPS)
	var east: Vector3 = north.cross(d)
	assert_float(absf(OrbitMath.heading_error(north, east, d))).is_equal_approx(PI * 0.5, EPS)
	var pole_h: Vector3 = OrbitMath.north_heading(Vector3(0, 0, 1))
	assert_float(pole_h.length()).is_equal_approx(1.0, EPS)


# --- grab pan -------------------------------------------------------------------------

func test_ray_sphere_point_hit_and_limb() -> void:
	var o: Vector3 = Vector3(R + 2000.0, 0, 0)
	var hit: Vector3 = OrbitMath.ray_sphere_point(o, Vector3(-1, 0, 0), R)
	assert_float(hit.distance_to(Vector3(R, 0, 0))).is_less(1e-2)
	# Ray well past the limb: result lies on the sphere, no NaN.
	var miss: Vector3 = OrbitMath.ray_sphere_point(o, Vector3(0, 1, 0), R)
	assert_float(miss.length()).is_equal_approx(R, 1e-2)
	assert_bool(_is_nan3(miss)).is_false()


func test_grab_pan_keeps_grabbed_point_under_finger() -> void:
	var d_f: Vector3 = Vector3(0, 0, 1)
	var h: Vector3 = Vector3(1, 0, 0)
	var g0: Vector3 = Sphere.from_lat_lon(deg_to_rad(80.0), deg_to_rad(10.0), R)
	var g1: Vector3 = Sphere.from_lat_lon(deg_to_rad(84.0), deg_to_rad(40.0), R)
	var out: PackedVector3Array = OrbitMath.grab_pan(d_f, h, g0, g1)
	# The rotation maps g1 to g0; the focus moves the same way.
	var q_axis: Vector3 = g1.normalized().cross(g0.normalized()).normalized()
	var ang: float = g1.angle_to(g0)
	assert_float(g1.normalized().rotated(q_axis, ang).distance_to(g0.normalized())).is_less(1e-5)
	assert_float(out[0].distance_to(d_f.rotated(q_axis, ang))).is_less(1e-5)
	assert_float(out[1].dot(out[0])).is_equal_approx(0.0, EPS)
	assert_float(out[1].length()).is_equal_approx(1.0, EPS)


func test_grab_pan_zero_motion_is_identity() -> void:
	var g: Vector3 = Vector3(R, 0, 0)
	var out: PackedVector3Array = OrbitMath.grab_pan(Vector3(0, 1, 0), Vector3(0, 0, 1), g, g)
	assert_float(out[0].distance_to(Vector3(0, 1, 0))).is_less(1e-6)
	assert_float(out[1].distance_to(Vector3(0, 0, 1))).is_less(1e-6)
