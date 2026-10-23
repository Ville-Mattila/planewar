extends GdUnitTestSuite
## NET-17 perf note: ClientSession.tick on the canonical scene (R0 B.10 A-40, 04 s4.5: 940 entities, A 40 / B 200 /
## C 700, 04 s4.1 schedule + 3 rolling-refresh FULLs per tick) for one client over LocalTransport (LAN). Budget row:
## 03 s10.2 "ClientSession.tick (decode + NetSimView + prediction) 1.0 ms per 30 Hz tick" PC (R0 C1-23); prediction
## is NET-18, so this measures transport poll + snapshot decode + clock + acks + NetSimView.sample. The presentation
## read of every pose (read_poses over the roster, the TA-52 entity-sync path) is reported against 03 s10.2 "entity
## sync 2.4 ms" (printed, not gated: presentation's row). Timing is report-only off the pinned runner (PerfGate, R0 B.17 A-97); the work counters are hard.

const CITE: String = "03 s10.2 ClientSession.tick 1.0 ms PC (R0 C1-23)"
const CITE_POSES: String = "03 s10.2 entity sync 2.4 ms"
const TICKS: int = 300
const WARMUP: int = 30


func test_client_session_tick_on_the_canonical_scene() -> void:
	var rig: SnapRig = SnapRig.new()
	rig.build(Vector3i(40, 200, 700), Vector3i(24, 70, 300), 6, 17)
	var clock: LocalClock = LocalClock.new()
	var server: LocalTransport = LocalTransport.new_server(clock)
	var ep: LocalTransport = server.connect_client()
	var conn: int = ep.server_conn_of()
	var cs: ClientSession = ClientSession.new(ep, 0)
	var defs: NetDefs = NetDefs.new()
	defs.gravity = SnapRig.G
	defs.gravity_def[SnapRig.DEF_BOMB] = 1
	cs.configure_defs(defs, null)
	var store: BaselineStore = BaselineStore.new(0)
	var acks: Array[int] = [0]
	var _c: int = server.packet.connect(func(_cn: int, _ch: int, b: PackedByteArray) -> void:
		if b.size() == SessionCodec.ACK_BYTES and b[0] == Protocol.SNAPSHOT_ACK:
			store.ack(b.decode_u32(1))
			acks[0] += 1)
	var w: WelcomeInfo = WelcomeInfo.new()
	w.slot = 0
	var _s: int = w.secret.resize(Protocol.SECRET_BYTES)
	var _h: int = w.map_hash.resize(Protocol.HASH_BYTES)
	w.tick = 1
	cs.receive(Protocol.CH_CONTROL, SessionCodec.encode_welcome(w))
	cs.mark_loaded(w.map_hash)
	var all: PackedInt32Array = PackedInt32Array()
	for i: int in rig.frame.count:
		var _a: bool = all.push_back(i)
	var metas: Array[PackedByteArray] = []
	var _m: int = RosterCodec.encode_meta(rig.roster, all, metas)
	for m: PackedByteArray in metas:
		server.send(conn, Protocol.CH_EVENTS, m, true)
	var a: PackedInt32Array = PackedInt32Array()
	var b: PackedInt32Array = PackedInt32Array()
	var c: PackedInt32Array = PackedInt32Array()
	var r: PackedInt32Array = PackedInt32Array()
	var tick_us: PackedInt64Array = PackedInt64Array()
	var pose_us: PackedInt64Array = PackedInt64Array()
	var ids: PackedInt32Array = PackedInt32Array()
	for i: int in all:
		var _i: bool = ids.push_back(EntityId.make(i, 1))
	var pos: PackedVector3Array = PackedVector3Array()
	var rot: PackedVector4Array = PackedVector4Array()
	var _p: int = pos.resize(ids.size())
	var _q: int = rot.resize(ids.size())
	var records: int = 0
	var kc: KeyframeCodec = KeyframeCodec.new()
	var alive_last: int = 0
	for t: int in TICKS + WARMUP:
		rig.step()
		if t == 0:                                                           # join: KEYFRAME(ALL) after the META (04 s2.2)
			server.send(conn, Protocol.CH_EVENTS, kc.encode(rig.codec, store, rig.tick, 1, Protocol.KeyframeScope.ALL, all), true)
		else:
			rig.canonical_lists(0, a, b, c, r)
			var out: Array[PackedByteArray] = []
			var _n: int = rig.codec.encode(store, rig.tick, a, b, c, null, out, r)
			for p: PackedByteArray in out:
				server.send(conn, Protocol.CH_SNAPSHOT, p, false)
		clock.advance_tick()
		server.poll()
		var before: int = cs.decoder.records_applied
		var t0: int = Time.get_ticks_usec()
		cs.tick()
		var t1: int = Time.get_ticks_usec()
		alive_last = cs.view().read_poses(ids, pos, rot)
		var t2: int = Time.get_ticks_usec()
		if t >= WARMUP:
			var _x: bool = tick_us.push_back(t1 - t0)
			var _y: bool = pose_us.push_back(t2 - t1)
			records += cs.decoder.records_applied - before
	var p50: float = _pct(tick_us, 0.5)
	var p95: float = _pct(tick_us, 0.95)
	print("PERF_REPORT name=test_client_session_perf.tick p50_us=%.0f p95_us=%.0f records_per_tick=%.1f poses_p50_us=%.0f alive=%d" % [
			p50, p95, float(records) / float(TICKS), _pct(pose_us, 0.5), alive_last])
	assert_bool(PerfGate.check("test_client_session_perf.tick_p50", p50, 1000.0, CITE)).is_true()
	# Presentation's row, not this task's: reported only (the dev box measures 3.4 ms p50 for all 940, over the 2.4 ms
	# entity-sync row; EntityViewPool.sync / TA-52 re-measures with its real read set).
	print("PERF_REPORT name=test_client_session_perf.read_poses_940_p50 us=%.0f row_us=2400 cite=%s" % [_pct(pose_us, 0.5), CITE_POSES])
	# hard work counters: every tick decoded, all 940 entities live, acks every third tick, A/B/C records in the band
	assert_int(cs.state).is_equal(ClientSession.State.PLAYING)
	assert_int(cs.keyframes_applied).is_equal(1)
	assert_int(cs.decoder.store.newest_tick).is_equal(rig.tick)
	assert_int(cs.snapshots_ok).is_greater_equal(TICKS + WARMUP - 1)       # split ticks count one per packet
	assert_int(cs.malformed).is_equal(0)
	assert_int(alive_last).is_equal(940)
	var third: int = floori(float(TICKS + WARMUP) / float(ClientSession.ACK_EVERY_TICKS))
	assert_int(acks[0]).is_between(third - 2, third + 2)
	assert_float(float(records) / float(TICKS)).is_between(60.0, 260.0)
	assert_int(cs.view().pose.computed).is_equal(940)                      # each pose computed once per sample


func _pct(v: PackedInt64Array, q: float) -> float:
	var s: Array[int] = []
	s.assign(Array(v))
	s.sort()
	return float(s[mini(floori(q * float(s.size())), s.size() - 1)])
