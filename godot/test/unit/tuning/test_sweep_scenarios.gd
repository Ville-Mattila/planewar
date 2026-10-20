extends GdUnitTestSuite
## AI-06: the gain-tuning harness' scenario runners (test/tuning/sweep_scenarios.gd) are deterministic per seed,
## apply candidate overrides, and reproduce the AI-05 / AI-09 acceptance at the shipped anchors.


func _setup(model: StringName, flight: Dictionary = {}, landing: Dictionary = {}) -> SweepScenarios.Setup:
	var su: SweepScenarios.Setup = SweepScenarios.Setup.new()
	su.model = model
	su.flight = flight
	su.landing = landing
	return su


func test_setup_gains_apply_overrides_over_the_anchor() -> void:
	var def: ShipDef = FlightTestKit.ship(&"dart")
	var rules: RulesDef = FlightTestKit.rules()
	var base: FlightGains = _setup(RulesDef.LIFT_SPEED_SCALED).gains(def, rules)
	var tuned: FlightGains = _setup(RulesDef.LIFT_SPEED_SCALED, {"kp_speed": 0.01}).gains(def, rules)
	assert_float(base.kp_speed).is_equal(Ai05Kit.num(Ai05Kit.block("flight"), "kp_speed"))
	assert_float(tuned.kp_speed).is_equal(0.01)
	assert_float(tuned.kp_path).is_equal(base.kp_path)


func test_step_response_meets_ai05_acceptance_at_the_anchors() -> void:
	var r: Vector2 = SweepScenarios.step_response(_setup(RulesDef.LIFT_SPEED_SCALED), &"dart", 30.0, 0.0)
	assert_float(r.x).is_between(0.0, 2.0)
	assert_float(r.y).is_less(0.15)


func test_step_response_is_deterministic() -> void:
	var su: SweepScenarios.Setup = _setup(RulesDef.LIFT_DAMPING_ONLY)
	assert_vector(SweepScenarios.step_response(su, &"dart", 0.0, -15.0)).is_equal(
		SweepScenarios.step_response(su, &"dart", 0.0, -15.0))


func test_steep_dive_same_seed_same_result_and_seeds_differ() -> void:
	var su: SweepScenarios.Setup = _setup(RulesDef.LIFT_SPEED_SCALED)
	assert_vector(SweepScenarios.steep_dive(su, 606, 3)).is_equal(SweepScenarios.steep_dive(su, 606, 3))
	assert_bool(SweepScenarios.steep_dive(su, 606, 3).y == SweepScenarios.steep_dive(su, 606, 4).y).is_false()


func test_landing_docks_under_speed_scaled_and_fills_every_column() -> void:
	var out: Dictionary = {}
	var ok: bool = SweepScenarios.landing(_setup(RulesDef.LIFT_SPEED_SCALED), 606, 0, out)
	assert_bool(ok).override_failure_message(str(out)).is_true()
	assert_str(str(out["outcome"])).is_equal("docked")
	for col: String in SweepScenarios.LANDING_COLS:
		assert_bool(out.has(col)).override_failure_message("missing column " + col).is_true()


func test_landing_is_deterministic_per_seed() -> void:
	var a: Dictionary = {}
	var b: Dictionary = {}
	var _x: bool = SweepScenarios.landing(_setup(RulesDef.LIFT_DAMPING_ONLY), 606, 1, a)
	var _y: bool = SweepScenarios.landing(_setup(RulesDef.LIFT_DAMPING_ONLY), 606, 1, b)
	assert_dict(a).is_equal(b)


func test_landing_override_changes_the_run() -> void:
	var a: Dictionary = {}
	var b: Dictionary = {}
	var _x: bool = SweepScenarios.landing(_setup(RulesDef.LIFT_SPEED_SCALED), 606, 2, a)
	var _y: bool = SweepScenarios.landing(_setup(RulesDef.LIFT_SPEED_SCALED, {}, {"glide_deg": 12.0}), 606, 2, b)
	assert_float(float(a["gate_to_dock_s"])).is_not_equal(float(b["gate_to_dock_s"]))


func test_csv_quote_escapes_embedded_quotes() -> void:
	assert_str(GainSweep._q("{\"a\":1}")).is_equal("\"{\"\"a\"\":1}\"")
	assert_vector(GainSweep._range("10,45")).is_equal(Vector2(10.0, 45.0))
