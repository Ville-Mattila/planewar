extends GdUnitTestSuite
## NET-58 perf note (R0 B.22 A-112): SnapshotCodec.prepare_tick and Interest (begin_tick + assign x 3) on the canonical
## 940-entity scene (R0 B.10 A-40) with and without ~60 live projectile entities (+ slug rows that are skipped). Budget
## row: 03 s4.2 row 12 "events + interest + encode + replay" 4.0 ms p95 for 8 clients (R0 B.7); bandwidth row: 04 s4.6
## ENTITY_META (A-112 note: ~0.2 KB/s for projectiles; test_projectile_interest.gd asserts <= 0.3 KB/s). The projectile
## share is bounded at 10 % of row 12 (400 us p95). Timing is report-only off the pinned runner (PerfGate, R0 B.17
## A-97); the work counters are hard. The ClientSession.tick delta is test_client_session_perf.gd before / after (PR).

const CITE: String = "03 s4.2 row 12 events+interest+encode+replay 4.0 ms p95 (R0 B.7); projectile share <= 10 %"
const TICKS: int = 240
const WARMUP: int = 150


## One run, interleaved so both halves see the same machine load: each tick prepare_tick + Interest on the frame
## without its projectile rows (an off codec / Interest / clients) and on the full frame (the rig's), order alternating.
func test_prepare_tick_and_interest_with_projectile_entities() -> void:
	var rig: ProjectileRig = ProjectileRig.new()
	rig.build(3, Vector3i(40, 200, 700), Vector3i(24, 70, 300), 6, 17)
	var off_codec: SnapshotCodec = SnapshotCodec.new(SnapRig.G, SnapRig.HZ)
	var off_it: Interest = Interest.new()
	var off_cl: Array[InterestClient] = []
	for cl: InterestClient in rig.clients:
		var c2: InterestClient = InterestClient.new(cl.key, cl.team)
		c2.possessed = cl.possessed
		c2.target = cl.target
		off_cl.append(c2)
	var us: Array[PackedInt64Array] = [PackedInt64Array(), PackedInt64Array(), PackedInt64Array(), PackedInt64Array()]
	var cached: int = 0
	for t: int in TICKS + WARMUP:
		rig.snap.frame.count = rig.n_entities
		rig.snap.tick += 1
		rig.snap.frame.tick = rig.snap.tick
		rig.snap.step_motion()
		rig.step_projectiles()
		var full: int = rig.snap.frame.count
		for half: int in 2:
			var on: bool = (half + t) % 2 == 0
			rig.snap.frame.count = full if on else rig.n_entities
			var t0: int = Time.get_ticks_usec()
			(rig.snap.codec if on else off_codec).prepare_tick(rig.snap.frame)
			var t1: int = Time.get_ticks_usec()
			_interest(rig.interest if on else off_it, rig.snap.codec if on else off_codec, rig.clients if on else off_cl, rig)
			var t2: int = Time.get_ticks_usec()
			if t >= WARMUP:
				var _a: bool = us[0 if on else 1].push_back(t1 - t0)
				var _b: bool = us[2 if on else 3].push_back(t2 - t1)
		rig.snap.frame.count = full
		cached += rig.live_replicated().size() if t >= WARMUP else 0
	var live: int = rig.live_replicated().size()
	assert_int(rig.snap.codec.prepare_count).is_equal(TICKS + WARMUP)          # hard: once per tick per codec
	assert_int(off_codec.prepare_count).is_equal(TICKS + WARMUP)
	for s: int in rig.live_replicated():                                        # hard: every live projectile cached
		assert_int(rig.snap.codec.c_tick[s]).is_equal(rig.snap.tick)
		assert_int(off_codec.c_tick[s]).is_not_equal(rig.snap.tick)
	assert_int(live).is_between(30, 100)
	assert_int(cached).is_greater(TICKS * 30)
	var p: PackedFloat64Array = PackedFloat64Array()
	for k: int in 4:
		var _x: bool = p.push_back(_pct(us[k], 0.5))
		var _y: bool = p.push_back(_pct(us[k], 0.95))
	print("PERF_REPORT name=test_projectile_roster_perf live=%d prepare_p50_us=%.0f->%.0f prepare_p95_us=%.0f->%.0f interest3_p50_us=%.0f->%.0f interest3_p95_us=%.0f->%.0f" % [
			live, p[2], p[0], p[3], p[1], p[6], p[4], p[7], p[5]])
	var delta_p95: float = maxf(p[1] - p[3], 0.0) + maxf(p[5] - p[7], 0.0)
	assert_bool(PerfGate.check("test_projectile_roster_perf.projectile_delta_p95", delta_p95, 400.0, CITE)).is_true()


func _interest(it: Interest, codec: SnapshotCodec, clients: Array[InterestClient], rig: ProjectileRig) -> void:
	it.begin_tick(rig.snap.frame, codec)
	for cl: InterestClient in clients:
		if it.present(cl.possessed):
			cl.focus_cell = it.cell[cl.possessed]
		it.assign(cl)


func _pct(v: PackedInt64Array, q: float) -> float:
	var s: Array[int] = []
	s.assign(Array(v))
	s.sort()
	return float(s[mini(floori(q * float(s.size())), s.size() - 1)])
