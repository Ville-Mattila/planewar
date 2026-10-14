extends GdUnitTestSuite
## TA-23: horizon culling is conservative (03 s7.5) and the frustum planes have outward normals.

const R: float = Sphere.PLANET_RADIUS


## 03 s7.5 formula acos(R_low / (R + RELIEF_MAX)) = acos(5500 / 6700) = 0.608 rad at R = 6,000 (the prose
## "0.2 rad" in 03 s7.5 does not match its own formula; the formula is the conservative one and is kept).
func test_theta_up_follows_the_03_s7_5_formula() -> void:
	var expected: float = acos((R + Sphere.RELIEF_MIN) / (R + Sphere.RELIEF_MAX))
	assert_float(HorizonCull.theta_up()).is_equal_approx(expected, 1e-12)
	assert_float(HorizonCull.theta_up()).is_equal_approx(0.608, 0.001)


func test_node_below_camera_is_never_culled() -> void:
	var cam: Vector3 = Vector3(R + 30.0, 0.0, 0.0)
	assert_bool(HorizonCull.is_culled(cam, Vector3(R, 0.0, 0.0), 10.0)).is_false()


func test_antipode_is_culled() -> void:
	var cam: Vector3 = Vector3(R + 30.0, 0.0, 0.0)
	assert_bool(HorizonCull.is_culled(cam, Vector3(-R, 0.0, 0.0), 100.0)).is_true()


func test_camera_inside_horizon_sphere_culls_nothing() -> void:
	assert_bool(HorizonCull.is_culled(Vector3(R - 600.0, 0.0, 0.0), Vector3(-R, 0.0, 0.0), 1.0)).is_false()


## Brute force: a point at any height in the relief band that a straight ray from the camera reaches without
## entering the R_low sphere must never be culled (even as a zero-radius node).
func test_conservative_against_line_of_sight() -> void:
	var r_low: float = HorizonCull.r_low()
	for alt: float in [1.0, 30.0, 300.0, 3000.0, 8000.0]:
		var cam: Vector3 = Vector3(R + alt, 0.0, 0.0)
		for k: int in 400:
			var ang: float = float(k) / 400.0 * PI
			for h: float in [Sphere.RELIEF_MIN, 0.0, Sphere.RELIEF_MAX]:
				var p: Vector3 = Vector3(cos(ang), sin(ang), 0.0) * (R + h)
				if not _segment_clears_sphere(cam, p, r_low):
					continue
				var cd: Vector3 = cam.normalized()
				var hz: float = HorizonCull.horizon_angle(cam)
				if HorizonCull.is_culled(cam, p, 0.0) or HorizonCull.is_culled_angle(cd, hz, p, 0.0, h):
					fail("alt %.0f angle %.3f h %.0f is visible but culled" % [alt, ang, h])
					return


func test_node_height_bound_tightens_the_test() -> void:
	var cam: Vector3 = Vector3(R + 30.0, 0.0, 0.0)
	var cd: Vector3 = cam.normalized()
	var hz: float = HorizonCull.horizon_angle(cam)
	var ang: float = 0.95                           # beyond a 0 m peak's limit (0.83), inside a 700 m peak's (1.03)
	var c: Vector3 = Vector3(cos(ang), sin(ang), 0.0) * R
	assert_bool(HorizonCull.is_culled_angle(cd, hz, c, 0.0, 0.0)).is_true()
	assert_bool(HorizonCull.is_culled_angle(cd, hz, c, 0.0, Sphere.RELIEF_MAX)).is_false()
	assert_float(HorizonCull.theta_up_for(Sphere.RELIEF_MIN - 10.0)).is_equal(0.0)


func test_far_side_is_culled_from_low_altitude() -> void:
	var cam: Vector3 = Vector3(R + 30.0, 0.0, 0.0)
	var culled: int = 0
	for k: int in 100:
		var ang: float = PI * 0.5 + float(k) / 100.0 * PI * 0.5
		culled += 1 if HorizonCull.is_culled(cam, Vector3(cos(ang), sin(ang), 0.0) * R, 50.0) else 0
	assert_int(culled).is_equal(100)


static func _segment_clears_sphere(a: Vector3, b: Vector3, radius: float) -> bool:
	var d: Vector3 = b - a
	var t: float = clampf(-a.dot(d) / d.length_squared(), 0.0, 1.0)
	return (a + d * t).length() >= radius - 1e-3


func test_perspective_planes_outward_and_match_camera3d() -> void:
	var xf: Transform3D = Transform3D(Basis.looking_at(Vector3(0, 0, -1), Vector3.UP), Vector3(1, 2, 3))
	var planes: Array[Plane] = PlanetView.perspective_planes(xf, 75.0, 16.0 / 9.0, 0.3, 40000.0)
	var view: PlanetView = PlanetView.make(xf.origin, Vector3(0, 0, -1), planes)
	assert_bool(view.sphere_in_frustum(Vector3(1, 2, -50), 0.0)).is_true()
	assert_bool(view.sphere_in_frustum(Vector3(1, 2, 50), 1.0)).is_false()
	assert_bool(view.sphere_in_frustum(Vector3(1000, 2, -50), 1.0)).is_false()
	assert_bool(view.sphere_in_frustum(Vector3(1000, 2, -50), 2000.0)).is_true()
	assert_bool(view.is_ahead(Vector3(1, 2, -1))).is_true()
	var cam: Camera3D = auto_free(Camera3D.new())
	add_child(cam)
	cam.fov = 75.0
	cam.near = 0.3
	cam.far = 40000.0
	cam.global_transform = xf
	var from_cam: PlanetView = PlanetView.from_camera(cam)
	assert_int(from_cam.frustum.size()).is_equal(6)
	assert_bool(from_cam.sphere_in_frustum(Vector3(1, 2, -50), 0.0)).is_true()
	assert_bool(from_cam.sphere_in_frustum(Vector3(1, 2, 50), 1.0)).is_false()
