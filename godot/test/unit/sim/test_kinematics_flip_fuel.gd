extends GdUnitTestSuite
## TA-48 (R0 B.9 A-29, A-32; 02 s2.2-2.3): flip velocity redirect with `flip_speed_retain`, fuel burn per mode,
## empty tank, determinism. Def values: canonical fixture via FlightTestKit (R0 B.1, 02 s2.2 flight_common).

const STEPS: int = 3000

var _dart: ShipDef
var _bomber: ShipDef
var _common: FlightCommonDef
var _rules: RulesDef
var _flat: Terrain
var _dt: float
var _idle: PilotInput


func before_test() -> void:
	_dart = FlightTestKit.ship(&"dart")
	_bomber = FlightTestKit.ship(&"bomber")
	_common = FlightTestKit.common()
	_rules = FlightTestKit.rules()
	_flat = Terrain.new()
	_dt = FlightTestKit.dt(_rules)
	_idle = FlightTestKit.input(0.0, 0.0, 0.0, 0.0, 0)


func _step(s: ShipState, inp: PilotInput, def: ShipDef, rules: RulesDef) -> void:
	var _r: ShipState = Kinematics.step_ship(s, inp, def, _common, rules, _flat, _dt)


# Presses FLIP once from level flight at `speed`, then idles until the flip ends; returns the ticks it took.
func _fly_flip(s: ShipState, def: ShipDef, rules: RulesDef) -> int:
	var flip: PilotInput = FlightTestKit.input(0.0, 0.0, 0.0, 0.0, PilotInput.FLIP)
	_step(s, flip, def, rules)
	var ticks: int = 1
	while s.flip_time > 0.0 and ticks < 1000:
		_step(s, _idle, def, rules)
		ticks += 1
	return ticks


# --- flip (A-11 form, A-29 redirect) ---------------------------------------------------------------------

func test_flip_end_state_reversed_heading_retained_speed_upright_in_duration() -> void:
	for def: ShipDef in [_dart, _bomber]:
		var v0: float = def.v_cruise
		var s: ShipState = FlightTestKit.level(def, 300.0, v0, 0.0)
		var east0: Vector3 = Sphere.tangent_frame(s.p).x
		var ticks: int = _fly_flip(s, def, _rules)
		assert_int(ticks).is_equal(roundi(def.flip_duration_s / _dt))      # within flip_duration_s
		var east: Vector3 = Sphere.tangent_frame(s.p).x
		assert_float(s.fwd.dot(east)).is_less(-0.999)                       # nose reversed
		assert_float(s.up.dot(s.p.normalized())).is_greater(0.999)          # upright
		assert_vector(s.rates).is_equal(Vector3.ZERO)
		assert_float(s.v.normalized().dot(s.fwd)).is_greater(0.99)          # flying nose-first (A-29)
		assert_float(s.v.dot(east)).is_less(0.0)
		# gravity and body damping act for flip_duration_s on top of the redirect: allow 5 %
		var want: float = _common.flip_speed_retain * v0
		assert_float(s.v.length()).is_equal_approx(want, want * 0.05)
		assert_float(s.v.dot(east0)).is_less(0.0)


func test_flip_speed_retain_is_exact_without_gravity_and_reads_the_field() -> void:
	# Gravity 0 and v along the nose: damping never acts, so the only speed change is the last-tick scale.
	var r: RulesDef = FlightTestKit.rules()
	r.gravity = 0.0
	for retain: float in [_common.flip_speed_retain, 0.5]:
		_common.flip_speed_retain = retain
		var v0: float = _dart.v_cruise
		var s: ShipState = FlightTestKit.level(_dart, 300.0, v0, 0.0)
		var speeds: PackedFloat32Array = PackedFloat32Array()
		var flip: PilotInput = FlightTestKit.input(0.0, 0.0, 0.0, 0.0, PilotInput.FLIP)
		_step(s, flip, _dart, r)
		while s.flip_time > 0.0:
			var _a: bool = speeds.push_back(s.v.length())
			_step(s, _idle, _dart, r)
		for sp: float in speeds:
			assert_float(sp).is_equal_approx(v0, v0 * 0.0001)               # redirect keeps speed mid-flip
		assert_float(s.v.length()).is_equal_approx(retain * v0, v0 * 0.0001)
		assert_float(s.v.normalized().dot(s.fwd)).is_greater(0.9999)


func test_flip_redirect_rotates_velocity_with_the_body_each_tick() -> void:
	# Mid-flip (half loop under way) the velocity follows the nose: the angle between v and fwd stays small.
	var s: ShipState = FlightTestKit.level(_bomber, 600.0, _bomber.v_cruise, 0.0)
	var flip: PilotInput = FlightTestKit.input(0.0, 0.0, 0.0, 0.0, PilotInput.FLIP)
	_step(s, flip, _bomber, _rules)
	while s.flip_time > 0.0:
		assert_float(s.v.normalized().dot(s.fwd)).is_greater(0.98)
		_step(s, _idle, _bomber, _rules)


# --- fuel burn (A-32, 02 s2.3) -----------------------------------------------------------------------------

func test_flight_common_burn_fields_are_the_02_rates() -> void:
	assert_float(_common.fuel_burn_boost_per_s).is_equal(2.0)
	assert_float(_common.fuel_burn_brake_per_s).is_equal(0.6)
	assert_float(_common.fuel_burn_idle_per_s).is_equal(0.05)
	assert_float(_common.flip_speed_retain).is_equal(0.75)


func test_fuel_per_mode_over_n_ticks_matches_02_rates() -> void:
	# 02 s2.3: burn/s = thrust input + 2.0 boosting + 0.6 braking + 0.05 idle. 60 ticks, boost held active.
	var n: int = 2 * _rules.tick_hz
	var t: float = n * _dt
	var cases: Array[Array] = [
		[0.0, 0, false, 0.05], [1.0, 0, false, 1.05], [0.5, 0, false, 0.55],
		[0.0, PilotInput.BRAKE, false, 0.65], [1.0, 0, true, 3.05], [1.0, PilotInput.BRAKE, true, 3.65],
	]
	for c: Array in cases:
		var s: ShipState = FlightTestKit.level(_dart, 900.0, 60.0, 0.0)
		if c[2] as bool:
			s.boost_time = _dart.boost_duration_s                           # boosting for all n ticks
		var inp: PilotInput = FlightTestKit.input(c[0] as float, 0.0, 0.0, 0.0, c[1] as int)
		for i: int in n:
			_step(s, inp, _dart, _rules)
		assert_float(_dart.fuel_s - s.fuel).is_equal_approx((c[3] as float) * t, 0.0001)


func test_fuel_burn_reads_the_def_fields() -> void:
	var n: int = _rules.tick_hz
	_common.fuel_burn_idle_per_s *= 2.0
	_common.fuel_burn_brake_per_s *= 2.0
	var s: ShipState = FlightTestKit.level(_dart, 900.0, 60.0, 0.0)
	var brake: PilotInput = FlightTestKit.input(0.0, 0.0, 0.0, 0.0, PilotInput.BRAKE)
	for i: int in n:
		_step(s, brake, _dart, _rules)
	var want: float = (_common.fuel_burn_idle_per_s + _common.fuel_burn_brake_per_s) * n * _dt
	assert_float(_dart.fuel_s - s.fuel).is_equal_approx(want, 0.0001)


func test_zero_fuel_disables_boost_thrust_and_brake() -> void:
	var all_in: PilotInput = FlightTestKit.input(1.0, 0.0, 0.0, 0.0, PilotInput.BOOST | PilotInput.BRAKE)
	var a: ShipState = FlightTestKit.level(_dart, 900.0, 60.0, 0.0)
	a.fuel = 0.0
	var b: ShipState = FlightTestKit.copy(a)
	for i: int in 30:
		_step(a, all_in, _dart, _rules)
		_step(b, _idle, _dart, _rules)
		assert_bool(FlightTestKit.state_bytes(a) == FlightTestKit.state_bytes(b)).is_true()   # glides
	assert_float(a.boost_time).is_less_equal(0.0)
	assert_float(a.fuel).is_equal(0.0)


func test_running_dry_mid_boost_ends_the_boost() -> void:
	var s: ShipState = FlightTestKit.level(_dart, 900.0, 60.0, 0.0)
	s.boost_time = _dart.boost_duration_s
	s.fuel = 0.5 * _dt
	var boost: PilotInput = FlightTestKit.input(1.0, 0.0, 0.0, 0.0, PilotInput.BOOST)
	_step(s, boost, _dart, _rules)
	assert_float(s.fuel).is_equal(0.0)
	assert_float(s.boost_time).is_less_equal(0.0)
	for i: int in roundi(_dart.boost_cooldown_s / _dt) + 2:
		_step(s, boost, _dart, _rules)
		assert_float(s.boost_time).is_less_equal(0.0)                     # never re-triggers while empty
	s.fuel = _dart.fuel_s                                                   # refuelled: BOOST works again
	_step(s, boost, _dart, _rules)
	assert_float(s.boost_time).is_equal(_dart.boost_duration_s)


# --- determinism (S8) ----------------------------------------------------------------------------------------

func _run(inputs: Array[PilotInput], fuel: float) -> PackedByteArray:
	var s: ShipState = FlightTestKit.level(_dart, 900.0, _dart.v_cruise, 0.0)
	s.fuel = fuel
	var out: PackedByteArray = PackedByteArray()
	for inp: PilotInput in inputs:
		_step(s, inp, _dart, _rules)
		out.append_array(FlightTestKit.state_bytes(s))
	return out


func test_flip_and_fuel_paths_replay_bit_identical() -> void:
	# Random inputs with FLIP / BOOST / BRAKE from a small tank: flips, boosts, the empty-tank edge and the glide
	# all happen inside the run; two runs are byte-identical.
	var inputs: Array[PilotInput] = FlightTestKit.random_inputs(4848, STEPS)
	var a: PackedByteArray = _run(inputs, 20.0)
	var b: PackedByteArray = _run(inputs, 20.0)
	assert_bool(a == b).is_true()
	var s: ShipState = FlightTestKit.level(_dart, 900.0, _dart.v_cruise, 0.0)
	s.fuel = 20.0
	var flips: int = 0
	for inp: PilotInput in inputs:
		var was: bool = s.flip_time > 0.0
		_step(s, inp, _dart, _rules)
		if s.flip_time > 0.0 and not was:
			flips += 1
	assert_int(flips).is_greater(0)
	assert_float(s.fuel).is_equal(0.0)
