extends GdUnitTestSuite
## Unit tests for camera/orbit_controller.gd (UX-13): grab pan, fling, anchored zoom, tilt curve, heading
## modes, follow, dive. Time-stepped at 60 Hz; deterministic (no randomness, no clock).

const DT: float = 1.0 / 60.0
const R: float = Sphere.PLANET_RADIUS


func _ctl(dir: Vector3 = Vector3(1.0, 0.0, 0.0), alt: float = 1800.0) -> OrbitController:
	return OrbitController.new(dir.normalized(), alt)


func _hit(c: OrbitController, local: Vector3) -> Vector3:
	var p: Transform3D = c.pose()
	return OrbitMath.ray_sphere_point(p.origin, p.basis * local.normalized(), c.focus_length())


## Screen error in radians between the finger ray and the ray to the grabbed point g0. 2 du at 1080 p and a
## 60 deg vertical FOV is about 0.002 rad (UX-13 acceptance).
func _screen_err(c: OrbitController, local: Vector3, g0: Vector3) -> float:
	var p: Transform3D = c.pose()
	return local.normalized().angle_to(p.basis.inverse() * (g0 - p.origin))


const TWO_DU: float = 0.002


func _run(c: OrbitController, secs: float) -> void:
	for i in int(secs / DT):
		c.update(DT)


func _north_err(c: OrbitController) -> float:
	return absf(OrbitMath.heading_error(c.h, OrbitMath.north_heading(c.d_f), c.d_f))


func _has_nan(c: OrbitController) -> bool:
	return is_nan(c.h.x) or is_nan(c.d_f.x) or is_nan(c.h.y) or is_nan(c.d_f.y)


# region grab
func test_grab_keeps_ground_point_under_finger() -> void:
	var c: OrbitController = _ctl()
	var p: Transform3D = c.pose()
	var l0: Vector3 = Vector3(0.1, -0.1, -1.0).normalized()
	c.grab_begin(p.origin, p.basis * l0)
	var g0: Vector3 = _hit(c, l0)
	for i in 30:
		var l: Vector3 = Vector3(0.1 + 0.01 * i, -0.1 + 0.006 * i, -1.0).normalized()
		var q: Transform3D = c.pose()
		c.grab_move(q.origin, q.basis * l, DT)
		assert_float(_screen_err(c, l, g0)).is_less(TWO_DU)
		c.update(DT)


func test_grab_across_pole_stays_finite_and_pinned() -> void:
	var c: OrbitController = _ctl(Vector3(0.2, 0.0, 1.0))
	var l0: Vector3 = Vector3(0.0, 0.2, -1.0).normalized()
	var q: Transform3D = c.pose()
	c.grab_begin(q.origin, q.basis * l0)
	var g0: Vector3 = _hit(c, l0)
	for i in 40:
		var l: Vector3 = Vector3(0.0, 0.2 - 0.012 * i, -1.0).normalized()
		q = c.pose()
		c.grab_move(q.origin, q.basis * l, DT)
		assert_float(_screen_err(c, l, g0)).is_less(TWO_DU)
		assert_bool(_has_nan(c)).is_false()


func test_grab_past_limb_is_finite() -> void:
	var c: OrbitController = _ctl(Vector3(1.0, 0.0, 0.0), 14000.0)
	var q: Transform3D = c.pose()
	c.grab_begin(q.origin, q.basis * Vector3(0.0, 0.0, -1.0))
	c.grab_move(q.origin, q.basis * Vector3(0.0, 1.0, -0.01).normalized(), DT)
	assert_float(c.d_f.length()).is_equal_approx(1.0, 1e-4)
	assert_bool(_has_nan(c)).is_false()


func test_fling_decays_with_tau_and_stops() -> void:
	var c: OrbitController = _ctl()
	var q: Transform3D = c.pose()
	c.grab_begin(q.origin, q.basis * Vector3(0.0, 0.0, -1.0))
	for i in 10:
		q = c.pose()
		var l: Vector3 = Vector3(0.02 * (i + 1), 0.0, -1.0).normalized()
		c.grab_move(q.origin, q.basis * l, DT)
		c.update(DT)
	c.grab_end()
	assert_bool(c.is_flinging()).is_true()
	var v0: float = c._fling.length()
	_run(c, OrbitController.TAU_FLING)
	assert_float(c._fling.length() / v0).is_equal_approx(exp(-1.0), 0.03)
	_run(c, 8.0)
	assert_bool(c.is_flinging()).is_false()


func test_paused_grab_does_not_fling_and_new_grab_cancels() -> void:
	var c: OrbitController = _ctl()
	var q: Transform3D = c.pose()
	c.grab_begin(q.origin, q.basis * Vector3(0.0, 0.0, -1.0))
	c.grab_move(q.origin, q.basis * Vector3(0.1, 0.0, -1.0).normalized(), DT)
	_run(c, 0.3)
	c.grab_end()
	assert_bool(c.is_flinging()).is_false()
	c._fling = Vector3(0.0, 0.0, 0.5)
	c.grab_begin(q.origin, q.basis * Vector3(0.0, 0.0, -1.0))
	assert_bool(c.is_flinging()).is_false()
# endregion


# region zoom, tilt
func test_zoom_anchor_keeps_ground_point() -> void:
	var c: OrbitController = _ctl()
	var l: Vector3 = Vector3(0.3, -0.2, -1.0).normalized()
	var g: Vector3 = _hit(c, l)
	var q: Transform3D = c.pose()
	c.zoom(0.8, q.origin, q.basis * l)
	for i in 60:
		c.update(DT)
		assert_float(_hit(c, l).distance_to(g)).is_less(0.5)
	assert_float(c.altitude()).is_equal_approx(1800.0 * exp(-0.8), 5.0)


func test_zoom_clamps_to_altitude_range() -> void:
	var c: OrbitController = _ctl()
	c.zoom(-10.0)
	_run(c, 3.0)
	assert_float(c.altitude()).is_equal_approx(OrbitMath.A_MAX, 5.0)
	c.zoom(20.0)
	_run(c, 3.0)
	assert_float(c.altitude()).is_equal_approx(OrbitMath.altitude_min(0.0), 1.0)
	c.ground_h = 500.0
	c.zoom(-1.0)
	c.zoom(5.0)
	_run(c, 3.0)
	assert_float(c.altitude()).is_equal_approx(OrbitMath.altitude_min(500.0), 1.0)


func test_tilt_curve_and_smoothing() -> void:
	var c: OrbitController = _ctl(Vector3.RIGHT, 600.0)
	_run(c, 1.0)
	assert_float(c._theta).is_equal_approx(OrbitMath.theta_of(OrbitMath.zoom_z(600.0), 0.0), 1e-3)
	c.tilt(100.0)
	assert_float(c.delta_deg).is_equal_approx(OrbitMath.DELTA_MAX_DEG, 1e-6)
	var before: float = c._theta
	c.update(DT)
	assert_float(absf(c._theta - before)).is_less(deg_to_rad(5.0))
	_run(c, 1.5)
	assert_float(c._theta).is_equal_approx(OrbitMath.theta_of(OrbitMath.zoom_z(600.0), 30.0), 1e-3)
	c.zoom(-3.0)
	_run(c, 2.0)
	assert_float(c._theta).is_equal_approx(OrbitMath.theta_of(OrbitMath.zoom_z(c.altitude()), 30.0), 2e-3)
	c.tilt(-100.0)
	assert_float(c.delta_deg).is_equal_approx(OrbitMath.DELTA_MIN_DEG, 1e-6)


func test_dive_to_build_takes_half_second() -> void:
	var c: OrbitController = _ctl(Vector3.RIGHT, 3000.0)
	c.dive_to_build()
	_run(c, OrbitController.DIVE_TIME + DT)
	assert_float(c.altitude()).is_equal_approx(OrbitController.DIVE_ALTITUDE, 2.0)
# endregion


# region velocity pan, heading
func test_velocity_pan_speed() -> void:
	var c: OrbitController = _ctl()
	var d0: Vector3 = c.d_f
	for i in 60:
		c.pan_velocity(Vector2(0.0, 1.0), DT)
	var dist: float = R * d0.angle_to(c.d_f)
	assert_float(dist).is_equal_approx(OrbitMath.pan_speed(1800.0, 0.0), 2.0)
	assert_float(c.h.dot(c.d_f)).is_equal_approx(0.0, 1e-4)


func test_rotate_heading_leaves_north_up() -> void:
	var c: OrbitController = _ctl()
	c.set_heading_mode(OrbitController.HeadingMode.NORTH_UP)
	c.rotate_heading(0.5)
	assert_int(c.mode).is_equal(OrbitController.HeadingMode.FREE)
	assert_float(_north_err(c)).is_equal_approx(0.5, 1e-4)


func test_north_up_slews_to_north_with_tau() -> void:
	var c: OrbitController = _ctl()
	c.rotate_heading(1.0)
	c.set_heading_mode(OrbitController.HeadingMode.NORTH_UP)
	_run(c, OrbitController.TAU_NORTH)
	assert_float(_north_err(c)).is_equal_approx(exp(-1.0), 0.02)
	_run(c, 6.0)
	assert_float(_north_err(c)).is_less(1e-3)


func test_north_up_never_spins_at_pole_crossing() -> void:
	var lat: float = deg_to_rad(70.0)
	var c: OrbitController = OrbitController.new(Vector3(cos(lat), 0.0, sin(lat)), 1800.0)
	c.set_heading_mode(OrbitController.HeadingMode.NORTH_UP)
	var prev: Vector3 = c.h
	var max_step: float = 0.0
	var was_suspended: bool = false
	for i in 400:
		c.pan_velocity(Vector2(0.0, 1.0), DT)
		c.update(DT)
		assert_bool(_has_nan(c)).is_false()
		max_step = maxf(max_step, rad_to_deg(prev.angle_to(c.h)))
		prev = c.h
		was_suspended = was_suspended or c.is_north_suspended()
	assert_float(max_step).is_less(2.0)
	assert_bool(was_suspended).is_true()
	assert_bool(c.d_f.z < 0.9).is_true()


func test_north_up_resumes_below_100_deg_error() -> void:
	var lat: float = deg_to_rad(40.0)
	var c: OrbitController = OrbitController.new(Vector3(cos(lat), 0.0, sin(lat)), 1800.0)
	c.set_heading_mode(OrbitController.HeadingMode.NORTH_UP)
	c._north_suspended = true
	c.h = OrbitMath.north_heading(c.d_f).rotated(c.d_f, deg_to_rad(150.0))
	_run(c, 2.0)
	assert_bool(c.is_north_suspended()).is_true()
	assert_float(rad_to_deg(_north_err(c))).is_equal_approx(150.0, 0.01)
	c.h = OrbitMath.north_heading(c.d_f).rotated(c.d_f, deg_to_rad(60.0))
	_run(c, 0.1)
	assert_bool(c.is_north_suspended()).is_false()


func test_compass_tap_north_in_0_4_s_and_core_in_cap() -> void:
	var c: OrbitController = _ctl()
	c.rotate_heading(2.0)
	c.compass_tap(Vector3(1.0, 0.0, 0.0))
	_run(c, OrbitController.COMPASS_TIME + DT)
	assert_float(_north_err(c)).is_less(1e-3)
	var p: OrbitController = OrbitController.new(Vector3(0.05, 0.0, 1.0).normalized(), 1800.0)
	var core: Vector3 = Vector3(0.0, 1.0, 0.0)
	p.compass_tap(core)
	_run(p, OrbitController.COMPASS_TIME + DT)
	var want: Vector3 = (core - p.d_f * core.dot(p.d_f)).normalized()
	assert_float(p.h.dot(want)).is_greater(0.999)
# endregion


func test_follow_converges_and_pan_cancels() -> void:
	var c: OrbitController = _ctl()
	var target: Vector3 = Vector3(1.0, 0.3, 0.1).normalized()
	var total: float = c.d_f.angle_to(target)
	c.follow(target)
	assert_bool(c.is_following()).is_true()
	_run(c, OrbitController.TAU_FOLLOW)
	assert_float(c.d_f.angle_to(target) / total).is_equal_approx(exp(-1.0), 0.03)
	c.pan_velocity(Vector2(1.0, 0.0), DT)
	assert_bool(c.is_following()).is_false()
	var d: Vector3 = c.d_f
	c.update(DT)
	assert_bool(c.d_f.is_equal_approx(d)).is_true()


func test_home_and_pose_orbit_radius() -> void:
	var c: OrbitController = _ctl()
	c.home(Vector3(0.0, 0.0, 1.0))
	assert_float(c.altitude()).is_equal_approx(OrbitController.HOME_ALTITUDE, 0.5)
	assert_float(c.pose().origin.length()).is_equal_approx(R + OrbitController.HOME_ALTITUDE, 0.01)
