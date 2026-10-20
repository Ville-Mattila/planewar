extends GdUnitTestSuite
## SC-16 possess_during_final_approach (05:1003, 05:237): the AI-09 autopilot flies RETURN to L5 HOVER, the player
## possesses with DOCK held and the ship lands. The caller (here the test, in the game the sim at POSSESS) copies the
## autopilot's LandingState into the assist, so the phase continues: no regression to L4, no altitude gain (the A-70
## floor would climb a ship dropped back to L4), a safe tail-down touchdown, and the AUTO mark (`assist_near`) set.

const PAD_LAT: float = 40.0
const PAD_LON: float = 22.5
const SEEDS: int = 12
const R: float = Sphere.PLANET_RADIUS


static func at(center: Vector3, dist: float, az_deg: float, agl: float) -> Vector3:
	var f: Basis = Sphere.tangent_frame(center)
	var az: float = deg_to_rad(az_deg)
	var b: Vector3 = f.y * cos(az) + f.x * sin(az)
	return (center * cos(dist / R) + b * sin(dist / R)) * (R + agl)


static func heading(p: Vector3, to: Vector3, off_deg: float) -> Vector3:
	var n: Vector3 = p.normalized()
	return ((to - n * to.dot(n)).normalized()).rotated(n, deg_to_rad(off_deg))


func _handoff(id: StringName, seed_value: int) -> String:
	var pad_dir: Vector3 = Ai05Kit.geo(PAD_LAT, PAD_LON)
	var sc: LandingScenario = LandingScenario.new(Terrain.new())
	var pad: int = sc.world.add_pad(pad_dir)
	var rng: Rng = Rng.new(seed_value)
	var p: Vector3 = at(pad_dir, rng.range_f(1200.0, 2200.0), rng.range_f(0.0, 360.0), 300.0)
	var def: ShipDef = FlightTestKit.ship(id)
	var _i: int = sc.add_ship(id, p, heading(p, pad_dir, rng.range_f(-60.0, 60.0)), def.v_cruise, pad, true)
	var want: int = LandingController.Phase.HOVER
	var guard: int = 0
	while sc.phase(0) != want and sc.world.flying(0) and guard < 90 * 30:
		sc.step()
		guard += 1
	if sc.phase(0) != want or not sc.world.flying(0):
		return "%s seed %d: never reached L5 (phase %d)" % [id, seed_value, sc.phase(0)]
	# possession with DOCK held: the autopilot's LandingState goes to the assist
	var slot: int = EntityId.slot(sc.world.ids[0])
	var ls: LandingState = LandingState.new()
	ls.phase = sc.st.land_phase[slot]
	ls.attempts = sc.st.land_attempts[slot]
	ls.bearing = sc.st.land_bearing[slot]
	ls.integ = sc.st.integ[slot]
	var world: LandingWorld = sc.world
	var prm: LandingParams = Ai09Kit.landing(world.rules)
	var g: FlightGains = Ai05Kit.gains(def, world.rules)
	var ship: ShipSnapshot = ShipSnapshot.new()
	var pad_s: PadSnapshot = PadSnapshot.new()
	pad_s.p = world.pad_pos[0]
	pad_s.n = world.pad_up[0]
	pad_s.radius_m = world.pad_radius_by_def[LandingWorld.PAD_DEF]
	pad_s.valid = true
	var inp: PilotInput = PilotInput.new()
	var h0: float = world.ss[0].p.dot(pad_s.n) - pad_s.p.dot(pad_s.n)
	var h_max: float = h0
	var min_phase: int = ls.phase
	for t: int in 60 * 30:
		if not world.flying(0):
			break
		inp.thrust = 0.3
		inp.pitch = 0.0
		inp.yaw = 0.0
		inp.roll = 0.0
		inp.buttons = PilotInput.DOCK
		Ai09Kit.snapshot(world.ss[0], def, world.common, world.rules, ship)
		var acted: bool = Assist.auto_dock(ls, ship, pad_s, prm, g, world.common.auto_dock_radius_m,
			world.common.auto_dock_latch_mult, inp)
		if not acted:
			return "%s seed %d: assist off at tick %d phase %d" % [id, seed_value, t, ls.phase]
		min_phase = mini(min_phase, ls.phase)
		h_max = maxf(h_max, world.ss[0].p.dot(pad_s.n) - pad_s.p.dot(pad_s.n))
		world.step_ship(0, inp)
		world.end_tick()
	var td: Vector4 = world.touchdown[0]
	var what: String = "%s seed %d: outcome %d td %s h0 %.1f h_max %.2f min_phase %d" % [id, seed_value,
		world.outcome[0], td, h0, h_max, min_phase]
	if world.outcome[0] != LandingWorld.Outcome.LANDED or world.scrapes[0] != 0:
		return "no safe landing: " + what
	if td.z > 25.0:
		return "tilt: " + what
	if h_max > h0 + 1.0:
		return "altitude gain: " + what
	if min_phase < want:
		return "phase regression: " + what
	if not ls.assist_near:
		return "no AUTO mark: " + what
	return ""


func _run(id: StringName) -> void:
	var fails: PackedStringArray = PackedStringArray()
	for k: int in SEEDS:
		var r: String = _handoff(id, 1700 + k)
		if r != "":
			var _b: bool = fails.push_back(r)
	print("SC-16 handoff %s: %d/%d" % [id, SEEDS - fails.size(), SEEDS])
	assert_int(fails.size()).override_failure_message("; ".join(fails)).is_equal(0)


func test_dart_possessed_in_l5_lands() -> void:
	_run(&"dart")


func test_bomber_possessed_in_l5_lands() -> void:
	_run(&"bomber")
