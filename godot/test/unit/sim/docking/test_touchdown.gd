extends GdUnitTestSuite
## GD-15 landings in a SimWorld (03 s6.4, R0 B.5, 02 s17.1): `Docking.land` at the end of step 9 on the PAD contacts of
## step 8. Covers the docked pose and events (LANDING then DOCKED), manual vs AUTO (an assist tick inside / outside the
## final 150 m; an unpossessed autopilot landing), hot by an enemy ship or a recent hit, dead stick, BENT hull damage,
## CRASH (the pad takes crash_pad_damage, R0 B.24 A-120), the pad-free rule (occupied, queue head, site, launch pad) and the pad_radius_m boundary through Collision.

var _w: SimWorld
var _pad: int


func before_test() -> void:
	_w = WorldTestKit.world()
	_pad = DockingTestKit.pad(_w)
	var _e: Array[SimEvent] = _w.drain_events()


func _slot(id: int) -> int:
	return EntityId.slot(id)


func _landing(events: Array[SimEvent]) -> SimEvent:
	var l: Array[SimEvent] = DockingTestKit.of_kind(events, SimEvent.Kind.LANDING)
	return l[0] if l.size() == 1 else null


# A Dart possessed by player 0 far from the pad (its last autopilot tick is beyond the window), then posed on the pad.
func _possessed_dart_on_pad() -> int:
	var id: int = DockingTestKit.ship_over(_w, &"dart", 0, 0, _pad, DockingTestKit.HIGH, 0.0)
	DockingTestKit.pose(_w, id, _pad, 100.0, _w.economy().docking.grade.manual_window_m * 3.0, Vector3.ZERO)
	assert_bool(DockingTestKit.possess(_w, id)).is_true()
	DockingTestKit.pose(_w, id, _pad, 6.0, 0.0, Vector3.ZERO)
	return id


func test_an_autopilot_landing_through_the_tick_docks_and_grades_auto() -> void:
	var sd: ShipDef = DockingTestKit.ship_def(&"dart")
	var id: int = DockingTestKit.ship_over(_w, &"dart", 0, 0, _pad, sd.bounding_radius, 0.0, -_w.store().up[_slot(_pad)] * 2.0)
	var _d: Array[SimEvent] = _w.drain_events()
	_w.step()
	var ev: Array[SimEvent] = _w.drain_events()
	var kinds: PackedInt32Array = WorldTestKit.kinds(ev)
	var li: int = kinds.find(SimEvent.Kind.LANDING)
	assert_int(li).is_greater_equal(0)
	assert_int(kinds.find(SimEvent.Kind.DOCKED)).is_equal(li + 1)            # LANDING, then DOCKED (03 s6.4)
	var e: SimEvent = ev[li]
	assert_int(e.a).is_equal(id)
	assert_int(e.b).is_equal(_pad)
	assert_int(e.tick).is_equal(_w.tick())
	assert_int(e.extra[0]).is_equal(LandingGrade.Grade.AUTO)
	assert_int(e.extra[2] & 1).is_equal(0)                                    # not manual
	var st: EntityStore = _w.store()
	var s: int = _slot(id)
	var p: int = _slot(_pad)
	assert_int(st.flags[s] & (EntityStore.F_DOCKED | EntityStore.F_LANDED)).is_equal(EntityStore.F_DOCKED | EntityStore.F_LANDED)
	assert_int(st.link[s]).is_equal(_pad)
	assert_vector(st.vel[s]).is_equal(Vector3.ZERO)
	assert_vector(st.pos[s]).is_equal_approx(st.pos[p] + st.up[p] * st.radius[s], Vector3.ONE * 1e-3)   # A-82 socket
	assert_vector(st.fwd[s]).is_equal_approx(st.up[p], Vector3.ONE * 1e-6)                             # nose up
	assert_float(st.up[s].dot(st.up[p])).is_equal_approx(0.0, 1e-6)
	assert_int(_w.view().landing_grade_last(id)).is_equal(LandingGrade.Grade.AUTO)
	assert_int(_w.view().dock_state(id)).is_equal(2)
	assert_int(_w.view().pad_occupant(_pad)).is_equal(id)
	for _t: int in 5:                                                          # parked: no second landing, no motion
		_w.step()
		assert_int(DockingTestKit.of_kind(_w.drain_events(), SimEvent.Kind.LANDING).size()).is_equal(0)
	assert_vector(st.pos[s]).is_equal_approx(st.pos[p] + st.up[p] * st.radius[s], Vector3.ONE * 1e-3)


func test_a_manual_landing_grades_by_q_and_carries_the_event_fields() -> void:
	var id: int = _possessed_dart_on_pad()
	var g: LandingGrade = _w.economy().docking.grade
	var r: float = DockingTestKit.pad_radius(_w, _pad)
	var _b: int = DockingTestKit.contact(_w, id, _pad, 1.0, 1.0, 2.0, 1.0)
	var e: SimEvent = _landing(_w.drain_events())
	assert_object(e).is_not_null()
	var q: float = g.q(1.0, 1.0, 2.0, 1.0, r)
	assert_float(e.value).is_equal_approx(q, 1e-6)
	assert_int(e.extra.size()).is_equal(5)
	assert_int(e.extra[0]).is_equal(g.grade(Collision.L_SAFE, q, true))
	assert_int(e.extra[0]).is_equal(LandingGrade.Grade.ACE)
	assert_int(e.extra[1]).is_equal(roundi(q * 255.0))
	assert_int(e.extra[2]).is_equal(1)                                         # manual, not hot, fuel full
	assert_int(e.extra[3]).is_equal(10)                                        # 1.0 m/s in 0.1 m/s
	assert_int(e.extra[4]).is_equal(10)
	assert_int(_w.view().landing_grade_last(id)).is_equal(LandingGrade.Grade.ACE)


func test_an_assist_tick_inside_the_final_150_m_grades_auto() -> void:
	var id: int = _possessed_dart_on_pad()
	var d: Docking = _w.economy().docking
	DockingTestKit.pose(_w, id, _pad, 40.0, d.grade.manual_window_m - 10.0, Vector3.ZERO)
	d.pilots.note_assist(_slot(id))                                            # the auto-dock seam (Assist.auto_dock acting)
	DockingTestKit.pose(_w, id, _pad, 6.0, 0.0, Vector3.ZERO)
	var _b: int = DockingTestKit.contact(_w, id, _pad, 1.0, 0.0, 0.0, 0.0)
	var e: SimEvent = _landing(_w.drain_events())
	assert_int(e.extra[0]).is_equal(LandingGrade.Grade.AUTO)
	assert_int(e.extra[2] & 1).is_equal(0)


func test_an_assist_tick_beyond_the_window_keeps_the_landing_manual() -> void:
	var id: int = _possessed_dart_on_pad()
	var d: Docking = _w.economy().docking
	DockingTestKit.pose(_w, id, _pad, 40.0, d.grade.manual_window_m + 10.0, Vector3.ZERO)
	d.pilots.note_assist(_slot(id))
	DockingTestKit.pose(_w, id, _pad, 6.0, 0.0, Vector3.ZERO)
	var _b: int = DockingTestKit.contact(_w, id, _pad, 1.0, 0.0, 0.0, 0.0)
	var e: SimEvent = _landing(_w.drain_events())
	assert_int(e.extra[2] & 1).is_equal(1)
	assert_int(e.extra[0]).is_equal(LandingGrade.Grade.ACE)


func test_a_link_bridge_tick_near_the_pad_grades_auto() -> void:
	# 05 C13: a silent pilot is flown by LINK_BRIDGE (step 4 substitution) while still POSSESSED: an assist tick.
	var id: int = _possessed_dart_on_pad()
	DockingTestKit.pose(_w, id, _pad, 60.0, 50.0, Vector3.ZERO)
	var bridged: bool = false
	for _t: int in 20:
		_w.step()
		bridged = bridged or _w.store().overlay[_slot(id)] == ControlMachine.Overlay.LINK_BRIDGE
	assert_bool(bridged).is_true()
	assert_int(_w.view().possessor(id)).is_equal(0)
	DockingTestKit.pose(_w, id, _pad, 6.0, 0.0, Vector3.ZERO)
	var _d: Array[SimEvent] = _w.drain_events()
	var _b: int = DockingTestKit.contact(_w, id, _pad, 1.0, 0.0, 0.0, 0.0)
	assert_int(_landing(_w.drain_events()).extra[0]).is_equal(LandingGrade.Grade.AUTO)


func test_possession_while_docked_has_no_autopilot_approach() -> void:
	var id: int = DockingTestKit.ship_over(_w, &"dart", 0, 0, _pad, DockingTestKit.HIGH)
	DockingTestKit.dock(_w, id, _pad)
	assert_bool(DockingTestKit.possess(_w, id)).is_true()
	var d: Docking = _w.economy().docking
	assert_bool(d.pilots.manual(id, _w.store().pos[_slot(_pad)], _w.store().up[_slot(_pad)], d.grade.manual_window_m)).is_true()
	assert_bool(d.pilots.manual(_pad, Vector3.ZERO, Vector3.UP, d.grade.manual_window_m)).is_false()   # not possessed


func test_hot_by_an_enemy_ship_within_1500_m_or_a_hit_within_5_s() -> void:
	var g: LandingGrade = _w.economy().docking.grade
	for _t: int in roundi(g.hot_window_s * 2.0 * float(WorldTestKit.content().rules.tick_hz)):   # past the first 5 s
		_w.step()
	var enemy: int = DockingTestKit.ship_over(_w, &"dart", 1, 1, _pad, DockingTestKit.HIGH)
	var cases: Array = [[g.hot_radius_m - 5.0, false, true], [g.hot_radius_m + 5.0, false, false], [g.hot_radius_m + 5.0, true, true]]
	for c: Array in cases:
		var w0: int = _w.tick()
		var id: int = DockingTestKit.ship_over(_w, &"dart", 0, 0, _pad, DockingTestKit.HIGH)
		DockingTestKit.pose(_w, enemy, _pad, 100.0, float(c[0]), Vector3.ZERO)
		DockingTestKit.pose(_w, id, _pad, 6.0, 0.0, Vector3.ZERO)
		var s: int = _slot(id)
		_w.store().last_damage_tick[s] = _w.tick() - roundi(g.hot_window_s * float(WorldTestKit.content().rules.tick_hz)) if bool(c[1]) else 0
		var _d: Array[SimEvent] = _w.drain_events()
		var _b: int = DockingTestKit.contact(_w, id, _pad, 1.0, 0.0, 0.0, 0.0)
		var e: SimEvent = _landing(_w.drain_events())
		assert_int(e.extra[2] & 2).override_failure_message("case %s at tick %d" % [str(c), w0]).is_equal(2 if bool(c[2]) else 0)
		DockingTestKit.clear(_w, id)                                          # free the pad for the next case
	_w.store().last_damage_tick[_slot(enemy)] = 0
	var late: int = DockingTestKit.ship_over(_w, &"dart", 0, 0, _pad, DockingTestKit.HIGH)
	DockingTestKit.pose(_w, late, _pad, 6.0, 0.0, Vector3.ZERO)
	_w.store().last_damage_tick[_slot(late)] = _w.tick() - roundi(g.hot_window_s * float(WorldTestKit.content().rules.tick_hz)) - 1   # just outside 5 s
	var _d2: Array[SimEvent] = _w.drain_events()
	var _b2: int = DockingTestKit.contact(_w, late, _pad, 1.0, 0.0, 0.0, 0.0)
	assert_int(_landing(_w.drain_events()).extra[2] & 2).is_equal(0)


func test_dead_stick_below_three_percent_fuel() -> void:
	var g: LandingGrade = _w.economy().docking.grade
	var sd: ShipDef = DockingTestKit.ship_def(&"dart")
	for share: float in [g.dead_stick_fuel01 * 0.5, g.dead_stick_fuel01 * 1.5]:
		var id: int = DockingTestKit.ship_over(_w, &"dart", 0, 0, _pad, DockingTestKit.HIGH)
		DockingTestKit.pose(_w, id, _pad, 6.0, 0.0, Vector3.ZERO)
		_w.store().fuel[_slot(id)] = sd.fuel_s * share
		var _d: Array[SimEvent] = _w.drain_events()
		var _b: int = DockingTestKit.contact(_w, id, _pad, 1.0, 0.0, 0.0, 0.0)
		assert_int(_landing(_w.drain_events()).extra[2] & 4).is_equal(4 if share < g.dead_stick_fuel01 else 0)
		DockingTestKit.clear(_w, id)


func test_damage_band_lands_bent_and_takes_the_hull_ratio() -> void:
	var c: FlightCommonDef = DockingTestKit.common()
	var id: int = DockingTestKit.ship_over(_w, &"dart", 0, 0, _pad, DockingTestKit.HIGH)
	DockingTestKit.pose(_w, id, _pad, 6.0, 0.0, Vector3.ZERO)
	var hp: float = _w.store().hp[_slot(id)]
	var vv: float = c.landing_safe_v_vert + (c.landing_damage_v_vert - c.landing_safe_v_vert) * 0.5       # ratio 0.5
	var tilt: float = c.landing_safe_pitch_deg + (c.landing_damage_tilt_deg - c.landing_safe_pitch_deg) * 0.25   # 0.25
	var _d: Array[SimEvent] = _w.drain_events()
	assert_int(DockingTestKit.contact(_w, id, _pad, vv, 0.0, tilt, 0.0)).is_equal(Collision.L_DAMAGE)
	var ev: Array[SimEvent] = _w.drain_events()
	var kinds: PackedInt32Array = WorldTestKit.kinds(ev)
	assert_array(Array(kinds)).is_equal([SimEvent.Kind.HIT, SimEvent.Kind.LANDING, SimEvent.Kind.DOCKED])
	assert_float(ev[0].value).is_equal_approx(hp * 0.5, 1e-3)                # max(ratios) = 0.5
	assert_float(_w.store().hp[_slot(id)]).is_equal_approx(hp * 0.5, 1e-3)
	assert_int(ev[1].extra[0]).is_equal(LandingGrade.Grade.BENT)


func test_a_hull_emptied_at_the_damage_limit_or_beyond_any_limit_crashes() -> void:
	var c: FlightCommonDef = DockingTestKit.common()
	for vv: float in [c.landing_damage_v_vert, c.landing_damage_v_vert + 1.0]:
		var id: int = DockingTestKit.ship_over(_w, &"dart", 0, 0, _pad, DockingTestKit.HIGH)
		DockingTestKit.pose(_w, id, _pad, 6.0, 0.0, Vector3.ZERO)
		var _d: Array[SimEvent] = _w.drain_events()
		var _b: int = DockingTestKit.contact(_w, id, _pad, vv, 0.0, 0.0, 0.0)
		var ev: Array[SimEvent] = _w.drain_events()
		assert_int(_landing(ev).extra[0]).is_equal(LandingGrade.Grade.CRASH)
		assert_int(DockingTestKit.of_kind(ev, SimEvent.Kind.DOCKED).size()).is_equal(0)
		assert_float(_w.store().hp[_slot(id)]).is_equal(0.0)
		_w.step()                                                              # the deferred death of the crash
		assert_bool(_w.view().alive(id)).is_false()


# R0 B.24 A-120: on a CRASH outcome (DESTROY band, or a DAMAGE band that empties the hull) the pad takes
# flight_common.crash_pad_damage through DamageSink, the HIT naming the ship (02 s2.2: "the pad takes 100 damage").
func test_a_crash_on_a_pad_deals_crash_pad_damage_to_it_named_after_the_ship() -> void:
	var c: FlightCommonDef = DockingTestKit.common()
	var dmg: float = DockingTestKit.crash_pad_damage()
	assert_float(dmg).is_equal(100.0)                                        # 02 s2.2 literal
	var p: int = _slot(_pad)
	for hull_empty: bool in [false, true]:
		var hp0: float = _w.store().hp[p]
		var id: int = DockingTestKit.ship_over(_w, &"dart", 0, 0, _pad, DockingTestKit.HIGH)
		DockingTestKit.pose(_w, id, _pad, 6.0, 0.0, Vector3.ZERO)
		var vv: float = c.landing_damage_v_vert + 1.0                         # DESTROY band
		if hull_empty:
			_w.store().hp[_slot(id)] = 1.0
			vv = (c.landing_safe_v_vert + c.landing_damage_v_vert) * 0.5      # DAMAGE band, the hull runs out
		var _d: Array[SimEvent] = _w.drain_events()
		var _b: int = DockingTestKit.contact(_w, id, _pad, vv, 0.0, 0.0, 0.0)
		var ev: Array[SimEvent] = _w.drain_events()
		assert_int(_landing(ev).extra[0]).is_equal(LandingGrade.Grade.CRASH)
		assert_float(_w.store().hp[p]).is_equal_approx(hp0 - dmg, 1e-3)
		var pad_hits: Array[SimEvent] = []
		for e: SimEvent in DockingTestKit.of_kind(ev, SimEvent.Kind.HIT):
			if e.a == _pad:
				pad_hits.append(e)
		assert_int(pad_hits.size()).is_equal(1)
		assert_int(pad_hits[0].b).is_equal(id)                               # attacker = the crashing ship
		assert_float(pad_hits[0].value).is_equal(dmg)
		_w.step()
		assert_bool(_w.view().alive(id)).is_false()
	var hp1: float = _w.store().hp[p]
	var safe: int = DockingTestKit.ship_over(_w, &"dart", 0, 0, _pad, DockingTestKit.HIGH, 60.0)
	DockingTestKit.pose(_w, safe, _pad, 6.0, 0.0, Vector3.ZERO)
	var _x: int = DockingTestKit.contact(_w, safe, _pad, c.landing_safe_v_vert, 0.0, 0.0, 0.0)
	assert_float(_w.store().hp[p]).is_equal(hp1)                              # a landing that is not a crash costs the pad nothing


# R0 B.25 A-135 (amends A-120, closes CQ-8): a crash is ship contact, not a projectile, so no shield absorbs it
# (02 s4.3 rule 6 covers shield_absorbed projectiles only): the Core takes the full crash_pad_damage, charge untouched.
func test_a_crash_on_the_shielded_core_reaches_the_core_unshielded() -> void:
	var c: FlightCommonDef = DockingTestKit.common()
	var core: int = DockingTestKit.pad(_w, &"core", 0, 0, 1500.0)
	_w.step()
	var k: int = _slot(core)
	assert_bool(_w.shields().core_up(0)).is_true()
	var charge0: float = _w.shields().charge_of(k)
	var hp0: float = _w.store().hp[k]
	var id: int = DockingTestKit.ship_over(_w, &"dart", 0, 0, core, DockingTestKit.HIGH)
	DockingTestKit.pose(_w, id, core, 6.0, 0.0, Vector3.ZERO)
	var _d: Array[SimEvent] = _w.drain_events()
	var _b: int = DockingTestKit.contact(_w, id, core, c.landing_damage_v_vert + 1.0, 0.0, 0.0, 0.0)
	assert_int(_landing(_w.drain_events()).extra[0]).is_equal(LandingGrade.Grade.CRASH)
	assert_float(_w.store().hp[k]).is_equal_approx(hp0 - DockingTestKit.crash_pad_damage(), 1e-3)
	assert_float(_w.shields().charge_of(k)).is_equal(charge0)


func test_a_crash_through_the_tick_dies_the_same_tick() -> void:
	var c: FlightCommonDef = DockingTestKit.common()
	var sd: ShipDef = DockingTestKit.ship_def(&"dart")
	var up: Vector3 = _w.store().up[_slot(_pad)]
	var id: int = DockingTestKit.ship_over(_w, &"dart", 0, 0, _pad, sd.bounding_radius, 0.0, -up * (c.landing_damage_v_vert + 5.0))
	var _d: Array[SimEvent] = _w.drain_events()
	_w.step()
	var ev: Array[SimEvent] = _w.drain_events()
	assert_int(_landing(ev).extra[0]).is_equal(LandingGrade.Grade.CRASH)
	var deaths: Array[SimEvent] = DockingTestKit.of_kind(ev, SimEvent.Kind.DEATH)
	assert_int(deaths.size()).is_equal(1)
	assert_int(deaths[0].a).is_equal(id)
	assert_bool(_w.view().alive(id)).is_false()


func test_an_occupied_pad_holds_the_arrival_unless_it_crashes() -> void:
	var a: int = DockingTestKit.ship_over(_w, &"dart", 0, 0, _pad, DockingTestKit.HIGH)
	DockingTestKit.dock(_w, a, _pad)
	var b: int = DockingTestKit.ship_over(_w, &"dart", 0, 0, _pad, DockingTestKit.HIGH)
	DockingTestKit.pose(_w, b, _pad, 6.0, 3.0, Vector3.ZERO)
	var _d: Array[SimEvent] = _w.drain_events()
	var _x: int = DockingTestKit.contact(_w, b, _pad, 1.0, 0.0, 0.0, 3.0)
	assert_int(_w.drain_events().size()).is_equal(0)                          # holds: nothing happens
	assert_int(_w.store().flags[_slot(b)] & EntityStore.F_DOCKED).is_equal(0)
	var _y: int = DockingTestKit.contact(_w, b, _pad, DockingTestKit.common().landing_damage_v_vert + 1.0, 0.0, 0.0, 3.0)
	assert_int(_landing(_w.drain_events()).extra[0]).is_equal(LandingGrade.Grade.CRASH)


func test_a_site_or_a_launch_pad_never_takes_a_landing() -> void:
	var site: int = DockingTestKit.pad(_w, &"pad", 0, 0, 900.0)
	_w.store().flags[_slot(site)] |= EntityStore.F_BUILDING
	var yard: int = DockingTestKit.pad(_w, &"shipyard", 0, 0, 1800.0)
	for p: int in [site, yard]:
		var id: int = DockingTestKit.ship_over(_w, &"dart", 0, 0, p, DockingTestKit.HIGH)
		DockingTestKit.pose(_w, id, p, 6.0, 0.0, Vector3.ZERO)
		var _d: Array[SimEvent] = _w.drain_events()
		var _b: int = DockingTestKit.contact(_w, id, p, 1.0, 0.0, 0.0, 0.0)
		assert_int(_w.drain_events().size()).is_equal(0)


func test_two_arrivals_in_one_tick_dock_only_the_first() -> void:
	var a: int = DockingTestKit.ship_over(_w, &"dart", 0, 0, _pad, DockingTestKit.HIGH)
	var b: int = DockingTestKit.ship_over(_w, &"dart", 2, 0, _pad, DockingTestKit.HIGH)
	DockingTestKit.pose(_w, a, _pad, 6.0, 0.0, Vector3.ZERO)
	DockingTestKit.pose(_w, b, _pad, 6.0, 2.0, Vector3.ZERO)
	var c: Collision = _w.collision
	for k: int in 2:
		c.c_kind[k] = Collision.C_PAD
		c.c_class[k] = Collision.L_SAFE
		c.c_a[k] = a if k == 0 else b
		c.c_b[k] = _pad
		c.c_value[k] = 2.0 * float(k)
		c.c_vec[k] = Vector3(1.0, 0.0, 0.0)
	c.contact_count = 2
	var _d: Array[SimEvent] = _w.drain_events()
	_w.economy().docking.land(_w.tick(), c)
	var l: Array[SimEvent] = DockingTestKit.of_kind(_w.drain_events(), SimEvent.Kind.LANDING)
	assert_int(l.size()).is_equal(1)
	assert_int(l[0].a).is_equal(a)
	assert_int(_w.economy().docking.touchdown.landed).is_equal(1)


func test_the_pad_radius_boundary_through_collision() -> void:
	var sd: ShipDef = DockingTestKit.ship_def(&"dart")
	var r: float = DockingTestKit.pad_radius(_w, _pad)
	var up: Vector3 = _w.store().up[_slot(_pad)]
	for off: float in [r - 0.05, r + 0.05]:
		var id: int = DockingTestKit.ship_over(_w, &"dart", 0, 0, _pad, sd.bounding_radius, off, -up)
		var _d: Array[SimEvent] = _w.drain_events()
		_w.step()
		var e: SimEvent = _landing(_w.drain_events())
		if off < r:
			assert_object(e).is_not_null()
			assert_int(e.extra[0]).is_equal(LandingGrade.Grade.AUTO)
			DockingTestKit.clear(_w, id)
		else:
			assert_object(e).is_null()
