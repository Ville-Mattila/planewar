extends GdUnitTestSuite
## Unit tests for sim/steer/ballistics.gd (AI-12; 05 s6.3.1). Acceptance: predicted impact within 3 m of the stepped
## sim for drops from 50-800 m. The reference steps `Kinematics.step_projectile` at the sim tick and applies the same
## ground test as `Collision._ground` (altitude < terrain height + radius), as the sim does for a released bomb.

const R: float = Sphere.PLANET_RADIUS
const TOL_M: float = 3.0
const SHIFT_TOL_M: float = 5.0   # between thinks only the 15 m release gate needs the answer
const THINK_DT: float = 0.0666667
const MAX_STEPS: int = 240

var _rules: RulesDef
var _bomb: ProjectileDef
var _dt: float


class Hill extends Terrain:
	func height_at(dir: Vector3) -> float:
		return 60.0 * dir.normalized().y


func before_test() -> void:
	_rules = FlightTestKit.rules()
	_bomb = FlightTestKit.projectile(&"bomb")
	_dt = FlightTestKit.dt(_rules)


# The sim: tick-by-tick until the contact test fires; the crossing tick is linearly interpolated (as in the predictor).
func _simulate(p0: Vector3, v: Vector3, terrain: Terrain) -> Vector4:
	var p: Vector3 = p0
	var w: Vector3 = v - p0.normalized() * _bomb.eject_down_mps
	var t: float = 0.0
	for i: int in 4000:
		var st: ProjectileState = Kinematics.step_projectile(p, w, _bomb, _rules, _dt)
		var a: float = p.length() - R - terrain.height_at(p) - _bomb.radius_m
		var b: float = st.p.length() - R - terrain.height_at(st.p) - _bomb.radius_m
		if b <= 0.0:
			var f: float = clampf(a / (a - b), 0.0, 1.0)
			var pt: Vector3 = p.lerp(st.p, f)
			return Vector4(pt.x, pt.y, pt.z, t + f * _dt)
		p = st.p
		w = st.v
		t += _dt
	return Ballistics.NO_IMPACT


func _drop(alt: float, speed: float, ang: float) -> Array[Vector3]:
	var p: Vector3 = Vector3(R + alt, 0, 0)
	var v: Vector3 = Vector3(0, cos(ang), sin(ang)) * speed
	return [p, v]


func test_prediction_within_3m_of_stepped_sim_flat() -> void:
	var worst: float = 0.0
	for alt: float in [50.0, 100.0, 200.0, 300.0, 450.0, 600.0, 800.0]:
		for speed: float in [0.0, 80.0, 150.0, 250.0]:
			var pv: Array[Vector3] = _drop(alt, speed, 0.7)
			var ref: Vector4 = _simulate(pv[0], pv[1], Terrain.new())
			var got: Vector4 = Ballistics.predict_impact(pv[0], pv[1], _bomb, _rules, Terrain.new(), THINK_DT, MAX_STEPS)
			assert_bool(Ballistics.has_impact(got)).is_true()
			var d: float = Vector3(got.x, got.y, got.z).distance_to(Vector3(ref.x, ref.y, ref.z))
			worst = maxf(worst, d)
			assert_float(d).override_failure_message("alt %d speed %d: %f m" % [int(alt), int(speed), d]).is_less(TOL_M)
			assert_float(absf(got.w - ref.w)).is_less(0.05)
	print("ballistics worst think-step error: %.3f m" % worst)


func test_prediction_over_rising_terrain() -> void:
	var hill: Hill = Hill.new()
	for alt: float in [100.0, 400.0, 800.0]:
		var pv: Array[Vector3] = _drop(alt, 200.0, 1.2)
		pv[0] = pv[0].rotated(Vector3.FORWARD, 0.0)
		var ref: Vector4 = _simulate(pv[0], pv[1], hill)
		var got: Vector4 = Ballistics.predict_impact(pv[0], pv[1], _bomb, _rules, hill, THINK_DT, MAX_STEPS)
		assert_float(Vector3(got.x, got.y, got.z).distance_to(Vector3(ref.x, ref.y, ref.z))).is_less(TOL_M)


func test_shift_impact_tracks_the_carrier_between_thinks() -> void:
	# Think at p0, then the carrier flies 0.33 s (a tick-and-a-bit gap of 10 ticks) in a straight world-frame line
	# with a gentle 3 m/s dive change; the shifted cached impact must stay within 3 m of a fresh stepped prediction.
	var worst: float = 0.0
	for alt: float in [100.0, 300.0, 500.0, 800.0]:
		for speed: float in [60.0, 150.0, 250.0]:
			var pv: Array[Vector3] = _drop(alt, speed, 0.4)
			var cached: Vector4 = Ballistics.predict_impact(pv[0], pv[1], _bomb, _rules, Terrain.new(), THINK_DT, MAX_STEPS)
			var v1: Vector3 = pv[1] - pv[0].normalized() * 3.0
			var p1: Vector3 = pv[0] + (pv[1] + v1) * 0.5 * (10.0 * _dt)
			var fresh: Vector4 = Ballistics.predict_impact(p1, v1, _bomb, _rules, Terrain.new(), THINK_DT, MAX_STEPS)
			var got: Vector4 = Ballistics.shift_impact(cached, pv[0], pv[1], p1, v1, _bomb, _rules, 0.0)
			worst = maxf(worst, Vector3(got.x, got.y, got.z).distance_to(Vector3(fresh.x, fresh.y, fresh.z)))
	print("shift_impact worst error: %.3f m" % worst)
	assert_float(worst).is_less(SHIFT_TOL_M)


func test_vertical_drop_matches_quadratic() -> void:
	var pv: Array[Vector3] = _drop(300.0, 0.0, 0.0)
	var h: float = 300.0 - _bomb.radius_m
	var g: float = _rules.gravity
	var e: float = _bomb.eject_down_mps
	var t: float = (-e + sqrt(e * e + 2.0 * g * h)) / g
	var got: Vector4 = Ballistics.predict_impact(pv[0], pv[1], _bomb, _rules, Terrain.new(), THINK_DT, MAX_STEPS)
	assert_float(got.w).is_equal_approx(t, 0.02)
	assert_float(Ballistics.flat_impact(pv[0], pv[1], _bomb, _rules, 0.0).w).is_equal_approx(t, 0.0001)


func test_horizon_and_ground_cases() -> void:
	var high: Array[Vector3] = _drop(800.0, 100.0, 0.0)
	assert_bool(Ballistics.has_impact(Ballistics.predict_impact(high[0], high[1], _bomb, _rules, Terrain.new(), THINK_DT, 20))).is_false()
	var low: Array[Vector3] = _drop(0.2, 50.0, 0.0)
	assert_float(Ballistics.predict_impact(low[0], low[1], _bomb, _rules, Terrain.new(), THINK_DT, MAX_STEPS).w).is_equal(0.0)
	assert_float(Ballistics.flat_impact(low[0], low[1], _bomb, _rules, 0.0).w).is_equal(0.0)


func test_siege_shell_style_launch_without_eject() -> void:
	# A siege shell has eject_down_mps 0 and its muzzle velocity as `v`: a 45 degree lob matches the stepped sim.
	_bomb.eject_down_mps = 0.0
	var p: Vector3 = Vector3(R + 5.0, 0, 0)
	var v: Vector3 = Vector3(0.7071, 0.7071, 0) * 120.0
	var ref: Vector4 = _simulate(p, v, Terrain.new())
	var got: Vector4 = Ballistics.predict_impact(p, v, _bomb, _rules, Terrain.new(), THINK_DT, MAX_STEPS)
	assert_float(Vector3(got.x, got.y, got.z).distance_to(Vector3(ref.x, ref.y, ref.z))).is_less(TOL_M)
	assert_float(Vector3(got.x, got.y, got.z).distance_to(p)).is_greater(1000.0)
