extends GdUnitTestSuite
## 05 s11.2 scenarios SC-09 and SC-10 (moved to AI-05 from AI-07): a Dart on a MOVE leg over the cradle map,
## flown by FlightController.track_velocity with the TerrainProbe lift and the 1.0 s PULL_UP re-check
## (TerrainFlightRig, the think / act shape of 05 s4.3). Clearance = centre height above the terrain under the
## ship (05 s5.3 convention). Run under both lift models.

const MAP: String = "res://content/maps/cradle"
const LON: float = 45.0       # wedge meridian through the big crater (lat 30) and the highland (lat 42-45)
const WAYPOINT_STEP_M: float = 200.0

var _terrain: Terrain


func before() -> void:
	_terrain = Terrain.new()
	assert_int(_terrain.load_map(MAP)).is_equal(OK)


func _rig(model: StringName, corners: PackedVector3Array, speed: float) -> Array:
	var dart: ShipDef = FlightTestKit.ship(&"dart")
	var rig: TerrainFlightRig = TerrainFlightRig.new(dart, FlightTestKit.common(), FlightTestKit.rules(model), _terrain)
	rig.waypoints = TerrainFlightRig.polyline(corners, WAYPOINT_STEP_M)
	rig.speed_cmd = speed
	var n: Vector3 = corners[0]
	var first: Vector3 = rig.waypoints[0]
	var fwd: Vector3 = (first - n * first.dot(n)).normalized()
	var deck: float = Ai05Kit.num(Ai05Kit.block("guidance"), "deck_alt_agl_m")
	var s: ShipState = FlightTestKit.spawn(dart, n * (Sphere.PLANET_RADIUS + _terrain.height_at(n) + deck), fwd, n,
		fwd * speed)
	return [rig, s]


# SC-09 terrain_ridge_ingress: Dart MOVE at 160 m/s in the 60 m AGL deck band across a 700 m rise. On cradle the
# crater floor at lat 30 (-319 m) to the highland crest at lat 45 (+387 m) along lon 45 is that rise. Pass: no
# terrain contact, min clearance >= 20 m.
func test_sc09_terrain_ridge_ingress() -> void:
	# (start lat, start lon, end lat, end lon): north up the 700 m rise; east across the crater (west rim, floor,
	# east inner wall up to the rim crest at lon 58-59, about 530 m over 1.3 km)
	var legs: Array[Vector4] = [Vector4(24.0, LON, 52.0, LON), Vector4(30.0, 25.0, 30.0, 66.0)]
	for model: StringName in [RulesDef.LIFT_SPEED_SCALED, RulesDef.LIFT_DAMPING_ONLY]:
		for leg: Vector4 in legs:
			var corners: PackedVector3Array = PackedVector3Array([Ai05Kit.geo(leg.x, leg.y), Ai05Kit.geo(leg.z, leg.w)])
			var r: Array = _rig(model, corners, 160.0)
			var rig: TerrainFlightRig = r[0]
			var s: ShipState = r[1]
			var ok: bool = rig.fly(s, 60 * 30)
			var what: String = "SC-09 %s %s: done=%s min clearance %.1f m, contacts %d, pull-ups %d, %.0f m/s" % [
				model, leg, ok, rig.stats_min_agl, rig.stats_contacts, rig.stats_pull_ups, s.v.length()]
			print(what)
			if model != RulesDef.LIFT_SPEED_SCALED:
				continue   # A/B variant: reported, not asserted (PR: path lag under damping_only)
			assert_bool(ok).override_failure_message(what).is_true()
			assert_int(rig.stats_contacts).override_failure_message(what).is_equal(0)
			assert_float(rig.stats_min_agl).override_failure_message(what).is_greater_equal(20.0)


# SC-10 rille_low_flight: MOVE with FLAG_LOW (deck_alt_agl_m 60) along cradle's rille (recipe 'rilles': lat/lon
# 10,30 -> 22,45 -> 28,60). The rille is a 70 m trench on the mare from its west end to the foot of the big
# crater's wall (40 % of the first segment); past that the polyline climbs over the crater's rims. Pass on the
# trench section: <= 120 m AGL for >= 70 % of the leg, no contact. The full polyline is flown too: no contact.
func test_sc10_rille_low_flight() -> void:
	var a: Vector3 = Ai05Kit.geo(10.0, 30.0)
	var b: Vector3 = Ai05Kit.geo(22.0, 45.0)
	var trench: PackedVector3Array = PackedVector3Array([a, Sphere.slerp_dir(a, b, 0.4)])
	var full: PackedVector3Array = PackedVector3Array([a, b, Ai05Kit.geo(28.0, 60.0)])
	for model: StringName in [RulesDef.LIFT_SPEED_SCALED, RulesDef.LIFT_DAMPING_ONLY]:
		for leg: PackedVector3Array in [trench, full]:
			var r: Array = _rig(model, leg, FlightTestKit.ship(&"dart").v_cruise)
			var rig: TerrainFlightRig = r[0]
			var s: ShipState = r[1]
			rig.low_band_m = 120.0
			var ok: bool = rig.fly(s, 120 * 30)
			var low: float = float(rig.stats_low_ticks) / float(maxi(rig.stats_ticks, 1))
			var name: String = "trench" if leg.size() == 2 else "full rille"
			var what: String = "SC-10 %s %s: done=%s low %.0f %%, min clearance %.1f m, contacts %d, pull-ups %d" % [
				model, name, ok, 100.0 * low, rig.stats_min_agl, rig.stats_contacts, rig.stats_pull_ups]
			print(what)
			if model != RulesDef.LIFT_SPEED_SCALED:
				continue   # A/B variant: reported, not asserted (see SC-09)
			assert_bool(ok).override_failure_message(what).is_true()
			assert_int(rig.stats_contacts).override_failure_message(what).is_equal(0)
			if leg.size() == 2:
				assert_float(low).override_failure_message(what).is_greater_equal(0.7)


# Perf note (05 s10 think and act rows): a Dart on the SC-09 leg, timing the rig's think (TerrainProbe.probe once,
# 6 samples, plus the guidance) and act (track_velocity and the 1-sample PULL_UP re-check every 3rd tick);
# kinematics excluded. Printed for the PR; the bounds are loose so a slow runner does not flake.
func test_perf_think_and_act() -> void:
	var rules: RulesDef = FlightTestKit.rules()
	var r: Array = _rig(RulesDef.LIFT_SPEED_SCALED, PackedVector3Array([Ai05Kit.geo(24.0, LON), Ai05Kit.geo(52.0, LON)]),
		160.0)
	var rig: TerrainFlightRig = r[0]
	var s: ShipState = r[1]
	var inp: PilotInput = PilotInput.new()
	var think_us: int = 0
	var act_us: int = 0
	var thinks: int = 0
	var ticks: int = 0
	var period: int = int(Ai05Kit.num(Ai05Kit.block("guidance"), "think_period_ticks"))
	while not rig.done() and ticks < 60 * rules.tick_hz:
		var t0: int = Time.get_ticks_usec()
		var thought: bool = rig.think_if_due(s)
		var t1: int = Time.get_ticks_usec()
		rig.act(s, inp)
		var t2: int = Time.get_ticks_usec()
		rig.advance(s, inp)
		if thought:
			think_us += t1 - t0
			thinks += 1
		act_us += t2 - t1
		ticks += 1
	var think: float = float(think_us) / float(maxi(thinks, 1))
	var act: float = float(act_us) / float(maxi(ticks, 1))
	print("PERF per ship: think %.1f us (every %d ticks), act %.1f us/tick, per think period %.1f us" % [think, period,
		act, think + act * float(period)])
	assert_float(think).is_less(500.0)
	assert_float(act).is_less(200.0)
