extends GdUnitTestSuite
## NET-07 integration (net/keyframe/MODULE.md K1, K4, K5): one server (SnapRig world, SnapshotCodec, KeyframePolicy,
## RollingRefresh, BaselineStore mirror) and one client (SnapshotDecoder + KeyframeCodec) over a LocalTransport pair with
## loss / reorder injection (FaultModel presets). Asserted numerically: the join keyframe once, no periodic keyframe,
## a 33-tick ack gap = exactly one more, server mirror == client frame at every complete tick under loss, and the
## rolling-refresh bytes at 700 C entities against the 04 s4.3 / R0 C1-15 figure (<= 1.8 KB/s).

const TICKS_PER_ACK: int = 3

var _rig: SnapRig
var _lr: LocalRig
var _store: BaselineStore
var _policy: KeyframePolicy
var _refresh: RollingRefresh
var _skc: KeyframeCodec
var _ckc: KeyframeCodec
var _dec: SnapshotDecoder
var _all: PackedInt32Array = PackedInt32Array()
var _c_all: PackedInt32Array = PackedInt32Array()
var _a: PackedInt32Array = PackedInt32Array()
var _b: PackedInt32Array = PackedInt32Array()
var _c: PackedInt32Array = PackedInt32Array()
var _ref: PackedInt32Array = PackedInt32Array()
var _mute_from: int = 0
var _mute_to: int = 0
var _keyframes_applied: int = 0
var _keyframes_sent: int = 0
var _snapshot_ok: int = 0
var _bytes_snapshot: int = 0


func before_test() -> void:
	_all = PackedInt32Array()
	_c_all = PackedInt32Array()
	_mute_from = 0
	_mute_to = 0
	_keyframes_applied = 0
	_keyframes_sent = 0
	_snapshot_ok = 0
	_bytes_snapshot = 0


func _setup(model: FaultModel) -> void:
	_rig = SnapRig.new()
	_rig.build(Vector3i(20, 80, 120), Vector3i(10, 40, 40), 2, 31)
	_lr = LocalRig.new(model)
	_store = BaselineStore.new(0)
	_policy = KeyframePolicy.new()
	_refresh = RollingRefresh.new()
	_skc = KeyframeCodec.new()
	_ckc = KeyframeCodec.new()
	_dec = _rig.new_decoder(0)
	for i: int in _rig.frame.count:
		_all.append(i)
		if _rig.tier[i] == 2:
			_c_all.append(i)
	_lr.server.packet.connect(_on_server)
	_lr.client.packet.disconnect(_lr._on_client_packet)
	_lr.client.packet.connect(_on_client)
	_policy.start(1)


func _on_server(_conn: int, channel: int, bytes: PackedByteArray) -> void:
	if channel == Protocol.CH_INPUT and bytes.size() == 7 and bytes[0] == Protocol.SNAPSHOT_ACK:
		_store.ack(bytes.decode_u32(1))


func _on_client(_conn: int, channel: int, bytes: PackedByteArray) -> void:
	if channel == Protocol.CH_EVENTS and bytes[0] == Protocol.KEYFRAME:
		if _ckc.decode(bytes, _dec) == KeyframeCodec.Status.OK:
			_keyframes_applied += 1
	elif channel == Protocol.CH_SNAPSHOT:
		if _dec.decode(bytes) == SnapshotDecoder.Status.OK:
			_snapshot_ok += 1


func _tick_once() -> void:
	_rig.step()
	_lr.step()                                          # advance the clock, deliver what is due (acks, snapshots)
	var tick: int = _rig.tick
	var scope: int = _policy.poll(_store, tick)
	if scope != KeyframePolicy.NONE:
		var msg: PackedByteArray = _skc.encode(_rig.codec, _store, tick, _policy.seq, scope, _all)
		assert_int(msg.size()).is_greater(0)
		_lr.server.send(_lr.server_conn, Protocol.CH_EVENTS, msg, true)
		_refresh.note_full(_all, tick)
		_keyframes_sent += 1
	else:
		_rig.lists(0, _a, _b, _c)
		var _n: int = _refresh.pick(_c_all, tick, _ref)
		var out: Array[PackedByteArray] = []
		var _k: int = _rig.codec.encode(_store, tick, _a, _b, _c, null, out, _ref)
		for p: PackedByteArray in out:
			assert_int(p.size()).is_less_equal(Protocol.MAX_UNRELIABLE_BYTES)
			_bytes_snapshot += p.size()
			_lr.server.send(_lr.server_conn, Protocol.CH_SNAPSHOT, p, false)
	if tick % TICKS_PER_ACK == 0 and (tick < _mute_from or tick >= _mute_to):
		var ack: PackedByteArray = PackedByteArray([Protocol.SNAPSHOT_ACK, 0, 0, 0, 0, 0, 0])
		ack.encode_u32(1, _dec.store.complete_tick)
		_lr.client.send(LocalTransport.CLIENT_CONN, Protocol.CH_INPUT, ack, false)


## The client's newest complete frame equals the server mirror of the same tick (N9 / K4).
func _assert_mirrors_equal() -> bool:
	var t: int = _dec.store.complete_tick
	var server_frame: BaselineFrame = _store.frame_at(t)
	var client_frame: BaselineFrame = _dec.store.frame_at(t)
	if t <= 0 or server_frame == null or client_frame == null:
		return false
	assert_bool(client_frame.same_state(server_frame)).is_true()
	return true


func test_join_keyframe_once_and_no_periodic_keyframe_on_a_clean_link() -> void:
	_setup(null)
	var checked: int = 0
	for t: int in 900:
		_tick_once()
		if t % 17 == 0 and _assert_mirrors_equal():
			checked += 1
	assert_int(_keyframes_sent).is_equal(1)
	assert_int(_keyframes_applied).is_equal(1)
	assert_int(_policy.sent_stale).is_equal(0)
	assert_int(_policy.sent_all).is_equal(1)
	assert_int(checked).is_greater(40)
	assert_int(_refresh.picked).is_greater(0)
	assert_int(_dec.store.complete_tick).is_greater(890)


func test_33_tick_ack_gap_sends_exactly_one_more_keyframe() -> void:
	_setup(null)
	_mute_from = 100
	_mute_to = 141
	var stale_at: int = -1
	var acked_before_mute: int = -1
	for t: int in 500:
		var before: int = _keyframes_sent
		_tick_once()
		if _rig.tick == _mute_from:
			acked_before_mute = _store.acked_tick
		if _keyframes_sent > before and _rig.tick > 1:
			stale_at = _rig.tick
	assert_int(_policy.sent_stale).is_equal(1)
	assert_int(_keyframes_sent).is_equal(2)
	assert_int(_keyframes_applied).is_equal(2)
	assert_int(acked_before_mute).is_greater(90)         # acks flowed until the blackout (complete ticks, every 3rd tick)
	assert_int(stale_at).is_equal(acked_before_mute + KeyframePolicy.STALE_TICKS)   # the first tick of a 33-tick gap
	assert_bool(_assert_mirrors_equal()).is_true()
	assert_int(_store.acked_tick).is_greater(480)


func test_loss_and_reorder_keep_the_baselines_identical() -> void:
	_setup(FaultModel.preset(FaultModel.Preset.TARGET, 11))
	var checked: int = 0
	for t: int in 1200:
		_tick_once()
		if t % 7 == 0 and _assert_mirrors_equal():
			checked += 1
	assert_int(checked).is_greater(80)
	assert_int(_keyframes_applied).is_greater(0)
	assert_int(_policy.sent_all).is_equal(1)
	assert_int(_snapshot_ok).is_greater(900)


func test_mobile_switch_burst_loss_recovers_with_stale_ack_keyframes() -> void:
	_setup(FaultModel.preset(FaultModel.Preset.MOBILE_SWITCH, 5))   # ticks 900-1019 lost both ways
	for t: int in 1300:
		_tick_once()
	assert_int(_policy.sent_stale).is_greater_equal(1)
	assert_int(_policy.sent_stale).is_less_equal(2)               # an unacked keyframe is never repeated: one per episode
	assert_int(_keyframes_applied).is_equal(_keyframes_sent)      # reliable: every keyframe arrives
	var ok: bool = false
	for t: int in 60:
		_tick_once()
		ok = _assert_mirrors_equal() or ok
	assert_bool(ok).is_true()


## One scene at 700 C entities for `ticks` ticks (the first 30 are the join storm and not counted). Returns
## Vector2i(stream bytes, refresh FULL record bytes): the record bytes are what 04 s4.3 counts, 19 B (+1 ai_tag for the
## client's own team) per record; the stream bytes are every packet byte after the join storm.
func _bytes_over(refresh_on: bool, ticks: int) -> Vector2i:
	var rig: SnapRig = SnapRig.new()
	rig.build(Vector3i(40, 200, 700), Vector3i(24, 100, 200), 4, 7)
	var store: BaselineStore = BaselineStore.new(0)
	var dec: SnapshotDecoder = rig.new_decoder(0)
	var rr: RollingRefresh = RollingRefresh.new()
	var c_all: PackedInt32Array = PackedInt32Array()
	for i: int in rig.frame.count:
		if rig.tier[i] == 2:
			c_all.append(i)
	assert_int(c_all.size()).is_equal(700)
	var total: int = 0
	var records: int = 0
	var a: PackedInt32Array = PackedInt32Array()
	var b: PackedInt32Array = PackedInt32Array()
	var c: PackedInt32Array = PackedInt32Array()
	var ref: PackedInt32Array = PackedInt32Array()
	for t: int in ticks:
		rig.step()
		rig.lists(0, a, b, c)
		if refresh_on:
			assert_int(rr.pick(c_all, rig.tick, ref)).is_equal(3)
		else:
			ref.clear()
		var out: Array[PackedByteArray] = []
		var _k: int = rig.codec.encode(store, rig.tick, a, b, c, null, out, ref)
		for p: PackedByteArray in out:
			assert_int(p.size()).is_less_equal(Protocol.MAX_UNRELIABLE_BYTES)
			assert_int(dec.decode(p)).is_equal(SnapshotDecoder.Status.OK)
			if t >= 30:
				total += p.size()
		if t >= 30:
			for s: int in ref:
				records += 19 + (1 if rig.roster.team_of(s) == 0 else 0)
		store.ack(dec.store.complete_tick)
	assert_bool(dec.current().same_state(store.frame_at(rig.tick))).is_true()
	return Vector2i(total, records)


## Acceptance: refresh bytes at 700 C entities <= 1.8 KB/s (04 s4.3, R0 C1-15: 3 records of 19-20 B per tick, 1.74 KB/s).
## The stream also pays for the escape gaps and the section-C count byte. NET-54: the C-BLIP that used to follow every
## refresh FULL is skipped when the mirror implies the true blip, so the stream delta is itself <= 1.8 KB/s.
func test_refresh_bytes_at_700_c_entities_within_1_8_kb_per_second() -> void:
	var ticks: int = 330
	var with: Vector2i = _bytes_over(true, ticks)
	var without: Vector2i = _bytes_over(false, ticks)
	var window_s: float = float(ticks - 30) / 30.0
	var rec_kb_s: float = float(with.y) / window_s / 1000.0
	var stream_kb_s: float = float(with.x - without.x) / window_s / 1000.0
	print("NET-07 refresh at 700 C: records %.3f KB/s (%d B in %d ticks), stream delta %.3f KB/s (with %d B, without %d B)" % [
			rec_kb_s, with.y, ticks - 30, stream_kb_s, with.x, without.x])
	assert_int(without.y).is_equal(0)
	assert_float(rec_kb_s).is_less_equal(1.8)
	assert_float(rec_kb_s).is_greater(1.6)
	assert_float(stream_kb_s).is_less_equal(1.8)       # NET-54 acceptance: records + escapes + count byte
	# A refresh FULL also displaces C-BLIPs the run without refresh sends (the refreshed entry then implies its blip),
	# so the delta can sit just under the records; a refresh that silently dropped its FULLs would fall far below.
	assert_float(stream_kb_s).is_greater(0.9 * rec_kb_s)
