extends GdUnitTestSuite
## AI-13 acceptance append (R0 B.12 A-69, B.15 A-88 (3), A-89) on the cradle map through SimWorld.step() with the Dart
## brain (DartKit): SC-09 and SC-10 as MOVE orders flown by DartBrain (the drop-free terrain lift on the current radial
## speed, the act-time PULL_UP trigger = 1.0 s re-sample OR pull-up budget), SC-11 as the SAFETY overlay with the
## budget ORed in (Overlays.run_safety). In all three the Dart never enters a state SweepScenarios.dive_recoverable
## classifies as unrecoverable (DartKit.recoverable: the 19 fixed-elevation pull-ups and Assist.pull_up from that
## state on the map's terrain), checked every tick while the Dart sinks (SC-09 / SC-10) and every tick of the overlay
## (SC-11). Lift model: the shipped `speed_scaled` (asserted); the AI-05 rig versions stay in test_sc_terrain_flight.gd.
## "Contact" = the centre within the bounding radius (+ 0.5 m) of the terrain, hull damage or death.

const MAP: StringName = &"cradle"
const HZ: int = 30


class Run extends RefCounted:
	var min_agl: float = INF
	var low_ticks: int = 0
	var ticks: int = 0
	var checks: int = 0
	var unrecoverable: int = 0
	var arrived: bool = false
	var contacts: int = 0      ## ticks with the centre within the bounding radius (+ 0.5 m) of the terrain
	var hp: float = 1.0
	var pull_ups: int = 0
	var longest_pull_up: int = 0   ## ticks (R0 B.17 A-92: reported; no max hold in v1)


# Flies a MOVE (FLAG_LOW) from `a` to `b` (unit directions) starting at the deck band at `speed`; stops on arrival
# (within the order's arrival radius) or after `max_s`.
func _move(a: Vector3, b: Vector3, speed: float, max_s: int, low_band: float = INF) -> Run:
	var w: SimWorld = DartKit.world(9, MAP)
	var brain: DartBrain = DartKit.brain(w)
	var _d: AiDriver = DartKit.driver(w, brain)
	var prm: DartParams = DartKit.params()
	var p0: Vector3 = DartKit.above(w, a, prm.deck_agl)
	var h: Vector3 = DartKit.heading(p0, b)
	var id: int = DartKit.spawn(w, &"dart", 0, p0, h * speed, h)
	var mv: OrderSpec = OrderSpec.make(OrderSpec.Kind.MOVE, 0, DartKit.above(w, b, prm.deck_agl), OrderSpec.FLAG_LOW)
	DartKit.order(w, id, mv)
	var g: FlightGains = DartKit.gains()
	var r: Run = Run.new()
	for k: int in max_s * HZ:
		w.step()
		var _e: Array[SimEvent] = w.drain_events()
		if not w.view().alive(id):
			r.hp = 0.0
			break
		var agl: float = DartKit.agl(w, id)
		r.min_agl = minf(r.min_agl, agl)
		r.ticks += 1
		r.low_ticks += 1 if agl <= low_band else 0
		r.contacts += 1 if agl <= DartKit.ship(&"dart").bounding_radius + 0.5 else 0
		r.hp = w.view().hp01(id)
		if w.view().vel(id).dot(w.view().pos(id).normalized()) < 0.0:   # every tick while sinking (A-88 (3): "never")
			r.checks += 1
			r.unrecoverable += 0 if DartKit.recoverable(w, id, g) else 1
		if Guidance.ground_dist(w.view().pos(id), b * w.view().pos(id).length()) <= prm.arrival:
			r.arrived = true
			break
	r.pull_ups = brain.stats_pull_ups
	r.longest_pull_up = brain.stats_longest_pull_up
	return r


func _report(name: String, r: Run) -> String:
	var what: String = "%s: arrived=%s min AGL %.1f m, low %.0f %%, contacts %d, hp %.2f, pull-ups %d (longest %d ticks), unrecoverable %d of %d checks" % [
		name, r.arrived, r.min_agl, 100.0 * float(r.low_ticks) / float(maxi(r.ticks, 1)), r.contacts, r.hp, r.pull_ups, r.longest_pull_up,
		r.unrecoverable, r.checks]
	print(what)
	return what


# SC-09 terrain_ridge_ingress: Dart MOVE (FLAG_LOW: the 60 m deck band) across the 700 m rise from the big crater's
# floor (lat 30, -319 m) to the highland (lat 45, +387 m) along lon 45, and east across the crater (its east wall,
# ~530 m over 1.3 km), entering at 160 m/s. Pass: no contact, min clearance >= 20 m, never unrecoverable.
func test_sc09_terrain_ridge_ingress_dart_brain() -> void:
	assert_str(String(DartKit.content().rules.lift_model)).is_equal(String(RulesDef.LIFT_SPEED_SCALED))   # the asserted model
	var legs: Array[Vector4] = [Vector4(24.0, 45.0, 52.0, 45.0), Vector4(30.0, 25.0, 30.0, 66.0)]
	for leg: Vector4 in legs:
		var r: Run = _move(DartKit.geo(leg.x, leg.y), DartKit.geo(leg.z, leg.w), 160.0, 60)
		var what: String = _report("SC-09 %s" % leg, r)
		assert_bool(r.arrived).override_failure_message(what).is_true()
		assert_float(r.hp).override_failure_message(what).is_equal(1.0)
		assert_int(r.contacts).override_failure_message(what).is_equal(0)
		assert_float(r.min_agl).override_failure_message(what).is_greater_equal(20.0)
		assert_int(r.unrecoverable).override_failure_message(what).is_equal(0)


# SC-10 rille_low_flight: MOVE with FLAG_LOW along cradle's rille (recipe 'rilles': 10,30 -> 22,45 -> 28,60). The
# trench is the first 40 % of the first segment: <= 120 m AGL for >= 70 % of it; the full polyline is flown as two MOVE
# legs (order completion is not wired, so one MOVE per run): no contact. Never unrecoverable on any of them.
func test_sc10_rille_low_flight_dart_brain() -> void:
	assert_str(String(DartKit.content().rules.lift_model)).is_equal(String(RulesDef.LIFT_SPEED_SCALED))   # the asserted model
	var a: Vector3 = DartKit.geo(10.0, 30.0)
	var b: Vector3 = DartKit.geo(22.0, 45.0)
	var c: Vector3 = DartKit.geo(28.0, 60.0)
	var cruise: float = DartKit.ship(&"dart").v_cruise
	var trench: Run = _move(a, Sphere.slerp_dir(a, b, 0.4), cruise, 60, 120.0)
	var what: String = _report("SC-10 trench", trench)
	assert_bool(trench.arrived).override_failure_message(what).is_true()
	assert_float(trench.hp).override_failure_message(what).is_equal(1.0)
	assert_int(trench.contacts).override_failure_message(what).is_equal(0)
	assert_float(float(trench.low_ticks) / float(maxi(trench.ticks, 1))).override_failure_message(what).is_greater_equal(0.7)
	assert_int(trench.unrecoverable).override_failure_message(what).is_equal(0)
	for leg: Array in [[a, b], [b, c]]:
		var r: Run = _move(leg[0] as Vector3, leg[1] as Vector3, cruise, 90)
		var w2: String = _report("SC-10 rille leg", r)
		assert_bool(r.arrived).override_failure_message(w2).is_true()
		assert_float(r.hp).override_failure_message(w2).is_equal(1.0)
		assert_int(r.contacts).override_failure_message(w2).is_equal(0)
		assert_int(r.unrecoverable).override_failure_message(w2).is_equal(0)


# SC-11 release_terrain_imminent on cradle: possessed Dart, scripted inputs dive at 190 m/s (30 degrees) over the mare
# east of the rille's west end; release at 150 m AGL. Pass: PULL_UP within 1 tick; survives (full hull); the overlay
# ends with TTI >= 4 s; never unrecoverable from the release to the end of the overlay (every tick) and in the brain's
# next 5 s (every tick while sinking).
func test_sc11_release_terrain_imminent_on_cradle() -> void:
	assert_str(String(DartKit.content().rules.lift_model)).is_equal(String(RulesDef.LIFT_SPEED_SCALED))   # the asserted model
	var w: SimWorld = DartKit.world(11, MAP)
	var d: AiDriver = DartKit.driver(w)
	var dir0: Vector3 = DartKit.geo(12.0, 20.0)
	var p0: Vector3 = DartKit.above(w, dir0, 700.0)
	var east: Vector3 = DartKit.heading(p0, DartKit.geo(12.0, 40.0))
	var up: Vector3 = p0.normalized()
	var fwd: Vector3 = (east * cos(deg_to_rad(30.0)) - up * sin(deg_to_rad(30.0))).normalized()
	var id: int = DartKit.spawn(w, &"dart", 0, p0, fwd * 190.0, fwd)
	OverlayKit.ok(w, Command.possess(0, id))
	w.step()
	var guard: int = 0
	while DartKit.agl(w, id) > 150.0 and guard < 300:
		OverlayKit.pilot(w, 0, 0.0, 0.0)
		w.step()
		guard += 1
	OverlayKit.ok(w, Command.release(0))
	w.step()
	var t_rel: int = w.tick()
	var s: int = EntityId.slot(id)
	var g: FlightGains = DartKit.gains()
	var pull_tick: int = t_rel if (d.state.ov_flags[s] & AiState.OV_PULL_UP) != 0 else -1
	var unrec: int = 0 if DartKit.recoverable(w, id, g) else 1
	var checks: int = 1
	var min_agl: float = DartKit.agl(w, id)
	var ticks: int = 0
	while d.state.overlay[s] != Overlays.NONE and ticks < 600:
		w.step()
		var _e: Array[SimEvent] = w.drain_events()
		ticks += 1
		min_agl = minf(min_agl, DartKit.agl(w, id))
		if pull_tick < 0 and (d.state.ov_flags[s] & AiState.OV_PULL_UP) != 0:
			pull_tick = w.tick()
		checks += 1
		unrec += 0 if DartKit.recoverable(w, id, g) else 1
	var end_tti: float = d.state.tti[s]
	var ended: bool = d.state.overlay[s] == Overlays.NONE
	for k: int in 5 * HZ:
		w.step()
		var _e2: Array[SimEvent] = w.drain_events()
		min_agl = minf(min_agl, DartKit.agl(w, id))
		if w.view().vel(id).dot(w.view().pos(id).normalized()) < 0.0:
			checks += 1
			unrec += 0 if DartKit.recoverable(w, id, g) else 1
	var what: String = "SC-11 cradle: pull-up at +%d ticks, overlay %d ticks, min AGL %.1f m, end TTI %.2f s, hp %.2f, unrecoverable %d of %d checks" % [
		pull_tick - t_rel, ticks, min_agl, end_tti, w.view().hp01(id), unrec, checks]
	print(what)
	assert_int(pull_tick).override_failure_message(what).is_between(t_rel, t_rel + 1)
	assert_bool(ended).override_failure_message(what).is_true()
	assert_float(end_tti).override_failure_message(what).is_greater_equal(4.0)
	assert_bool(w.view().alive(id)).override_failure_message(what).is_true()
	assert_float(w.view().hp01(id)).override_failure_message(what).is_equal(1.0)
	assert_int(unrec).override_failure_message(what).is_equal(0)
