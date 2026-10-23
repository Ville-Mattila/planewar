extends GdUnitTestSuite
## AI-14 unit tests per behaviour of the Lancer brain (05 s6.4, s6.3 R3) through SimWorld.step() with Ai14Kit's
## driver: the rocket lock per `lock_time_s` (FIRE2 from the tick the target enters the seeker cone inside
## `lock_range_m`; the first rocket `lock_ticks` later with the sim's LOCK_ACQUIRED; never outside cone or range),
## the bomber reserve, the AUTO GUARD centre (structure cluster centroid), the ground-first choice flying a rocket
## AttackRun with a salvo of ceil(hp / rocket damage), and the counters of its weapons act.

const HZ: int = 30


# A world with the Ai14Kit driver (all four brains) whose enemy Bomber / Dart / Hauler fly DartKit.CruiseBrain.
func _world(seed_value: int) -> Array:
	var w: SimWorld = Ai14Kit.world(seed_value)
	var d: AiDriver = Ai14Kit.driver(w)
	return [w, d]


func _cruise(w: SimWorld, d: AiDriver, def: StringName, speed: float, agl: float) -> DartKit.CruiseBrain:
	var c: DartKit.CruiseBrain = DartKit.CruiseBrain.new(DartKit.gains_of(def), w.terrain())
	c.speed = speed
	c.agl = agl
	d.set_brain(Ai14Kit.cls(def), c)
	return c


func _fire2(w: SimWorld, id: int) -> bool:
	var inp: PilotInput = PilotInput.new()
	ControlTestKit.inputs(w).read_entity(EntityId.slot(id), inp)
	return (inp.buttons & PilotInput.FIRE2) != 0


# 05 s6.4 lock: an enemy Bomber 1.3 km ahead (inside the Lancer's 1.4 km sensor) flying away at 60 m/s, ATTACK on it. The Lancer holds FIRE2 from the tick the
# Bomber is inside the rocket seeker's cone and within lock_range_m (AiState.lock_tick; it restarts whenever the Bomber
# leaves the cone), on every tick after it, and the first rocket leaves lock_ticks (lock_time_s 0.8 s = 24 ticks) after
# the start of that continuous hold, on the sim's LOCK_ACQUIRED tick; FIRE2 is never held while the Bomber is outside
# the cone or beyond lock_range_m (judged after the step: the boundary tick at most).
func test_rocket_lock_holds_lock_time_s_before_the_first_rocket() -> void:
	var r: Array = _world(41)
	var w: SimWorld = r[0]
	var d: AiDriver = r[1]
	var c: DartKit.CruiseBrain = _cruise(w, d, &"bomber", 60.0, 300.0)
	var p0: Vector3 = DartKit.above(w, Vector3(1, 0, 0), 300.0)
	var h: Vector3 = DartKit.heading(p0, Vector3(0, 1, 0))
	var lancer: int = DartKit.spawn(w, &"lancer", 0, p0, h * 80.0, h)
	var pb: Vector3 = DartKit.above(w, DartKit.offset(Vector3(1, 0, 0), 0.0, 1300.0), 300.0)
	var bomber: int = DartKit.spawn(w, &"bomber", DartKit.FOE, pb, h * 60.0, h)
	c.heading[bomber] = DartKit.heading(pb, Vector3(0, 1, 0))
	DartKit.order(w, lancer, OrderSpec.make(OrderSpec.Kind.ATTACK, bomber))
	var s: int = EntityId.slot(lancer)
	var lp: LancerParams = (Ai14Kit.brain_of(d, &"lancer") as LancerBrain).lp
	var rockets0: int = w.view().rockets(lancer)
	var first_lock: int = -1
	var first_rocket: int = -1
	var acquired: int = -1
	var held_outside: int = 0
	var gaps: int = 0
	var held: PackedInt32Array = PackedInt32Array()   # ticks with FIRE2 held
	for _k: int in 40 * HZ:
		var ev: Array[SimEvent] = Ai14Kit.step(w)
		for e: SimEvent in ev:
			if e.kind == SimEvent.Kind.LOCK_ACQUIRED and e.a == lancer and acquired < 0:
				acquired = w.tick()
		var v: SimView = w.view()
		var rel: Vector3 = v.pos(bomber) - v.pos(lancer)
		var in_lock: bool = rel.length() <= lp.lock_range and (-v.basis(lancer).z).dot(rel.normalized()) >= lp.cone_cos
		if _fire2(w, lancer) and not in_lock:
			held_outside += 1   # the act decided on this tick's pre-kinematics pose: judged with the input, see below
		if _fire2(w, lancer):
			var _h: bool = held.push_back(w.tick())
		if first_rocket < 0 and v.rockets(lancer) < rockets0:
			first_rocket = w.tick()
			first_lock = d.state.lock_tick[s]   # the start of the continuous hold that fired
			break
	for t: int in range(first_lock, first_rocket + 1):
		gaps += 0 if held.has(t) else 1
	var what: String = "lock start %d, LOCK_ACQUIRED %d, first rocket %d (lock_ticks %d), FIRE2 gaps %d, FIRE2 outside %d" % [
		first_lock, acquired, first_rocket, lp.lock_ticks, gaps, held_outside]
	print(what)
	assert_int(lp.lock_ticks).is_equal(24)
	assert_int(first_lock).override_failure_message(what).is_greater(0)
	assert_int(gaps).override_failure_message(what).is_equal(0)
	assert_int(first_rocket - first_lock).override_failure_message(what).is_equal(lp.lock_ticks)   # exactly lock_time_s x tick_hz
	assert_int(acquired).override_failure_message(what).is_equal(first_rocket)
	assert_int(held_outside).override_failure_message(what).is_less_equal(1)   # the boundary tick at most


# 05 s6.4: while an enemy Bomber is known within bomber_known_m, rockets on anything else stop at bomber_reserve (2);
# on the Bomber itself the reserve is spent. The Lancer carries 3 rockets; target: an enemy Hauler 1.3 km ahead, an
# enemy Bomber 850 m behind it (the team sees both; the Bomber is never in the seeker cone while the Hauler is chased).
func test_bomber_reserve_keeps_two_rockets_for_bombers() -> void:
	var r: Array = _world(42)
	var w: SimWorld = r[0]
	var d: AiDriver = r[1]
	var ch: DartKit.CruiseBrain = _cruise(w, d, &"hauler", 40.0, 300.0)
	var cb: DartKit.CruiseBrain = _cruise(w, d, &"bomber", 60.0, 300.0)
	var p0: Vector3 = DartKit.above(w, Vector3(1, 0, 0), 300.0)
	var h: Vector3 = DartKit.heading(p0, Vector3(0, 1, 0))
	var lancer: int = DartKit.spawn(w, &"lancer", 0, p0, h * 80.0, h)
	var ph: Vector3 = DartKit.above(w, DartKit.offset(Vector3(1, 0, 0), 0.0, 1300.0), 300.0)
	var hauler: int = DartKit.spawn(w, &"hauler", DartKit.FOE, ph, h * 40.0, h)
	ch.heading[hauler] = DartKit.heading(ph, Vector3(0, 1, 0))
	var pb: Vector3 = DartKit.above(w, DartKit.offset(Vector3(1, 0, 0), -800.0, -300.0), 300.0)   # seen, behind: no lock
	var bomber: int = DartKit.spawn(w, &"bomber", DartKit.FOE, pb, h * 60.0, h)
	cb.heading[bomber] = DartKit.heading(pb, Vector3(0, 1, 0))
	w.store().rockets[EntityId.slot(lancer)] = 3
	DartKit.order(w, lancer, OrderSpec.make(OrderSpec.Kind.ATTACK, hauler))
	var s: int = EntityId.slot(lancer)
	var reserve_seen: bool = false
	for _k: int in 40 * HZ:
		var _e: Array[SimEvent] = Ai14Kit.step(w)
		reserve_seen = reserve_seen or (d.state.fire_mask[s] & AttackRun.FIRE_RESERVE) != 0
		if not w.view().alive(hauler):
			break
	var left: int = w.view().rockets(lancer)
	var what: String = "rockets left %d, reserve flag %s, hauler alive %s" % [left, reserve_seen, w.view().alive(hauler)]
	print(what)
	assert_bool(reserve_seen).override_failure_message(what).is_true()
	assert_int(left).override_failure_message(what).is_equal(2)
	DartKit.order(w, lancer, OrderSpec.make(OrderSpec.Kind.ATTACK, bomber))
	for _k: int in 60 * HZ:
		var _e: Array[SimEvent] = Ai14Kit.step(w)
		if w.view().rockets(lancer) < 2 or not w.view().alive(bomber):
			break
	assert_int(w.view().rockets(lancer)).override_failure_message("on the bomber: %d" % w.view().rockets(lancer)).is_less(2)


# 05 s6.4 AUTO = GUARD: the orbit centre is the centroid of the friendly structures within guard_cluster_m (800) of
# the home pad (one structure query); a structure beyond it and an enemy one inside it do not count.
func test_auto_guard_centres_on_the_structure_cluster() -> void:
	var r: Array = _world(43)
	var w: SimWorld = r[0]
	var d: AiDriver = r[1]
	var c0: Vector3 = Vector3(1, 0, 0)
	var core: int = Ai14Kit.core(w, c0, 0)
	var ref_p: Vector3 = DartKit.above(w, DartKit.offset(c0, 500.0, 0.0), 0.0)
	var refinery: int = DartKit.spawn(w, &"refinery", 0, ref_p, Vector3.ZERO, DartKit.heading(ref_p, Vector3(0, 1, 0)))
	var mast_p: Vector3 = DartKit.above(w, DartKit.offset(c0, 0.0, 600.0), 0.0)
	var mast: int = DartKit.spawn(w, &"sensor_mast", 0, mast_p, Vector3.ZERO, DartKit.heading(mast_p, Vector3(0, 1, 0)))
	var far_p: Vector3 = DartKit.above(w, DartKit.offset(c0, -1500.0, 0.0), 0.0)
	var _far: int = DartKit.spawn(w, &"sensor_mast", 0, far_p, Vector3.ZERO, DartKit.heading(far_p, Vector3(0, 1, 0)))
	var foe_p: Vector3 = DartKit.above(w, DartKit.offset(c0, -300.0, -300.0), 0.0)
	var _foe: int = DartKit.spawn(w, &"sensor_mast", DartKit.FOE, foe_p, Vector3.ZERO, DartKit.heading(foe_p, Vector3(0, 1, 0)))
	var up: Vector3 = w.view().pos(core).normalized()
	var lancer: int = DartKit.spawn(w, &"lancer", 0, w.view().pos(core) + up * 30.0, Vector3.ZERO, up)
	var brain: LancerBrain = Ai14Kit.brain_of(d, &"lancer") as LancerBrain
	var v: SimView = w.view()
	var want: Vector3 = (v.pos(core) + v.pos(refinery) + v.pos(mast)) / 3.0
	var s: int = EntityId.slot(lancer)
	var tags: Dictionary = {}
	for _k: int in 40 * HZ:
		var _e: Array[SimEvent] = Ai14Kit.step(w)
		tags[w.view().ai_tag(lancer)] = true
	var what: String = "home %s want %s, queries %d, tags %s, dist to centre %.0f" % [d.state.home[s], want,
		brain.stats_cluster_queries, str(tags.keys()), Guidance.ground_dist(w.view().pos(lancer), want)]
	print(what)
	assert_float(d.state.home[s].distance_to(want)).override_failure_message(what).is_less(0.01)
	assert_int(brain.stats_cluster_queries).override_failure_message(what).is_equal(1)
	assert_int(w.view().ai_tag(lancer)).override_failure_message(what).is_equal(AiTag.Tag.GUARD)
	assert_float(Guidance.ground_dist(w.view().pos(lancer), want)).override_failure_message(what).is_between(400.0, 800.0)


# 05 s6.4 ground-first: an enemy Harvester and an enemy Dart (weights 1.0 / 0.4) both inside the guard radius; the
# Lancer picks the Harvester and flies a rocket AttackRun (BOMB) whose R3 salvo is ceil(150 hp / 40) = 4 rockets;
# the Harvester takes rocket hits.
func test_ground_first_pick_flies_a_rocket_run() -> void:
	var r: Array = _world(44)
	var w: SimWorld = r[0]
	var d: AiDriver = r[1]
	var cd: DartKit.CruiseBrain = _cruise(w, d, &"dart", 90.0, 600.0)
	var c0: Vector3 = Vector3(1, 0, 0)
	var core: int = Ai14Kit.core(w, c0, 0)
	var up: Vector3 = w.view().pos(core).normalized()
	var lancer: int = DartKit.spawn(w, &"lancer", 0, w.view().pos(core) + up * 30.0, Vector3.ZERO, up)
	var hv_p: Vector3 = DartKit.above(w, DartKit.offset(c0, 1100.0, 300.0), 0.0)
	var harvester: int = DartKit.spawn(w, &"harvester", DartKit.FOE, hv_p, Vector3.ZERO, DartKit.heading(hv_p, Vector3(0, 1, 0)))
	var pd: Vector3 = DartKit.above(w, DartKit.offset(c0, -900.0, 400.0), 600.0)
	var hd: Vector3 = DartKit.heading(pd, Vector3(0, 0, 1))
	var dart: int = DartKit.spawn(w, &"dart", DartKit.FOE, pd, hd * 90.0, hd)
	cd.heading[dart] = hd
	var s: int = EntityId.slot(lancer)
	var picked: int = 0
	var salvo_wp: int = -1
	var rockets_at_release: int = -1
	var hp0: float = w.view().hp01(harvester)
	for _k: int in 120 * HZ:
		var _e: Array[SimEvent] = Ai14Kit.step(w)
		if picked == 0 and d.state.target[s] != 0:
			picked = d.state.target[s]
		if salvo_wp < 0 and d.state.mode[s] == AiTag.Tag.BOMB and AttackRun.step_of(d.state, s) == AttackRun.Step.RELEASE:
			salvo_wp = d.state.wp[s]
			rockets_at_release = w.view().rockets(lancer)
		if not w.view().alive(harvester):
			break   # the rockets of the pass are in flight at egress: run until they land
	var brain: LancerBrain = Ai14Kit.brain_of(d, &"lancer") as LancerBrain
	var what: String = "picked %s, salvo %d -> %d, harvester hp %.2f -> %.2f, ground candidates %d" % [
		"harvester" if picked == harvester else ("dart" if picked == dart else str(picked)), rockets_at_release, salvo_wp,
		hp0, w.view().hp01(harvester) if w.view().alive(harvester) else 0.0, brain.modes.stats_ground]
	print(what)
	assert_int(picked).override_failure_message(what).is_equal(harvester)
	assert_int(brain.modes.stats_ground).override_failure_message(what).is_greater(0)
	assert_int(rockets_at_release - salvo_wp).override_failure_message(what).is_equal(4)
	assert_bool(not w.view().alive(harvester) or w.view().hp01(harvester) < hp0).override_failure_message(what).is_true()
	assert_int(brain.stats_weapon_visible).override_failure_message(what).is_equal(brain.stats_weapon_acts)
