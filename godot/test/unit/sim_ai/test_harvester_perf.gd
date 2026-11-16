extends GdUnitTestSuite
## AI-16 perf note (05 s10: think slice 25 us per unit, act row "ground + towers" 2.7 us per unit; A* is the separate
## "A* 0.5 ms" row, not the AI budget). 100 Harvesters (the row's ground count) cycle between two fields and two Refineries on
## the flat datum for a minute so every mode is in play, then the per-call cost of `think_one` and of an `act_batch` over all of
## them is timed (best of several batches; the minimum is the robust location for timing noise that only adds, as
## test_escort_perf.gd). Timing bounds are report-only on hosted runners (R0 B.17 A-97, `PerfGate`); the work counters are hard:
## one structure scan per team per `refinery_scan_s`, one `ids_near` family per PICK_FIELD only, picks and flees rare against
## the thinks, no unit driven without an act.

const HZ: int = 30
const UNITS: int = 100
const THINK_ROW_US: float = 25.0
const ACT_ROW_US: float = 2.7
const CI_FACTOR: float = 2.0
const BATCHES: int = 6
const ACT_LOOPS: int = 30


func _world() -> Array:
	var rules: MatchRules = DartKit.rules()
	rules.caps.units = 400
	var w: SimWorld = Ai16Kit.world(21, &"", rules)
	var _r1: int = Ai16Kit.put(w, &"refinery", 0, 0.0)
	var _r2: int = Ai16Kit.put(w, &"refinery", 0, 0.0, 400.0)
	var _f1: int = Ai16Kit.field(w, 700.0, 0.0, 60000, 2.0, 200.0, 40)
	var _f2: int = Ai16Kit.field(w, 700.0, 700.0, 60000, 2.0, 200.0, 40)
	var ids: PackedInt32Array = PackedInt32Array()
	for i: int in UNITS:
		var e: float = 60.0 + float(i % 10) * 22.0
		var n: float = -150.0 + float(i / 10) * 45.0
		var _a: bool = ids.push_back(Ai16Kit.put(w, &"harvester", 0, e, n))
	var b: HarvesterBrain = Ai16Kit.brain()
	var d: AiDriver = Ai16Kit.driver(w, b)
	Ai16Kit.step(w, 70 * HZ)
	return [w, d, b, ids]


func _think_us(b: HarvesterBrain, w: SimWorld, st: AiState, sink: CommandSink, ids: PackedInt32Array) -> float:
	var best: float = INF
	var v: SimView = w.view()
	for k: int in BATCHES + 1:
		var t0: int = Time.get_ticks_usec()
		for id: int in ids:
			b.think_one(id, v, st, sink, w.tick() + 1)
		var us: float = float(Time.get_ticks_usec() - t0) / float(ids.size())
		if k > 0:
			best = minf(best, us)
	return best


func _act_us(b: HarvesterBrain, w: SimWorld, st: AiState, sink: CommandSink, ids: PackedInt32Array) -> float:
	var best: float = INF
	var v: SimView = w.view()
	b.act_batch(ids, v, st, sink)
	for _k: int in ACT_LOOPS:
		var t0: int = Time.get_ticks_usec()
		for _j: int in 20:
			b.act_batch(ids, v, st, sink)
		best = minf(best, float(Time.get_ticks_usec() - t0) / float(20 * ids.size()))
	return best


func test_perf_harvester_think_and_act() -> void:
	var r: Array = _world()
	var w: SimWorld = r[0]
	var d: AiDriver = r[1]
	var b: HarvesterBrain = r[2]
	var ids: PackedInt32Array = r[3]
	var modes: Dictionary = {}
	for id: int in ids:
		var m: int = d.state.mode[EntityId.slot(id)]
		modes[m] = int(modes.get(m, 0)) + 1
	# the real driver for 10 s: the counters per think
	var th0: int = b.stats_thinks
	var pk0: int = b.stats_picks
	var sc0: int = b.sites.scans
	var fl0: int = b.stats_flees
	var sk0: int = b.stats_strikes
	Ai16Kit.step(w, 10 * HZ)
	var thinks: int = b.stats_thinks - th0
	var picks: int = b.stats_picks - pk0
	var scans: int = b.sites.scans - sc0
	# a bound sink: the timed calls go through the same CommandSink the driver uses, to the real sim
	var sink: CommandSink = CommandSink.new()
	var inner: PerfPathSink = PerfPathSink.new()
	inner.pa = w._pathing
	sink.bind(inner)
	var st: AiState = d.state
	var think_us: float = _think_us(b, w, st, sink, ids)
	var act_us: float = _act_us(b, w, st, sink, ids)
	var mv: PackedInt32Array = PackedInt32Array()
	var still: PackedInt32Array = PackedInt32Array()
	for id: int in ids:
		var _p: bool = (mv if HarvesterBrain.moving(st.mode[EntityId.slot(id)]) else still).push_back(id)
	print("AI-16 perf split: moving %d units %.2f us, standing %d units %.2f us" % [mv.size(), _act_us(b, w, st, sink, mv), still.size(), _act_us(b, w, st, sink, still)])
	print("AI-16 perf (%d Harvesters, modes %s; best of %d batches): think %.1f us (row %.1f), act %.2f us (row %.1f); 10 s: %d thinks, %d picks, %d structure scans, %d flees, %d strikes" % [
		UNITS, str(modes), BATCHES, think_us, THINK_ROW_US, act_us, ACT_ROW_US, thinks, picks, scans, b.stats_flees - fl0, b.stats_strikes - sk0])
	# deterministic counters (hard on every runner)
	assert_int(thinks).is_between(UNITS * HZ * 10 / d.think_period() - UNITS, UNITS * HZ * 10 / d.think_period() + UNITS)   # 1 / P of the units per tick
	assert_int(picks * 20).is_less(thinks)                                  # a choice point is a trip event, not a per-think cost
	assert_int(scans).is_less_equal(10 / 5 + 1)                              # one structure scan per team per refinery_scan_s (5 s)
	assert_int(b.stats_flees).is_equal(0)
	assert_int(b.stats_strikes).is_equal(0)                                  # a crowd of 100 on two fields never gets stuck
	assert_int(modes.size()).is_greater(2)                                   # the sample really mixes modes
	# timings: report-only on hosted runners
	var cite: String = "05 s10 think 25 us, ground act 2.7 us"
	assert_bool(PerfGate.check("test_harvester_perf.think", think_us, THINK_ROW_US * CI_FACTOR, cite)).is_true()
	assert_bool(PerfGate.check("test_harvester_perf.act", act_us, ACT_ROW_US * CI_FACTOR, cite)).is_true()


class PerfPathSink extends CommandSinkBase:
	var pa: Pathing
	func pathing() -> Pathing:
		return pa
