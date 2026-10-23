extends GdUnitTestSuite
## AI-17 perf note (05 s10: think row 25 us = 1 neighbour query + 1 choice point; act row "ground + towers" 2.7 us per item,
## a fleet mean, R0 B.17 A-96) for `TowerBrain` on a real SimWorld: FAR_FOES enemy Darts around a base, ENGAGED towers
## (two of each def) with a Bomber, Darts, Harvesters inside their range and envelope, and IDLE towers (the same
## defs) 6 km away with enemies in sight but out of range. The world is frozen after WARM_S and per-call `think_one` /
## `act_batch` timings are taken on the driver's own state:
##   think   idle (the TeamPicture scan finds nothing in range: no choice point) and engaged (one choice point);
##   act     idle (no drive: the zero-drive latch) and tracking (slew + lead + one visible_to);
##   fleet   (1 - f) idle + f engaged with f = 0.25 against the row (think and act), the engaged act against 3 x row (A-96).
## Timing bounds are report-only on hosted runners (R0 B.17 A-97, PerfGate); the deterministic counters are hard
## everywhere: an idle tower never calls `drive`, one `visible_to` per tracking act, one TeamPicture build per team per
## Vision epoch, the ground list built once per Perception refresh (not per think), one choice point per engaged think.

const HZ: int = 30
const FAR_FOES: int = 60
const WARM_S: int = 5
const CALLS: int = 600
const BATCHES: int = 5
const THINK_ROW_US: float = 25.0
const ACT_ROW_US: float = 2.7
const CI_FACTOR: float = 2.0
const ENGAGED_SHARE: float = 0.25   ## A-96 f
const DEFS: Array[StringName] = [&"autocannon_turret", &"flak_battery", &"missile_tower"]


func _ring(w: SimWorld, c: Vector3, def: StringName, k: int, radius: float, agl: float) -> int:
	var a: float = TAU * float(k) / 6.0
	var p: Vector3 = DartKit.above(w, DartKit.offset(c, radius * cos(a), radius * sin(a)), agl)
	return Ai17Kit.spawn_many(w, def, 0, p, Vector3.ZERO, DartKit.heading(p, c))


func _world() -> Array:
	var w: SimWorld = Ai17Kit.world(33)
	var brain: TowerBrain = Ai17Kit.brain()
	var d: Ai17Kit.SlewDriver = Ai17Kit.driver(w, true, 3, brain)
	for k: int in 4:   # power: 4 Cores (+20 each) carry the 12 towers and 2 masts above tower_offline_ratio
		var _core: int = Ai14Kit.core(w, DartKit.offset(Vector3(-1, 0, 0), 400.0 * float(k), 0.0), 0)
	var a: Vector3 = Vector3(1, 0, 0)
	var b: Vector3 = DartKit.offset(a, 0.0, 6000.0)
	var engaged: PackedInt32Array = PackedInt32Array()
	var idle: PackedInt32Array = PackedInt32Array()
	for k: int in 6:
		var _e: bool = engaged.push_back(_ring(w, a, DEFS[k % 3], k, 120.0, 0.0))
		var _i: bool = idle.push_back(_ring(w, b, DEFS[k % 3], k, 120.0, 0.0))
	var mast_p: Vector3 = DartKit.above(w, DartKit.offset(a, 20.0, 0.0), 0.0)
	var _m: int = Ai17Kit.spawn_many(w, &"sensor_mast", 0, mast_p, Vector3.ZERO, DartKit.heading(mast_p, a))
	var mast_b: Vector3 = DartKit.above(w, DartKit.offset(b, 20.0, 0.0), 0.0)
	var _m2: int = Ai17Kit.spawn_many(w, &"sensor_mast", 0, mast_b, Vector3.ZERO, DartKit.heading(mast_b, b))
	var hover: Dictionary = {}   # id -> position: the engaged group's targets hover (ships fall) and survive the warm-up
	for k: int in 3:   # inside range and envelope of the engaged group
		var fp: Vector3 = DartKit.above(w, DartKit.offset(a, 300.0 + 40.0 * float(k), 60.0 * float(k)), 150.0 + 40.0 * float(k))
		hover[Ai17Kit.spawn_many(w, [&"bomber", &"dart", &"lancer"][k], DartKit.FOE, fp, Vector3.ZERO, Vector3(0, 1, 0))] = fp
	for k: int in 2:
		var gp: Vector3 = DartKit.above(w, DartKit.offset(a, 250.0, -80.0 * float(k + 1)), 0.0)
		hover[Ai17Kit.spawn_many(w, &"harvester", DartKit.FOE, gp, Vector3.ZERO, Vector3(0, 1, 0))] = gp
	for id: int in hover:
		w.store().hp[EntityId.slot(id)] = 10000000.0
	for k: int in FAR_FOES:   # the visible roster of the idle group: in sight of the near towers (1.53-1.58 km), out of every range (<= 1.5 km)
		var ang: float = TAU * float(k) / float(FAR_FOES)
		var r: float = 1650.0 + 50.0 * float(k % 2)
		var _x: int = Ai17Kit.spawn_many(w, &"dart", DartKit.FOE, DartKit.above(w, DartKit.offset(b, r * cos(ang), r * sin(ang)), 400.0),
			Vector3.ZERO, Vector3(0, 1, 0))
	for _k: int in WARM_S * HZ:
		for id: int in hover:
			IntelKit.teleport(w, id, hover[id])
		var _s: Array[SimEvent] = Ai17Kit.step(w)
	return [w, d, brain, engaged, idle]


func _thinks(brain: TowerBrain, v: SimView, st: AiState, ids: PackedInt32Array, t0_tick: int, epochs: Dictionary) -> Vector3:
	var sink: CommandSink = CommandSink.new()
	var best: Vector3 = Vector3(INF, 0.0, 0.0)
	var period: int = 10
	for b: int in BATCHES:
		var us: PackedFloat32Array = PackedFloat32Array()
		var _r: int = us.resize(CALLS)
		for k: int in CALLS:
			var id: int = ids[k % ids.size()]
			var tick: int = t0_tick + period * MathX.floori_div(k, ids.size()) + 100000 * b
			epochs[brain.picture.epoch(0, tick)] = true
			var _pic: PackedInt32Array = brain.picture.enemies(v, 0, tick)   # the tick's shared picture: timed apart
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


func _acts(brain: TowerBrain, v: SimView, st: AiState, ids: PackedInt32Array, sink: CommandSink) -> float:
	var best: float = INF
	for b: int in BATCHES + 1:
		var t0: int = Time.get_ticks_usec()
		for _k: int in 100:
			brain.act_batch(ids, v, st, sink)
		var us: float = float(Time.get_ticks_usec() - t0) / float(100 * ids.size())
		if b > 0:
			best = minf(best, us)
	return best


func test_perf_tower_think_and_act() -> void:
	var r: Array = _world()
	var w: SimWorld = r[0]
	var brain: TowerBrain = r[2]
	var engaged: PackedInt32Array = r[3]
	var idle: PackedInt32Array = r[4]
	var v: SimView = w.view()
	var st: AiState = (r[1] as AiDriver).state
	var tick: int = w.tick() + 1
	var epochs: Dictionary = {}
	var epochs_e: Dictionary = {}
	var builds0: int = brain.picture.builds
	var gb0: int = brain.stats_ground_builds
	var c0: int = brain.stats_choices
	var th0: int = brain.stats_thinks
	var it: Vector3 = _thinks(brain, v, st, idle, tick, epochs)
	var idle_choices: int = brain.stats_choices - c0
	var idle_thinks: int = brain.stats_thinks - th0
	var builds_idle: int = brain.picture.builds - builds0
	var c1: int = brain.stats_choices
	var th1: int = brain.stats_thinks
	var b1: int = brain.picture.builds
	var et: Vector3 = _thinks(brain, v, st, engaged, tick, epochs_e)
	var eng_choices: int = brain.stats_choices - c1
	var eng_thinks: int = brain.stats_thinks - th1
	var builds: int = builds_idle + brain.picture.builds - b1
	epochs.merge(epochs_e)
	var ground_builds: int = brain.stats_ground_builds - gb0
	# the engaged towers hold targets now (the last think of each)
	var tracking: int = 0
	for id: int in engaged:
		tracking += 1 if st.mode[EntityId.slot(id)] == AiTag.Tag.TRACK else 0
	var sink_idle: CommandSink = CommandSink.new()
	var ia: float = _acts(brain, v, st, idle, sink_idle)
	var sink_eng: CommandSink = CommandSink.new()
	var acts0: int = brain.stats_acts
	var vis0: int = brain.stats_visible
	var ea: float = _acts(brain, v, st, engaged, sink_eng)
	var tracked: int = brain.stats_acts - acts0
	var visible: int = brain.stats_visible - vis0
	var fleet: float = (1.0 - ENGAGED_SHARE) * ia + ENGAGED_SHARE * ea
	var think_fleet: float = (1.0 - ENGAGED_SHARE) * it.x + ENGAGED_SHARE * et.x
	print("AI-17 perf (%d far foes; best of %d batches of %d per-call thinks, hard counters below): think idle mean %.1f / median %.1f / p95 %.1f us, engaged %.1f / %.1f / %.1f us; think fleet (f=%.2f) %.1f us (row %.1f); act idle %.2f us, tracking %.2f us, fleet %.2f us (row %.1f); tracking towers %d / %d; choices idle %d of %d, engaged %d of %d; picture builds %d for %d epochs; ground builds %d" % [
		FAR_FOES, BATCHES, CALLS, it.x, it.y, it.z, et.x, et.y, et.z, ENGAGED_SHARE, think_fleet, THINK_ROW_US, ia, ea, fleet, ACT_ROW_US, tracking, engaged.size(),
		idle_choices, idle_thinks, eng_choices, eng_thinks, builds, epochs.size(), ground_builds])
	# deterministic counters (hard on every runner)
	assert_int(tracking).is_equal(engaged.size())
	assert_int(sink_idle.drives).is_equal(0)                       # an idle tower is never driven
	assert_int(tracked).is_greater(0)
	assert_int(visible).is_equal(tracked)                          # one visible_to per tracking act
	assert_int(sink_eng.drives).is_equal(tracked)                  # one drive per tracking act
	assert_int(eng_choices).is_equal(eng_thinks)                   # one choice point per think
	assert_int(builds_idle).is_less_equal(epochs.size())
	assert_int(builds - builds_idle).is_less_equal(epochs_e.size())   # one TeamPicture build per team per Vision epoch, per pass
	assert_int(ground_builds).is_less_equal(2)                     # the Perception list: once per refresh, never per think
	# timings: report-only on hosted runners (R0 B.17 A-97)
	var cite: String = "05 s10 / R0 A-96"
	assert_bool(PerfGate.check("test_tower_perf.think_fleet", think_fleet, THINK_ROW_US * CI_FACTOR, cite)).is_true()
	assert_bool(PerfGate.check("test_tower_perf.think_engaged", et.x, 3.0 * THINK_ROW_US * CI_FACTOR, cite)).is_true()
	assert_bool(PerfGate.check("test_tower_perf.act_fleet", fleet, ACT_ROW_US * CI_FACTOR, cite)).is_true()
	assert_bool(PerfGate.check("test_tower_perf.act_tracking", ea, 3.0 * ACT_ROW_US * CI_FACTOR, cite)).is_true()
