extends GdUnitTestSuite
## AI-04 perf note: scheduling overhead of AiDriver.on_tick for 400 AI units with a no-op brain (03 s4.2 "AI think + act"
## row, 6.0 ms p95; scheduling must stay a small fraction). Prints us/tick; the bound is a loose regression guard.

const UNITS: int = 400
const TICKS: int = 600
const GUARD_US: float = 1500.0


func test_scheduling_overhead_400_units_no_brains() -> void:
	var d: AiDriver = AiDriver.new(Rng.new(1))
	d.set_brain(0, AiBrain.new())
	for s: int in range(1, UNITS + 1):
		var _ok: bool = d.register(EntityId.make(s, 1), 0)
	var v: AiTestKit.StubView = AiTestKit.StubView.new()
	AiTestKit.run(d, v, 0, 60)
	d.reset_stats()
	AiTestKit.run(d, v, 60, TICKS)
	var us: float = d.stats()["us_per_tick"]
	print("AI-04 perf: %d units, no-op brain: %.1f us/tick (thinks %d)" % [UNITS, us, d.stats()["thinks"]])
	assert_int(d.stats()["thinks"]).is_equal(UNITS * TICKS / 10)
	assert_float(us).is_less(GUARD_US)
