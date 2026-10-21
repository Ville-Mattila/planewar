extends GdUnitTestSuite
## AI-13 unit tests per behaviour of the Dart brain (05 s6.2, s6.3, s5.3; R0 B.12 A-69, B.15 A-89): the parameter
## parse, the Guidance shaping, the SAFETY overlay's pull-up budget OR, patrol geometry, the aim-error draw, the
## AttackRun ingress band, the RTB rule, vision fairness, the launch rule, AiState FORMAT 5 and its derived
## focus-fire counts, determinism and S4 of a brain-flown world, and the purity of the brain sources.

const R: float = Sphere.PLANET_RADIUS
const TO := preload("res://test/unit/sim_ai/test_overlays.gd")
const BRAIN_FILES: PackedStringArray = ["res://src/sim_ai/brains/dart_brain.gd", "res://src/sim_ai/brains/dart_modes.gd",
	"res://src/sim_ai/brains/dart_combat.gd", "res://src/sim_ai/brains/attack_run.gd",
	"res://src/sim_ai/brains/dart_params.gd", "res://src/sim_ai/autopilot/guidance.gd"]


func test_params_parse_and_refuse_every_missing_key() -> void:
	var p: DartParams = DartKit.params()
	assert_object(p).is_not_null()
	assert_float(p.cruise_agl).is_equal(300.0)
	assert_float(p.deck_agl).is_equal(60.0)
	assert_float(p.fire_range).is_equal(650.0)
	assert_int(p.burst_ticks).is_equal(18)
	assert_int(p.cycle_ticks).is_equal(27)
	assert_float(p.slug_speed).is_equal(700.0)
	assert_float(p.threat_range[DartKit.def_id(&"flak_battery")]).is_equal(1500.0)
	assert_int(p.threat_kind[DartKit.def_id(&"flak_battery")]).is_equal(DartParams.THREAT_FLAK)
	assert_int(p.threat_kind[DartKit.def_id(&"autocannon_turret")]).is_equal(DartParams.THREAT_GUN)
	assert_int(p.threat_kind[DartKit.def_id(&"missile_tower")]).is_equal(DartParams.THREAT_MISSILE)
	assert_float(p.hp_by_def[DartKit.def_id(&"refinery")]).is_equal(1000.0)
	var blocks: Dictionary = {"": DartParams.KEYS, "gun": DartParams.GUN_KEYS, "bomb": DartParams.BOMB_KEYS,
		"evade": DartParams.EVADE_KEYS, "guidance": DartParams.GUIDE_KEYS, "intercept": DartParams.INTERCEPT_KEYS,
		"attack_run": DartParams.RUN_KEYS, "landing": DartParams.LAUNCH_KEYS, "rtb": DartParams.RTB_KEYS}
	for blk: String in blocks.keys():
		for k: String in blocks[blk] as PackedStringArray:
			var ap: Dictionary = DartKit.ap().duplicate(true)
			var d: Dictionary = ap if blk == "" else ap[blk] as Dictionary
			var _e: bool = d.erase(k)
			assert_object(DartParams.from_content(ap, DartKit.ship(&"dart"), DartKit.content())) \
				.override_failure_message("%s.%s" % [blk, k]).is_null()


func test_guidance_band_level_and_max_alt() -> void:
	assert_float(Guidance.band_vz(60.0, 300.0, 300.0, 1450.0, 0.5, 60.0)).is_equal(60.0)
	assert_float(Guidance.band_vz(280.0, 300.0, 300.0, 1450.0, 0.5, 60.0)).is_equal(10.0)
	assert_float(Guidance.band_vz(500.0, 300.0, 500.0, 1450.0, 0.5, 60.0)).is_equal(-60.0)
	assert_float(Guidance.band_vz(100.0, 300.0, 1450.0, 1450.0, 0.5, 60.0)).is_equal(0.0)   # never climb at max_alt
	var up: Vector3 = Vector3(1, 0, 0)
	var c: Vector3 = Guidance.level(Vector3(0, 1, 0), 110.0, 20.0, 110.0, up)
	assert_float(c.length()).is_equal_approx(110.0, 1e-3)
	assert_float(c.dot(up) / c.dot(Vector3(0, 1, 0))).is_equal_approx(20.0 / 110.0, 1e-5)


func test_guidance_lift_on_the_current_radial_speed_and_its_signed_generalisation() -> void:
	var up: Vector3 = Vector3(1, 0, 0)
	var vel: Vector3 = Vector3(-5.0, 110.0, 0.0)
	var hold: Vector3 = Vector3(0.0, 110.0, 0.0)            # a level hold command
	assert_float(Guidance.lifted(hold, vel, up, 12.0).dot(up)).is_equal_approx(7.0, 1e-4)   # v_r + lift, A-69
	assert_vector(Guidance.lifted(hold, vel, up, 0.0)).is_equal(hold)
	assert_float(Guidance.cleared(hold, vel, up, 12.0).dot(up)).is_equal_approx(7.0, 1e-4)
	var sink: Vector3 = Vector3(-40.0, 110.0, 0.0)
	assert_float(Guidance.cleared(sink, vel, up, -15.0).dot(up)).is_equal_approx(-20.0, 1e-4)  # the samples allow -20 only
	assert_vector(Guidance.cleared(sink, vel, up, -100.0)).is_equal(sink)                     # open ground: never binds
	assert_float(Guidance.floored(sink, up, 30.0, 60.0, 0.5, 60.0).dot(up)).is_equal_approx(15.0, 1e-4)
	assert_vector(Guidance.floored(sink, up, 80.0, 60.0, 0.5, 60.0)).is_equal(sink)


func test_pull_up_budget_is_zero_while_climbing_and_triggers_below_the_loss() -> void:
	var g: FlightGains = DartKit.gains()
	var p: Vector3 = Vector3(R + 100.0, 0.0, 0.0)
	var up: Vector3 = p.normalized()
	var dive: Vector3 = Vector3(-40.0, 105.0, 0.0)
	var b: Basis = _basis(p, dive)
	var loss: float = FlightController.pull_up_loss(b, dive, up, g)
	assert_float(loss).is_between(20.0, 100.0)
	assert_bool(Guidance.budget_low(loss - 1.0, b, dive, up, g)).is_true()
	assert_bool(Guidance.budget_low(loss + 1.0, b, dive, up, g)).is_false()
	var climb: Vector3 = Vector3(10.0, 110.0, 0.0)
	assert_bool(Guidance.budget_low(1.0, _basis(p, climb), climb, up, g)).is_false()
	var flat: Terrain = Terrain.new()
	assert_bool(Guidance.pull_up_due(flat, b, p, dive, up, g, 1.0, 400.0)).is_false()   # 1 s sample above ground, budget met
	assert_bool(Guidance.pull_up_due(flat, b, p, dive, up, g, 1.0, loss - 1.0)).is_true()   # budget short
	assert_bool(Guidance.pull_up_due(flat, b, p, Vector3(-120.0, 60.0, 0.0), up, g, 1.0, 1000.0)).is_true()  # re-sample < 0
	var c: Vector3 = Guidance.sink_limited(dive, b, up, g, 0.5 * loss)      # one exact call, the sink scaled
	assert_float(c.dot(up)).is_greater(dive.dot(up))
	assert_float(FlightController.pull_up_loss(b, c, up, g)).is_less(loss)
	assert_vector(Guidance.sink_limited(dive, b, up, g, loss + 1.0)).is_equal(dive)
	assert_vector(Guidance.sink_limited(climb, b, up, g, -10.0)).is_equal(climb)   # a climb is never limited


# R0 B.15 A-89 in Overlays.run_safety: a release sinking at 40 m/s 100 m over flat ground has TTI >= safety_pull_up_tti_s
# (2.0 s) but the AGL is below the pull-up budget: PULL_UP starts that tick. 400 m up the budget holds: no PULL_UP.
func test_safety_overlay_ors_the_pull_up_budget_into_its_trigger() -> void:
	var op: OverlayParams = OverlayParams.for_ship(DartKit.ap(), DartKit.ship(&"dart"), DartKit.content().rules, 30,
		DartKit.content().flight_common)
	for agl: float in [100.0, 400.0]:
		var v: TO.FakeView = TO.FakeView.new()
		v.p = Vector3(R + agl, 0.0, 0.0)
		v.v = Vector3(-40.0, 105.0, 0.0)
		var st: AiState = AiState.new()
		var sink: CommandSink = CommandSink.new()
		sink.bind(TO.Rec.new())
		var probe: ProbeResult = ProbeResult.new()
		var id: int = EntityId.make(5, 1)
		Overlays.enter(id, v, st, op, 0)
		var _e: bool = Overlays.run(id, v, st, op, Terrain.new(), sink, 0, probe, PilotInput.new())
		var pulling: bool = (st.ov_flags[5] & AiState.OV_PULL_UP) != 0
		var what: String = "AGL %.0f: TTI %.2f, loss %.1f, pulling %s" % [agl, probe.tti_s,
			FlightController.pull_up_loss(v.basis(id), v.v, v.p.normalized(), op.bridge.gains), pulling]
		assert_float(probe.tti_s).override_failure_message(what).is_greater_equal(op.bridge.pull_up_tti_s)
		assert_bool(pulling).override_failure_message(what).is_equal(agl < 200.0)


func test_patrol_points_lie_on_the_circle_around_home() -> void:
	var home: Vector3 = Vector3(R, 0.0, 0.0)
	var seen: Dictionary = {}
	for k: int in 6:
		var q: Vector3 = DartModes.patrol_point(home, k, 6, 1200.0)
		assert_float(Guidance.ground_dist(home, q)).is_equal_approx(1200.0, 0.01)
		assert_float(q.length()).is_equal_approx(R, 1e-3)
		seen[snappedf(Sphere.bearing(home, q), 0.01)] = true
	assert_int(seen.size()).is_equal(6)
	assert_vector(DartModes.patrol_point(home, 7, 6, 1200.0)).is_equal(DartModes.patrol_point(home, 1, 6, 1200.0))


func test_aim_error_is_a_deterministic_standard_normal_of_the_ai_stream() -> void:
	var a: Rng = Rng.new(5).fork(&"ai")
	var b: Rng = Rng.new(5).fork(&"ai")
	var sum: Vector2 = Vector2.ZERO
	var sq: Vector2 = Vector2.ZERO
	var n: int = 4000
	for i: int in n:
		var x: Vector2 = DartCombat.gauss2(a)
		assert_vector(x).is_equal(DartCombat.gauss2(b))
		sum += x
		sq += x * x
	assert_float(absf(sum.x / float(n))).is_less(0.06)
	assert_float(absf(sum.y / float(n))).is_less(0.06)
	assert_float(sqrt(sq.x / float(n))).is_between(0.95, 1.05)
	assert_float(sqrt(sq.y / float(n))).is_between(0.95, 1.05)
	var up: Vector3 = Vector3(1, 0, 0)
	var d: Vector3 = Vector3(0, 1, 0)
	assert_float(rad_to_deg(DartCombat.aim_offset(d, Vector2(deg_to_rad(1.2), 0.0), up).angle_to(d))).is_equal_approx(1.2, 1e-3)
	assert_float(rad_to_deg(DartCombat.aim_offset(d, Vector2(0.0, deg_to_rad(-1.2)), up).angle_to(d))).is_equal_approx(1.2, 1e-3)
	var e: Vector2 = Vector2(deg_to_rad(0.9), deg_to_rad(0.6))
	assert_float(DartCombat.aim_offset(d, e, up).angle_to(d)).is_equal_approx(e.length(), 1e-5)
	assert_vector(DartCombat.aim_offset(d, Vector2.ZERO, up)).is_equal(d)


# 05 s6.3 R1 ingress band from the visible enemy towers covering the aim point.
func test_attack_run_band_follows_the_visible_towers_covering_the_target() -> void:
	var cases: Array = [[[&"flak_battery"], AttackRun.Band.DECK], [[&"missile_tower"], AttackRun.Band.DECK],
		[[&"autocannon_turret"], AttackRun.Band.HIGH], [[&"flak_battery", &"autocannon_turret"], AttackRun.Band.LOW],
		[[], AttackRun.Band.LOW]]
	for c: Array in cases:
		var w: SimWorld = DartKit.world(3)
		var _d: AiDriver = DartKit.driver(w)
		var tgt: Vector3 = Vector3(1, 0, 0)
		var _mast: int = DartKit.spawn(w, &"sensor_mast", 0, DartKit.above(w, DartKit.offset(tgt, -800.0, 0.0), 0.0), Vector3.ZERO, Vector3(0, 1, 0))
		var k: int = 0
		for t: StringName in c[0] as Array:
			var _id: int = DartKit.spawn(w, t, DartKit.FOE, DartKit.above(w, DartKit.offset(tgt, 0.0, 300.0 + 200.0 * k), 0.0), Vector3.ZERO, Vector3(0, 1, 0))
			k += 1
		var p0: Vector3 = DartKit.above(w, DartKit.offset(tgt, -5000.0, 0.0), 300.0)
		var dart: int = DartKit.spawn(w, &"dart", 0, p0, Vector3(0, 110, 0), Vector3(0, 1, 0))
		for _i: int in 3:
			w.step()
		var st: AiState = AiState.new()
		var run: AttackRun = AttackRun.new(DartKit.params(), w.terrain())
		run.begin(dart, w.view(), st, DartKit.above(w, tgt, 0.0), 0)
		assert_int(AttackRun.band_of(st, EntityId.slot(dart))).override_failure_message(str(c[0])).is_equal(c[1] as int)
		assert_int(AttackRun.step_of(st, EntityId.slot(dart))).is_equal(AttackRun.Step.ROUTE)
		assert_float(Guidance.ground_dist(st.guidance_point[EntityId.slot(dart)], DartKit.above(w, tgt, 0.0))).is_equal_approx(DartKit.params().ip_dist, 1.0)


# The common RTB rule (05 s6): low fuel prepends one system RETURN; a Dart with an empty gun and no bombs as well.
func test_rtb_rule_prepends_one_system_return() -> void:
	for case: int in 2:
		var w: SimWorld = DartKit.world(4)
		var d: AiDriver = DartKit.driver(w)
		var dart: int = DartKit.spawn(w, &"dart", 0, DartKit.above(w, Vector3(1, 0, 0), 300.0), Vector3(0, 110, 0), Vector3(0, 1, 0))
		if case == 0:
			OverlayKit.ok(w, CommandPayload.debug_set(0, dart, CommandPayload.SET_FUEL, 0.2 * DartKit.ship(&"dart").fuel_s))
		else:
			w.store().ammo[EntityId.slot(dart)] = 0
			w.store().bombs[EntityId.slot(dart)] = 0
		for _k: int in 40:
			w.step()
		var head: OrderSpec = w.view().order_head(dart)
		assert_object(head).override_failure_message("case %d" % case).is_not_null()
		assert_int(head.kind).is_equal(OrderSpec.Kind.RETURN)
		assert_int(w.view().order_issuer(dart)).is_equal(-1)
		assert_int(d.state.mode[EntityId.slot(dart)]).is_equal(AiTag.Tag.LOITER)   # no friendly pad on the map


# Brains read only what the team sees (05 s6, 02 s15): an enemy Bomber outside every team-0 sensor is never a target,
# and an ATTACK on a never-seen structure flies no run (no aim point); once seen, both proceed.
func test_vision_fairness() -> void:
	var w: SimWorld = DartKit.world(6)
	var d: AiDriver = DartKit.driver(w)
	var home: Vector3 = Vector3(1, 0, 0)
	var dart: int = DartKit.spawn(w, &"dart", 0, DartKit.above(w, home, 300.0), Vector3(0, 110, 0), Vector3(0, 1, 0))
	var far: Vector3 = DartKit.above(w, DartKit.offset(home, 0.0, 1900.0), 50.0)    # inside the 2 km radius, beyond the Dart's 1.4 km sensor
	var bomber: int = DartKit.spawn(w, &"bomber", DartKit.FOE, far, Vector3.ZERO, Vector3(0, 1, 0))
	var ref: int = DartKit.spawn(w, &"refinery", DartKit.FOE, DartKit.above(w, DartKit.offset(home, 3000.0, 0.0), 0.0), Vector3.ZERO, Vector3(0, 1, 0))
	DartKit.order(w, dart, OrderSpec.make(OrderSpec.Kind.ATTACK, ref))
	var s: int = EntityId.slot(dart)
	for _k: int in 90:
		w.step()
		if w.view().visible_to(0, bomber) or w.view().visible_to(0, ref):
			break
		assert_int(d.state.target[s]).is_not_equal(bomber)
		assert_int(d.state.mode[s]).is_not_equal(AiTag.Tag.BOMB)
	assert_bool(w.view().visible_to(0, ref)).is_false()


func test_launch_only_off_a_pad_not_in_low_flight() -> void:
	var w: SimWorld = DartKit.world(8)
	var d: AiDriver = DartKit.driver(w)
	var low: int = DartKit.spawn(w, &"dart", 0, DartKit.above(w, Vector3(1, 0, 0), 40.0), Vector3(0, 110, 0), Vector3(0, 1, 0))
	var slow: Vector3 = DartKit.above(w, DartKit.offset(Vector3(1, 0, 0), 3000.0, 0.0), 30.0)
	var hover: int = DartKit.spawn(w, &"dart", 0, slow, slow.normalized() * 5.0, slow.normalized())
	for _k: int in 12:
		w.step()
	assert_int(d.state.mode[EntityId.slot(low)]).is_equal(AiTag.Tag.PATROL)
	assert_int(d.state.mode[EntityId.slot(hover)]).is_equal(AiTag.Tag.LAUNCH)
	assert_int(w.view().ai_tag(hover)).is_equal(AiTag.Tag.LAUNCH)


func test_ai_state_format5_round_trips_and_derives_the_focus_counts() -> void:
	var st: AiState = AiState.new(64)
	for s: int in [3, 9, 11]:
		st.cls[s] = 0
		st.eid[s] = EntityId.make(s, 1)
	st.set_target(3, EntityId.make(40, 2))
	st.set_target(9, EntityId.make(40, 2))
	st.set_target(11, EntityId.make(41, 1))
	st.set_target(11, EntityId.make(40, 2))
	assert_int(st.target_count[40]).is_equal(3)
	assert_int(st.target_count[41]).is_equal(0)
	st.sub[3] = 0x13
	st.passes[3] = 1
	st.prev_mode[3] = 4
	st.wp[3] = 5
	st.bflags[3] = 0x41
	st.seen_tick[3] = 77
	st.mark_tick[3] = 78
	st.burst_tick[3] = 79
	st.order_tick[3] = 80
	st.hp_mark[3] = 0.75
	st.clear_m[3] = 42.5
	st.home[3] = Vector3(1, 2, 3)
	st.goal[3] = Vector3(4, 5, 6)
	st.aim_err[3] = Vector2(0.01, -0.02)
	var bytes: PackedByteArray = st.serialize()
	var r: AiState = AiState.new(64)
	assert_bool(r.deserialize(bytes)).is_true()
	assert_bool(r.serialize() == bytes).is_true()
	assert_int(r.target_count[40]).is_equal(3)
	assert_int(r.sub[3]).is_equal(0x13)
	assert_vector(r.goal[3]).is_equal(Vector3(4, 5, 6))
	assert_float(r.aim_err[3].y).is_equal_approx(-0.02, 1e-7)
	assert_int(r.order_tick[3]).is_equal(80)
	r.clear_slot(9)
	assert_int(r.target_count[40]).is_equal(2)
	assert_int(AiState.new(8).order_tick[1]).is_equal(-1)


# Determinism and S4 with the brain flying: three Darts on one Bomber (the focus-fire penalty is live, so the derived
# target_count matters), run twice from scratch -> identical bytes. Restored into a fresh world whose driver is fully
# configured BEFORE SimWorld.deserialize (as a session restores), so the driver's own deserialize must rebind the
# restored AI stream to the brain (`AiBrain.bind_rng`): with the loop deleted the brain draws its aim errors from the
# pre-restore stream and the bytes diverge. Checked: target_count equal right after the restore and after 150 ticks,
# aim-error draws after the restore (the RNG half is not vacuous), identical bytes.
func test_dart_brain_is_deterministic_and_restores_s4() -> void:
	var a: Array = _fight(41)
	var b: Array = _fight(41)
	var wa: SimWorld = a[0]
	var wb: SimWorld = b[0]
	var da: AiDriver = a[1]
	var bomber: int = a[3]
	assert_bool(wa.serialize() == wb.serialize()).is_true()
	assert_int(da.state.target_count[EntityId.slot(bomber)]).is_equal(3)
	assert_int(wa.projectiles().live.size()).is_greater(0)   # saved mid-burst, slugs in flight (TA-65: the store round-trips at any tick)
	var bytes: PackedByteArray = wa.serialize()
	var cruise: DartKit.CruiseBrain = a[2]
	var d2: AiDriver = AiDriver.new(Rng.new(99))
	var brain2: DartBrain = DartBrain.from_content(DartKit.content(), DartKit.ap(), DartKit.ship(&"dart"), Terrain.new(),
		FormationKit.ring2_m())
	d2.set_class_table(AiClassTable.from_content(DartKit.content()))
	d2.set_brain(DartKit.CLS_DART, brain2)
	d2.set_overlay_params(DartKit.CLS_DART, OverlayParams.for_ship(DartKit.ap(), DartKit.ship(&"dart"), DartKit.content().rules, 30, DartKit.content().flight_common))
	var c2: DartKit.CruiseBrain = DartKit.CruiseBrain.new(cruise.gains, Terrain.new())
	c2.heading = cruise.heading.duplicate()
	d2.set_brain(DartKit.class_of(&"bomber"), c2)
	var w2: SimWorld = SimWorld.deserialize(bytes, DartKit.content(), d2)
	assert_object(w2).is_not_null()
	d2.set_terrain(w2.terrain())
	assert_bool(w2.serialize() == bytes).is_true()
	assert_bool(d2.state.target_count == da.state.target_count).is_true()
	var draws0: int = brain2.modes.combat.stats_draws
	for _k: int in 150:
		wa.step()
		w2.step()
		var _x: Array[SimEvent] = wa.drain_events()
		var _y: Array[SimEvent] = w2.drain_events()
	assert_int(brain2.modes.combat.stats_draws).is_greater(draws0)
	assert_bool(d2.state.target_count == da.state.target_count).is_true()
	assert_bool(w2.serialize() == wa.serialize()).is_true()


# [world, driver, bomber brain, bomber] with three Darts ENGAGEd on one Bomber (target_count 3).
func _fight(seed_value: int) -> Array:
	var w: SimWorld = DartKit.world(seed_value)
	var d: AiDriver = DartKit.driver(w)
	var cruise: DartKit.CruiseBrain = DartKit.CruiseBrain.new(DartKit.gains_of(&"bomber"), w.terrain())
	d.set_brain(DartKit.class_of(&"bomber"), cruise)
	var home: Vector3 = Vector3(1, 0, 0)
	var _core: int = DartKit.spawn(w, &"core", 0, DartKit.above(w, home, 0.0), Vector3.ZERO, Vector3(0, 1, 0))
	var pb: Vector3 = DartKit.above(w, DartKit.offset(home, 0.0, 600.0), 400.0)
	var hb: Vector3 = DartKit.heading(pb, DartKit.above(w, DartKit.offset(home, 500.0, 600.0), 400.0))
	var bomber: int = DartKit.spawn(w, &"bomber", DartKit.FOE, pb, hb * 70.0, hb)
	cruise.heading[bomber] = hb
	for k: int in 3:   # 300 m behind it, 80 m apart: all three in gun range at once
		var pd: Vector3 = DartKit.above(w, DartKit.offset(home, -300.0, 600.0 + 80.0 * float(k - 1)), 400.0 + 30.0 * float(k))
		var dart: int = DartKit.spawn(w, &"dart", 0, pd, hb * 90.0, hb)
		DartKit.order(w, dart, OrderSpec.make(OrderSpec.Kind.ATTACK, bomber))
	for _k: int in 45:   # 1.5 s: all three ENGAGEd and firing, the Bomber still alive
		w.step()
		var _e: Array[SimEvent] = w.drain_events()
	return [w, d, cruise, bomber]


# 05 s6.1: the HUD tag follows the mode into PULL_UP (set the tick PULL_UP starts, kept while pulling).
func test_pull_up_shows_in_the_ai_tag() -> void:
	var w: SimWorld = DartKit.world(17)
	var d: AiDriver = DartKit.driver(w)
	var p0: Vector3 = DartKit.above(w, Vector3(1, 0, 0), 250.0)
	var fwd: Vector3 = OverlayKit.dive_dir(p0, 35.0)
	var id: int = DartKit.spawn(w, &"dart", 0, p0, fwd * 150.0, fwd)
	var seen: bool = false
	for _k: int in 90:
		w.step()
		var _e: Array[SimEvent] = w.drain_events()
		if d.state.mode[EntityId.slot(id)] == AiTag.Tag.PULL_UP:
			assert_int(w.view().ai_tag(id)).is_equal(AiTag.Tag.PULL_UP)
			seen = true
	assert_bool(seen).is_true()
	assert_float(w.view().hp01(id)).is_equal(1.0)


# TeamPicture (05 s6 vision only; AI-13): one build per team per Vision epoch however many choice points ask, and the
# cached list equals, on every tick, the brute-force set of visible enemy ships (team bits change only in the team's
# own Vision pass, so the epoch cache is exact; this is what makes it S4-safe).
func test_team_picture_is_built_once_per_vision_epoch_and_stays_exact() -> void:
	var w: SimWorld = DartKit.world(21)
	var _d: AiDriver = DartKit.driver(w)
	var home: Vector3 = Vector3(1, 0, 0)
	var _dart: int = DartKit.spawn(w, &"dart", 0, DartKit.above(w, home, 300.0), Vector3(0, 110, 0), Vector3(0, 1, 0))
	for k: int in 4:   # enemies crossing the edge of the Dart's 1.4 km sensor, in and out
		var pe: Vector3 = DartKit.above(w, DartKit.offset(home, -1600.0 + 900.0 * float(k), 1300.0), 300.0)
		var _e: int = DartKit.spawn(w, &"scout", DartKit.FOE, pe, Vector3(0, 0, 60.0 - 40.0 * float(k)), Vector3(0, 0, 1))
	var pic: TeamPicture = TeamPicture.new()
	pic.period = DartKit.params().vision_period
	assert_int(pic.period).is_greater(1)
	var changes: int = 0
	var last: int = -1
	for _k: int in 240:
		w.step()
		var _e2: Array[SimEvent] = w.drain_events()
		var v: SimView = w.view()
		var tick: int = v.tick() + 1   # the next hook call's tick: this step's Vision pass is already in the bits
		var builds0: int = pic.builds
		var list: PackedInt32Array = pic.enemies(v, 0, tick)
		var _again: PackedInt32Array = pic.enemies(v, 0, tick)
		assert_int(pic.builds - builds0).is_less_equal(1)
		var truth: PackedInt32Array = PackedInt32Array()
		for id: int in v.ships():
			if v.team(id) != 0 and v.visible_to(0, id):
				var _a: bool = truth.push_back(id)
		assert_array(Array(list)).override_failure_message("tick %d" % tick).is_equal(Array(truth))
		changes += 1 if truth.size() != last else 0
		last = truth.size()
	assert_int(pic.builds).is_between(MathX.floori_div(240, pic.period) - 1, MathX.floori_div(240, pic.period) + 1)
	assert_int(changes).is_greater(1)   # visibility did change during the run


# 05 s4.3 / S8 discipline for brains: per-entity state lives in AiState; no static state, no clock, no RNG but the
# bound AI stream, no Node, no await, no signal.
func test_brain_sources_hold_no_hidden_state() -> void:
	for path: String in BRAIN_FILES:
		var src: String = FileAccess.get_file_as_string(path)
		assert_bool(src.is_empty()).override_failure_message(path).is_false()
		for bad: String in ["static var", "randf", "randi", "Time.", "OS.", "await", "signal ", "Node", "RandomNumberGenerator"]:
			assert_bool(src.contains(bad)).override_failure_message("%s contains %s" % [path, bad]).is_false()


static func _basis(p: Vector3, v: Vector3) -> Basis:
	var f: Vector3 = v.normalized()
	var n: Vector3 = p.normalized()
	var u: Vector3 = (n - f * n.dot(f)).normalized()
	return Basis(f.cross(u), u, -f)


# R0 B.17 A-94: AiTag.Tag is the one ai_tag vocabulary; its ordinals equal the sim_ai/MODULE.md "Enumerations" bullet
# (the test_protocol.gd parse of the sim/MODULE.md block), and the Dart's modes are 0-15 of it.
func test_ai_tag_ordinals_match_the_module_enumeration() -> void:
	var md: String = FileAccess.get_file_as_string("res://src/sim_ai/MODULE.md")
	var line: String = ""
	for l: String in md.split("
"):
		if l.begins_with("- `AiTag.Tag`"):
			line = l
	assert_str(line).is_not_empty()
	var body: String = line.substr(line.find("): ") + 3)
	body = body.substr(0, body.find(" (0-15"))
	var keys: Array = AiTag.Tag.keys()
	var items: PackedStringArray = body.split(", ")
	assert_int(items.size()).is_equal(keys.size())
	for i: int in items.size():
		assert_str(items[i]).is_equal("%d %s" % [i, keys[i]])
	assert_int(keys.size()).is_equal(34)
	assert_int(AiTag.Tag.LOITER).is_equal(15)
	assert_int(AiTag.Tag.PULL_UP).is_equal(10)


# R0 B.17 A-92: a think with TTI >= safety_clear_tti_s and the hold met but climb_need_mps > 0 stays in PULL_UP; the
# first think with climb_need_mps <= 0 resumes prev_mode. A Dart climbing at 5 m/s 45 m over flat ground has no ballistic
# contact within the probe (TTI INF) and still needs climb (h_req 52 m); 400 m up it needs none.
func test_pull_up_exit_waits_for_the_climb_need() -> void:
	var w: SimWorld = DartKit.world(23)
	var brain: DartBrain = DartKit.brain(w)
	var _d: AiDriver = DartKit.driver(w, brain)
	var st: AiState = _d.state
	var sink: CommandSink = CommandSink.new()
	var up: Vector3 = Vector3(1, 0, 0)
	var low: int = DartKit.spawn(w, &"dart", 0, DartKit.above(w, up, 45.0), Vector3(5, 110, 0), Vector3(0, 1, 0))
	var high: int = DartKit.spawn(w, &"dart", 0, DartKit.above(w, DartKit.offset(up, 3000.0, 0.0), 400.0), Vector3(0, 110, 0), Vector3(0, 1, 0))
	var v: SimView = w.view()
	for id: int in [low, high]:
		var s: int = EntityId.slot(id)
		st.mode[s] = AiTag.Tag.PULL_UP
		st.prev_mode[s] = AiTag.Tag.PATROL
		st.mode_since[s] = 0
		st.home[s] = v.pos(id)
		brain.think_one(id, v, st, sink, 600)
	var sl: int = EntityId.slot(low)
	assert_float(st.tti[sl]).is_greater_equal(DartKit.params().clear_tti)
	assert_float(st.lift[sl]).is_greater(0.0)
	assert_int(st.mode[sl]).is_equal(AiTag.Tag.PULL_UP)
	assert_int(st.mode[EntityId.slot(high)]).is_equal(AiTag.Tag.PATROL)
	assert_int(brain.stats_longest_pull_up).is_equal(600)
