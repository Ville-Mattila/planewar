extends GdUnitTestSuite
## Assist.link_bridge (AI-08; 05 s2.4 LINK_BRIDGE = SAFETY behaviour while POSSESSED; R0 C2-08): the law (pull up
## below safety_pull_up_tti_s, else hold the current velocity), the ground stop, BridgeParams parsing, purity, and the
## bridge flying every ship class on the cradle map without terrain contact: for the A-45 window of 10 ticks from
## dives a pilot can be in when the link drops, and for a long stall (C13 keeps LINK_BRIDGE until the transport
## timeout). Defs: the canonical fixture (FlightTestKit); autopilot keys: OverlayKit's AI-08 fixture.

const MAP: String = "res://content/maps/cradle"
const CLASSES: Array[StringName] = [&"dart", &"lancer", &"bomber", &"scout", &"hauler"]
const WINDOW_TICKS: int = 10           # A-45: net InputBuffer.DECAY_TICKS / ControlMachine.DECAY_TICKS
const STARTS: int = 100                # per class

var _cradle: Terrain


func before() -> void:
	_cradle = Terrain.new()
	assert_int(_cradle.load_map(MAP)).is_equal(OK)


func _bp(id: StringName, rules: RulesDef) -> BridgeParams:
	return BridgeParams.from_autopilot(OverlayKit.ap(id), FlightTestKit.ship(id), rules, rules.tick_hz)


func test_from_autopilot_reads_the_keys_and_refuses_gaps() -> void:
	var rules: RulesDef = FlightTestKit.rules()
	var bp: BridgeParams = _bp(&"dart", rules)
	assert_object(bp).is_not_null()
	assert_float(bp.pull_up_tti_s).is_equal(2.0)
	assert_float(bp.probe.gravity).is_equal(rules.gravity)
	assert_int(bp.probe.probe_times_s.size()).is_equal(6)
	assert_float(bp.gains.pitch_rate).is_equal_approx(deg_to_rad(FlightTestKit.ship(&"dart").pitch_rate_dps), 1e-6)
	for k: String in ["safety_pull_up_tti_s", "flight", "probe_times_s", "min_clearance_m"]:
		var ap: Dictionary = OverlayKit.ap(&"dart").duplicate(true)
		var _e: bool = ap.erase(k)
		assert_object(BridgeParams.from_autopilot(ap, FlightTestKit.ship(&"dart"), rules, 30)).override_failure_message(k).is_null()
	assert_object(BridgeParams.from_autopilot({}, FlightTestKit.ship(&"dart"), rules, 30)).is_null()


func test_table_follows_content_ships_and_nulls_classes_without_a_def() -> void:
	var c: ContentSet = OverlayKit.content()
	var t: Array[BridgeParams] = BridgeParams.table(c, c.rules, c.rules.tick_hz)
	assert_int(t.size()).is_equal(c.ships.size())
	for i: int in c.ships.size():
		assert_object(t[i]).override_failure_message(String(c.ships[i].id)).is_not_null()
	var shipped: ContentSet = WorldTestKit.content()    # no autopilots.json yet (AI-19): every entry null
	for bp: BridgeParams in BridgeParams.table(shipped, shipped.rules, shipped.rules.tick_hz):
		assert_object(bp).is_null()


func test_pulls_up_below_the_threshold() -> void:
	var rules: RulesDef = FlightTestKit.rules()
	var def: ShipDef = FlightTestKit.ship(&"dart")
	var s: ShipState = _dive(def, Vector3(1, 0, 0), Vector3(0, 1, 0), 60.0, 30.0, def.v_cruise)
	var out: PilotInput = FlightTestKit.input(0.2, 0.0, 0.0, 0.0, PilotInput.FIRE1 | PilotInput.DOCK | PilotInput.BRAKE)
	var probe: ProbeResult = ProbeResult.new()
	Assist.link_bridge(Ai05Kit.basis(s), s.p, s.v, Terrain.new(), _bp(&"dart", rules), probe, out)
	assert_float(probe.tti_s).is_less(2.0)
	assert_float(out.thrust).is_equal(1.0)
	assert_float(out.pitch).is_greater(0.0)      # nose up
	assert_int(out.buttons).is_equal(0)


func test_holds_velocity_when_clear() -> void:
	var rules: RulesDef = FlightTestKit.rules()
	var def: ShipDef = FlightTestKit.ship(&"dart")
	var bp: BridgeParams = _bp(&"dart", rules)
	var s: ShipState = _dive(def, Vector3(1, 0, 0), Vector3(0, 1, 0), 800.0, 10.0, def.v_cruise)
	var out: PilotInput = FlightTestKit.input(0.0, 0.0, 0.0, 0.0, PilotInput.FIRE2 | PilotInput.BOOST)
	var probe: ProbeResult = ProbeResult.new()
	Assist.link_bridge(Ai05Kit.basis(s), s.p, s.v, Terrain.new(), bp, probe, out)
	var want: PilotInput = PilotInput.new()
	var lead: float = Assist.trim_lead(s.v, s.p.normalized(), bp)
	assert_float(lead).is_greater(0.0)
	var _i: Vector2 = FlightController.track_velocity(Ai05Kit.basis(s), s.v, s.v, s.p.normalized(), bp.gains,
		Vector2(lead, 0.0), want)
	assert_bool(is_inf(probe.tti_s)).is_true()
	assert_float(out.thrust).is_equal(want.thrust)
	assert_float(out.pitch).is_equal(want.pitch)
	assert_float(out.yaw).is_equal(want.yaw)
	assert_float(out.roll).is_equal(want.roll)
	assert_int(out.buttons).is_equal(want.buttons & PilotInput.BRAKE)


func test_trim_lead_follows_the_lift_law() -> void:
	var def: ShipDef = FlightTestKit.ship(&"dart")
	var up: Vector3 = Vector3(1, 0, 0)
	var level: Vector3 = Vector3(0, def.v_cruise, 0)
	var scaled: RulesDef = FlightTestKit.rules(RulesDef.LIFT_SPEED_SCALED)
	var damping: RulesDef = FlightTestKit.rules(RulesDef.LIFT_DAMPING_ONLY)
	var g: float = scaled.gravity
	assert_float(Assist.trim_lead(level, up, _bp(&"dart", scaled))).is_equal_approx(asin(g / (def.v_cruise * def.k_up_flight)), 1e-6)
	var bd: BridgeParams = _bp(&"dart", damping)
	var want: float = minf(asin(minf(g / (def.v_cruise * def.k_up), 1.0)), bd.gains.integ_max)
	assert_float(Assist.trim_lead(level, up, bd)).is_equal_approx(want, 1e-6)
	assert_float(Assist.trim_lead(Vector3(-def.v_cruise, 0, 0), up, _bp(&"dart", scaled))).is_equal_approx(0.0, 1e-6)
	assert_float(Assist.trim_lead(Vector3(0, 0.5, 0), up, _bp(&"dart", scaled))).is_equal(0.0)


func test_drop_free_lift_removes_the_gravity_drop() -> void:
	var rules: RulesDef = FlightTestKit.rules()
	var bp: BridgeParams = _bp(&"dart", rules)
	var p: Vector3 = Vector3(Sphere.PLANET_RADIUS + 30.0, 0, 0)
	var v: Vector3 = Vector3(0, 110.0, 0)
	var r: ProbeResult = ProbeResult.new()
	var h_req: float = bp.probe.required_clearance(110.0)
	TerrainProbe.probe(Terrain.new(), p, v, bp.probe, h_req, r)
	var t: float = r.worst_t_s
	var c: float = r.min_clearance_m + 0.5 * rules.gravity * t * t
	assert_float(c).is_equal_approx(30.0, 1e-3)               # level path, flat datum: drop-free clearance = altitude
	var want: float = minf(maxf(0.0, h_req - c) / maxf(t, bp.probe.lift_min_time_s), bp.probe.lift_max_frac * 110.0)
	assert_float(TerrainProbe.drop_free_lift(r, bp.probe, h_req, 110.0)).is_equal_approx(want, 1e-9)
	assert_float(TerrainProbe.drop_free_lift(r, bp.probe, h_req, 110.0)).is_less(r.lift_mps)
	assert_float(TerrainProbe.drop_free_lift(r, bp.probe, 10.0, 110.0)).is_equal(0.0)


func test_ground_bridge_stops_without_brake() -> void:
	var out: PilotInput = FlightTestKit.input(0.9, 0.3, 0.4, 0.5, PilotInput.BRAKE | PilotInput.FIRE1)
	Assist.link_bridge_ground(out)
	assert_array([out.thrust, out.pitch, out.yaw, out.roll]).is_equal([0.0, 0.0, 0.0, 0.0])
	assert_int(out.buttons).is_equal(0)


func test_pure_and_deterministic() -> void:
	var rules: RulesDef = FlightTestKit.rules()
	var def: ShipDef = FlightTestKit.ship(&"bomber")
	var bp: BridgeParams = _bp(&"bomber", rules)
	var a: Array = _bridge_run(def, bp, rules, _start(def, Rng.new(5), 30.0), 300)
	var b: Array = _bridge_run(def, bp, rules, _start(def, Rng.new(5), 30.0), 300)
	assert_bool(FlightTestKit.state_bytes(a[0]) == FlightTestKit.state_bytes(b[0])).is_true()


func test_source_has_no_state() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/sim/steer/assist.gd")
	assert_bool(src.contains("\nvar ")).is_false()
	assert_bool(src.contains("static var")).is_false()
	for line: String in src.split("\n"):
		if line.begins_with("func "):
			fail("non-static func: " + line)
		if line.contains("Rng") or line.contains("Time.") or line.contains("randf"):
			fail("clock or RNG: " + line)


# The A-45 window (10 ticks), then on to 2 s: starts at 150-600 m AGL in level flight or a dive up to 30 degrees at
# v_cruise (a hand-over during a dive, SC-22; a stall mid-flight, SC-25), anywhere on cradle, any heading.
func test_bridge_window_no_terrain_contact_on_cradle() -> void:
	_classes_on_cradle(30.0, 2 * 30, "window")


# A long stall (C13 keeps LINK_BRIDGE until the 15 s native transport timeout) from level flight or a gentle
# descent up to 10 degrees: the bridge alone keeps every class off the cradle terrain.
func test_long_bridge_no_terrain_contact_on_cradle() -> void:
	_classes_on_cradle(10.0, 15 * 30, "long")


func _classes_on_cradle(max_dive: float, ticks: int, label: String) -> void:
	var rules: RulesDef = FlightTestKit.rules()
	for id: StringName in CLASSES:
		var def: ShipDef = FlightTestKit.ship(id)
		var bp: BridgeParams = _bp(id, rules)
		var rng: Rng = Rng.new(8000 + CLASSES.find(id))
		var hits: PackedStringArray = PackedStringArray()
		var worst: float = INF
		for k: int in STARTS:
			var s: ShipState = _start(def, rng, max_dive)
			var r: Array = _bridge_run(def, bp, rules, s, ticks)
			var min_agl: float = r[1]
			var hit_tick: int = r[2]
			worst = minf(worst, min_agl)
			if hit_tick >= 0:
				var _b: bool = hits.push_back("start %d hit at tick %d" % [k, hit_tick])
		print("BRIDGE %s %s: %d starts x %d ticks, contacts %d, min AGL %.1f m" % [label, id, STARTS, ticks,
			hits.size(), worst])
		assert_int(hits.size()).override_failure_message("%s %s: %s" % [label, id, "; ".join(hits)]).is_equal(0)


# Random start on cradle: direction uniform, 150-600 m AGL, heading uniform, dive 0..max_dive, speed v_cruise.
func _start(def: ShipDef, rng: Rng, max_dive: float) -> ShipState:
	var n: Vector3 = Vector3(rng.next_float() * 2.0 - 1.0, rng.next_float() * 2.0 - 1.0, rng.next_float() * 2.0 - 1.0)
	n = n.normalized() if n.length_squared() > 1e-6 else Vector3(1, 0, 0)
	var f: Basis = Sphere.tangent_frame(n)
	var hd: float = rng.next_float() * TAU
	var heading: Vector3 = f.x * cos(hd) + f.y * sin(hd)
	var agl: float = 150.0 + rng.next_float() * 450.0
	return _dive_on(def, _cradle, n, heading, agl, rng.next_float() * max_dive, def.v_cruise)


func _dive(def: ShipDef, n: Vector3, heading: Vector3, agl: float, dive_deg: float, speed: float) -> ShipState:
	return _dive_on(def, Terrain.new(), n, heading, agl, dive_deg, speed)


func _dive_on(def: ShipDef, t: Terrain, n: Vector3, heading: Vector3, agl: float, dive_deg: float, speed: float) -> ShipState:
	var a: float = deg_to_rad(dive_deg)
	var fwd: Vector3 = (heading * cos(a) - n * sin(a)).normalized()
	var up: Vector3 = (n - fwd * n.dot(fwd)).normalized()
	var p: Vector3 = n * (Sphere.PLANET_RADIUS + t.height_at(n) + agl)
	return FlightTestKit.spawn(def, p, fwd, up, fwd * speed)


# [final state, min AGL, first contact tick or -1] of `ticks` bridge ticks over cradle.
func _bridge_run(def: ShipDef, bp: BridgeParams, rules: RulesDef, s: ShipState, ticks: int) -> Array:
	var probe: ProbeResult = ProbeResult.new()
	var inp: PilotInput = PilotInput.new()
	var common: FlightCommonDef = FlightTestKit.common()
	var min_agl: float = INF
	for t: int in ticks:
		Assist.link_bridge(Ai05Kit.basis(s), s.p, s.v, _cradle, bp, probe, inp)
		Ai05Kit.step(s, inp, def, common, rules, _cradle)
		min_agl = minf(min_agl, Ai05Kit.agl(s, _cradle))
		if s.terrain_hit:
			return [s, min_agl, t]
	return [s, min_agl, -1]
