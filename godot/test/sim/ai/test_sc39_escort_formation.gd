extends GdUnitTestSuite
## 05 s11.2 SC-39 escort_formation (AI-11): a Bomber on a 5 km MOVE with 2 Dart ESCORT, through SimWorld.step() with an
## AiDriver hook (FormationKit: EscortPilot on the Darts, FlightController on the Bomber). Pass: the escorts are within
## 80 m of their slots for >= 80 % of the run, no friendly collision (no DEATH, centres never within the bounding radii).
## The Darts start 150-250 m off their slots, so the run includes the join-up.

const LEG_M: float = 5000.0
const WITHIN_M: float = 80.0
const FRACTION: float = 0.8
const MAX_TICKS: int = 30 * 140


func _run(seed_value: int, wing: bool) -> Dictionary:
	var w: SimWorld = WorldTestKit.world(seed_value)
	var pilot: EscortPilot = FormationKit.pilot(&"dart")
	var escort: FormationKit.EscortTestBrain = FormationKit.EscortTestBrain.new(pilot)
	var leader: FormationKit.LeaderTestBrain = FormationKit.LeaderTestBrain.new(FormationKit.gains(&"bomber"))
	var d: AiDriver = FormationKit.driver(w, escort, leader)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	var alt: float = leader.alt_cmd
	var east: Vector3 = Vector3(0, 1, 0)
	var vb: Vector3 = east * leader.speed
	var bomber: int = WorldTestKit.spawn(w, &"bomber", 0, 0, WorldTestKit.at(alt, 0.0), vb)
	var theta: float = LEG_M / (Sphere.PLANET_RADIUS + alt)   # arc length along the flight level
	leader.goal = Vector3(cos(theta), sin(theta), 0.0) * (Sphere.PLANET_RADIUS + alt)
	var darts: PackedInt32Array = PackedInt32Array()
	for k: int in 2:
		var off: Vector3 = Vector3(rng.randf_range(-250.0, -150.0), rng.randf_range(-250.0, 250.0), rng.randf_range(0.0, 60.0))
		var p: Vector3 = WorldTestKit.at(alt + off.z, off.x + (0.0 if k == 0 else 0.0))
		p.y += off.y
		var _p: bool = darts.push_back(WorldTestKit.spawn(w, &"dart", 0, 0, p, vb))
	assert_bool(d.register(bomber, FormationKit.CLS_LEADER)).is_true()
	for id: int in darts:
		assert_bool(d.register(id, FormationKit.CLS_ESCORT)).is_true()
	FormationKit.move_order(w, bomber, leader.goal)
	FormationKit.escort_order(w, PackedInt32Array([darts[0]]), bomber, 0 if wing else -1)
	FormationKit.escort_order(w, PackedInt32Array([darts[1]]), bomber, 1 if wing else -1)
	var in_slot: int = 0
	var samples: int = 0
	var min_sep: float = INF
	var deaths: int = 0
	var ticks: int = 0
	while not leader.arrived and ticks < MAX_TICKS:
		w.step()
		for e: SimEvent in w.drain_events():
			deaths += 1 if e.kind == SimEvent.Kind.DEATH else 0
		ticks += 1
		if ticks % 10 != 0:
			continue
		var v: SimView = w.view()
		for id: int in darts:
			samples += 1
			in_slot += 1 if pilot.slot_error(id, v, d.state) <= WITHIN_M else 0
			min_sep = minf(min_sep, v.pos(id).distance_to(v.pos(bomber)) - v.radius(id) - v.radius(bomber))
		min_sep = minf(min_sep, v.pos(darts[0]).distance_to(v.pos(darts[1])) - 2.0 * v.radius(darts[0]))
	return {"frac": float(in_slot) / float(maxi(samples, 1)), "min_sep": min_sep, "deaths": deaths, "ticks": ticks,
		"arrived": leader.arrived}


func test_sc39_escort_formation_class_slots() -> void:
	for sv: int in [39, 40, 41]:
		var r: Dictionary = _run(sv, false)
		var what: String = "SC-39 seed %d: in slot %.0f %%, min gap %.1f m, deaths %d, %d ticks, arrived %s" % [
			sv, float(r["frac"]) * 100.0, r["min_sep"], r["deaths"], r["ticks"], r["arrived"]]
		print(what)
		assert_bool(r["arrived"]).override_failure_message(what).is_true()
		assert_float(r["frac"]).override_failure_message(what).is_greater_equal(FRACTION)
		assert_int(r["deaths"]).override_failure_message(what).is_equal(0)
		assert_float(r["min_sep"]).override_failure_message(what).is_greater(0.0)


func test_sc39_escort_formation_wing_slots() -> void:
	var r: Dictionary = _run(42, true)
	var what: String = "SC-39 (SL-2 wing slots): in slot %.0f %%, min gap %.1f m, deaths %d" % [
		float(r["frac"]) * 100.0, r["min_sep"], r["deaths"]]
	print(what)
	assert_float(r["frac"]).override_failure_message(what).is_greater_equal(FRACTION)
	assert_int(r["deaths"]).override_failure_message(what).is_equal(0)
