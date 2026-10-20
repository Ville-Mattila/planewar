extends GdUnitTestSuite
## AI-41: the shipped `FlightController.track_velocity` (AI-38 review rounds: 5961ff9 skips / inlined lookup /
## cached constants, 94c0272 integ_band 0 guard) is bit-identical to the ded8b4e law (`FlightControllerRefAi38`)
## under both lift models, for the AI-05 anchors and both `recommended_gains.json` sets, open-loop over random
## states and closed-loop down a landing approach (glide, deceleration to hover speeds, below floor_u_max).

const MODELS: Array[StringName] = [RulesDef.LIFT_SPEED_SCALED, RulesDef.LIFT_DAMPING_ONLY]
const RECOMMENDED: String = "res://test/tuning/recommended_gains.json"
const AI38_GIVEN: String = "res://test/tuning/ai38_given.json"
const FUZZ_CASES: int = 3000

var _common: FlightCommonDef
var _def: ShipDef
var _floor_ticks: int = 0   ## approach ticks where the weight-support floor is non-zero (coverage)


func before_test() -> void:
	_common = FlightTestKit.common()
	_def = FlightTestKit.ship(&"dart")


# Gain sets: AI-05 anchors, the two recommended override sets, and integ_band_deg 0 (the 94c0272 guard).
func _flight_sets() -> Array[Dictionary]:
	var rec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(RECOMMENDED)) as Dictionary
	var out: Array[Dictionary] = []
	for over: Dictionary in [{}, (rec["damping_only"] as Dictionary)["flight"], (rec["speed_scaled"] as Dictionary)["flight"],
			{"integ_band_deg": 0.0}]:
		var d: Dictionary = Ai05Kit.block("flight").duplicate()
		d.merge(over, true)
		out.append(d)
	return out


func _same(label: String, b: Basis, v: Vector3, v_cmd: Vector3, n: Vector3, g: FlightGains, integ: Vector2) -> bool:
	var a: PilotInput = PilotInput.new()
	var r: PilotInput = PilotInput.new()
	var ia: Vector2 = FlightController.track_velocity(b, v, v_cmd, n, g, integ, a)
	var ir: Vector2 = FlightControllerRefAi38.track_velocity(b, v, v_cmd, n, g, integ, r)
	var got: Array = [ia, a.thrust, a.pitch, a.yaw, a.roll, a.buttons]
	var want: Array = [ir, r.thrust, r.pitch, r.yaw, r.roll, r.buttons]
	assert_array(got).override_failure_message("%s: %s != ded8b4e %s" % [label, got, want]).is_equal(want)
	return got == want


func test_track_velocity_matches_ded8b4e_on_random_states() -> void:
	var rng: Rng = Rng.new(4141)
	var checked: int = 0
	var floored: int = 0
	for model: StringName in MODELS:
		var rules: RulesDef = FlightTestKit.rules(model)
		for flight: Dictionary in _flight_sets():
			var g: FlightGains = FlightGains.from_dict(flight, _def, rules.tick_hz, rules, _common)
			var u_top: float = minf(g.floor_u_max, _def.v_cruise * 2.0)
			for k: int in FUZZ_CASES:
				var n: Vector3 = _unit(rng)
				var fwd: Vector3 = _unit(rng)
				var up: Vector3 = _unit(rng).cross(fwd)
				if up.length_squared() < 0.01:
					continue
				var s: ShipState = FlightTestKit.spawn(_def, n * Sphere.PLANET_RADIUS, fwd, up, Vector3.ZERO)
				# half the cases below floor_u_max (the floor's regime), velocity near the nose or anywhere
				var u: float = rng.range_f(0.0, u_top) if k % 2 == 0 else rng.range_f(0.0, _def.v_cruise * 2.0)
				var vdir: Vector3 = (fwd * rng.range_f(0.0, 3.0) + _unit(rng)).normalized()
				var v_cmd: Vector3 = (vdir * rng.range_f(0.0, 2.0) + _unit(rng)).normalized() * rng.range_f(0.0, 150.0)
				var integ: Vector2 = Vector2(rng.range_f(-g.integ_max, g.integ_max), rng.range_f(-1.0, 1.0))
				if FlightControllerRefAi38.weight_support_throttle(Ai05Kit.basis(s), vdir * u, n, g) > 0.0:
					floored += 1
				if not _same("%s case %d / %d" % [model, checked, k], Ai05Kit.basis(s), vdir * u, v_cmd, n, g, integ):
					return
				checked += 1
	assert_float(float(checked)).is_greater(0.9 * float(MODELS.size() * 4 * FUZZ_CASES))
	assert_int(floored).is_greater(1000)   # the weight-support floor is exercised, not just skipped


func test_track_velocity_matches_ded8b4e_down_a_landing_approach() -> void:
	# Closed loop: the shipped law and the reference each fly their own Dart from 3 km out, 300 m up, at v_cruise,
	# down a glide toward the pad while the speed command ramps to hover speeds. Every tick's input and state must
	# match bit for bit, so any divergence shows at its first tick.
	var ticks: int = 0
	for model: StringName in MODELS:
		var rules: RulesDef = FlightTestKit.rules(model)
		var flat: Terrain = Terrain.new()
		for flight: Dictionary in _flight_sets():
			var g: FlightGains = FlightGains.from_dict(flight, _def, rules.tick_hz, rules, _common)
			ticks += _fly_approach(model, g, rules, flat)
	assert_int(ticks).is_greater(MODELS.size() * 4 * 30 * 30)
	assert_int(_floor_ticks).is_greater(MODELS.size() * 4 * 30 * 5)   # the slow end flies on the floor


# One approach under one gain set; returns the ticks compared.
func _fly_approach(model: StringName, g: FlightGains, rules: RulesDef, flat: Terrain) -> int:
	var pad: Vector3 = Vector3(0, 0, 1)
	var start_n: Vector3 = Vector3(0, sin(3000.0 / Sphere.PLANET_RADIUS), cos(3000.0 / Sphere.PLANET_RADIUS))
	var fwd: Vector3 = (pad - start_n * pad.dot(start_n)).normalized()
	var p0: Vector3 = start_n * (Sphere.PLANET_RADIUS + 300.0)
	var a: ShipState = FlightTestKit.spawn(_def, p0, fwd, start_n, fwd * _def.v_cruise)
	var r: ShipState = FlightTestKit.spawn(_def, p0, fwd, start_n, fwd * _def.v_cruise)
	var ia: Vector2 = Vector2.ZERO
	var ir: Vector2 = Vector2.ZERO
	var in_a: PilotInput = PilotInput.new()
	var in_r: PilotInput = PilotInput.new()
	var n_ticks: int = 60 * rules.tick_hz
	for t: int in n_ticks:
		if FlightControllerRefAi38.weight_support_throttle(Ai05Kit.basis(r), r.v, r.p.normalized(), g) > 0.0:
			_floor_ticks += 1
		var n: Vector3 = a.p.normalized()
		var f: float = float(t) / float(n_ticks)
		var h: Vector3 = pad - n * pad.dot(n)
		h = h.normalized() if h.length_squared() > 1e-8 else Vector3.ZERO
		var alt_err: float = lerpf(300.0, 60.0, f) - (a.p.length() - Sphere.PLANET_RADIUS)
		var v_cmd: Vector3 = h * lerpf(_def.v_cruise, 8.0, f) + n * clampf(0.2 * alt_err, -15.0, 10.0)
		ia = FlightController.track_velocity(Ai05Kit.basis(a), a.v, v_cmd, n, g, ia, in_a)
		ir = FlightControllerRefAi38.track_velocity(Ai05Kit.basis(r), r.v, v_cmd, n, g, ir, in_r)
		var got: Array = [ia, in_a.thrust, in_a.pitch, in_a.yaw, in_a.roll, in_a.buttons, a.p, a.v, a.fwd, a.up]
		var want: Array = [ir, in_r.thrust, in_r.pitch, in_r.yaw, in_r.roll, in_r.buttons, r.p, r.v, r.fwd, r.up]
		if got != want:
			assert_array(got).override_failure_message("%s tick %d" % [model, t]).is_equal(want)
			return t
		Ai05Kit.step(a, in_a, _def, _common, rules, flat)
		Ai05Kit.step(r, in_r, _def, _common, rules, flat)
		if a.terrain_hit:
			return t + 1
	return n_ticks


func test_ai38_given_is_the_recommended_damping_only_set_for_both_models() -> void:
	# reports/ai38/after_*.csv come from `gain_sweep --given` on ai38_given.json (AI-41: --given recommended_gains.json
	# flies speed_scaled on its own set and does not reproduce them); the file must not drift from the recommendation.
	var rec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(RECOMMENDED)) as Dictionary
	var given: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(AI38_GIVEN)) as Dictionary
	for model: StringName in MODELS:
		assert_dict(given[str(model)] as Dictionary).is_equal(rec["damping_only"] as Dictionary)


func _unit(rng: Rng) -> Vector3:
	return Vector3(rng.range_f(-1.0, 1.0), rng.range_f(-1.0, 1.0), rng.range_f(-1.0, 1.0)).normalized()
