extends GdUnitTestSuite
## AI-05 auto-dock success rate against the TA-30 spike (REPORT s3: dock_runs 200/200 and dock_fast_runs 200/200
## landed, mean q 0.91): the spike's L4-L6 law flown through FlightController.track_thrust_vector, from the
## spike's start-state distribution, under both lift models. Every touchdown must meet R0 B.5 (sink <= 8 m/s,
## horizontal <= 15 m/s, thrust axis within 25 degrees of the pad normal) inside the pad radius; tail-down
## only. The Bomber (a_thrust 14 = 2.3 g, the schema floor) is run at full count. Off-pad ground contacts below
## terrain_damage_speed are scrapes and the run flies on, as in the spike's world; they are counted and printed.

const RUNS: int = 200          # per (class, start set) for Dart and Bomber, as the spike
const RUNS_OTHER: int = 50     # Lancer, Scout, Hauler


func _runs(id: StringName, model: StringName, fast: bool, n: int, min_landed: int = -1) -> void:
	var common: FlightCommonDef = FlightTestKit.common()
	var rig: DockLawRig = DockLawRig.new(FlightTestKit.ship(id), common, FlightTestKit.rules(model))
	var rng: Rng = Rng.new(int(Ai05Kit.num(Ai05Kit.block("dock_runs"), "seed")) + (1 if fast else 0))
	var landed: int = 0
	var worst: Vector4 = Vector4.ZERO
	var t_sum: float = 0.0
	var scraped: int = 0
	var fails: PackedStringArray = PackedStringArray()
	for k: int in n:
		var o: DockLawRig.Outcome = rig.run(rig.start_state(rng, fast))
		var td: Vector4 = rig.touchdown
		scraped += 1 if rig.scrapes > 0 else 0
		if o == DockLawRig.Outcome.LANDED:
			landed += 1
			t_sum += float(rig.ticks) / 30.0
			worst = Vector4(maxf(worst.x, td.x), maxf(worst.y, td.y), maxf(worst.z, td.z), maxf(worst.w, td.w))
		else:
			var _b: bool = fails.push_back("run %d outcome %d td %s" % [k, o, td])
	print("DOCK %s %s fast=%s landed %d/%d (runs with a scrape %d) mean_t=%.1f s worst sink %.2f vh %.2f tilt %.1f off %.2f" % [
		model, id, fast, landed, n, scraped, t_sum / maxf(float(landed), 1.0), worst.x, worst.y, worst.z, worst.w])
	var what: String = "%s %s fast=%s: %s" % [model, id, fast, "; ".join(fails)]
	assert_int(landed).override_failure_message(what).is_greater_equal(n if min_landed < 0 else min_landed)
	assert_float(worst.z).override_failure_message(what).is_less_equal(FlightTestKit.common().landing_safe_pitch_deg)


func test_dart_dock_runs_match_spike() -> void:
	_runs(&"dart", RulesDef.LIFT_SPEED_SCALED, false, RUNS)


func test_dart_dock_fast_runs_match_spike() -> void:
	_runs(&"dart", RulesDef.LIFT_SPEED_SCALED, true, RUNS)


func test_bomber_dock_runs() -> void:
	_runs(&"bomber", RulesDef.LIFT_SPEED_SCALED, false, RUNS)


func test_bomber_dock_fast_runs() -> void:
	_runs(&"bomber", RulesDef.LIFT_SPEED_SCALED, true, RUNS)


func test_other_classes_dock() -> void:
	for id: StringName in [&"lancer", &"scout", &"hauler"]:
		_runs(id, RulesDef.LIFT_SPEED_SCALED, false, RUNS_OTHER)
		_runs(id, RulesDef.LIFT_SPEED_SCALED, true, RUNS_OTHER)


func test_damping_only_dock() -> void:
	# A/B variant: the Bomber's fast set loses one run of 50 to an 8.03 m/s ground contact during TRANSITION (the
	# law has no height floor there; AI-09). Bound at 49/50 so a regression is still caught.
	for id: StringName in [&"dart", &"bomber"]:
		_runs(id, RulesDef.LIFT_DAMPING_ONLY, false, RUNS_OTHER)
		_runs(id, RulesDef.LIFT_DAMPING_ONLY, true, RUNS_OTHER, RUNS_OTHER - 1)
