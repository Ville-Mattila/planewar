extends GdUnitTestSuite
## NET-03: jitter buffer window, duplicates, lateness, redundancy, axis decay (R0 C2-08), LINK_BRIDGE hand-off.


func _mk(t: float, p: float) -> PilotInput:
	var i: PilotInput = PilotInput.new()
	i.thrust = t
	i.pitch = p
	i.yaw = -p
	i.roll = p
	i.buttons = PilotInput.BOOST | PilotInput.FIRE1 | PilotInput.FLIP
	return i


func _pkt(epoch: int, base: int, n: int, ack: int = 0) -> PackedByteArray:
	var arr: Array[PilotInput] = []
	for i: int in n:
		arr.append(_mk(0.8, 1.0))
	return InputCodec.encode(epoch, base, ack, arr, n)


func _buf() -> InputBuffer:
	var b: InputBuffer = InputBuffer.new()
	b.begin_epoch(4)
	return b


func test_window_boundaries_counted() -> void:
	var b: InputBuffer = _buf()
	# current 100: accepted 98..108
	assert_int(b.submit(_pkt(4, 97, 1), 100)).is_equal(0)
	assert_int(b.submit(_pkt(4, 98, 1), 100)).is_equal(1)
	assert_int(b.submit(_pkt(4, 108, 1), 100)).is_equal(1)
	assert_int(b.submit(_pkt(4, 109, 1), 100)).is_equal(0)
	assert_int(b.rejected_window).is_equal(2)
	assert_int(b.accepted).is_equal(2)
	assert_int(b.late).is_equal(1)           # tick 98 is behind 100


func test_duplicates_and_stale_epoch_and_malformed() -> void:
	var b: InputBuffer = _buf()
	assert_int(b.submit(_pkt(4, 100, 3), 100)).is_equal(3)
	assert_int(b.submit(_pkt(4, 100, 3), 100)).is_equal(0)
	assert_int(b.duplicates).is_equal(3)
	assert_int(b.submit(_pkt(5, 100, 1), 100)).is_equal(-1)
	assert_int(b.rejected_epoch).is_equal(1)
	var bad: PackedByteArray = _pkt(4, 100, 1)
	bad[InputCodec.HEADER_BYTES + 5] = 9
	assert_int(b.submit(bad, 100)).is_equal(-1)
	assert_int(b.rejected_malformed).is_equal(1)
	for i: int in 200:
		var _s: int = b.submit(bad, 100)
	assert_int(b.strikes).is_equal(2)         # 202 bad packets -> 2 strikes


func test_overlapping_redundancy_fills_gap() -> void:
	var b: InputBuffer = _buf()
	# packets for 100 and 103 lost; 101 covers 99..101, 104 covers 102..104 would too: send 101 and 104 only
	var _a: int = b.submit(_pkt(4, 99, 3), 100)
	var _c: int = b.submit(_pkt(4, 102, 3), 102)
	for t: int in range(100, 105):
		var _p: PilotInput = b.take(t)
		assert_bool(b.bridge).is_false()
		assert_int(b.miss_run).is_equal(0)


func test_decay_sequence_then_bridge_once() -> void:
	var b: InputBuffer = _buf()
	var _s: int = b.submit(_pkt(4, 100, 1), 100)
	var p: PilotInput = b.take(100)
	assert_bool(b.bridge).is_false()
	var thrust: float = p.thrust
	var pitch: float = p.pitch
	assert_float(pitch).is_equal(1.0)
	for k: int in range(1, 11):               # 10 missing ticks: reuse, decaying 50 %/tick
		p = b.take(100 + k)
		assert_float(p.pitch).is_equal(pitch * pow(0.5, k))
		assert_float(p.yaw).is_equal(-pitch * pow(0.5, k))
		assert_float(p.thrust).is_equal(thrust)
		assert_int(p.buttons).is_equal(PilotInput.BOOST)       # edge and fire buttons dropped
		assert_bool(b.bridge).is_false()
	assert_int(b.bridge_raised).is_equal(0)
	p = b.take(111)                           # the 11th missing tick
	assert_bool(b.bridge).is_true()
	assert_int(b.bridge_raised).is_equal(1)
	for k: int in range(12, 40):
		var _q: PilotInput = b.take(100 + k)
		assert_bool(b.bridge).is_true()
	assert_int(b.bridge_raised).is_equal(1)   # once
	var _s2: int = b.submit(_pkt(4, 141, 1), 141)
	var _q2: PilotInput = b.take(141)
	assert_bool(b.bridge).is_false()          # first fresh input clears it
	assert_int(b.miss_run).is_equal(0)
	for k: int in range(1, 12):
		var _q3: PilotInput = b.take(141 + k)
	assert_int(b.bridge_raised).is_equal(2)   # a second silence raises it again


func test_epoch_start_is_bridge_and_never_replays_previous_pilot() -> void:
	var b: InputBuffer = _buf()
	var _s: int = b.submit(_pkt(4, 100, 1), 100)
	var _p: PilotInput = b.take(100)
	b.begin_epoch(5)                          # hand-over: B takes over
	var n: PilotInput = b.take(101)
	assert_bool(b.bridge).is_true()
	assert_float(n.thrust).is_equal(0.0)      # A's input not replayed
	assert_float(n.pitch).is_equal(0.0)
	assert_int(b.bridge_raised).is_equal(0)   # hand-off bridge is not a LINK_WEAK alert
	assert_int(b.submit(_pkt(4, 102, 1), 102)).is_equal(-1)       # A's late packet dropped
	var _s2: int = b.submit(_pkt(5, 103, 1), 102)
	var f: PilotInput = b.take(103)
	assert_bool(b.bridge).is_false()
	assert_float(f.thrust).is_equal_approx(0.8, 1.0 / 255.0)


func test_ack_tick_tracks_newest_and_ring_wraps() -> void:
	var b: InputBuffer = _buf()
	var _a: int = b.submit(_pkt(4, 10, 1, 50), 10)
	var _c: int = b.submit(_pkt(4, 11, 1, 40), 10)
	assert_int(b.ack_tick).is_equal(50)
	for t: int in range(10, 400):
		var _s: int = b.submit(_pkt(4, t, 1), t)
		var _p: PilotInput = b.take(t)
		assert_bool(b.bridge).is_false()
	assert_int(b.rejected_window).is_equal(0)


func test_determinism_same_inputs_same_outputs() -> void:
	var out: PackedInt64Array = PackedInt64Array()
	for run: int in 2:
		var b: InputBuffer = _buf()
		var h: int = 17
		for t: int in range(100, 200):
			if t % 5 != 0 and not (t > 130 and t < 150):
				var _s: int = b.submit(_pkt(4, t, 1), t)
			var p: PilotInput = b.take(t)
			h = (h * 31 + int(p.pitch * 1000.0) + int(p.thrust * 255.0) + (1 if b.bridge else 0)) & 0x7FFFFFFF
		var _a: bool = out.append(h)
	assert_int(out[0]).is_equal(out[1])
