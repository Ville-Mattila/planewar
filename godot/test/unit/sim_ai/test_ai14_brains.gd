extends GdUnitTestSuite
## AI-14 unit tests per behaviour of the Bomber and Scout brains and the rules every class brain shares (05 s6.4,
## s2.5; R0 B.17 A-92 / A-94): the PULL_UP exit in every brain, the Bomber's AUTO RETURN / DOCKED, its refusal to
## dogfight, an ATTACK on a ship, the R1 abort under attack and the R2 continue, the Scout's cell choice (staleness over
## distance, threat and fuel exclusions), its flee rule (armed and closing only, ends beyond `flee_clear_m`), and
## determinism plus a mid-fight S4 restore of a world flown by the four brains (FORMAT 6, a rocket lock in progress).

const HZ: int = 30


# R0 B.17 A-92 in every class brain: a think with TTI >= safety_clear_tti_s and the hold met but climb_need_mps > 0
# stays in PULL_UP; 400 m up (no climb need) it resumes prev_mode (the DartBrain exit the class brains inherit).
func test_pull_up_exit_waits_for_the_climb_need_in_every_class_brain() -> void:
	for def: StringName in [&"lancer", &"bomber", &"scout"]:
		var w: SimWorld = Ai14Kit.world(23)
		var d: AiDriver = Ai14Kit.driver(w)
		var brain: DartBrain = Ai14Kit.brain_of(d, def) as DartBrain
		var st: AiState = d.state
		var sink: CommandSink = CommandSink.new()
		var up: Vector3 = Vector3(1, 0, 0)
		var v0: float = Ai14Kit.ship(def).v_cruise
		var h_req: float = brain.probe_params.required_clearance(v0)   # 3 m under it: a climb need, no ballistic contact
		var low: int = DartKit.spawn(w, def, 0, DartKit.above(w, up, h_req - 3.0), Vector3(5, v0, 0), Vector3(0, 1, 0))
		var high: int = DartKit.spawn(w, def, 0, DartKit.above(w, DartKit.offset(up, 3000.0, 0.0), 400.0), Vector3(0, v0, 0),
			Vector3(0, 1, 0))
		var v: SimView = w.view()
		for id: int in [low, high]:
			var s: int = EntityId.slot(id)
			st.mode[s] = AiTag.Tag.PULL_UP
			st.prev_mode[s] = AiTag.Tag.HOLD
			st.mode_since[s] = 0
			st.home[s] = v.pos(id)
			brain.think_one(id, v, st, sink, 600)
		var sl: int = EntityId.slot(low)
		var what: String = "%s: low tti %.1f lift %.1f mode %d, high mode %d" % [def, st.tti[sl], st.lift[sl], st.mode[sl],
			st.mode[EntityId.slot(high)]]
		assert_float(st.tti[sl]).override_failure_message(what).is_greater_equal(brain.prm.clear_tti)
		assert_float(st.lift[sl]).override_failure_message(what).is_greater(0.0)
		assert_int(st.mode[sl]).override_failure_message(what).is_equal(AiTag.Tag.PULL_UP)
		assert_int(st.mode[EntityId.slot(high)]).override_failure_message(what).is_not_equal(AiTag.Tag.PULL_UP)


# 05 s6.4 Bomber AUTO = DOCKED: airborne with no order it asks once for a system RETURN (FLAG_PREPEND, issuer -1);
# docked it shows DOCKED and asks for nothing.
func test_bomber_auto_returns_once_and_docked_stays_docked() -> void:
	var w: SimWorld = Ai14Kit.world(51)
	var d: AiDriver = Ai14Kit.driver(w)
	var core: int = Ai14Kit.core(w, Vector3(1, 0, 0), 0)
	var p: Vector3 = DartKit.above(w, DartKit.offset(Vector3(1, 0, 0), 2000.0, 0.0), 400.0)
	var h: Vector3 = DartKit.heading(p, Vector3(0, 1, 0))
	var bomber: int = DartKit.spawn(w, &"bomber", 0, p, h * 70.0, h)
	var up: Vector3 = w.view().pos(core).normalized()
	var parked: int = DartKit.spawn(w, &"bomber", 0, w.view().pos(core) + up * 10.0, Vector3.ZERO, up)
	var ps: int = EntityId.slot(parked)
	w.store().flags[ps] |= EntityStore.F_DOCKED
	w.store().link[ps] = core
	for _k: int in 3 * d.think_period() + 2:
		var _e: Array[SimEvent] = Ai14Kit.step(w)
	var head: OrderSpec = w.view().order_head(bomber)
	assert_object(head).is_not_null()
	assert_int(head.kind).is_equal(OrderSpec.Kind.RETURN)
	assert_int(w.view().order_issuer(bomber)).is_equal(-1)
	var issued: int = head.issue_tick
	for _k: int in 5 * d.think_period():
		var _e: Array[SimEvent] = Ai14Kit.step(w)
	assert_int(w.view().order_head(bomber).issue_tick).is_equal(issued)   # one request: no second RETURN on top
	assert_int(d.state.mode[EntityId.slot(bomber)]).is_equal(AiTag.Tag.RETURN)
	assert_object(w.view().order_head(parked)).is_null()
	assert_int(w.view().ai_tag(parked)).is_equal(AiTag.Tag.DOCKED)


# 05 s6.4: the Bomber never dogfights: on PATROL with an enemy Dart crossing 700 m away it runs no choice point and
# never enters an air-combat mode.
func test_bomber_never_dogfights() -> void:
	var w: SimWorld = Ai14Kit.world(52)
	var d: AiDriver = Ai14Kit.driver(w)
	var cd: DartKit.CruiseBrain = DartKit.CruiseBrain.new(DartKit.gains_of(&"dart"), w.terrain())
	cd.speed = 90.0
	d.set_brain(Ai14Kit.cls(&"dart"), cd)
	var c0: Vector3 = Vector3(1, 0, 0)
	var p: Vector3 = DartKit.above(w, c0, 400.0)
	var h: Vector3 = DartKit.heading(p, Vector3(0, 1, 0))
	var bomber: int = DartKit.spawn(w, &"bomber", 0, p, h * 70.0, h)
	var pd: Vector3 = DartKit.above(w, DartKit.offset(c0, 700.0, 0.0), 400.0)
	var dart: int = DartKit.spawn(w, &"dart", DartKit.FOE, pd, h * 90.0, h)
	cd.heading[dart] = h
	var patrol: OrderSpec = OrderSpec.make(OrderSpec.Kind.PATROL)
	patrol.points = PackedVector3Array([DartKit.above(w, DartKit.offset(c0, 0.0, 1500.0), 400.0),
		DartKit.above(w, DartKit.offset(c0, 0.0, -1500.0), 400.0)])
	DartKit.order(w, bomber, patrol)
	var modes: Dictionary = {}
	for _k: int in 20 * HZ:
		var _e: Array[SimEvent] = Ai14Kit.step(w)
		modes[d.state.mode[EntityId.slot(bomber)]] = true
	var brain: BomberBrain = Ai14Kit.brain_of(d, &"bomber") as BomberBrain
	assert_int(brain.modes.stats_choices).is_equal(0)
	for m: int in [AiTag.Tag.INTERCEPT, AiTag.Tag.ENGAGE, AiTag.Tag.EXTEND, AiTag.Tag.EVADE]:
		assert_bool(modes.has(m)).override_failure_message(str(modes.keys())).is_false()
	assert_bool(modes.has(AiTag.Tag.PATROL)).is_true()


# 05 s6.4: only ATTACK / MOVE / RETURN / HOLD suit a Bomber; an ATTACK on a ship is done at once and RETURN follows.
func test_bomber_attack_on_a_ship_is_done_and_returns() -> void:
	var w: SimWorld = Ai14Kit.world(53)
	var d: AiDriver = Ai14Kit.driver(w, true, 3, [false, true, true, true])
	var c0: Vector3 = Vector3(1, 0, 0)
	var p: Vector3 = DartKit.above(w, c0, 400.0)
	var h: Vector3 = DartKit.heading(p, Vector3(0, 1, 0))
	var bomber: int = DartKit.spawn(w, &"bomber", 0, p, h * 70.0, h)
	var dart: int = DartKit.spawn(w, &"dart", DartKit.FOE, DartKit.above(w, DartKit.offset(c0, 600.0, 0.0), 400.0), h * 90.0, h)
	for _k: int in 3:
		var _x: Array[SimEvent] = Ai14Kit.step(w)
	DartKit.order(w, bomber, OrderSpec.make(OrderSpec.Kind.ATTACK, dart))
	for _k: int in 3 * d.think_period():
		var _e: Array[SimEvent] = Ai14Kit.step(w)
	assert_int(w.view().order_head(bomber).kind).is_equal(OrderSpec.Kind.RETURN)
	assert_int(w.view().order_issuer(bomber)).is_equal(-1)
	assert_bool(d.state.mode[EntityId.slot(bomber)] == AiTag.Tag.INTERCEPT).is_false()


# 05 s6.4 / s6.3: damage taken during R1 aborts the run to egress (no reattack, RETURN follows); in R2 a hull above
# abort_hp01 keeps the run going.
func test_bomber_aborts_under_attack_in_r1_and_continues_in_r2() -> void:
	for phase: int in [AttackRun.Step.ROUTE, AttackRun.Step.RUN_IN]:
		var w: SimWorld = Ai14Kit.world(54)
		var d: AiDriver = Ai14Kit.driver(w)
		var tgt: Vector3 = Vector3(1, 0, 0)
		var refinery: int = DartKit.spawn(w, &"refinery", DartKit.FOE, DartKit.above(w, tgt, 0.0), Vector3.ZERO, Vector3(0, 1, 0))
		var mast_p: Vector3 = DartKit.above(w, DartKit.offset(tgt, -1000.0, 0.0), 0.0)
		var _m: int = DartKit.spawn(w, &"sensor_mast", 0, mast_p, Vector3.ZERO, DartKit.heading(mast_p, Vector3(0, 1, 0)))
		var p0: Vector3 = DartKit.above(w, DartKit.offset(tgt, -4500.0, 150.0), 300.0)
		var h0: Vector3 = DartKit.heading(p0, DartKit.above(w, tgt, 300.0))
		var bomber: int = DartKit.spawn(w, &"bomber", 0, p0, h0 * 70.0, h0)
		for _k: int in 3:
			var _x: Array[SimEvent] = Ai14Kit.step(w)
		DartKit.order(w, bomber, OrderSpec.make(OrderSpec.Kind.ATTACK, refinery))
		var s: int = EntityId.slot(bomber)
		for _k: int in 120 * HZ:
			var _e: Array[SimEvent] = Ai14Kit.step(w)
			if AttackRun.step_of(d.state, s) == phase:
				break
		assert_int(AttackRun.step_of(d.state, s)).is_equal(phase)
		var hp: float = float(Ai14Kit.ship(&"bomber").hp) * 0.8   # 80 %: above abort_hp01 0.5
		OverlayKit.ok(w, CommandPayload.debug_set(0, bomber, CommandPayload.SET_HP, hp))
		for _k: int in 2 * d.think_period():
			var _e: Array[SimEvent] = Ai14Kit.step(w)
		var step: int = AttackRun.step_of(d.state, s)
		var what: String = "hit in step %d -> step %d, bflags %d" % [phase, step, d.state.bflags[s]]
		if phase == AttackRun.Step.ROUTE:
			assert_int(step).override_failure_message(what).is_equal(AttackRun.Step.EGRESS)
			assert_int(d.state.bflags[s] & AttackRun.F_ABORTED).override_failure_message(what).is_equal(AttackRun.F_ABORTED)
		else:
			assert_bool(step == AttackRun.Step.RUN_IN or step == AttackRun.Step.RELEASE).override_failure_message(what).is_true()


# One airborne Scout over its home Core with the driver's intel; returns [world, driver, brain, scout, map].
func _scout_rig(seed_value: int) -> Array:
	var w: SimWorld = Ai14Kit.world(seed_value)
	var d: AiDriver = Ai14Kit.driver(w)
	var _core: int = Ai14Kit.core(w, Vector3(1, 0, 0), 0)
	var p: Vector3 = DartKit.above(w, Vector3(1, 0, 0), 500.0)
	var h: Vector3 = DartKit.heading(p, Vector3(0, 1, 0))
	var scout: int = DartKit.spawn(w, &"scout", 0, p, h * 140.0, h)
	for _k: int in 2 * HZ:
		var _e: Array[SimEvent] = Ai14Kit.step(w)
	return [w, d, Ai14Kit.brain_of(d, &"scout") as ScoutBrain, scout, d.threat_map(0)]


# The cell `goal` lies in (the Scout's chosen cell).
static func _goal_cell(map: ThreatMap, d: AiDriver, scout: int) -> int:
	return map.tables.cell_of(d.state.goal[EntityId.slot(scout)], -1)


# 05 s6.4 cell choice: max staleness_s / (1 + dist_km). Every cell is marked seen now except a near one seen 60 s ago
# and a far one never seen; the formula picks between them; an air threat in the winner moves the pick to the other;
# with fuel for a short trip only the near one is left.
func test_scout_cell_choice_staleness_threat_and_fuel() -> void:
	var r: Array = _scout_rig(61)
	var w: SimWorld = r[0]
	var d: AiDriver = r[1]
	var brain: ScoutBrain = r[2]
	var scout: int = r[3]
	var map: ThreatMap = r[4]
	var s: int = EntityId.slot(scout)
	var tick: int = w.tick()
	var p: Vector3 = w.view().pos(scout)
	var here: int = map.tables.cell_of(p, -1)
	var near: int = -1
	var far: int = -1
	for c: int in ThreatMap.CELLS:
		var dk: float = p.normalized().angle_to(map.tables.centre[c]) * Sphere.PLANET_RADIUS
		if near < 0 and c != here and dk > 2500.0 and dk < 3000.0:
			near = c
		if far < 0 and dk > 9000.0 and dk < 10000.0:
			far = c
	assert_bool(near >= 0 and far >= 0).override_failure_message("near %d far %d here %d" % [near, far, here]).is_true()
	map.last_seen.fill(tick)
	map.last_seen[near] = tick - 60 * HZ
	map.last_seen[far] = -1
	var d_near: float = p.normalized().angle_to(map.tables.centre[near]) * Sphere.PLANET_RADIUS * 0.001
	var d_far: float = p.normalized().angle_to(map.tables.centre[far]) * Sphere.PLANET_RADIUS * 0.001
	var u_near: float = 60.0 / (1.0 + d_near)
	var u_far: float = (float(tick + 1) / float(HZ)) / (1.0 + d_far)
	var winner: int = near if u_near > u_far else far
	var other: int = far if winner == near else near
	d.state.mode[s] = AiTag.Tag.PATROL
	d.state.timer[s] = -1000.0   # the last scan long ago: the next think scans
	brain.think_one(scout, w.view(), d.state, CommandSink.new(), tick)
	assert_int(_goal_cell(map, d, scout)).override_failure_message("u near %.2f far %.2f" % [u_near, u_far]).is_equal(winner)
	map.ch[ThreatMap.AIR_HIGH * ThreatMap.CELLS + winner] = 5.0
	d.state.mode[s] = AiTag.Tag.PATROL
	d.state.timer[s] = -1000.0
	brain.think_one(scout, w.view(), d.state, CommandSink.new(), tick)
	assert_int(_goal_cell(map, d, scout)).is_equal(other)
	map.ch[ThreatMap.AIR_HIGH * ThreatMap.CELLS + winner] = 0.0
	map.last_seen[near] = tick   # only the far cell is stale: picked on full fuel ...
	d.state.mode[s] = AiTag.Tag.PATROL
	d.state.timer[s] = -1000.0
	brain.think_one(scout, w.view(), d.state, CommandSink.new(), tick)
	assert_int(_goal_cell(map, d, scout)).is_equal(far)
	w.store().fuel[s] = 0.45 * Ai14Kit.ship(&"scout").fuel_s   # ... not on 81 s (51 s past the reserve: ~7 km round trip)
	d.state.mode[s] = AiTag.Tag.PATROL
	d.state.timer[s] = -1000.0
	var scans: int = brain.stats_scans
	brain.think_one(scout, w.view(), d.state, CommandSink.new(), tick)
	assert_int(brain.stats_scans).is_equal(scans + 1)
	assert_vector(d.state.goal[s]).is_equal(Vector3.ZERO)   # nothing reachable: the patrol fallback
	assert_int(d.state.mode[s]).is_equal(AiTag.Tag.PATROL)


# 05 s6.4 flee: an armed enemy (Dart) inside flee_radius_m flying at the Scout -> FLEE (BOOST, FLIP when it is ahead and
# the flip is ready, heading away, the deck band); an unarmed one (Hauler) or an armed one flying away -> no flee; the
# flee ends once the threat is beyond flee_clear_m.
func test_scout_flees_armed_closing_enemies_only() -> void:
	for case: int in 3:
		var r: Array = _scout_rig(62 + case)
		var w: SimWorld = r[0]
		var d: AiDriver = r[1]
		var brain: ScoutBrain = r[2]
		var scout: int = r[3]
		var s: int = EntityId.slot(scout)
		var v: SimView = w.view()
		var p: Vector3 = v.pos(scout)
		var ahead: Vector3 = (-v.basis(scout).z)
		ahead = (ahead - p.normalized() * ahead.dot(p.normalized())).normalized()
		var def: StringName = &"hauler" if case == 1 else &"dart"
		var pe: Vector3 = p + ahead * (900.0 if case != 2 else -900.0)
		var he: Vector3 = -ahead   # cases 0 / 1 fly at the Scout; case 2 is behind it flying away (opening)
		var e: int = DartKit.spawn(w, def, DartKit.FOE, pe, he * 60.0, he)
		for _k: int in 6:
			var _x: Array[SimEvent] = Ai14Kit.step(w)
		assert_bool(w.view().visible_to(0, e)).is_true()
		d.state.mode[s] = AiTag.Tag.SEARCH
		var flees: int = brain.stats_flees
		brain.think_one(scout, w.view(), d.state, CommandSink.new(), w.tick())
		var what: String = "case %d (%s): mode %d, flees %d -> %d, bflags %d" % [case, def, d.state.mode[s], flees,
			brain.stats_flees, d.state.bflags[s]]
		if case != 0:
			assert_int(d.state.mode[s]).override_failure_message(what).is_not_equal(AiTag.Tag.FLEE)
			continue
		assert_int(d.state.mode[s]).override_failure_message(what).is_equal(AiTag.Tag.FLEE)
		assert_int(brain.stats_flees).override_failure_message(what).is_equal(flees + 1)
		assert_int(d.state.bflags[s] & AttackRun.F_BOOST).override_failure_message(what).is_equal(AttackRun.F_BOOST)
		assert_int(d.state.bflags[s] & AttackRun.F_FLIP).override_failure_message(what).is_equal(AttackRun.F_FLIP)
		assert_float(d.state.guidance_point[s].dot(ahead)).override_failure_message(what).is_less(-0.9)
		var es: int = EntityId.slot(e)
		w.store().pos[es] = p + ahead * 2500.0   # beyond flee_clear_m
		for _k: int in 6:
			var _y: Array[SimEvent] = Ai14Kit.step(w)
		brain.think_one(scout, w.view(), d.state, CommandSink.new(), w.tick())
		assert_int(d.state.mode[s]).override_failure_message(what).is_equal(AiTag.Tag.SEARCH)
		assert_int(w.view().ai_tag(scout)).is_not_equal(AiTag.Tag.NONE)


# A world flown by the four brains: team 0 Lancer on an enemy Bomber (CruiseBrain), team 0 Bomber on an enemy Refinery,
# team 0 Scout on AUTO; intel for both teams. Returns [world, driver, enemy bomber brain, lancer].
func _fight(seed_value: int) -> Array:
	var w: SimWorld = Ai14Kit.world(seed_value)
	var d: AiDriver = Ai14Kit.driver(w)
	var c: DartKit.CruiseBrain = DartKit.CruiseBrain.new(DartKit.gains_of(&"bomber"), w.terrain())
	c.speed = 60.0
	c.agl = 300.0
	d.set_brain(Ai14Kit.cls(&"bomber"), c)   # the enemy Bomber flies straight; team 0 has no Bomber in this rig
	var c0: Vector3 = Vector3(1, 0, 0)
	var _core: int = Ai14Kit.core(w, c0, 0)
	var p0: Vector3 = DartKit.above(w, DartKit.offset(c0, 0.0, -500.0), 300.0)
	var h: Vector3 = DartKit.heading(p0, Vector3(0, 1, 0))
	var lancer: int = DartKit.spawn(w, &"lancer", 0, p0, h * 80.0, h)
	var pb: Vector3 = DartKit.above(w, DartKit.offset(c0, 0.0, 800.0), 300.0)
	var bomber: int = DartKit.spawn(w, &"bomber", DartKit.FOE, pb, h * 60.0, h)
	c.heading[bomber] = DartKit.heading(pb, Vector3(0, 1, 0))
	var ps: Vector3 = DartKit.above(w, DartKit.offset(c0, 500.0, 0.0), 500.0)
	var _scout: int = DartKit.spawn(w, &"scout", 0, ps, h * 140.0, h)
	DartKit.order(w, lancer, OrderSpec.make(OrderSpec.Kind.ATTACK, bomber))
	var s: int = EntityId.slot(lancer)
	for _k: int in 40 * HZ:
		var _e: Array[SimEvent] = Ai14Kit.step(w)
		if d.state.lock_tick[s] != 0 and w.tick() - d.state.lock_tick[s] == 10:
			break   # saved mid-lock: lock_tick and the seeker's lock_time are both live
	return [w, d, c, lancer]


# Determinism and S4 (FORMAT 6): the same seed twice gives the same bytes; saved mid-lock and restored into a world whose
# driver is configured before SimWorld.deserialize, both runs stay byte-identical for 300 ticks.
func test_class_brains_are_deterministic_and_restore_s4_mid_lock() -> void:
	var a: Array = _fight(71)
	var b: Array = _fight(71)
	var wa: SimWorld = a[0]
	var wb: SimWorld = b[0]
	var da: AiDriver = a[1]
	var lancer: int = a[3]
	assert_int(da.state.lock_tick[EntityId.slot(lancer)]).is_not_equal(0)
	assert_bool(wa.serialize() == wb.serialize()).is_true()
	var bytes: PackedByteArray = wa.serialize()
	var d2: AiDriver = Ai14Kit.make_driver(Terrain.new())
	var ca: DartKit.CruiseBrain = a[2]
	var c2: DartKit.CruiseBrain = DartKit.CruiseBrain.new(ca.gains, Terrain.new())
	c2.speed = ca.speed
	c2.agl = ca.agl
	c2.heading = ca.heading.duplicate()
	d2.set_brain(Ai14Kit.cls(&"bomber"), c2)
	var w2: SimWorld = SimWorld.deserialize(bytes, Ai14Kit.content(), d2)
	assert_object(w2).is_not_null()
	d2.set_terrain(w2.terrain())
	assert_bool(w2.serialize() == bytes).is_true()
	var rockets0: int = wa.view().rockets(lancer)
	for _k: int in 300:
		wa.step()
		w2.step()
		var _x: Array[SimEvent] = wa.drain_events()
		var _y: Array[SimEvent] = w2.drain_events()
	assert_int(wa.view().rockets(lancer)).is_less(rockets0)   # the lock fired after the save point
	assert_bool(w2.serialize() == wa.serialize()).is_true()
