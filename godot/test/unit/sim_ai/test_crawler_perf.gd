extends GdUnitTestSuite
## AI-18 perf note (05 s10: think slice 25 us per unit, act row "ground + towers" 2.7 us per unit). 24 Siege Crawlers are
## put on the flat datum round an enemy Refinery, half inside the band (they siege where they stand), half 600 m outside
## (they drive to a ring spot), with a friendly Sensor Mast; after 30 s every mode of an attack is in play. The per-call
## cost of `think_one`, of an `act_batch` over all of them and of one lofted solve (`SiegeAim.loft`, run once per spot) is
## timed, best of several batches. Timing bounds are report-only on hosted runners (R0 B.17 A-97, `PerfGate`); the work
## counters are hard: a solve per spot, not per think; no spot search on a steady siege think.

const HZ: int = 30
const UNITS: int = 24
const THINK_ROW_US: float = 25.0
const ACT_ROW_US: float = 2.7
const CI_FACTOR: float = 2.0
const BATCHES: int = 6
const ACT_LOOPS: int = 30


func _world() -> Array:
	var w: SimWorld = Ai16Kit.world(23)
	var t: int = Ai16Kit.put(w, &"refinery", DartKit.FOE, 0.0)
	var _m: int = Ai16Kit.put(w, &"sensor_mast", 0, 600.0, 300.0)
	var ids: PackedInt32Array = PackedInt32Array()
	for i: int in UNITS:
		var a: float = TAU * float(i) / float(UNITS)
		var r: float = 1075.0 if (i & 1) == 0 else 1700.0
		var _a: bool = ids.push_back(Ai16Kit.put(w, &"siege_crawler", 0, r * cos(a), r * sin(a)))
	var b: CrawlerBrain = Ai18Kit.brain(w.terrain())
	var d: AiDriver = Ai18Kit.driver(w, b)
	for id: int in ids:
		var cmd: Command = Command.order(0, PackedInt32Array([id]), OrderSpec.make(OrderSpec.Kind.ATTACK, t))
		while w.apply_command(cmd).code == CommandResult.Code.REJECTED_RATE:   # the sim's command rate limit
			Ai16Kit.step(w)
	Ai16Kit.step(w, 30 * HZ)
	return [w, d, b, ids, t]


func _think_us(b: CrawlerBrain, w: SimWorld, st: AiState, sink: CommandSink, ids: PackedInt32Array) -> float:
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


func _act_us(b: CrawlerBrain, w: SimWorld, st: AiState, sink: CommandSink, ids: PackedInt32Array) -> float:
	var best: float = INF
	var v: SimView = w.view()
	b.act_batch(ids, v, st, sink)
	for _k: int in ACT_LOOPS:
		var t0: int = Time.get_ticks_usec()
		for _j: int in 20:
			b.act_batch(ids, v, st, sink)
		best = minf(best, float(Time.get_ticks_usec() - t0) / float(20 * ids.size()))
	return best


func _loft_us(b: CrawlerBrain, w: SimWorld, c: int, t: int) -> float:
	var p: CrawlerParams = b.prm
	var st: ProjectileState = ProjectileState.new()
	var muzzle: Vector3 = w.view().pos(c)
	var aim: Vector3 = w.view().pos(t)
	var best: float = INF
	for _k: int in BATCHES:
		var t0: int = Time.get_ticks_usec()
		var _e: float = SiegeAim.loft(muzzle, aim, p.speed, p.shell, p.rules, w.terrain(), 2.0 * p.dt, p.max_steps,
			CrawlerParams.LOFT_ITERS, p.loft_tol_m, st)
		best = minf(best, float(Time.get_ticks_usec() - t0))
	return best


func test_perf_crawler_think_and_act() -> void:
	var r: Array = _world()
	var w: SimWorld = r[0]
	var d: AiDriver = r[1]
	var b: CrawlerBrain = r[2]
	var ids: PackedInt32Array = r[3]
	var modes: Dictionary = {}
	for id: int in ids:
		var m: int = d.state.mode[EntityId.slot(id)]
		modes[m] = int(modes.get(m, 0)) + 1
	var th0: int = b.stats_thinks
	var so0: int = b.stats_solves
	var sp0: int = b.stats_spots
	Ai16Kit.step(w, 10 * HZ)
	var thinks: int = b.stats_thinks - th0
	var solves: int = b.stats_solves - so0
	var spots: int = b.stats_spots - sp0
	var sink: CommandSink = CommandSink.new()
	var inner: PerfPathSink = PerfPathSink.new()
	inner.pa = w._pathing
	sink.bind(inner)
	var think_us: float = _think_us(b, w, d.state, sink, ids)
	var act_us: float = _act_us(b, w, d.state, sink, ids)
	var loft_us: float = _loft_us(b, w, ids[0], r[4] as int)
	var aimed: PackedInt32Array = PackedInt32Array()
	var other: PackedInt32Array = PackedInt32Array()
	for id: int in ids:
		var _p: bool = (aimed if (d.state.bflags[EntityId.slot(id)] & CrawlerBrain.B_AIMED) != 0 else other).push_back(id)
	print("AI-18 perf split: firing on the bearing %d units %.2f us, driving to a spot %d units %.2f us" % [aimed.size(),
		_act_us(b, w, d.state, sink, aimed), other.size(), _act_us(b, w, d.state, sink, other)])
	print("AI-18 perf (%d Crawlers, modes %s; best of %d batches): think %.1f us (row %.1f), act %.2f us (row %.1f), one lofted solve %.0f us; 10 s: %d thinks, %d solves, %d spot searches" % [
		UNITS, str(modes), BATCHES, think_us, THINK_ROW_US, act_us, ACT_ROW_US, loft_us, thinks, solves, spots])
	assert_int(thinks).is_between(UNITS * HZ * 10 / d.think_period() - UNITS, UNITS * HZ * 10 / d.think_period() + UNITS)
	assert_int(solves).is_less_equal(UNITS)                                  # a solve per spot arrival, never per think
	assert_int(spots).is_less_equal(UNITS)                                   # no spot search on a steady think
	assert_int(b.stats_gave_up).is_equal(0)
	var cite: String = "05 s10 think 25 us, ground act 2.7 us"
	assert_bool(PerfGate.check("test_crawler_perf.think", think_us, THINK_ROW_US * CI_FACTOR, cite)).is_true()
	assert_bool(PerfGate.check("test_crawler_perf.act", act_us, ACT_ROW_US * CI_FACTOR, cite)).is_true()


class PerfPathSink extends CommandSinkBase:
	var pa: Pathing
	func pathing() -> Pathing:
		return pa
