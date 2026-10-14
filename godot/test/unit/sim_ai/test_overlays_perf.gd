extends GdUnitTestSuite
## AI-08 perf note (05 s10 rows; 03 s4.2 "AI think + act" 6.0 ms): (1) the release-edge scan, one control-state read
## per registered entity per tick: 400 units with the no-op brain, with and without overlay parameters (the delta
## is the scan); (2) one overlay tick (Overlays.run: one TerrainProbe.probe, 6 samples, + track_velocity + drive);
## (3) one Assist.link_bridge (step 4, at most one per player slot). Best of 6 batches (the desktop's scheduler noise
## is larger than the code); printed for the PR, bounds are loose regression guards.

const UNITS: int = 400
const TICKS: int = 300


func _driver(params: bool) -> AiDriver:
	var d: AiDriver = AiDriver.new(Rng.new(1))
	d.set_brain(0, AiBrain.new())
	if params:
		d.set_overlay_params(0, OverlayKit.overlay_params(&"dart"))
	for s: int in range(1, UNITS + 1):
		var _ok: bool = d.register(EntityId.make(s, 1), 0)
	return d


func _us_per_tick(d: AiDriver) -> float:
	var v: AiTestKit.StubView = AiTestKit.StubView.new()
	var best: float = INF
	for _b: int in 6:
		d.reset_stats()
		AiTestKit.run(d, v, 0, TICKS / 6)
		best = minf(best, float(d.stats()["us_per_tick"]))
	return best


func test_perf_scan_400_units() -> void:
	var base: float = _us_per_tick(_driver(false))
	var scan: float = _us_per_tick(_driver(true))
	print("AI-08 perf: 400 units no-op brain: %.1f us/tick without overlays, %.1f with the scan (+%.1f us, %.2f us/unit)" % [
		base, scan, scan - base, (scan - base) / float(UNITS)])
	assert_float(scan).is_less(2000.0)


func test_perf_overlay_tick_and_link_bridge() -> void:
	var p: OverlayParams = OverlayKit.overlay_params(&"dart")
	var st: AiState = AiState.new()
	var rec: CommandSinkBase = CommandSinkBase.new()
	var sink: CommandSink = CommandSink.new()
	sink.bind(rec)
	var v: TestOverlaysView = TestOverlaysView.new()
	var t: Terrain = Terrain.new()
	var probe: ProbeResult = ProbeResult.new()
	var out: PilotInput = PilotInput.new()
	var id: int = EntityId.make(5, 1)
	var n: int = 2000
	var us_run: float = INF
	var us_bridge: float = INF
	for _b: int in 6:
		Overlays.enter(id, v, st, p, 0)
		var t0: int = Time.get_ticks_usec()
		for k: int in n:
			st.overlay_since[5] = k              # never settles: every call is a full SAFETY tick
			var _e: bool = Overlays.run(id, v, st, p, t, sink, k, probe, out)
		var t1: int = Time.get_ticks_usec()
		for _k: int in n:
			Assist.link_bridge(v.basis(id), v.pos(id), v.vel(id), t, p.bridge, probe, out)
		var t2: int = Time.get_ticks_usec()
		us_run = minf(us_run, float(t1 - t0) / float(n))
		us_bridge = minf(us_bridge, float(t2 - t1) / float(n))
	print("AI-08 perf: Overlays.run (SAFETY tick) %.1f us/call, Assist.link_bridge %.1f us/call" % [us_run, us_bridge])
	assert_float(us_run).is_less(200.0)
	assert_float(us_bridge).is_less(200.0)


class TestOverlaysView extends SimView:
	func alive(_id: int) -> bool:
		return true

	func pos(_id: int) -> Vector3:
		return Vector3(Sphere.PLANET_RADIUS + 500.0, 0.0, 0.0)

	func vel(_id: int) -> Vector3:
		return Vector3(0.0, 110.0, 0.0)

	func basis(_id: int) -> Basis:
		return Basis(Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0, -1, 0))

	func fuel01(_id: int) -> float:
		return 1.0
