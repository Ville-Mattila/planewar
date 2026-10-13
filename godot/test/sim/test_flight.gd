extends GdUnitTestSuite
## Sim-layer flight scenarios for Kinematics (TA-12): 10,000-tick replay determinism, great-circle cruise,
## tail-down hover for Dart and Bomber (O-2), 30 degree tilt authority.

var _common: FlightCommonDef
var _rules: RulesDef
var _flat: Terrain
var _dt: float


func before_test() -> void:
	_common = FlightTestKit.common()
	_rules = FlightTestKit.rules()
	_flat = Terrain.new()
	_dt = FlightTestKit.dt(_rules)


func _step(s: ShipState, inp: PilotInput, def: ShipDef) -> void:
	var _r: ShipState = Kinematics.step_ship(s, inp, def, _common, _rules, _flat, _dt)


func test_replay_10000_ticks_is_bit_identical() -> void:
	var dart: ShipDef = FlightTestKit.ship(&"dart")
	var inputs: Array[PilotInput] = FlightTestKit.random_inputs(9001, 10000)
	var a: ShipState = FlightTestKit.level(dart, 1200.0, dart.v_cruise, 0.0)
	var b: ShipState = FlightTestKit.level(dart, 1200.0, dart.v_cruise, 0.0)
	var mismatches: int = 0
	for i: int in inputs.size():
		_step(a, inputs[i], dart)
		_step(b, inputs[i], dart)
		if FlightTestKit.state_bytes(a) != FlightTestKit.state_bytes(b):
			mismatches += 1
	assert_int(mismatches).is_equal(0)
	assert_bool(is_finite(a.p.length()) and is_finite(a.v.length())).is_true()


func test_great_circle_cruise_stays_on_the_circle_at_constant_altitude() -> void:
	# 90 s of autopilot-held level cruise heading east from (R + 300, 0, 0): the track stays in the equatorial
	# plane (parallel transport keeps the heading on the great circle) at 300 m +-1 m, covering ~v * t.
	var dart: ShipDef = FlightTestKit.ship(&"dart")
	var v: float = 0.9 * dart.v_cruise
	var trim: float = _rules.gravity / (v * Kinematics.k_up_effective(v, dart, _rules))
	var s: ShipState = FlightTestKit.level(dart, 300.0, v, trim)
	var p0: Vector3 = s.p
	var inp: PilotInput = PilotInput.new()
	var off_plane: float = 0.0
	var h_err: float = 0.0
	var n_ticks: int = 90 * _rules.tick_hz
	for i: int in n_ticks:
		var _i: PilotInput = FlightTestKit.level_hold(s, dart, _rules, 300.0, v, inp)
		_step(s, inp, dart)
		off_plane = maxf(off_plane, absf(s.p.z))
		h_err = maxf(h_err, absf(FlightTestKit.altitude(s) - 300.0))
	var arc: float = Sphere.great_circle(p0, s.p)
	assert_float(off_plane).is_less(0.01)
	assert_float(h_err).is_less_equal(1.0)
	assert_float(arc).is_between(0.95 * v * n_ticks * _dt, 1.05 * v * n_ticks * _dt)
	assert_float(s.fwd.dot(s.p.normalized())).is_less(0.2)        # still flying level, not climbing


func test_dart_and_bomber_hold_a_tail_down_hover() -> void:
	for id: StringName in [&"dart", &"bomber"]:
		var def: ShipDef = FlightTestKit.ship(id)
		var n: Vector3 = Vector3(1, 0, 0)
		var s: ShipState = FlightTestKit.spawn(def, n * (Sphere.PLANET_RADIUS + 50.0), n, Vector3(0, 0, 1),
			Vector3.ZERO)
		var inp: PilotInput = PilotInput.new()
		var h_err: float = 0.0
		var tilt: float = 0.0
		for i: int in 30 * _rules.tick_hz:
			var _i: PilotInput = FlightTestKit.hover_hold(s, def, _rules, s.p.normalized(), 50.0, 0.0, true, inp)
			_step(s, inp, def)
			h_err = maxf(h_err, absf(FlightTestKit.altitude(s) - 50.0))
			tilt = maxf(tilt, rad_to_deg(s.fwd.angle_to(s.p.normalized())))
		assert_float(h_err).is_less_equal(1.0)
		assert_float(tilt).is_less_equal(_common.landing_safe_pitch_deg)
		assert_float(inp.thrust).is_less(1.0)
		assert_float(s.fuel).is_greater(0.0)


func test_tail_down_hover_has_30_degree_tilt_authority() -> void:
	# 03 s5.3 hover check: a_thrust >= 2 g leaves >= 30 degrees of tilt authority (Bomber is the floor).
	for id: StringName in [&"dart", &"bomber"]:
		var def: ShipDef = FlightTestKit.ship(id)
		var tilt: float = deg_to_rad(30.0)
		var n: Vector3 = Vector3(1, 0, 0)
		var axis0: Vector3 = n * cos(tilt) + Vector3(0, 1, 0) * sin(tilt)
		var s: ShipState = FlightTestKit.spawn(def, n * (Sphere.PLANET_RADIUS + 50.0), axis0, Vector3(0, 0, 1),
			Vector3.ZERO)
		var inp: PilotInput = PilotInput.new()
		var h_err: float = 0.0
		var thr_max: float = 0.0
		for i: int in 5 * _rules.tick_hz:
			var axis: Vector3 = s.p.normalized() * cos(tilt) + Sphere.tangent_frame(s.p).x * sin(tilt)
			var _i: PilotInput = FlightTestKit.hover_hold(s, def, _rules, axis, 50.0, 0.0, true, inp)
			_step(s, inp, def)
			h_err = maxf(h_err, absf(FlightTestKit.altitude(s) - 50.0))
			thr_max = maxf(thr_max, inp.thrust)
		assert_float(h_err).is_less_equal(1.0)
		assert_float(thr_max).is_less(1.0)
