extends GdUnitTestSuite
## TA-23: per-frame build budget (count cap, ms cap) and the starvation rule (03 s7.4, R0 C1-06).

var _cost: float = 1.0
var _built: Array[ChunkNode] = []
var _fail_after: int = 1 << 30


func before_test() -> void:
	_cost = 1.0
	_built.clear()
	_fail_after = 1 << 30


func _build(node: ChunkNode) -> float:
	if _built.size() >= _fail_after:
		return -1.0
	_built.append(node)
	return _cost


func _sched(builds: int, ms: float) -> ChunkScheduler:
	var s: ChunkScheduler = ChunkScheduler.new()
	var cfg: PlanetTierConfig = PlanetTierConfig.new()
	cfg.builds_per_frame = builds
	cfg.build_ms_cap = ms
	s.configure(cfg)
	return s


func _fill(s: ChunkScheduler, count: int, frame: int) -> Array[ChunkNode]:
	s.begin_plan()
	var out: Array[ChunkNode] = []
	for k: int in count:
		var n: ChunkNode = ChunkNode.make(0, 3, k % 8, k >> 3, 0.0, 0.0)
		n.priority = float(k)
		s.push(n, frame, frame * 16)
		out.append(n)
	return out


func test_count_cap() -> void:
	var s: ChunkScheduler = _sched(6, 100.0)
	var _q: Array[ChunkNode] = _fill(s, 20, 1)
	assert_int(s.run(_build)).is_equal(6)
	assert_int(_built.size()).is_equal(6)


func test_highest_priority_first() -> void:
	var s: ChunkScheduler = _sched(2, 100.0)
	var q: Array[ChunkNode] = _fill(s, 10, 1)
	var _n: int = s.run(_build)
	assert_object(_built[0]).is_same(q[9])
	assert_object(_built[1]).is_same(q[8])


func test_ms_cap_stops_when_estimate_would_overrun() -> void:
	var s: ChunkScheduler = _sched(6, 4.0)
	_cost = 1.5
	var _q: Array[ChunkNode] = _fill(s, 20, 1)
	# 1.5 + 1.5 = 3.0; a third (estimate 1.5) would reach 4.5 > 4.0 and waits
	assert_int(s.run(_build)).is_equal(2)
	assert_float(s.last_ms).is_less_equal(4.0)


func test_starvation_rule_forces_exactly_one_build_every_third_frame() -> void:
	var s: ChunkScheduler = _sched(2, 2.0)
	_cost = 5.0                                  # every build exceeds the 2 ms cap
	var _q: Array[ChunkNode] = _fill(s, 5, 1)
	assert_int(s.run(_build)).is_equal(1)        # first build: no estimate yet, runs
	var pattern: Array[int] = []
	for f: int in range(2, 11):
		_q = _fill(s, 5, f)
		pattern.append(s.run(_build))
	# waits 2 frames, then exactly one forced build, repeating
	assert_array(pattern).is_equal([0, 0, 1, 0, 0, 1, 0, 0, 1])


func test_forced_build_is_flagged() -> void:
	var s: ChunkScheduler = _sched(2, 2.0)
	_cost = 5.0
	var _q: Array[ChunkNode] = _fill(s, 3, 1)
	var _n: int = s.run(_build)
	for f: int in range(2, 5):
		_q = _fill(s, 3, f)
		_n = s.run(_build)
	assert_bool(s.last_forced).is_true()
	assert_int(s.frames_since_build).is_equal(0)


func test_starvation_frames_is_data() -> void:
	var s: ChunkScheduler = _sched(2, 2.0)
	s.starvation_frames = 4
	_cost = 5.0
	var _q: Array[ChunkNode] = _fill(s, 3, 1)
	var _n: int = s.run(_build)
	var pattern: Array[int] = []
	for f: int in range(2, 7):
		_q = _fill(s, 3, f)
		pattern.append(s.run(_build))
	assert_array(pattern).is_equal([0, 0, 0, 0, 1])


func test_empty_queue_resets_starvation_counter() -> void:
	var s: ChunkScheduler = _sched(2, 2.0)
	s.frames_since_build = 5
	s.begin_plan()
	assert_int(s.run(_build)).is_equal(0)
	assert_int(s.frames_since_build).is_equal(0)


func test_failed_build_ends_the_run() -> void:
	var s: ChunkScheduler = _sched(6, 100.0)
	_fail_after = 2
	var _q: Array[ChunkNode] = _fill(s, 10, 1)
	assert_int(s.run(_build)).is_equal(2)


func test_push_dedupes_per_frame_and_tracks_wait_start() -> void:
	var s: ChunkScheduler = _sched(6, 100.0)
	var n: ChunkNode = ChunkNode.make(0, 2, 0, 0, 0.0, 0.0)
	s.begin_plan()
	s.push(n, 1, 100)
	s.push(n, 1, 100)
	assert_int(s.queue.size()).is_equal(1)
	s.begin_plan()
	s.push(n, 2, 116)
	assert_int(n.wanted_since_ms).is_equal(100)  # queued without a gap: same wait
	s.begin_plan()
	s.push(n, 5, 200)
	assert_int(n.wanted_since_ms).is_equal(200)  # gap: a new wait starts
