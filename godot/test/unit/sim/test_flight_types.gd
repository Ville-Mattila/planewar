extends GdUnitTestSuite
## Unit tests for the TA-12 value types: ShipState, ProjectileState, PilotInput, the flat Terrain stub and the
## content `*Def` types Kinematics reads (values = R0 B.1 via the canonical fixture; the real defs via ContentLoader).


func test_ship_state_defaults_are_zero() -> void:
	var s: ShipState = ShipState.new()
	assert_vector(s.p).is_equal(Vector3.ZERO)
	assert_vector(s.v).is_equal(Vector3.ZERO)
	assert_vector(s.rates).is_equal(Vector3.ZERO)
	assert_float(s.fuel).is_equal(0.0)
	assert_bool(s.terrain_hit).is_false()
	assert_bool(s.ceiling_forced).is_false()
	assert_float(s.over_dive_excess).is_equal(0.0)


func test_projectile_state_holds_p_and_v() -> void:
	var ps: ProjectileState = ProjectileState.new()
	ps.p = Vector3(1, 2, 3)
	ps.v = Vector3(4, 5, 6)
	assert_vector(ps.p).is_equal(Vector3(1, 2, 3))
	assert_vector(ps.v).is_equal(Vector3(4, 5, 6))


func test_pilot_input_button_bits_match_contract() -> void:
	# sim/MODULE.md PilotInput.buttons: bit0 BOOST .. bit6 RELEASE (append-only).
	var bits: Array[int] = [PilotInput.BOOST, PilotInput.BRAKE, PilotInput.FLIP, PilotInput.FIRE1,
		PilotInput.FIRE2, PilotInput.DOCK, PilotInput.RELEASE]
	for i: int in bits.size():
		assert_int(bits[i]).is_equal(1 << i)
	var inp: PilotInput = PilotInput.new()
	assert_float(inp.thrust).is_equal(0.0)
	assert_int(inp.buttons).is_equal(0)


func test_terrain_stub_is_the_datum_sphere() -> void:
	var t: Terrain = Terrain.new()
	var d: Vector3 = Vector3(3, -4, 12)
	assert_float(t.height_at(d)).is_equal(0.0)
	assert_vector(t.normal_at(d)).is_equal_approx(d.normalized(), Vector3.ONE * 0.000001)


func test_ship_def_loads_r0_b1_dart_and_bomber() -> void:
	var dart: ShipDef = FlightTestKit.ship(&"dart")
	var bomber: ShipDef = FlightTestKit.ship(&"bomber")
	var raw: Dictionary = _ship_dict(&"dart")
	assert_str(str(dart.id)).is_equal("dart")
	assert_float(dart.v_cruise).is_equal(float(raw["v_cruise"]))
	assert_float(dart.a_thrust).is_equal(float(raw["a_thrust"]))
	assert_float(dart.k_up_flight).is_equal(float(raw["k_up_flight"]))
	assert_float(dart.flip_duration_s).is_equal(float(raw["flip_duration_s"]))
	assert_str(str(bomber.id)).is_equal("bomber")
	# O-2: every ship hovers (a_thrust >= 2 g); the Bomber is the floor.
	var g: float = FlightTestKit.rules().gravity
	assert_float(dart.a_thrust).is_greater_equal(2.0 * g)
	assert_float(bomber.a_thrust).is_greater_equal(2.0 * g)


func test_flight_common_rules_and_projectile_defs_load() -> void:
	var c: FlightCommonDef = FlightTestKit.common()
	var raw: Dictionary = FlightTestKit.load_json("ships.json")["flight_common"]
	assert_float(c.eff_fade_start).is_equal(float(raw["eff_fade_start"]))
	assert_float(c.brake_fade_mps).is_equal(float(raw["brake_fade_mps"]))
	assert_float(c.landing_safe_pitch_deg).is_equal(float(raw["landing_safe_pitch_deg"]))
	assert_float(c.auto_dock_radius_m).is_equal(float(raw["auto_dock_radius_m"]))
	var r: RulesDef = RulesDef.from_dict(FlightTestKit.load_json("rules.json"))
	assert_str(str(r.lift_model)).is_equal("speed_scaled")
	assert_float(r.ceiling_hard_m).is_equal(Sphere.CEILING_HARD)
	assert_float(r.ceiling_soft_m).is_equal(Sphere.CEILING_SOFT)
	assert_int(r.tick_hz).is_equal(30)
	var slug: ProjectileDef = FlightTestKit.projectile(&"slug_light")
	assert_bool(slug.gravity).is_false()
	assert_bool(slug.transport).is_false()
	var bomb: ProjectileDef = FlightTestKit.projectile(&"bomb")
	assert_bool(bomb.gravity).is_true()
	assert_bool(bomb.transport).is_true()
	assert_float(bomb.eject_down_mps).is_greater(0.0)



func test_canonical_defs_parse_without_errors() -> void:
	# TA-45: content's *Def classes parse the canonical flight fixture; brake_fade_mps is a read field. The A-29..A-35
	# flight_common appends stay unknown until TA-48 / content add them.
	var defs: Array[Def] = [FlightTestKit.ship(&"dart"), FlightTestKit.ship(&"bomber"),
		FlightTestKit.rules(), FlightTestKit.projectile(&"slug_light"), FlightTestKit.projectile(&"bomb")]
	for d: Def in defs:
		assert_array(d.errors).override_failure_message("%s: %s" % [d.id, d.errors]).is_empty()
	var c: FlightCommonDef = FlightTestKit.common()
	assert_array(c.errors).is_empty()
	assert_array(c.unknown).not_contains(["brake_fade_mps"])


func test_real_content_steps_through_kinematics() -> void:
	# TA-45: the shipped defs, built by ContentLoader, are what Kinematics takes; one Dart tick stays finite.
	var cs: ContentSet = FlightTestKit.real_content()
	assert_array(cs.errors).is_empty()
	assert_array(cs.flight_common.unknown).not_contains(["brake_fade_mps"])
	assert_float(cs.flight_common.brake_fade_mps).is_greater(0.0)
	var dart: ShipDef = null
	for sd: ShipDef in cs.ships:
		if sd.id == &"dart":
			dart = sd
	assert_object(dart).is_not_null()
	var dt: float = FlightTestKit.dt(cs.rules)
	var s: ShipState = FlightTestKit.level(dart, 300.0, dart.v_cruise, 0.0)
	var inp: PilotInput = FlightTestKit.input(1.0, 0.0, 0.0, 0.0, PilotInput.BRAKE)
	var _r: ShipState = Kinematics.step_ship(s, inp, dart, cs.flight_common, cs.rules, Terrain.new(), dt)
	assert_bool(s.p.is_finite() and s.v.is_finite()).is_true()
	assert_float(s.v.dot(s.fwd)).is_less(dart.v_cruise)


func _ship_dict(id: StringName) -> Dictionary:
	for e: Variant in FlightTestKit.load_json("ships.json")["ships"]:
		var d: Dictionary = e as Dictionary
		if StringName(str(d["id"])) == id:
			return d
	return {}
