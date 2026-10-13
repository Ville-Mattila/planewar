extends GdUnitTestSuite
## S8 purity (03 s5.6, TA-12): 3,000 random steps run twice are bit-identical; interleaving two ships does
## not change either (no hidden static or global state).

const STEPS: int = 3000

var _dart: ShipDef
var _common: FlightCommonDef
var _rules: RulesDef
var _flat: Terrain
var _dt: float


func before_test() -> void:
	_dart = FlightTestKit.ship(&"dart")
	_common = FlightTestKit.common()
	_rules = FlightTestKit.rules()
	_flat = Terrain.new()
	_dt = FlightTestKit.dt(_rules)


func _run(inputs: Array[PilotInput]) -> PackedByteArray:
	var s: ShipState = FlightTestKit.level(_dart, 600.0, _dart.v_cruise, 0.0)
	var out: PackedByteArray = PackedByteArray()
	for inp: PilotInput in inputs:
		var _r: ShipState = Kinematics.step_ship(s, inp, _dart, _common, _rules, _flat, _dt)
		out.append_array(FlightTestKit.state_bytes(s))
	return out


func test_step_ship_3000_random_steps_twice_bit_identical() -> void:
	var inputs: Array[PilotInput] = FlightTestKit.random_inputs(1234, STEPS)
	var a: PackedByteArray = _run(inputs)
	var b: PackedByteArray = _run(inputs)
	assert_int(a.size()).is_greater(0)
	assert_bool(a == b).is_true()


func test_interleaved_ships_match_solo_runs() -> void:
	var in_a: Array[PilotInput] = FlightTestKit.random_inputs(1, STEPS)
	var in_b: Array[PilotInput] = FlightTestKit.random_inputs(2, STEPS)
	var solo_a: PackedByteArray = _run(in_a)
	var solo_b: PackedByteArray = _run(in_b)
	var bomber: ShipDef = FlightTestKit.ship(&"bomber")
	var sa: ShipState = FlightTestKit.level(_dart, 600.0, _dart.v_cruise, 0.0)
	var sb: ShipState = FlightTestKit.level(_dart, 600.0, _dart.v_cruise, 0.0)
	var sc: ShipState = FlightTestKit.level(bomber, 900.0, bomber.v_cruise, 0.0)
	var out_a: PackedByteArray = PackedByteArray()
	var out_b: PackedByteArray = PackedByteArray()
	for i: int in STEPS:
		var _r1: ShipState = Kinematics.step_ship(sa, in_a[i], _dart, _common, _rules, _flat, _dt)
		var _r2: ShipState = Kinematics.step_ship(sc, in_b[i], bomber, _common, _rules, _flat, _dt)
		var _r3: ShipState = Kinematics.step_ship(sb, in_b[i], _dart, _common, _rules, _flat, _dt)
		out_a.append_array(FlightTestKit.state_bytes(sa))
		out_b.append_array(FlightTestKit.state_bytes(sb))
	assert_bool(out_a == solo_a).is_true()
	assert_bool(out_b == solo_b).is_true()


func test_step_ship_returns_the_scratch_it_was_given() -> void:
	var s: ShipState = FlightTestKit.level(_dart, 600.0, _dart.v_cruise, 0.0)
	var inp: PilotInput = FlightTestKit.input(0.5, 0.0, 0.0, 0.0, 0)
	assert_object(Kinematics.step_ship(s, inp, _dart, _common, _rules, _flat, _dt)).is_same(s)


func test_step_projectile_is_pure() -> void:
	var bomb: ProjectileDef = FlightTestKit.projectile(&"bomb")
	var p: Vector3 = Vector3(Sphere.PLANET_RADIUS + 400.0, 10.0, -20.0)
	var v: Vector3 = Vector3(3.0, 90.0, 12.0)
	var a: ProjectileState = Kinematics.step_projectile(p, v, bomb, _rules, _dt)
	var b: ProjectileState = Kinematics.step_projectile(p, v, bomb, _rules, _dt)
	assert_bool(var_to_bytes([a.p, a.v]) == var_to_bytes([b.p, b.v])).is_true()
	assert_object(a).is_not_same(b)


# --- step_projectile `out` scratch (TA-43, R0 B.9 A-12) ---------------------------------------------------

func test_step_projectile_fills_and_returns_out() -> void:
	var scratch: ProjectileState = ProjectileState.new()
	for id: StringName in [&"slug_light", &"bomb", &"rocket"]:
		var def: ProjectileDef = FlightTestKit.projectile(id)
		var p: Vector3 = Vector3(Sphere.PLANET_RADIUS + 400.0, 10.0, -20.0)
		var v: Vector3 = Vector3(3.0, 90.0, 12.0)
		var fresh: ProjectileState = Kinematics.step_projectile(p, v, def, _rules, _dt)
		var got: ProjectileState = Kinematics.step_projectile(p, v, def, _rules, _dt, scratch)
		assert_object(got).is_same(scratch)
		assert_bool(var_to_bytes([got.p, got.v]) == var_to_bytes([fresh.p, fresh.v])).is_true()


func test_step_projectile_scratch_loop_allocates_nothing_and_matches_reference() -> void:
	# One reused scratch over a whole flight: every call returns that same object (no allocation per call), and
	# the trajectory is bit-identical to the TA-12 formula (03 s5.4) evaluated independently here.
	var scratch: ProjectileState = ProjectileState.new()
	for id: StringName in [&"slug_light", &"bomb", &"rocket"]:
		var def: ProjectileDef = FlightTestKit.projectile(id)
		scratch.p = Vector3(Sphere.PLANET_RADIUS + 300.0, -5.0, 7.0)
		scratch.v = Vector3(1.0, maxf(def.speed_mps, 100.0), -2.0)
		var rp: Vector3 = scratch.p
		var rv: Vector3 = scratch.v
		var same: bool = true
		for _k: int in ceili(def.lifetime_s / _dt):
			same = same and Kinematics.step_projectile(scratch.p, scratch.v, def, _rules, _dt, scratch) == scratch
			var vel: Vector3 = rv
			if def.gravity:
				vel -= rp.normalized() * (_rules.gravity * _dt)
			var p_new: Vector3 = rp + vel * _dt
			if def.transport:
				vel = Sphere.transport(rp.normalized(), p_new.normalized()) * vel
			rp = p_new
			rv = vel
		assert_bool(same).is_true()
		assert_bool(var_to_bytes([scratch.p, scratch.v]) == var_to_bytes([rp, rv])) \
			.override_failure_message("trajectory drift for %s" % id).is_true()
