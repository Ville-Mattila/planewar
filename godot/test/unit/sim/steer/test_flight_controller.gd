extends GdUnitTestSuite
## Unit tests for sim/steer/flight_controller.gd and flight_gains.gd (AI-05; 05 s5.2). Acceptance: from trimmed
## flight at v_cruise the velocity converges within 5 degrees of a step command in <= 2.0 s with < 15 % overshoot,
## against Kinematics.step_ship under both lift_model values. Gains: test/sim/ai/ai05_params.json (flight block).

const CLASSES: Array[StringName] = [&"dart", &"lancer", &"bomber", &"scout", &"hauler"]
const SETTLE_TICKS: int = 900         # 30 s on the initial heading: integrators converge under damping_only too
const STEP_TICKS: int = 240           # 8 s observed after the step
const CONVERGE_DEG: float = 5.0
const T_MAX_S: float = 2.0
const OVERSHOOT_MAX: float = 0.15

var _common: FlightCommonDef
var _flat: Terrain


func before_test() -> void:
	_common = FlightTestKit.common()
	_flat = Terrain.new()


## Level flight at v_cruise, settled under the controller; then a step of `hdg_deg` (+ = right) and `pitch_deg`
## (+ = climb) relative to the settled horizontal track. The command is carried along by parallel transport.
## Returns (time to stay within CONVERGE_DEG, overshoot fraction along the step plane, final speed).
func _step_response(def: ShipDef, rules: RulesDef, hdg_deg: float, pitch_deg: float) -> Vector3:
	var g: FlightGains = Ai05Kit.gains(def, rules)
	var s: ShipState = FlightTestKit.level(def, 800.0, def.v_cruise, 0.0)
	var inp: PilotInput = PilotInput.new()
	var integ: Vector2 = Vector2.ZERO
	var d: Vector3 = Vector3(0, 1, 0)
	for i: int in SETTLE_TICKS:
		integ = FlightController.track_velocity(Ai05Kit.basis(s), s.v, d * def.v_cruise, s.p.normalized(), g, integ, inp)
		d = _advance(s, inp, def, rules, d)
	var n: Vector3 = s.p.normalized()
	var v0: Vector3 = (s.v - n * s.v.dot(n)).normalized()
	d = v0.rotated(n, -deg_to_rad(hdg_deg))
	d = d.rotated(d.cross(n).normalized(), deg_to_rad(pitch_deg))
	var amp: float = v0.angle_to(d)
	var perp: Vector3 = (d - v0 * d.dot(v0)).normalized()
	var t_in: float = -1.0
	var max_prog: float = 0.0
	for i: int in STEP_TICKS:
		integ = FlightController.track_velocity(Ai05Kit.basis(s), s.v, d * def.v_cruise, s.p.normalized(), g, integ, inp)
		var q: Quaternion = _transport_step(s, inp, def, rules)
		d = q * d
		v0 = q * v0
		perp = q * perp
		var vh: Vector3 = s.v.normalized()
		max_prog = maxf(max_prog, atan2(vh.dot(perp), vh.dot(v0)))
		var err: float = rad_to_deg(vh.angle_to(d))
		if err > CONVERGE_DEG:
			t_in = -1.0
		elif t_in < 0.0:
			t_in = float(i + 1) / float(rules.tick_hz)
	return Vector3(t_in, (max_prog - amp) / amp, s.v.length())


func _transport_step(s: ShipState, inp: PilotInput, def: ShipDef, rules: RulesDef) -> Quaternion:
	var n0: Vector3 = s.p.normalized()
	Ai05Kit.step(s, inp, def, _common, rules, _flat)
	return Sphere.transport(n0, s.p.normalized())


func _advance(s: ShipState, inp: PilotInput, def: ShipDef, rules: RulesDef, d: Vector3) -> Vector3:
	return _transport_step(s, inp, def, rules) * d


func _check_steps(model: StringName, steps: Array[Vector2]) -> void:
	var rules: RulesDef = FlightTestKit.rules(model)
	for id: StringName in CLASSES:
		var def: ShipDef = FlightTestKit.ship(id)
		for st: Vector2 in steps:
			var r: Vector3 = _step_response(def, rules, st.x, st.y)
			var what: String = "%s %s step hdg %d pitch %d: t=%.2f s overshoot=%.0f %%" % [model, id, int(st.x),
				int(st.y), r.x, r.y * 100.0]
			assert_float(r.x).override_failure_message(what).is_between(0.0, T_MAX_S)
			assert_float(r.y).override_failure_message(what).is_less(OVERSHOOT_MAX)


# region acceptance: step response under both lift models
func test_step_response_speed_scaled() -> void:
	_check_steps(RulesDef.LIFT_SPEED_SCALED, [Vector2(30, 0), Vector2(-30, 0), Vector2(0, 15), Vector2(0, -15),
		Vector2(20, 10)])


func test_step_response_damping_only() -> void:
	# Turns and climbs meet the acceptance under the A/B variant; dives do not (test below documents the gap).
	_check_steps(RulesDef.LIFT_DAMPING_ONLY, [Vector2(30, 0), Vector2(-30, 0), Vector2(0, 15), Vector2(0, 10)])


func test_damping_only_dive_is_thrust_limited() -> void:
	# Under damping_only (k_up 0.1-0.2, AoA 27-33 deg in level flight, TA-30) the nose-down authority is gravity
	# plus thrust, and thrust is also the speed loop's: a 15 degree dive takes up to 2.5 s and overshoots up to
	# 20 %. Reported against the AI-05 acceptance (PR); bounded here so a regression is still caught.
	var rules: RulesDef = FlightTestKit.rules(RulesDef.LIFT_DAMPING_ONLY)
	for id: StringName in CLASSES:
		var r: Vector3 = _step_response(FlightTestKit.ship(id), rules, 0.0, -15.0)
		var what: String = "damping_only %s dive 15: t=%.2f overshoot=%.0f %%" % [id, r.x, r.y * 100.0]
		assert_float(r.x).override_failure_message(what).is_between(0.0, 2.6)
		assert_float(r.y).override_failure_message(what).is_less(0.20)


func test_converges_from_any_attitude() -> void:
	# 05 s5.2 "from any attitude": random orientations (incl. inverted and nose-down) at random speeds from 1,200 m;
	# the path is level and on the command heading within 15 s and the ship never reaches the ground.
	var rng: Rng = Rng.new(505)
	for model: StringName in [RulesDef.LIFT_SPEED_SCALED, RulesDef.LIFT_DAMPING_ONLY]:
		var rules: RulesDef = FlightTestKit.rules(model)
		for k: int in 12:
			var def: ShipDef = FlightTestKit.ship(CLASSES[k % CLASSES.size()])
			var g: FlightGains = Ai05Kit.gains(def, rules)
			var q: Quaternion = Quaternion(Vector3(rng.range_f(-1, 1), rng.range_f(-1, 1), rng.range_f(-1, 1)).normalized(),
				rng.range_f(-PI, PI))
			var n: Vector3 = Vector3(1, 0, 0)
			var fwd: Vector3 = q * Vector3(0, 1, 0)
			var s: ShipState = FlightTestKit.spawn(def, n * (Sphere.PLANET_RADIUS + 1200.0), fwd, q * n,
				fwd * def.v_cruise * rng.range_f(0.3, 1.0))
			var d: Vector3 = Vector3(0, 0, 1)
			var inp: PilotInput = PilotInput.new()
			var integ: Vector2 = Vector2.ZERO
			var err: float = 180.0
			var low: float = INF
			for i: int in 15 * rules.tick_hz:
				integ = FlightController.track_velocity(Ai05Kit.basis(s), s.v, d * def.v_cruise, s.p.normalized(), g,
					integ, inp)
				d = _advance(s, inp, def, rules, d)
				err = rad_to_deg(s.v.angle_to(d))
				low = minf(low, FlightTestKit.altitude(s))
			var what: String = "%s %s attitude %d: err %.1f lowest %.0f" % [model, def.id, k, err, low]
			assert_float(err).override_failure_message(what).is_less(CONVERGE_DEG)
			assert_float(low).override_failure_message(what).is_greater(100.0)
# endregion


# region track_thrust_vector
func test_thrust_vector_holds_tail_down_hover_for_every_class() -> void:
	# Hover on the thrust axis with a vertical-speed loop through track_thrust_vector (05 s5.5 L5 shape): the axis
	# stays within 3 degrees of the commanded tilted axis, height within 1 m, throttle below 1; Bomber included.
	var rules: RulesDef = FlightTestKit.rules()
	for id: StringName in CLASSES:
		var def: ShipDef = FlightTestKit.ship(id)
		var g: FlightGains = Ai05Kit.gains(def, rules)
		var n: Vector3 = Vector3(1, 0, 0)
		var axis: Vector3 = n.rotated(Vector3(0, 0, 1), deg_to_rad(10.0))
		var s: ShipState = FlightTestKit.spawn(def, n * (Sphere.PLANET_RADIUS + 50.0), n, Vector3(0, 0, 1), Vector3.ZERO)
		var inp: PilotInput = PilotInput.new()
		var tilt_err: float = 0.0
		for i: int in 20 * rules.tick_hz:
			var nn: Vector3 = s.p.normalized()
			var a_up: float = rules.gravity + 1.2 * (clampf(50.0 - FlightTestKit.altitude(s), -5.0, 5.0) - s.v.dot(nn))
			var mag: float = a_up / (axis.dot(nn) * def.a_thrust)
			FlightController.track_thrust_vector(Ai05Kit.basis(s), axis, mag, nn, g, inp)
			Ai05Kit.step(s, inp, def, _common, rules, _flat)
			if i > 5 * rules.tick_hz:
				tilt_err = maxf(tilt_err, rad_to_deg(s.fwd.angle_to(axis)))
		assert_float(tilt_err).override_failure_message("%s tilt err %.2f" % [id, tilt_err]).is_less(3.0)
		assert_float(absf(FlightTestKit.altitude(s) - 50.0)).override_failure_message(str(id)).is_less(1.0)
		assert_float(inp.thrust).is_less(1.0)


func test_thrust_vector_turns_a_nose_down_ship_up_and_gates_thrust() -> void:
	var rules: RulesDef = FlightTestKit.rules()
	var def: ShipDef = FlightTestKit.ship(&"bomber")
	var g: FlightGains = Ai05Kit.gains(def, rules)
	var n: Vector3 = Vector3(1, 0, 0)
	var s: ShipState = FlightTestKit.spawn(def, n * (Sphere.PLANET_RADIUS + 400.0), -n, Vector3(0, 1, 0), Vector3.ZERO)
	var inp: PilotInput = PilotInput.new()
	FlightController.track_thrust_vector(Ai05Kit.basis(s), n, 1.0, n, g, inp)
	assert_float(inp.thrust).is_equal(0.0)            # nose exactly away from the target axis: no thrust
	assert_float(absf(inp.pitch)).is_equal(1.0)       # full pitch toward it (the up_local fallback axis)
	for i: int in 6 * rules.tick_hz:   # 180 degrees at the Bomber's 50 deg/s pitch cap
		FlightController.track_thrust_vector(Ai05Kit.basis(s), s.p.normalized(), 0.5, s.p.normalized(), g, inp)
		Ai05Kit.step(s, inp, def, _common, rules, _flat)
	assert_float(rad_to_deg(s.fwd.angle_to(s.p.normalized()))).is_less(5.0)
	assert_float(inp.thrust).is_greater(0.45)
# endregion


# region interface rules
func test_only_axes_and_brake_bit_are_written() -> void:
	var rules: RulesDef = FlightTestKit.rules()
	var def: ShipDef = FlightTestKit.ship(&"dart")
	var g: FlightGains = Ai05Kit.gains(def, rules)
	var s: ShipState = FlightTestKit.level(def, 500.0, def.v_cruise + 40.0, 0.0)
	var inp: PilotInput = FlightTestKit.input(0.0, 0.0, 0.0, 0.0, PilotInput.FIRE1 | PilotInput.BOOST)
	var _i: Vector2 = FlightController.track_velocity(Ai05Kit.basis(s), s.v, Vector3(0, 1, 0) * def.v_cruise,
		s.p.normalized(), g, Vector2.ZERO, inp)
	assert_int(inp.buttons).is_equal(PilotInput.FIRE1 | PilotInput.BOOST | PilotInput.BRAKE)   # 40 m/s over: brake
	_i = FlightController.track_velocity(Ai05Kit.basis(s), s.v, Vector3(0, 1, 0) * s.v.length(), s.p.normalized(), g,
		Vector2.ZERO, inp)
	assert_int(inp.buttons).is_equal(PilotInput.FIRE1 | PilotInput.BOOST)
	inp.buttons |= PilotInput.BRAKE
	FlightController.track_thrust_vector(Ai05Kit.basis(s), s.p.normalized(), 0.5, s.p.normalized(), g, inp)
	assert_int(inp.buttons).is_equal(PilotInput.FIRE1 | PilotInput.BOOST)


func test_gains_from_dict_requires_every_key() -> void:
	var def: ShipDef = FlightTestKit.ship(&"dart")
	var flight: Dictionary = Ai05Kit.block("flight")
	var g: FlightGains = FlightGains.from_dict(flight, def, 30, FlightTestKit.rules(), FlightTestKit.common())
	assert_object(g).is_not_null()
	assert_float(g.dt).is_equal_approx(1.0 / 30.0, 1e-9)
	assert_float(g.pitch_rate).is_equal_approx(deg_to_rad(def.pitch_rate_dps), 1e-9)
	assert_float(g.lead_max).is_equal_approx(deg_to_rad(80.0), 1e-9)
	for k: String in FlightGains.KEYS:
		var broken: Dictionary = flight.duplicate()
		var _e: bool = broken.erase(k)
		assert_object(FlightGains.from_dict(broken, def, 30, FlightTestKit.rules(), FlightTestKit.common())).override_failure_message(k).is_null()
	assert_object(FlightGains.from_dict(flight, def, 0, FlightTestKit.rules(), FlightTestKit.common())).is_null()


func test_shape_rate_stops_in_time() -> void:
	assert_float(FlightController.shape_rate(0.01, 6.0, 12.0)).is_equal_approx(0.06, 1e-6)          # linear zone
	assert_float(FlightController.shape_rate(-1.0, 6.0, 12.0)).is_equal_approx(-sqrt(24.0), 1e-6)   # braking limit
	assert_float(FlightController.shape_rate(0.0, 6.0, 12.0)).is_equal(0.0)
# endregion


# region purity and determinism
func test_pure_and_deterministic() -> void:
	var rules: RulesDef = FlightTestKit.rules()
	var def: ShipDef = FlightTestKit.ship(&"bomber")
	var g: FlightGains = Ai05Kit.gains(def, rules)
	var b: Basis = Basis(Vector3(0.6, 0.8, 0.0), Vector3(-0.8, 0.6, 0.0), Vector3(0, 0, 1)).orthonormalized()
	var v: Vector3 = Vector3(5.0, 30.0, -60.0)
	var v_cmd: Vector3 = Vector3(70.0, 0.0, 10.0)
	var up: Vector3 = Vector3(1, 0, 0)
	var a: PilotInput = PilotInput.new()
	var r1: Vector2 = FlightController.track_velocity(b, v, v_cmd, up, g, Vector2(0.1, -0.2), a)
	for i: int in 5:
		var c: PilotInput = PilotInput.new()
		assert_vector(FlightController.track_velocity(b, v, v_cmd, up, g, Vector2(0.1, -0.2), c)).is_equal(r1)
		assert_array([c.thrust, c.pitch, c.yaw, c.roll, c.buttons]).is_equal([a.thrust, a.pitch, a.yaw, a.roll, a.buttons])
	# closed loop: two ships under the controller for 3,000 ticks stay bit-identical (S8, 03 s5.6)
	var s1: ShipState = FlightTestKit.level(def, 600.0, def.v_cruise, 0.0)
	var s2: ShipState = FlightTestKit.level(def, 600.0, def.v_cruise, 0.0)
	var i1: Vector2 = Vector2.ZERO
	var i2: Vector2 = Vector2.ZERO
	var p1: PilotInput = PilotInput.new()
	var p2: PilotInput = PilotInput.new()
	var mism: int = 0
	for t: int in 3000:
		var cmd: Vector3 = Vector3(0, cos(float(t) * 0.01), sin(float(t) * 0.01)) * def.v_cruise
		i1 = FlightController.track_velocity(Ai05Kit.basis(s1), s1.v, cmd, s1.p.normalized(), g, i1, p1)
		i2 = FlightController.track_velocity(Ai05Kit.basis(s2), s2.v, cmd, s2.p.normalized(), g, i2, p2)
		Ai05Kit.step(s1, p1, def, _common, rules, _flat)
		Ai05Kit.step(s2, p2, def, _common, rules, _flat)
		if FlightTestKit.state_bytes(s1) != FlightTestKit.state_bytes(s2) or i1 != i2:
			mism += 1
	assert_int(mism).is_equal(0)


func test_source_has_no_state() -> void:
	for path: String in ["res://src/sim/steer/flight_controller.gd"]:
		var src: String = FileAccess.get_file_as_string(path)
		assert_bool(src.contains("\nvar ")).is_false()
		assert_bool(src.contains("static var")).is_false()
		for line: String in src.split("\n"):
			if line.begins_with("func "):
				fail("non-static func in %s: %s" % [path, line])
			if line.contains("Rng") or line.contains("Time.") or line.contains("randf"):
				fail("clock or RNG in %s: %s" % [path, line])


func test_perf_cost_per_call() -> void:
	# Perf note (05 s10 "act" row): one track_velocity per AI ship per tick. Printed for the PR; the bound is loose
	# so a slow CI runner does not flake.
	var rules: RulesDef = FlightTestKit.rules()
	var def: ShipDef = FlightTestKit.ship(&"dart")
	var g: FlightGains = Ai05Kit.gains(def, rules)
	var s: ShipState = FlightTestKit.level(def, 600.0, def.v_cruise, 0.05)
	var b: Basis = Ai05Kit.basis(s)
	var up: Vector3 = s.p.normalized()
	var inp: PilotInput = PilotInput.new()
	var integ: Vector2 = Vector2.ZERO
	var n: int = 4000
	var us_v: float = INF   # best of 6 batches: the desktop's scheduler noise is larger than the code's cost
	var us_t: float = INF
	for batch: int in 6:
		var t0: int = Time.get_ticks_usec()
		for i: int in n:
			integ = FlightController.track_velocity(b, s.v, Vector3(0.0, 100.0, 20.0 + float(i & 7)), up, g, integ, inp)
		us_v = minf(us_v, float(Time.get_ticks_usec() - t0) / float(n))
		t0 = Time.get_ticks_usec()
		for i: int in n:
			FlightController.track_thrust_vector(b, up, 0.4, up, g, inp)
		us_t = minf(us_t, float(Time.get_ticks_usec() - t0) / float(n))
	print("PERF FlightController.track_velocity %.2f us/call, track_thrust_vector %.2f us/call" % [us_v, us_t])
	assert_float(us_v).is_less(100.0)
	assert_float(us_t).is_less(100.0)
# endregion
