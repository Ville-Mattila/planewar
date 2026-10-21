extends GdUnitTestSuite
## NET-07 perf note (03 s4.2 "events + interest + encode + replay" row, 04 s4.3 / s4.6 rolling-refresh row): cost of a
## 1,200-entity KEYFRAME encode and decode (one reliable message per join / reconnect / stale ack, not a per-tick path)
## and of RollingRefresh.pick at 700 C entities (per tick, per client). Timing bounds follow R0 B.17 A-97: asserted only
## on the pinned runner (PerfGate), printed as PERF_REPORT otherwise; the size and work counters are hard.

const CITE: String = "NET-07; 03 s4.2 encode row, 04 s4.3"


func _scene(rig: SnapRig) -> void:
	rig.build(Vector3i(60, 240, 900), Vector3i(30, 100, 300), 4, 3)
	rig.step()


func _all(n: int) -> PackedInt32Array:
	var r: PackedInt32Array = PackedInt32Array()
	for i: int in n:
		r.append(i)
	return r


func test_keyframe_encode_decode_1200_entities() -> void:
	var rig: SnapRig = SnapRig.new()
	_scene(rig)
	var all: PackedInt32Array = _all(rig.frame.count)
	var kc: KeyframeCodec = KeyframeCodec.new()
	var store: BaselineStore = BaselineStore.new(0)
	var dec: SnapshotDecoder = rig.new_decoder(0)
	var msg: PackedByteArray = kc.encode(rig.codec, store, rig.tick, 1, 0, all)
	var own: int = 0
	for i: int in all.size():
		own += 1 if rig.roster.team_of(i) == 0 else 0
	assert_int(msg.size()).is_equal(KeyframeCodec.size_for(1200, own, 0))
	assert_int(msg.size()).is_less_equal(Protocol.MAX_RELIABLE_BYTES)
	var n: int = 60
	var t0: int = Time.get_ticks_usec()
	for i: int in n:
		var _m: PackedByteArray = kc.encode(rig.codec, store, rig.tick, i & 0xFFFF, 0, all)
	var t1: int = Time.get_ticks_usec()
	for i: int in n:
		kc.forget()
		assert_int(kc.decode(msg, dec)).is_equal(KeyframeCodec.Status.OK)
	var t2: int = Time.get_ticks_usec()
	var enc_us: float = float(t1 - t0) / n
	var dec_us: float = float(t2 - t1) / n
	print("NET-07 perf KEYFRAME 1200 entities: %d B, encode %.0f us, decode %.0f us" % [msg.size(), enc_us, dec_us])
	assert_bool(PerfGate.check("keyframe_encode_1200", enc_us, 8000.0, CITE)).is_true()
	assert_bool(PerfGate.check("keyframe_decode_1200", dec_us, 8000.0, CITE)).is_true()


func test_rolling_refresh_pick_at_700_c() -> void:
	var c: PackedInt32Array = PackedInt32Array()
	for i: int in 700:
		c.append(240 + i)
	var rr: RollingRefresh = RollingRefresh.new()
	var out: PackedInt32Array = PackedInt32Array()
	var n: int = 30000
	var t0: int = Time.get_ticks_usec()
	for t: int in n:
		var _k: int = rr.pick(c, t + 1, out)
	var t1: int = Time.get_ticks_usec()
	var us: float = float(t1 - t0) / n
	print("NET-07 perf RollingRefresh.pick at 700 C: %.2f us per call (3 entries)" % us)
	assert_int(rr.picked).is_equal(3 * n)
	assert_bool(PerfGate.check("rolling_refresh_pick_700", us, 20.0, CITE)).is_true()
