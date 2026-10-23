extends GdUnitTestSuite
## AI-14 perf note (05 s10: think row 25 us = 6 probes + 1 neighbour query + 1 choice point; act row 6 us per ship, a
## fleet mean, R0 B.17 A-96) for the Lancer, Bomber and Scout brains on a real SimWorld: FAR_SHIPS friendly Darts over
## many hash cells, a home Core, MEASURED ships of each class flown by Ai14Kit's driver (with the team intel) for
## WARM_S, an enemy Harvester, Dart and Bomber inside the Lancers' guard radius, an enemy Refinery the Bombers attack.
## Then the world is frozen and per-call `think_one` / `act_batch` timings are taken on the driver's own state:
##   lancer   AUTO GUARD thinks (the choice point over ships + Perception ground contacts every 6th think) and the
##            act in INTERCEPT / ENGAGE on the enemy Bomber with the rocket lock (the engaged act, A-96's interim ceiling);
##   bomber   ATTACK run thinks and acts (R1 / R2 at the band, the bomb sight);
##   scout    SEARCH thinks in their natural mix (the cell scan at most once per choice period) and forced scan thinks.
## Timing bounds are report-only on hosted runners (R0 B.17 A-97, PerfGate; asserted with PLANEWAR_PINNED_RUNNER=1);
## the deterministic counters are hard everywhere: one structure query per Lancer AUTO start, one visible_to per Lancer
## INTERCEPT act and two per ENGAGE act (DartCombat.act_engage's + the rocket act's; counted at the calls), the choice share <= 1 / choice_period_thinks, Scout scans <= one per choice period per Scout, one
## TeamPicture build per team per Vision epoch.

const HZ: int = 30
const FAR_SHIPS: int = 120
const MEASURED: int = 6
const WARM_S: int = 12
const CALLS: int = 600
const BATCHES: int = 5
const THINK_ROW_US: float = 25.0
const ACT_ROW_US: float = 6.0
const CI_FACTOR: float = 2.0
const ACT_ENGAGE_CEILING_US: float = 3.0 * ACT_ROW_US   ## R0 B.17 A-96 interim ceiling of an engaged act (never raised here)


func _world() -> Array:
	var w: SimWorld = Ai14Kit.world(33)
	var d: AiDriver = Ai14Kit.driver(w)
	var dart: int = DartKit.def_id(&"dart")
	for k: int in FAR_SHIPS:
		var lat: float = deg_to_rad(-60.0 + 120.0 * float(k % 20) / 19.0)
		var lon: float = deg_to_rad(40.0 + 300.0 * float(k) / float(FAR_SHIPS))
		var pos: Vector3 = Sphere.from_lat_lon(lat, lon, Sphere.PLANET_RADIUS + 300.0)
		var code: int = CommandResult.Code.REJECTED_RATE
		while code == CommandResult.Code.REJECTED_RATE:
			code = w.apply_command(CommandPayload.debug_spawn(1, dart, 0, 0, pos, Vector3.ZERO, Vector3(0, 1, 0))).code
			w.step()
	var c0: Vector3 = Vector3(1, 0, 0)
	var _core: int = Ai14Kit.core(w, c0, 0)
	var ls: PackedInt32Array = PackedInt32Array()
	var bs: PackedInt32Array = PackedInt32Array()
	var ss: PackedInt32Array = PackedInt32Array()
	for k: int in MEASURED:
		var a: float = TAU * float(k) / float(MEASURED)
		var pl: Vector3 = DartKit.above(w, DartKit.offset(c0, 600.0 * cos(a), 600.0 * sin(a)), 200.0)
		var hl: Vector3 = DartKit.heading(pl, Vector3(0, 1, 0))
		var _l: bool = ls.push_back(DartKit.spawn(w, &"lancer", 0, pl, hl * 80.0, hl))
		var pb: Vector3 = DartKit.above(w, DartKit.offset(c0, -3000.0 - 150.0 * float(k), 0.0), 400.0)
		var hb: Vector3 = DartKit.heading(pb, Vector3(0, 0, 1))
		var _b: bool = bs.push_back(DartKit.spawn(w, &"bomber", 0, pb, hb * 70.0, hb))
		var ps: Vector3 = DartKit.above(w, DartKit.offset(c0, 300.0 * float(k), -2000.0), 500.0)
		var _s: bool = ss.push_back(DartKit.spawn(w, &"scout", 0, ps, hl * 140.0, hl))
	var ref_p: Vector3 = DartKit.above(w, DartKit.offset(c0, -3000.0, 4000.0), 0.0)
	var refinery: int = DartKit.spawn(w, &"refinery", DartKit.FOE, ref_p, Vector3.ZERO, DartKit.heading(ref_p, Vector3(0, 1, 0)))
	var mast_p: Vector3 = DartKit.above(w, DartKit.offset(c0, -3000.0, 3000.0), 0.0)
	var _m: int = DartKit.spawn(w, &"sensor_mast", 0, mast_p, Vector3.ZERO, DartKit.heading(mast_p, Vector3(0, 1, 0)))
	var hv_p: Vector3 = DartKit.above(w, DartKit.offset(c0, 900.0, 600.0), 0.0)
	var _h: int = DartKit.spawn(w, &"harvester", DartKit.FOE, hv_p, Vector3.ZERO, DartKit.heading(hv_p, Vector3(0, 1, 0)))
	var foe_b: int = DartKit.spawn(w, &"bomber", DartKit.FOE, DartKit.above(w, DartKit.offset(c0, 0.0, 1100.0), 300.0),
		Vector3(0, 0, 60), Vector3(0, 0, 1))
	var _fd: int = DartKit.spawn(w, &"dart", DartKit.FOE, DartKit.above(w, DartKit.offset(c0, -900.0, 600.0), 600.0),
		Vector3(0, 0, 100), Vector3(0, 0, 1))
	var ids: Dictionary = {&"lancer": ls, &"bomber": bs, &"scout": ss}   # packed arrays stored whole, never mutated in place
	for b: int in bs:
		DartKit.order(w, b, OrderSpec.make(OrderSpec.Kind.ATTACK, refinery))
	for _k: int in WARM_S * HZ:
		var _e: Array[SimEvent] = Ai14Kit.step(w)
	return [w, d, ids, foe_b]


func _thinks(brain: DartBrain, v: SimView, st: AiState, ids: PackedInt32Array, t0_tick: int) -> Vector3:
	var sink: CommandSink = CommandSink.new()
	var best: Vector3 = Vector3(INF, 0.0, 0.0)
	var period: int = brain.prm.think_ticks
	for b: int in BATCHES:
		var us: PackedFloat32Array = PackedFloat32Array()
		var _r: int = us.resize(CALLS)
		for k: int in CALLS:
			var id: int = ids[k % ids.size()]
			var tick: int = t0_tick + period * MathX.floori_div(k, ids.size()) + 100000 * b
			var _pic: PackedInt32Array = brain.modes.picture.enemies(v, 0, tick)   # the tick's shared picture: timed apart
			var t0: int = Time.get_ticks_usec()
			brain.think_one(id, v, st, sink, tick)
			us[k] = float(Time.get_ticks_usec() - t0)
		var a: PackedFloat32Array = us.duplicate()
		a.sort()
		var sum: float = 0.0
		for x: float in us:
			sum += x
		var s: Vector3 = Vector3(sum / float(CALLS), a[MathX.floori_div(CALLS, 2)], a[int(float(CALLS) * 0.95)])
		best = s if s.x < best.x else best
	return best


func _acts(brain: DartBrain, v: SimView, st: AiState, ids: PackedInt32Array) -> float:
	var sink: CommandSink = CommandSink.new()
	var best: float = INF
	for b: int in BATCHES + 1:
		var t0: int = Time.get_ticks_usec()
		for _k: int in 100:
			brain.act_batch(ids, v, st, sink)
		var us: float = float(Time.get_ticks_usec() - t0) / float(100 * ids.size())
		if b > 0:
			best = minf(best, us)
	return best


func test_perf_class_brains_think_and_act() -> void:
	var r: Array = _world()
	var w: SimWorld = r[0]
	var d: AiDriver = r[1]
	var ids: Dictionary = r[2]
	var foe_b: int = r[3]
	var v: SimView = w.view()
	var st: AiState = d.state
	var lancer: LancerBrain = Ai14Kit.brain_of(d, &"lancer") as LancerBrain
	var bomber: BomberBrain = Ai14Kit.brain_of(d, &"bomber") as BomberBrain
	var scout: ScoutBrain = Ai14Kit.brain_of(d, &"scout") as ScoutBrain
	var tick: int = w.tick() + 1
	# counters of the warm-up flight (deterministic)
	assert_int(lancer.stats_cluster_queries).is_equal(MEASURED)   # one structure query per Lancer AUTO start
	var builds0: int = lancer.modes.picture.builds
	var lids: PackedInt32Array = ids[&"lancer"]
	var c0: int = lancer.modes.stats_choices
	var th0: int = lancer.stats_thinks
	var lt: Vector3 = _thinks(lancer, v, st, lids, tick)
	var choice_share: float = float(lancer.modes.stats_choices - c0) / float(BATCHES * CALLS)
	var _th: int = lancer.stats_thinks - th0
	for id: int in lids:   # every Lancer on the enemy Bomber: INTERCEPT / ENGAGE with the rocket lock
		var s: int = EntityId.slot(id)
		st.set_target(s, foe_b)
		st.seen_tick[s] = tick
		st.goal[s] = v.pos(foe_b)
		st.aim_lead[s] = v.pos(foe_b)
		st.mode[s] = AiTag.Tag.INTERCEPT
	var wa0: Vector2i = Vector2i(lancer.stats_weapon_acts, lancer.stats_weapon_visible)
	var ce0: Vector2i = Vector2i(lancer.modes.combat.stats_engage_acts, lancer.modes.combat.stats_engage_visible)
	var la: float = _acts(lancer, v, st, lids)
	var wa1: Vector2i = Vector2i(lancer.stats_weapon_acts, lancer.stats_weapon_visible)
	var ce1: Vector2i = Vector2i(lancer.modes.combat.stats_engage_acts, lancer.modes.combat.stats_engage_visible)
	# INTERCEPT acts: the weapons act's one visible_to and no DartCombat ENGAGE read (1 per act)
	assert_int(ce1.x - ce0.x).is_equal(0)
	assert_int(wa1.x - wa0.x).is_greater(0)
	assert_int(wa1.y - wa0.y).is_equal(wa1.x - wa0.x)
	for id: int in lids:   # ENGAGE on the Bomber: DartCombat.act_engage's visible_to + the weapons act's (2 per act)
		var s: int = EntityId.slot(id)
		st.mode[s] = AiTag.Tag.ENGAGE
	var ew0: Vector2i = Vector2i(lancer.stats_weapon_acts, lancer.stats_weapon_visible)
	var le: float = _acts(lancer, v, st, lids)
	var ew1: Vector2i = Vector2i(lancer.stats_weapon_acts, lancer.stats_weapon_visible)
	var ce2: Vector2i = Vector2i(lancer.modes.combat.stats_engage_acts, lancer.modes.combat.stats_engage_visible)
	var engage_acts: int = ce2.x - ce1.x
	assert_int(engage_acts).is_greater(0)
	assert_int(ew1.x - ew0.x).is_equal(engage_acts)
	assert_int((ew1.y - ew0.y) + (ce2.y - ce1.y)).is_equal(2 * engage_acts)
	var bids: PackedInt32Array = ids[&"bomber"]
	var bt: Vector3 = _thinks(bomber, v, st, bids, tick)
	var ba: float = _acts(bomber, v, st, bids)
	var sids: PackedInt32Array = ids[&"scout"]
	var sc0: int = scout.stats_scans
	var stt: Vector3 = _thinks(scout, v, st, sids, tick)
	var scans: int = scout.stats_scans - sc0
	var sa: float = _acts(scout, v, st, sids)
	var forced: float = INF
	for b: int in BATCHES:
		var t0: int = Time.get_ticks_usec()
		for id: int in sids:
			var s: int = EntityId.slot(id)
			st.mode[s] = AiTag.Tag.PATROL
			st.timer[s] = -1000.0   # a scan on this think
			scout.think_one(id, v, st, CommandSink.new(), 500000 + b)
		forced = minf(forced, float(Time.get_ticks_usec() - t0) / float(sids.size()))
	var scan_bound: float = THINK_ROW_US * CI_FACTOR * float(scout.prm.choice_period)
	var modes_l: Dictionary = {}
	for id: int in lids:
		modes_l[st.mode[EntityId.slot(id)]] = true
	print("AI-14 perf (%d far ships; best of %d batches of %d per-call thinks): lancer guard think mean %.1f / median %.1f / p95 %.1f us (choice share %.3f), act intercept %.2f us/ship (weapons acts %d, visible_to %d), act engage %.2f; bomber run think %.1f / %.1f / %.1f us, act %.2f; scout search think %.1f / %.1f / %.1f us (scans %d in %d thinks), act %.2f, scan think %.1f us (bound %.0f: once per choice period); lancer modes %s" % [
		FAR_SHIPS, BATCHES, CALLS, lt.x, lt.y, lt.z, choice_share, la, wa1.x - wa0.x, wa1.y - wa0.y, le, bt.x, bt.y, bt.z, ba,
		stt.x, stt.y, stt.z, scans, BATCHES * CALLS, sa, forced, scan_bound, str(modes_l.keys())])
	# deterministic counters (hard on every runner)
	assert_float(choice_share).is_less_equal(1.0 / float(lancer.prm.choice_period) + 0.01)

	assert_int(scans).is_less_equal(MathX.floori_div(BATCHES * CALLS, scout.prm.choice_period) + sids.size())
	assert_int(lancer.modes.picture.builds - builds0).is_greater(0)
	# timings: report-only on hosted runners (R0 B.17 A-97)
	var cite: String = "05 s10 / R0 A-96"
	assert_bool(PerfGate.check("test_ai14_perf.lancer_think", lt.x, THINK_ROW_US * CI_FACTOR, cite)).is_true()
	assert_bool(PerfGate.check("test_ai14_perf.lancer_act_intercept", la, ACT_ENGAGE_CEILING_US, cite)).is_true()
	assert_bool(PerfGate.check("test_ai14_perf.lancer_act_engage", le, ACT_ENGAGE_CEILING_US, cite)).is_true()
	assert_bool(PerfGate.check("test_ai14_perf.bomber_think", bt.x, THINK_ROW_US * CI_FACTOR, cite)).is_true()
	assert_bool(PerfGate.check("test_ai14_perf.bomber_act", ba, ACT_ROW_US * CI_FACTOR, cite)).is_true()
	assert_bool(PerfGate.check("test_ai14_perf.scout_think", stt.x, THINK_ROW_US * CI_FACTOR, cite)).is_true()
	assert_bool(PerfGate.check("test_ai14_perf.scout_act", sa, ACT_ROW_US * CI_FACTOR, cite)).is_true()
	assert_bool(PerfGate.check("test_ai14_perf.scout_scan_think", forced, scan_bound, cite)).is_true()
