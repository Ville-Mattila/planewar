extends GdUnitTestSuite
## AI-38: the lift-law parts of sim/steer/flight_controller.gd and flight_gains.gd (05 s5.2, s5.3 as amended):
## the weight-support throttle floor, the lift-optimal nose-lead cap, the best-climb PULL_UP attitude and the
## pull-up budget, under both lift models (R0 B.12 A-68: one law, the lift model is physics, not a gain set).

const MODELS: Array[StringName] = [RulesDef.LIFT_SPEED_SCALED, RulesDef.LIFT_DAMPING_ONLY]

var _common: FlightCommonDef
var _flat: Terrain


func before_test() -> void:
	_common = FlightTestKit.common()
	_flat = Terrain.new()


# Dart diving `dive_deg` (nose along the velocity) at `agl` m over flat ground, `speed` m/s, wings level.
func _dive(def: ShipDef, agl: float, dive_deg: float, speed: float) -> ShipState:
	var n: Vector3 = Vector3(1, 0, 0)
	var a: float = deg_to_rad(dive_deg)
	var fwd: Vector3 = Vector3(0, 1, 0) * cos(a) - n * sin(a)
	return FlightTestKit.spawn(def, n * (Sphere.PLANET_RADIUS + agl), fwd, n, fwd * speed)


# Brute-force argmax of climb_accel over [0, 90] degrees (0.25 degree grid).
func _best_climb(v: Vector3, h: Vector3, n: Vector3, g: FlightGains) -> float:
	var best: float = 0.0
	var best_a: float = -INF
	for j: int in 361:
		var th: float = deg_to_rad(0.25 * float(j))
		var a: float = FlightController.climb_accel(v, h, n, th, g)
		if a > best_a:
			best_a = a
			best = th
	return best


# region FlightGains
func test_gains_carry_the_lift_law_and_refuse_missing_defs() -> void:
	var def: ShipDef = FlightTestKit.ship(&"dart")
	var rules: RulesDef = FlightTestKit.rules()
	var flight: Dictionary = Ai05Kit.block("flight")
	var g: FlightGains = FlightGains.from_dict(flight, def, 30, rules, _common)
	assert_object(g.ship).is_same(def)
	assert_object(g.rules).is_same(rules)
	assert_object(g.common).is_same(_common)
	assert_float(g.stop_angle).is_equal_approx(g.pitch_rate * g.pitch_rate / (2.0 * g.rate_accel), 1e-6)
	assert_int(g.lead_best.size()).is_equal(FlightGains.LEAD_TABLE_SIZE * FlightGains.LEAD_ERR_SIZE)
	assert_object(FlightGains.from_dict(flight, def, 30, null, _common)).is_null()
	assert_object(FlightGains.from_dict(flight, def, 30, rules, null)).is_null()
# endregion


# region weight-support floor
func test_weight_support_throttle_follows_the_lift_law() -> void:
	# Level path at 80 m/s (below the thrust-fade knee), nose 20 degrees up: the floor is the throttle whose radial
	# thrust carries what the best wing lift at that speed (any AoA) leaves of gravity.
	var def: ShipDef = FlightTestKit.ship(&"dart")
	var alpha: float = deg_to_rad(20.0)
	var u: float = 80.0
	var s: ShipState = FlightTestKit.level(def, 500.0, u, alpha)
	var n: Vector3 = s.p.normalized()
	for model: StringName in MODELS:
		var rules: RulesDef = FlightTestKit.rules(model)
		var g: FlightGains = Ai05Kit.gains(def, rules)
		var best: float = 0.0
		for k: int in 901:
			var a: float = deg_to_rad(0.1 * float(k))
			best = maxf(best, Kinematics.k_up_effective(u * cos(a), def, rules) * u * sin(a) * cos(a))
		assert_float(FlightController.lift_best(u, g)).override_failure_message(str(model)).is_equal_approx(best, 0.05 * best)
		var want: float = clampf((rules.gravity - FlightController.lift_best(u, g)) / (def.a_thrust * sin(alpha)), 0.0, 1.0)
		var ws: float = FlightController.weight_support_throttle(Ai05Kit.basis(s), s.v, n, g)
		assert_float(ws).override_failure_message(str(model)).is_equal_approx(want, 1e-4)
	var damping: FlightGains = Ai05Kit.gains(def, FlightTestKit.rules(RulesDef.LIFT_DAMPING_ONLY))
	var scaled: FlightGains = Ai05Kit.gains(def, FlightTestKit.rules(RulesDef.LIFT_SPEED_SCALED))
	assert_float(FlightController.lift_best(u, damping)).is_equal_approx(def.k_up * u * 0.5, 0.01)   # k_up u / 2
	assert_float(FlightController.weight_support_throttle(Ai05Kit.basis(s), s.v, n, damping)).is_greater(0.2)
	assert_float(FlightController.weight_support_throttle(Ai05Kit.basis(s), s.v, n, scaled)).is_equal(0.0)
	var down: ShipState = FlightTestKit.level(def, 500.0, u, deg_to_rad(-10.0))   # nose below the horizon
	assert_float(FlightController.weight_support_throttle(Ai05Kit.basis(down), down.v, n, damping)).is_equal(0.0)


func test_track_velocity_keeps_the_floor_while_decelerating_and_drops_it_to_descend() -> void:
	# damping_only, 110 m/s level, nose 30 degrees up, commanded 40 m/s: the speed loop alone cuts the throttle to 0
	# (the AI-06 approach crash); the floor holds the weight. A command 10 degrees down fades the floor out.
	# kp_turn_thrust 0 here so the turn term does not mask the floor.
	var def: ShipDef = FlightTestKit.ship(&"dart")
	var rules: RulesDef = FlightTestKit.rules(RulesDef.LIFT_DAMPING_ONLY)
	var flight: Dictionary = Ai05Kit.block("flight").duplicate()
	flight["kp_turn_thrust"] = 0.0
	var g: FlightGains = FlightGains.from_dict(flight, def, rules.tick_hz, rules, _common)
	var s: ShipState = FlightTestKit.level(def, 500.0, def.v_cruise, deg_to_rad(30.0))
	var n: Vector3 = s.p.normalized()
	var east: Vector3 = Vector3(0, 1, 0)
	var ws: float = FlightController.weight_support_throttle(Ai05Kit.basis(s), s.v, n, g)
	assert_float(ws).is_greater(0.05)   # wing lift at best k_up u / 2 = 5.5 m/s^2 of the 6
	var inp: PilotInput = PilotInput.new()
	var _i: Vector2 = FlightController.track_velocity(Ai05Kit.basis(s), s.v, east * 40.0, n, g, Vector2.ZERO, inp)
	assert_float(inp.thrust).is_equal_approx(ws, 1e-5)
	var down: Vector3 = (east * cos(deg_to_rad(10.0)) - n * sin(deg_to_rad(10.0))) * 40.0
	_i = FlightController.track_velocity(Ai05Kit.basis(s), s.v, down, n, g, Vector2.ZERO, inp)
	assert_float(inp.thrust).is_equal(0.0)


func test_damping_only_deceleration_holds_the_path() -> void:
	# Closed loop with the AI-06 recommended damping_only set (test/tuning/recommended_gains.json): settled level at
	# v_cruise, then a level 45 m/s command for 20 s (an approach deceleration). The throttle never sits at 0 while
	# the floor is positive; the sag is 137.9 m (165.6 m before AI-38) and the path is back within 5 degrees.
	# (At the AI-05 anchors, lead_max 80, the run still meets the ground: the gain limit AI-06 found.)
	var def: ShipDef = FlightTestKit.ship(&"dart")
	var rules: RulesDef = FlightTestKit.rules(RulesDef.LIFT_DAMPING_ONLY)
	var rec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://test/tuning/recommended_gains.json"))
	var flight: Dictionary = Ai05Kit.block("flight").duplicate()
	flight.merge(((rec["damping_only"] as Dictionary)["flight"] as Dictionary), true)
	var g: FlightGains = FlightGains.from_dict(flight, def, rules.tick_hz, rules, _common)
	var s: ShipState = FlightTestKit.level(def, 800.0, def.v_cruise, 0.0)
	var inp: PilotInput = PilotInput.new()
	var integ: Vector2 = Vector2.ZERO
	var d: Vector3 = Vector3(0, 1, 0)
	for i: int in 900:
		integ = FlightController.track_velocity(Ai05Kit.basis(s), s.v, d * def.v_cruise, s.p.normalized(), g, integ, inp)
		d = _step(s, inp, def, rules) * d
	var h0: float = FlightTestKit.altitude(s)
	var low: float = INF
	var unsupported: int = 0
	for i: int in 20 * rules.tick_hz:
		var n: Vector3 = s.p.normalized()
		var ws: float = FlightController.weight_support_throttle(Ai05Kit.basis(s), s.v, n, g)
		integ = FlightController.track_velocity(Ai05Kit.basis(s), s.v, d * 45.0, n, g, integ, inp)
		if inp.thrust <= 0.0 and ws > 0.0:
			unsupported += 1
		d = _step(s, inp, def, rules) * d
		low = minf(low, FlightTestKit.altitude(s))
	var path: float = rad_to_deg(asin(s.v.normalized().dot(s.p.normalized())))
	print("AI-38 damping_only 110 -> 45 m/s level: sag %.1f m, speed %.1f, path %.1f deg" % [h0 - low, s.v.length(), path])
	assert_int(unsupported).is_equal(0)
	assert_float(h0 - low).is_less(150.0)
	assert_float(absf(path)).is_less(5.0)


func _step(s: ShipState, inp: PilotInput, def: ShipDef, rules: RulesDef) -> Quaternion:
	var n0: Vector3 = s.p.normalized()
	Ai05Kit.step(s, inp, def, _common, rules, _flat)
	return Sphere.transport(n0, s.p.normalized())
# endregion


# region lead cap
func test_best_lead_matches_a_brute_force_search_and_the_lift_law() -> void:
	var def: ShipDef = FlightTestKit.ship(&"dart")
	for model: StringName in MODELS:
		var g: FlightGains = Ai05Kit.gains(def, FlightTestKit.rules(model))
		for i: int in [2, 6, 9, 12]:
			for j: int in [0, 2, 5]:
				var u: float = float(i) * g.lead_du
				var err: float = float(j) * g.lead_de
				var best: float = 0.0
				var best_a: float = -INF
				for k: int in 721:
					var a: float = FlightController.turn_accel(u, deg_to_rad(0.25 * float(k)), err, g)
					if a > best_a:
						best_a = a
						best = deg_to_rad(0.25 * float(k))
				var what: String = "%s u %.0f err %.0f: table %.1f brute %.1f" % [model, u, rad_to_deg(err),
					rad_to_deg(FlightController.best_lead(u, err, g)), rad_to_deg(best)]
				assert_float(rad_to_deg(absf(FlightController.best_lead(u, err, g) - best))) \
					.override_failure_message(what).is_less(2.0)
	# At a Dart's cruise and no path error: the speed_scaled lift stalls near 40 degrees, damping_only turns on thrust.
	var sc: FlightGains = Ai05Kit.gains(def, FlightTestKit.rules(RulesDef.LIFT_SPEED_SCALED))
	var dm: FlightGains = Ai05Kit.gains(def, FlightTestKit.rules(RulesDef.LIFT_DAMPING_ONLY))
	assert_float(rad_to_deg(FlightController.best_lead(def.v_cruise, 0.0, sc))).is_between(30.0, 55.0)
	assert_float(rad_to_deg(FlightController.best_lead(def.v_cruise, 0.0, dm))).is_greater(60.0)
	assert_float(FlightController.best_lead(def.v_cruise, 1.5, sc)).is_greater(FlightController.best_lead(def.v_cruise, 0.0, sc))


func test_lead_cap_opens_to_lead_max_with_overspeed() -> void:
	var def: ShipDef = FlightTestKit.ship(&"dart")
	var g: FlightGains = Ai05Kit.gains(def, FlightTestKit.rules(RulesDef.LIFT_SPEED_SCALED))
	var best: float = FlightController.best_lead(def.v_cruise, 0.0, g)
	assert_float(best).is_less(g.lead_max)
	assert_float(FlightController.lead_cap(def.v_cruise, 0.0, 5.0, g)).is_equal_approx(best, 1e-6)
	assert_float(FlightController.lead_cap(def.v_cruise, 0.0, -g.brake_overspeed, g)).is_equal_approx(g.lead_max, 1e-6)
	assert_float(FlightController.lead_cap(def.v_cruise, 0.0, -0.5 * g.brake_overspeed, g)) \
		.is_equal_approx(0.5 * (best + g.lead_max), 1e-6)
	var slow: float = FlightController.best_lead(5.0, 0.0, g)   # no lift at walking pace: thrust turns, cap = lead_max
	assert_float(FlightController.lead_cap(5.0, 0.0, 0.0, g)).is_equal_approx(minf(slow, g.lead_max), 1e-6)
# endregion


# region PULL_UP
func test_pull_up_elevation_tracks_the_best_climb() -> void:
	# The nose following the target from a 40 degree dive converges on the brute-force best-climb elevation; under
	# speed_scaled it is far below "nose to local up", under damping_only (thrust is the lift) much higher.
	var def: ShipDef = FlightTestKit.ship(&"dart")
	var s: ShipState = _dive(def, 300.0, 40.0, 95.0)
	var n: Vector3 = s.p.normalized()
	var h: Vector3 = FlightController.pull_up_plane(Ai05Kit.basis(s), s.v, n)
	var got: Dictionary = {}
	for model: StringName in MODELS:
		var g: FlightGains = Ai05Kit.gains(def, FlightTestKit.rules(model))
		var th: float = deg_to_rad(-40.0)
		for i: int in 40:
			var tgt: float = FlightController.pull_up_elevation(s.v, h, n, th, g)
			th += clampf(tgt - th, -g.pitch_rate * g.dt, g.pitch_rate * g.dt)
		var want: float = _best_climb(s.v, h, n, g)
		got[model] = th
		assert_float(rad_to_deg(absf(th - want))).override_failure_message("%s %.1f vs %.1f" % [model, rad_to_deg(th),
			rad_to_deg(want)]).is_less(3.0)
	assert_float(rad_to_deg(float(got[RulesDef.LIFT_SPEED_SCALED]))).is_less(45.0)
	assert_float(rad_to_deg(float(got[RulesDef.LIFT_DAMPING_ONLY]))).is_greater(50.0)


func test_pull_up_gates_thrust_levels_the_wings_and_leaves_buttons() -> void:
	var def: ShipDef = FlightTestKit.ship(&"dart")
	var g: FlightGains = Ai05Kit.gains(def, FlightTestKit.rules())
	var s: ShipState = _dive(def, 200.0, 30.0, 100.0)
	s.up = s.up.rotated(s.fwd, deg_to_rad(40.0))   # banked
	var inp: PilotInput = FlightTestKit.input(0.3, 0.0, 0.0, 0.0, PilotInput.FIRE1)
	FlightController.pull_up(Ai05Kit.basis(s), s.v, s.p.normalized(), g, inp)
	assert_float(inp.thrust).is_equal(0.0)          # nose below the horizon
	assert_float(inp.pitch).is_greater(0.0)
	assert_float(absf(inp.roll)).is_greater(0.0)    # rolling back toward wings level
	assert_int(inp.buttons).is_equal(PilotInput.FIRE1)
	var up: ShipState = FlightTestKit.level(def, 200.0, 80.0, deg_to_rad(15.0))
	FlightController.pull_up(Ai05Kit.basis(up), up.v - up.p.normalized() * 30.0, up.p.normalized(), g, inp)
	assert_float(inp.thrust).is_equal(1.0)


func test_pull_up_saves_a_steep_dive_that_nose_to_up_does_not() -> void:
	# speed_scaled, 43 degrees down at 96 m/s from 101 m (the AI-06 sweep's seed 104): 05's "nose to local up,
	# thrust 1" meets the ground, the best-climb attitude does not.
	var def: ShipDef = FlightTestKit.ship(&"dart")
	var rules: RulesDef = FlightTestKit.rules(RulesDef.LIFT_SPEED_SCALED)
	var g: FlightGains = Ai05Kit.gains(def, rules)
	var hits: Array[bool] = []
	for law: int in 2:
		var s: ShipState = _dive(def, 101.0, 43.0, 96.0)
		var inp: PilotInput = PilotInput.new()
		var hit: bool = false
		for i: int in 6 * rules.tick_hz:
			var n: Vector3 = s.p.normalized()
			if law == 0:
				FlightController.track_thrust_vector(Ai05Kit.basis(s), n, 1.0, n, g, inp)
				inp.thrust = 1.0
			else:
				FlightController.pull_up(Ai05Kit.basis(s), s.v, n, g, inp)
			Ai05Kit.step(s, inp, def, _common, rules, _flat)
			hit = hit or s.terrain_hit
		hits.append(hit)
	assert_array(hits).is_equal([true, false])


func test_pull_up_loss_bounds_the_height_lost() -> void:
	# The budget is 0 while climbing and, from tick 0 of a pull-up, at least the height actually lost (it assumes
	# gravity alone while the nose turns) and not wildly more (< 2.5x), for dives under both lift models.
	var def: ShipDef = FlightTestKit.ship(&"dart")
	for model: StringName in MODELS:
		var rules: RulesDef = FlightTestKit.rules(model)
		var g: FlightGains = Ai05Kit.gains(def, rules)
		var lvl: ShipState = FlightTestKit.level(def, 500.0, 90.0, 0.1)
		assert_float(FlightController.pull_up_loss(Ai05Kit.basis(lvl), lvl.v, lvl.p.normalized(), g)).is_equal(0.0)
		for dive: float in [15.0, 30.0, 45.0]:
			var s: ShipState = _dive(def, 1000.0, dive, 100.0)
			var est: float = FlightController.pull_up_loss(Ai05Kit.basis(s), s.v, s.p.normalized(), g)
			var h0: float = FlightTestKit.altitude(s)
			var low: float = h0
			var inp: PilotInput = PilotInput.new()
			for i: int in 10 * rules.tick_hz:
				FlightController.pull_up(Ai05Kit.basis(s), s.v, s.p.normalized(), g, inp)
				Ai05Kit.step(s, inp, def, _common, rules, _flat)
				low = minf(low, FlightTestKit.altitude(s))
			var what: String = "%s dive %d: estimate %.1f lost %.1f" % [model, int(dive), est, h0 - low]
			assert_float(est).override_failure_message(what).is_greater_equal(h0 - low)
			assert_float(est).override_failure_message(what).is_less(2.5 * (h0 - low))
# endregion


func test_perf_lift_law_calls() -> void:
	# Perf note: weight_support_throttle and lead_cap run inside every track_velocity (act row); pull_up and
	# pull_up_loss only in a pull-up / its act-time check. Best of 6 batches; loose bound.
	var def: ShipDef = FlightTestKit.ship(&"dart")
	var g: FlightGains = Ai05Kit.gains(def, FlightTestKit.rules())
	var s: ShipState = _dive(def, 200.0, 30.0, 100.0)
	var b: Basis = Ai05Kit.basis(s)
	var n: Vector3 = s.p.normalized()
	var inp: PilotInput = PilotInput.new()
	var n_calls: int = 4000
	var us: PackedFloat64Array = PackedFloat64Array([INF, INF, INF])
	var sink: float = 0.0
	for batch: int in 6:
		var t0: int = Time.get_ticks_usec()
		for i: int in n_calls:
			sink += FlightController.weight_support_throttle(b, s.v, n, g) + FlightController.lead_cap(90.0, 0.3, 1.0, g)
		us[0] = minf(us[0], float(Time.get_ticks_usec() - t0) / float(n_calls))
		t0 = Time.get_ticks_usec()
		for i: int in n_calls:
			FlightController.pull_up(b, s.v, n, g, inp)
		us[1] = minf(us[1], float(Time.get_ticks_usec() - t0) / float(n_calls))
		t0 = Time.get_ticks_usec()
		for i: int in n_calls:
			sink += FlightController.pull_up_loss(b, s.v, n, g)
		us[2] = minf(us[2], float(Time.get_ticks_usec() - t0) / float(n_calls))
	print("PERF AI-38 floor+lead_cap %.2f us, pull_up %.2f us, pull_up_loss %.2f us (%.0f)" % [us[0], us[1], us[2], sink])
	_assert_bounds(us)


func _assert_bounds(us: PackedFloat64Array) -> void:
	for x: float in us:
		assert_float(x).is_less(100.0)
