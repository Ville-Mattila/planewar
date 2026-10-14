extends GdUnitTestSuite
## AI-09 L4-L6 (TRANSITION, HOVER, FLARE) of LandingController from the TA-30 spike's dock start sets (AI-05's
## DockLawRig.start_state: inside 140 m, 15-120 m up, any heading; normal <= 40 m/s, fast 40 m/s .. v_cruise), on
## the flat datum, every ship class, both lift models. Pass: every run lands inside R0 B.5 with the thrust axis
## within 10 degrees of the pad normal (05 AI-09), zero aborts, and zero off-pad terrain scrapes (AI-05 measured
## 37 / 200 fast Dart runs scraping under the spike law, which had no height floor in L4).

const RUNS: int = 200          # Dart and Bomber (the a_thrust 14 floor), per start set
const RUNS_OTHER: int = 50     # Lancer, Scout, Hauler; the damping_only variant
const TILT_MAX_DEG: float = 10.0
const TIMEOUT_S: float = 120.0


func _runs(id: StringName, model: StringName, fast: bool, n: int) -> void:
	var def: ShipDef = FlightTestKit.ship(id)
	var common: FlightCommonDef = FlightTestKit.common()
	var rules: RulesDef = FlightTestKit.rules(model)
	var dock: DockLawRig = DockLawRig.new(def, common, rules)   # start states and pad of the spike
	var prm: LandingParams = Ai09Kit.landing(rules)
	var g: FlightGains = Ai05Kit.gains(def, rules)
	var rng: Rng = Rng.new(int(Ai05Kit.num(Ai05Kit.block("dock_runs"), "seed")) + (1 if fast else 0))
	var landed: int = 0
	var scraped: int = 0
	var aborted: int = 0
	var worst: Vector4 = Vector4.ZERO
	var t_sum: float = 0.0
	var fails: PackedStringArray = PackedStringArray()
	for k: int in n:
		var r: Vector4 = run_one(dock.start_state(rng, fast), def, common, rules, prm, g, dock.pad_p)
		scraped += 1 if r.y > 0.0 else 0
		aborted += 1 if r.z > 0.0 else 0
		if r.x > 0.0:
			landed += 1
			t_sum += r.x
			worst = Vector4(maxf(worst.x, _td.x), maxf(worst.y, _td.y), maxf(worst.z, _td.z), maxf(worst.w, _td.w))
		else:
			var _b: bool = fails.push_back("run %d td %s aborts %d %s" % [k, _td, int(r.z), _abort])
	print("L4-L6 %s %s fast=%s landed %d/%d scraped %d aborted %d mean_t=%.1f s worst sink %.2f vh %.2f tilt %.1f off %.2f" % [
		model, id, fast, landed, n, scraped, aborted, t_sum / maxf(float(landed), 1.0), worst.x, worst.y, worst.z, worst.w])
	var what: String = "%s %s fast=%s: %s" % [model, id, fast, "; ".join(fails)]
	assert_int(landed).override_failure_message(what).is_equal(n)
	assert_int(scraped).override_failure_message(what).is_equal(0)
	assert_int(aborted).override_failure_message(what).is_equal(0)
	assert_float(worst.z).override_failure_message(what).is_less_equal(TILT_MAX_DEG)
	assert_float(worst.x).override_failure_message(what).is_less_equal(common.landing_safe_v_vert)


var _td: Vector4 = Vector4.ZERO
var _abort: String = ""
var trace: bool = false


## Flies one run from TRANSITION. Returns (seconds to touchdown or -1, scrape episodes, aborts, 0); `_td` holds
## the touchdown (sink, horizontal speed, tilt deg, offset).
func run_one(s: ShipState, def: ShipDef, common: FlightCommonDef, rules: RulesDef, prm: LandingParams,
		g: FlightGains, pad_p: Vector3) -> Vector4:
	var world: LandingWorld = LandingWorld.new(Terrain.new(), common, rules)
	var _pad: int = world.add_pad(pad_p.normalized())
	var _id: int = world.add_ship(def, s)
	var st: LandingState = LandingState.new()
	st.phase = LandingController.Phase.TRANSITION
	var ship: ShipSnapshot = ShipSnapshot.new()
	var pad: PadSnapshot = PadSnapshot.new()
	pad.p = world.pad_pos[0]
	pad.n = world.pad_up[0]
	pad.radius_m = world.pad_radius_by_def[LandingWorld.PAD_DEF]
	pad.valid = true
	var inp: PilotInput = PilotInput.new()
	var aborts: int = 0
	for i: int in int(TIMEOUT_S * float(rules.tick_hz)):
		Ai09Kit.snapshot(s, def, common, rules, ship)
		var _ph: int = LandingController.step(st, ship, pad, prm, g, inp)
		if trace:
			var rel: Vector3 = s.p - pad.p
			var hh: float = rel.dot(pad.n)
			print("t=%.2f ph=%d h=%.1f e=%.1f w=%.1f vz=%.1f tilt=%.0f thr=%.2f brk=%d" % [float(i) / 30.0, st.phase,
				hh - def.bounding_radius, (rel - pad.n * hh).length(), (s.v - pad.n * s.v.dot(pad.n)).length(),
				s.v.dot(pad.n), rad_to_deg(s.fwd.angle_to(pad.n)), inp.thrust, inp.buttons & PilotInput.BRAKE])
		if st.phase < LandingController.Phase.TRANSITION:
			aborts += 1
			_abort = "reason %d at t=%.1f h=%.1f vz=%.1f" % [st.abort_reason, float(i) / 30.0,
				(s.p - pad.p).dot(pad.n) - def.bounding_radius, s.v.dot(pad.n)]
			break
		world.step_ship(0, inp)
		world.end_tick()
		if not world.flying(0):
			break
	_td = world.touchdown[0]
	var ok: bool = world.outcome[0] == LandingWorld.Outcome.LANDED
	return Vector4(float(world.now) / float(rules.tick_hz) if ok else -1.0, float(world.scrapes[0]), float(aborts), 0.0)


func test_dart_dock_set() -> void:
	_runs(&"dart", RulesDef.LIFT_SPEED_SCALED, false, RUNS)


func test_dart_fast_dock_set_no_scrapes() -> void:
	_runs(&"dart", RulesDef.LIFT_SPEED_SCALED, true, RUNS)


func test_bomber_dock_set() -> void:
	_runs(&"bomber", RulesDef.LIFT_SPEED_SCALED, false, RUNS)


func test_bomber_fast_dock_set() -> void:
	_runs(&"bomber", RulesDef.LIFT_SPEED_SCALED, true, RUNS)


func test_other_classes_dock_sets() -> void:
	for id: StringName in [&"lancer", &"scout", &"hauler"]:
		_runs(id, RulesDef.LIFT_SPEED_SCALED, false, RUNS_OTHER)
		_runs(id, RulesDef.LIFT_SPEED_SCALED, true, RUNS_OTHER)


func test_damping_only_dock_sets() -> void:
	for id: StringName in [&"dart", &"bomber"]:
		_runs(id, RulesDef.LIFT_DAMPING_ONLY, false, RUNS_OTHER)
		_runs(id, RulesDef.LIFT_DAMPING_ONLY, true, RUNS_OTHER)

