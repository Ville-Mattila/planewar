extends GdUnitTestSuite
## AI-23 perf note: the Commander's think slice against 05 s10 / 03 s4.2 (Commander row: <= 0.7 ms per slice). The book
## think does one `BuildPlanner.load_view` (own and known structures from Perception), one `BookContext` fill over the own
## list, and at most `cmds_per_think` steps; `resolve_site` examines <= `scan_cap` (64) candidates against tens of own
## structures. Measured on the SC-41 opening (two bots, the six books in turn is SC-41's job; here vanguard_standard) from
## 0:00 to 5:00, one think per bot per second. Timing is report-only off the pinned runner (PerfGate, R0 B.17 A-97; best of 3
## runs of the mean); the think count is asserted hard. The numbers go to the PR.

const HZ: int = Ai23Kit.HZ


class TimedCommander extends CommanderBrain:
	var us: PackedInt32Array = PackedInt32Array()

	func think_bot(slot: int, tier: int, tick: int, view: SimView, sink: CommandSink) -> void:
		var t0: int = Time.get_ticks_usec()
		super.think_bot(slot, tier, tick, view, sink)
		var _a: bool = us.push_back(Time.get_ticks_usec() - t0)


func _run() -> PackedInt32Array:
	var w: SimWorld = Ai23Kit.world(60)
	var cb: TimedCommander = TimedCommander.new(Ai23Kit.content(), Ai23Kit.params(), Ai23Kit.sites(), HZ)
	cb.set_books([Ai23Kit.book(&"vanguard_standard")])
	var _d: AiDriver = Ai23Kit.driver(w, cb, [0, 2])
	var _e: Array[SimEvent] = Ai23Kit.run(w, 300 * HZ)
	return cb.us


func test_think_slice_within_the_commander_row() -> void:
	var best_mean: float = INF
	var worst_p95: float = 0.0
	var worst_max: int = 0
	var n: int = 0
	for _i: int in 3:
		var us: PackedInt32Array = _run()
		var sorted: PackedInt32Array = us.duplicate()
		sorted.sort()
		var sum: int = 0
		for v: int in us:
			sum += v
		n = us.size()
		best_mean = minf(best_mean, float(sum) / float(n))
		worst_p95 = maxf(worst_p95, float(sorted[int(0.95 * float(n))]))
		worst_max = maxi(worst_max, sorted[n - 1])
	print("AI-23 perf: %d thinks per run, mean %.0f us (best of 3), p95 %.0f us, max %d us (budget 700 us)" % [n, best_mean, worst_p95, worst_max])
	assert_int(n).is_greater(500)
	assert_bool(PerfGate.check("test_commander_perf.think_mean", best_mean, 700.0, "05 s10 Commander row, 0.7 ms per slice")).is_true()
