extends GdUnitTestSuite
## NET-05 interest_test roster cases: a snapshot that outruns its ENTITY_META is held then applied after the
## meta; a record still held after exactly 1 s (30 ticks) triggers one REQUEST_KEYFRAME(ROSTER_GAP); re-adds
## within the hold window; the loss/reorder path over a LocalTransport pair.

var _sync: RosterSync


func before_test() -> void:
	_sync = RosterSync.new()


func _meta_packet(slot: int, gen: int = 1) -> PackedByteArray:
	var r: Roster = Roster.new()
	var _ok: bool = r.add(slot, gen, 5, 1, 0, "")
	var out: Array[PackedByteArray] = []
	var _n: int = RosterCodec.encode_meta(r, PackedInt32Array([slot]), out)
	return out[0]


func test_held_snapshot_applied_after_meta() -> void:
	_sync.hold(100, 98, PackedByteArray([1, 2, 3]), PackedInt32Array([12]))
	assert_int(_sync.held_count()).is_equal(1)
	var ticks: PackedInt32Array = PackedInt32Array()
	var bytes: Array[PackedByteArray] = []
	assert_int(_sync.take_ready(ticks, bytes)).is_equal(0)
	assert_int(_sync.on_meta(_meta_packet(12))).is_equal(1)
	assert_int(_sync.take_ready(ticks, bytes)).is_equal(1)
	assert_int(ticks[0]).is_equal(98)
	assert_array(bytes[0]).is_equal(PackedByteArray([1, 2, 3]))
	assert_int(_sync.held_count()).is_equal(0)
	assert_int(_sync.poll(100 + RosterSync.HOLD_TICKS).size()).is_equal(0)
	assert_int(_sync.requests_sent).is_equal(0)


func test_held_waits_for_all_missing_indices() -> void:
	_sync.hold(10, 9, PackedByteArray([7]), PackedInt32Array([1, 2]))
	var ticks: PackedInt32Array = PackedInt32Array()
	var bytes: Array[PackedByteArray] = []
	var _n: int = _sync.on_meta(_meta_packet(1))
	assert_int(_sync.take_ready(ticks, bytes)).is_equal(0)
	_n = _sync.on_meta(_meta_packet(2))
	assert_int(_sync.take_ready(ticks, bytes)).is_equal(1)


func test_timeout_exactly_one_second() -> void:
	_sync.hold(100, 99, PackedByteArray([1]), PackedInt32Array([4]))
	for t: int in range(100, 100 + RosterSync.HOLD_TICKS):
		assert_int(_sync.poll(t).size()).is_equal(0)          # ticks 100..129: still held
		assert_int(_sync.held_count()).is_equal(1)
	var req: PackedByteArray = _sync.poll(100 + RosterSync.HOLD_TICKS)   # tick 130 = 1 s
	assert_int(RosterSync.HOLD_TICKS).is_equal(30)
	assert_array(req).is_equal(PackedByteArray([Protocol.REQUEST_KEYFRAME, Protocol.KeyframeRequest.ROSTER_GAP]))
	assert_int(_sync.held_count()).is_equal(0)
	assert_int(_sync.requests_sent).is_equal(1)


func test_timeout_requests_once_for_many_records() -> void:
	for i: int in 5:
		_sync.hold(100 + i, 100 + i, PackedByteArray([i]), PackedInt32Array([9]))
	var sent: int = 0
	for t: int in range(100, 400):
		if _sync.poll(t).size() > 0:
			sent += 1
	assert_int(sent).is_equal(1)
	assert_int(_sync.held_count()).is_equal(0)


func test_request_rate_limited_to_5s() -> void:
	_sync.hold(0, 0, PackedByteArray([1]), PackedInt32Array([9]))
	assert_int(_sync.poll(30).size()).is_equal(2)
	_sync.hold(40, 40, PackedByteArray([1]), PackedInt32Array([9]))
	assert_int(_sync.poll(70).size()).is_equal(0)          # expired, but < 150 ticks since the last request
	_sync.hold(170, 170, PackedByteArray([1]), PackedInt32Array([9]))
	assert_int(_sync.poll(200).size()).is_equal(2)
	assert_int(_sync.requests_sent).is_equal(2)


func test_readd_within_hold_window() -> void:
	# The entity is removed, its snapshot arrives held, the meta is re-sent at tick 29: applied, no request.
	var _n: int = _sync.on_meta(_meta_packet(20, 1))
	var rm: Array[PackedByteArray] = []
	var _m: int = RosterCodec.encode_remove(PackedInt32Array([20]), PackedInt32Array([Protocol.RosterRemoveReason.OUT_OF_VISION]), rm)
	assert_int(_sync.on_remove(rm[0])).is_equal(1)
	assert_bool(_sync.roster.has(20)).is_false()
	assert_int(_sync.roster.removal_reason_of(20)).is_equal(Protocol.RosterRemoveReason.OUT_OF_VISION)
	_sync.hold(200, 199, PackedByteArray([9]), PackedInt32Array([20]))
	assert_int(_sync.poll(229).size()).is_equal(0)
	_n = _sync.on_meta(_meta_packet(20, 2))
	assert_int(_sync.roster.generation_of(20)).is_equal(2)
	assert_int(_sync.roster.removal_reason_of(20)).is_equal(Roster.NEVER)
	var ticks: PackedInt32Array = PackedInt32Array()
	var bytes: Array[PackedByteArray] = []
	assert_int(_sync.take_ready(ticks, bytes)).is_equal(1)
	assert_int(_sync.poll(230).size()).is_equal(0)
	assert_int(_sync.requests_sent).is_equal(0)


func test_readd_after_expiry_is_not_resurrected() -> void:
	_sync.hold(0, 0, PackedByteArray([1]), PackedInt32Array([3]))
	assert_int(_sync.poll(30).size()).is_equal(2)
	var _n: int = _sync.on_meta(_meta_packet(3))
	var ticks: PackedInt32Array = PackedInt32Array()
	var bytes: Array[PackedByteArray] = []
	assert_int(_sync.take_ready(ticks, bytes)).is_equal(0)


func test_hold_cap_evicts_oldest_and_requests() -> void:
	for i: int in RosterSync.MAX_HELD + 1:
		_sync.hold(5, i, PackedByteArray([1]), PackedInt32Array([1]))
	assert_int(_sync.held_count()).is_equal(RosterSync.MAX_HELD)
	assert_int(_sync.poll(6).size()).is_equal(2)


func test_meta_after_snapshot_over_lossy_local_transport() -> void:
	# Real transport pair: the snapshot (channel 2, LAN) beats the meta (channel 3, delayed by a stall-free
	# TARGET link); the client holds, applies on meta arrival, never requests a keyframe.
	var server: LocalTransport = LocalTransport.new_server()
	var client: LocalTransport = server.connect_client()
	server.set_fault_model(FaultModel.preset(FaultModel.Preset.TARGET, 7))
	var conn: int = server.server_conn_of()
	if conn <= 0:
		conn = 1
	var src: Roster = Roster.new()
	var _ok: bool = src.add(33, 1, 12, 2, 1, "ace")
	var metas: Array[PackedByteArray] = []
	var _n: int = RosterCodec.encode_meta(src, PackedInt32Array([33]), metas)
	server.send(conn, Protocol.CH_SNAPSHOT, PackedByteArray([Protocol.SNAPSHOT, 1]), false)
	server.send(conn, Protocol.CH_EVENTS, metas[0], true)
	var held_at: int = -1
	var ready_ticks: PackedInt32Array = PackedInt32Array()
	var ready_bytes: Array[PackedByteArray] = []
	var sink: Array = []
	client.packet.connect(func(_c: int, ch: int, b: PackedByteArray) -> void: sink.append([ch, b]))
	for tick: int in 60:
		server.clock.advance_tick()
		server.poll()
		client.poll()
		while not sink.is_empty():
			var item: Array = sink.pop_front()
			if item[0] == Protocol.CH_SNAPSHOT:
				_sync.hold(tick, 1, item[1], PackedInt32Array([33]))
				held_at = tick
			else:
				var _m: int = _sync.on_meta(item[1])
		var _t: int = _sync.take_ready(ready_ticks, ready_bytes)
		assert_int(_sync.poll(tick).size()).is_equal(0)
	assert_int(_sync.requests_sent).is_equal(0)
	assert_bool(_sync.roster.has(33)).is_true()
	assert_str(_sync.roster.tag_of(33)).is_equal("ace")
	assert_int(ready_ticks.size() + (1 if held_at < 0 else 0)).is_equal(1)
