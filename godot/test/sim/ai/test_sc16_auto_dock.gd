extends GdUnitTestSuite
## SC-16 / AI-10 acceptance (05 s5.5 "Auto-dock assist", R0 B.12 A-33, A-34): a player holding DOCK inside the
## horizontal auto-dock radius at 40-110 m/s docks tail-down within the R0 B.5 limits, measured as a success rate
## over N seeds per ship class against the TA-30 spike's 200/200 (REPORT s3). Closed loop through Assist.auto_dock
## and Kinematics.step_ship; the grade side (AUTO when an assist tick occurred in the last 150 m) is the sim's
## (GD-15), so the rig checks the assist ticks instead.

const RUNS: int = 200


func _runs(id: StringName, lo: float, hi: float, n: int, seed_value: int) -> void:
	var common: FlightCommonDef = FlightTestKit.common()
	var rig: AssistDockRig = AssistDockRig.new(FlightTestKit.ship(id), common, FlightTestKit.rules())
	var rng: Rng = Rng.new(seed_value)
	var landed: int = 0
	var worst_tilt: float = 0.0
	var no_assist: int = 0
	var fails: PackedStringArray = PackedStringArray()
	for k: int in n:
		var o: DockLawRig.Outcome = rig.run(rig.assist_start(rng, lo, hi))
		if o == DockLawRig.Outcome.LANDED:
			landed += 1
			worst_tilt = maxf(worst_tilt, rig.touchdown.z)
			no_assist += 1 if rig.assist_ticks == 0 else 0
		else:
			var _b: bool = fails.push_back("run %d outcome %d td %s" % [k, o, rig.touchdown])
	print("SC-16 %s %.0f-%.0f m/s landed %d/%d worst tilt %.1f" % [id, lo, hi, landed, n, worst_tilt])
	var what: String = "%s: %s" % [id, "; ".join(fails)]
	assert_int(landed).override_failure_message(what).is_equal(n)
	assert_int(no_assist).is_equal(0)
	assert_float(worst_tilt).is_less_equal(common.landing_safe_pitch_deg)


func test_dart_docks_at_40_to_110() -> void:
	_runs(&"dart", 40.0, 110.0, RUNS, 1601)


func test_dart_docks_slow() -> void:
	_runs(&"dart", 0.0, 40.0, RUNS, 1602)


func test_bomber_docks_at_40_to_110() -> void:
	_runs(&"bomber", 40.0, 110.0, RUNS, 1603)


func test_other_classes_dock() -> void:
	for id: StringName in [&"lancer", &"scout", &"hauler"]:
		_runs(id, 40.0, 110.0, 50, 1604)
