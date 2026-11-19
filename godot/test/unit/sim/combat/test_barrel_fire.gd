extends GdUnitTestSuite
## GD-50: a ground unit's mounted weapon fires along its heading pitched by the barrel (sim/ground B4, sim/combat CB15), and
## `Ballistics.predict_impact` agrees with the simulated impact within the Crawler's `loft_tol_m` for lofted shots at
## 1,000-1,150 m (05 s6.7), possessed and AUTO, on the flat datum and on cradle relief.

const DISTANCES: Array[float] = [1000.0, 1075.0, 1150.0]
const VEC_EPS: float = 1e-5     ## Vector3 components are float32


func _rate() -> float:
	return BarrelTestKit.rate()


## Possessed or AUTO: slew to the solved elevation for `d`, fire once; returns [shot, target point, elevation].
func _lofted(w: SimWorld, id: int, possessed: bool, d: float) -> Array:
	var p: BarrelTestKit.Pilot = BarrelTestKit.pilot(w, id, possessed)
	var e: float = BarrelTestKit.solve(w, id, d)
	assert_int(BarrelTestKit.slew_to(w, p, e, _rate())).is_less(300)
	var s: int = EntityId.slot(id)
	var target: Vector3 = BarrelTestKit.ahead(w.store().pos[s], w.store().fwd[s], d)
	var shot: BarrelTestKit.Shot = BarrelTestKit.fire_one(w, p)
	return [shot, target, e]


func _on_target(possessed: bool) -> void:
	for d: float in DISTANCES:
		var w: SimWorld = BarrelTestKit.world(BarrelTestKit.no_spread_content())
		var id: int = BarrelTestKit.crawler(w)
		var r: Array = _lofted(w, id, possessed, d)
		var shot: BarrelTestKit.Shot = r[0]
		var target: Vector3 = r[1]
		assert_bool(shot.landed).override_failure_message("no impact at %.0f m" % d).is_true()
		var miss: float = target.angle_to(shot.impact) * Sphere.PLANET_RADIUS
		assert_float(miss).override_failure_message("lofted %.0f m shot (e %.2f deg) missed by %.1f m" % [d, rad_to_deg(float(r[2])), miss]) \
			.is_less_equal(BarrelTestKit.LOFT_TOL_M)
		var pred: Vector4 = BarrelTestKit.predict_from(w, shot.at, shot.v)
		assert_float(Vector3(pred.x, pred.y, pred.z).distance_to(shot.impact)).is_less_equal(BarrelTestKit.LOFT_TOL_M)


func test_auto_lofted_shots_land_within_loft_tol_of_targets_at_1000_to_1150_m() -> void:
	_on_target(false)


func test_possessed_lofted_shots_land_within_loft_tol_of_targets_at_1000_to_1150_m() -> void:
	_on_target(true)


func test_the_shell_leaves_along_the_heading_at_the_barrel_elevation() -> void:
	var w: SimWorld = BarrelTestKit.world(BarrelTestKit.no_spread_content())
	var id: int = BarrelTestKit.crawler(w)
	var r: Array = _lofted(w, id, false, 1000.0)
	var shot: BarrelTestKit.Shot = r[0]
	var s: int = EntityId.slot(id)
	var n: Vector3 = w.store().pos[s].normalized()
	var dir: Vector3 = shot.v.normalized()
	assert_float(asin(dir.dot(n))).is_equal_approx(float(r[2]), VEC_EPS)         # Vector3 is float32
	assert_float((dir - n * dir.dot(n)).normalized().dot(w.store().fwd[s])).is_equal_approx(1.0, VEC_EPS)
	assert_float(shot.v.length()).is_equal_approx(BarrelTestKit.shell().speed_mps, 1e-3)
	assert_vector(shot.at).is_equal_approx(w.store().pos[s] + dir * w.store().radius[s], Vector3.ONE * 1e-3)


func test_a_crawler_at_rest_still_fires_level_and_lands_short() -> void:
	# The pre-GD-50 behaviour at the rest elevation (0): the shell leaves level and lands 150-300 m out.
	var w: SimWorld = BarrelTestKit.world(BarrelTestKit.no_spread_content())
	var id: int = BarrelTestKit.crawler(w)
	var p: BarrelTestKit.Pilot = BarrelTestKit.pilot(w, id, false)
	var shot: BarrelTestKit.Shot = BarrelTestKit.fire_one(w, p)
	var n: Vector3 = w.store().pos[EntityId.slot(id)].normalized()
	assert_float(shot.v.normalized().dot(n)).is_equal_approx(0.0, VEC_EPS)
	var reach: float = n.angle_to(shot.impact) * Sphere.PLANET_RADIUS
	assert_float(reach).is_between(100.0, 300.0)


func test_spread_is_drawn_around_the_barrel_and_prediction_from_the_spawned_shell_agrees() -> void:
	# Shipped defs (siege_gun spread 1.5 deg): the shell leaves within the spread cone of the barrel, and predict_impact
	# from the spawned position and velocity agrees with the simulated impact.
	for possessed: bool in [false, true]:
		var w: SimWorld = BarrelTestKit.world()
		var id: int = BarrelTestKit.crawler(w)
		var r: Array = _lofted(w, id, possessed, 1100.0)
		var shot: BarrelTestKit.Shot = r[0]
		var s: int = EntityId.slot(id)
		var barrel: Vector3 = BarrelSlew.muzzle_dir(w.store().pos[s], w.store().fwd[s], float(r[2]))
		var a: float = WorldTestKit.content().weapons[int(WorldTestKit.content().weapon_index[&"siege_gun"]) - DefRanges.WEAPON_BASE].spread_deg
		assert_float(rad_to_deg(shot.v.normalized().angle_to(barrel))).is_less_equal(a * sqrt(2.0) + 1e-6)
		assert_bool(shot.landed).is_true()
		var pred: Vector4 = BarrelTestKit.predict_from(w, shot.at, shot.v)
		assert_float(Vector3(pred.x, pred.y, pred.z).distance_to(shot.impact)).is_less_equal(BarrelTestKit.LOFT_TOL_M)


func test_lofted_shots_land_on_target_and_agree_with_the_prediction_on_cradle_relief() -> void:
	# Real relief (cradle): the solve flies the same terrain, so the shell lands within loft_tol_m of a target 1,000-1,150 m
	# out and predict_impact from the spawned shell agrees with the simulated GROUND contact. (tiny_test is flat by recipe.)
	for possessed: bool in [false, true]:
		for d: float in DISTANCES:
			var w: SimWorld = BarrelTestKit.world(BarrelTestKit.no_spread_content(), &"cradle")
			var id: int = BarrelTestKit.crawler(w, Sphere.from_lat_lon(0.1, 0.2, 1.0))
			var r: Array = _lofted(w, id, possessed, d)
			var shot: BarrelTestKit.Shot = r[0]
			var target: Vector3 = r[1]
			assert_bool(shot.landed).override_failure_message("no impact at %.0f m" % d).is_true()
			assert_float(target.angle_to(shot.impact) * Sphere.PLANET_RADIUS).is_less_equal(BarrelTestKit.LOFT_TOL_M)
			var pred: Vector4 = BarrelTestKit.predict_from(w, shot.at, shot.v)
			var gap: float = Vector3(pred.x, pred.y, pred.z).distance_to(shot.impact)
			assert_float(gap).override_failure_message("cradle %.0f m: predicted vs simulated %.1f m" % [d, gap]) \
				.is_less_equal(BarrelTestKit.LOFT_TOL_M)
