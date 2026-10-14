extends GdUnitTestSuite
## NET-06 malformed-input rejection: SnapshotDecoder.decode never errors and changes nothing unless it returns
## OK. Every truncation, a trailing byte, header faults, bad masks, gap/index faults, an invalid cell, an
## empty section, missing baselines, stale ticks, the A-36 packet-index rules (NET-48: HAS_PILOT off index 0,
## an index above the tick's LAST, CONTINUED on index 3; a repeated index is STALE; complete-tick ack), and
## 20,000 random mutations of a real A+B+C+pilot packet (the full 100,000-per-id harness is NET-23).

var _rig: SnapRig
var _store: BaselineStore
var _dec: SnapshotDecoder
var _pkt: PackedByteArray
var _hist: Array[PackedByteArray] = []


## Runs the rig to tick 30 (A, B and C scheduled) and keeps tick 30's packet undecoded in _pkt.
func before_test() -> void:
	_rig = SnapRig.new()
	_rig.build(Vector3i(10, 10, 10), Vector3i(8, 6, 6), 2, 13)
	_store = BaselineStore.new(0)
	_dec = _rig.new_decoder(0)
	var a: PackedInt32Array = PackedInt32Array()
	var b: PackedInt32Array = PackedInt32Array()
	var c: PackedInt32Array = PackedInt32Array()
	for t: int in 30:
		_rig.step()
		_rig.lists(0, a, b, c)
		var out: Array[PackedByteArray] = []
		var pilot: PilotBlock = PilotBlock.new() if _rig.tick == 30 else null
		var _n: int = _rig.codec.encode(_store, _rig.tick, a, b, c, pilot, out)
		if _rig.tick == 30:
			_pkt = out[0]
		else:
			_hist.append(out[0])
			var _s: int = _dec.decode(out[0])
			_store.ack(_dec.store.complete_tick)


## A decoder in the state before_test left `_dec` in (ticks 1-29 decoded), so an accepted mutation of tick 30
## does not turn every later copy into a repeat.
func _replayed() -> SnapshotDecoder:
	var d: SnapshotDecoder = _rig.new_decoder(0)
	for p: PackedByteArray in _hist:
		var _s: int = d.decode(p)
	return d


func _state() -> String:
	var cur: BaselineFrame = _dec.current()
	var h: int = cur.state_hash() if cur != null else 0
	return str(_dec.store.newest_tick) + ":" + str(_dec.store.complete_tick) + ":" + str(h) + ":" + str(_dec.pilot_tick)


func _expect(bytes: PackedByteArray, status: int) -> void:
	var before: String = _state()
	assert_int(_dec.decode(bytes)).is_equal(status)
	assert_str(_state()).is_equal(before)


func _header(tick: int, base: int, flags: int) -> PackedByteArray:
	var h: PackedByteArray = PackedByteArray([Protocol.SNAPSHOT, 0, 0, 0, 0, 0, 0, 0, 0, flags])
	h.encode_u32(1, tick)
	h.encode_u32(5, base)
	return h


func test_fixture_packet_has_every_section() -> void:
	var fl: int = _pkt[9]
	assert_int(fl & 0x0F).is_equal(Protocol.SNAP_HAS_A | Protocol.SNAP_HAS_B | Protocol.SNAP_HAS_C | Protocol.SNAP_HAS_PILOT)
	assert_int(_dec.decode(_pkt)).is_equal(SnapshotDecoder.Status.OK)
	assert_bool(_dec.current().same_state(_store.frame_at(30))).is_true()


func test_every_truncation_and_trailing_byte_rejected() -> void:
	for n: int in _pkt.size():
		_expect(_pkt.slice(0, n), SnapshotDecoder.Status.MALFORMED)
	var longer: PackedByteArray = _pkt.duplicate()
	var _a: bool = longer.push_back(0)
	_expect(longer, SnapshotDecoder.Status.MALFORMED)
	var huge: PackedByteArray = _pkt.duplicate()
	var _r: int = huge.resize(Protocol.MAX_UNRELIABLE_BYTES + 1)
	_expect(huge, SnapshotDecoder.Status.MALFORMED)
	_expect(PackedByteArray(), SnapshotDecoder.Status.MALFORMED)


func test_header_faults() -> void:
	var base: int = _pkt.decode_u32(5)
	# _pkt carries the pilot block, so index 1 or 2 in bits 6-7 is HAS_PILOT off index 0 (A-36).
	for mut: Array in [[0, 0x85], [9, _pkt[9] | 0x40], [9, _pkt[9] | 0x80], [9, _pkt[9] & ~Protocol.SNAP_LAST],
			[9, _pkt[9] | Protocol.SNAP_CONTINUED]]:
		var p: PackedByteArray = _pkt.duplicate()
		p[int(mut[0])] = int(mut[1])
		_expect(p, SnapshotDecoder.Status.MALFORMED)
	var t0: PackedByteArray = _pkt.duplicate()
	t0.encode_u32(1, 0)
	_expect(t0, SnapshotDecoder.Status.MALFORMED)
	var bad_base: PackedByteArray = _pkt.duplicate()
	bad_base.encode_u32(5, 30)                                         # base >= tick
	_expect(bad_base, SnapshotDecoder.Status.MALFORMED)
	var fresh: SnapshotDecoder = _rig.new_decoder(0)                   # never saw the baseline
	assert_int(fresh.decode(_pkt)).is_equal(SnapshotDecoder.Status.NO_BASELINE)
	assert_int(fresh.store.newest_tick).is_equal(0)
	assert_int(base).is_greater(0)
	assert_int(_dec.decode(_pkt)).is_equal(SnapshotDecoder.Status.OK)
	var old: PackedByteArray = _pkt.duplicate()
	old.encode_u32(1, 29)
	old.encode_u32(5, base - 1)
	_expect(old, SnapshotDecoder.Status.STALE)


func test_record_faults() -> void:
	# A FULL record for roster index 0 from scratch (base 0), then broken variants.
	var full: PackedByteArray = _header(31, 0, Protocol.SNAP_HAS_A | Protocol.SNAP_LAST)
	full.append_array(PackedByteArray([1, 0, SnapshotCodec.MASK_FULL]))
	var body: PackedByteArray = PackedByteArray()
	var _r: int = body.resize(SnapshotCodec.FULL_BODY_BYTES - 1 + 1)   # own team (team 0): + ai_tag
	var _w: int = Codec.write_pos(body, 0, Codec.pack_pos(7, 100, 100, 100))
	full.append_array(body)
	var ok_copy: PackedByteArray = full.duplicate()
	var bad_cell: PackedByteArray = full.duplicate()
	bad_cell.encode_u16(13, Codec.CELL_COUNT)
	_expect(bad_cell, SnapshotDecoder.Status.MALFORMED)
	var empty_section: PackedByteArray = _header(31, 0, Protocol.SNAP_HAS_A | Protocol.SNAP_LAST)
	var _e: bool = empty_section.push_back(0)
	_expect(empty_section, SnapshotDecoder.Status.MALFORMED)
	var idx: PackedByteArray = PackedByteArray([0, 0, 0])
	idx[0] = 0xFF
	idx.encode_u16(1, 2000)
	var esc2: PackedByteArray                                           # 0xFF + u16 index 2000 (>= 1,536) = _header(31, 0, Protocol.SNAP_HAS_A | Protocol.SNAP_LAST)
	esc2.append_array(PackedByteArray([1]))
	esc2.append_array(idx)
	esc2.append_array(PackedByteArray([SnapshotCodec.MASK_FULL]))
	esc2.append_array(body)
	_expect(esc2, SnapshotDecoder.Status.MALFORMED)
	var dup: PackedByteArray = _header(31, 0, Protocol.SNAP_HAS_A | Protocol.SNAP_LAST)
	dup.append_array(PackedByteArray([2, 0, SnapshotCodec.MASK_FULL]))
	dup.append_array(body)
	dup.append_array(PackedByteArray([0, SnapshotCodec.MASK_FULL]))   # gap 0 after the first record
	dup.append_array(body)
	_expect(dup, SnapshotDecoder.Status.MALFORMED)
	var delta_no_base: PackedByteArray = _header(31, 0, Protocol.SNAP_HAS_A | Protocol.SNAP_LAST)
	delta_no_base.append_array(PackedByteArray([1, 0, SnapshotCodec.MASK_HP, 9]))
	_expect(delta_no_base, SnapshotDecoder.Status.MALFORMED)
	assert_int(_dec.decode(ok_copy)).is_equal(SnapshotDecoder.Status.OK)


func test_bad_delta_masks() -> void:
	# _pkt's first A record is a DELTA (entities moved); one gap byte at 11, its mask at 12.
	assert_int(_pkt[11]).is_less(SnapshotCodec.GAP_ESCAPE)
	assert_int(_pkt[12] & 0x80).is_equal(0)
	for m: int in [_pkt[12] | SnapshotCodec.MASK_CELL_CHANGED, (_pkt[12] & ~3) | 3, 0]:
		var p: PackedByteArray = _pkt.duplicate()
		p[12] = m
		_expect(p, SnapshotDecoder.Status.MALFORMED)


func test_random_mutations_never_error() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 2026
	var counts: PackedInt32Array = PackedInt32Array([0, 0, 0, 0, 0])
	for i: int in 20000:
		var p: PackedByteArray = _pkt.duplicate()
		var kind: int = i % 4
		if kind == 0:
			for _k: int in rng.randi_range(1, 4):
				var at: int = rng.randi_range(9, p.size() - 1)          # header faults are covered above
				p[at] = p[at] ^ (1 << rng.randi_range(0, 7))
		elif kind == 1:
			p = p.slice(0, rng.randi_range(0, p.size()))
		elif kind == 2:
			p[rng.randi_range(SnapshotCodec.HEADER_BYTES, p.size() - 1)] = rng.randi_range(0, 255)
		else:
			var _ins: int = p.insert(rng.randi_range(0, p.size()), rng.randi_range(0, 255))
		var before: int = _dec.store.newest_tick
		var st: int = _dec.decode(p)
		assert_bool(st >= 0 and st <= SnapshotDecoder.Status.MISSING_ROSTER).is_true()
		counts[st] += 1
		if st != SnapshotDecoder.Status.OK:
			assert_int(_dec.store.newest_tick).is_equal(before)
		else:
			_dec = _replayed()                  # tick 30 index 0 again would be a repeat (STALE, A-36)
	# Value-byte flips still parse (OK); structural ones are rejected.
	assert_int(counts[SnapshotDecoder.Status.MALFORMED]).is_greater(1000)
	assert_int(counts[SnapshotDecoder.Status.OK]).is_greater(1000)
	print("MUTATIONS ok=%d malformed=%d stale=%d no_baseline=%d missing=%d" % [counts[0], counts[1], counts[2], counts[3], counts[4]])


## A one-record FULL packet for tick 31 (base 0): roster index `idx` (team 0, so + ai_tag), packet index `k`,
## `last` = LAST else CONTINUED, `pilot` appends a pilot block with HAS_PILOT.
func _part(idx: int, k: int, last: bool, pilot: bool) -> PackedByteArray:
	var fl: int = Protocol.SNAP_HAS_A | (k << 6) | (Protocol.SNAP_LAST if last else Protocol.SNAP_CONTINUED)
	fl |= Protocol.SNAP_HAS_PILOT if pilot else 0
	var p: PackedByteArray = _header(31, 0, fl)
	p.append_array(PackedByteArray([1, idx, SnapshotCodec.MASK_FULL]))
	var body: PackedByteArray = PackedByteArray()
	var _r: int = body.resize(SnapshotCodec.FULL_BODY_BYTES - 1 + 1)
	var _w: int = Codec.write_pos(body, 0, Codec.pack_pos(7, 100 + idx, 100, 100))
	p.append_array(body)
	if pilot:
		p.append_array(PilotBlock.new().to_bytes())
	return p


func test_packet_index_rules() -> void:
	var fresh: SnapshotDecoder = _rig.new_decoder(0)
	_dec = fresh
	_expect(_part(3, 1, false, true), SnapshotDecoder.Status.MALFORMED)       # HAS_PILOT on index 1
	_expect(_part(3, 3, false, false), SnapshotDecoder.Status.MALFORMED)      # CONTINUED on index 3: no index 4
	assert_int(_dec.decode(_part(6, 1, true, false))).is_equal(SnapshotDecoder.Status.OK)   # LAST = index 1
	assert_int(_dec.store.complete_tick).is_equal(0)                          # index 0 missing
	_expect(_part(9, 2, false, false), SnapshotDecoder.Status.MALFORMED)      # index 2 above LAST 1
	_expect(_part(9, 2, true, false), SnapshotDecoder.Status.MALFORMED)       # a second LAST
	_expect(_part(9, 0, true, false), SnapshotDecoder.Status.MALFORMED)       # LAST 0 below index 1
	_expect(_part(6, 1, true, false), SnapshotDecoder.Status.STALE)           # repeated index: nothing applied
	assert_int(_dec.decode(_part(3, 0, false, true))).is_equal(SnapshotDecoder.Status.OK)
	assert_int(_dec.store.complete_tick).is_equal(31)
	assert_int(_dec.pilot_tick).is_equal(31)
	assert_int(_dec.current().present[3] + _dec.current().present[6]).is_equal(2)


func test_index_above_seen_continued_is_malformed_and_lost_middle_never_completes() -> void:
	var fresh: SnapshotDecoder = _rig.new_decoder(0)
	_dec = fresh
	assert_int(_dec.decode(_part(3, 2, false, false))).is_equal(SnapshotDecoder.Status.OK)  # CONTINUED index 2
	_expect(_part(6, 1, true, false), SnapshotDecoder.Status.MALFORMED)       # index 2 above LAST 1
	assert_int(_dec.decode(_part(0, 0, false, true))).is_equal(SnapshotDecoder.Status.OK)
	assert_int(_dec.decode(_part(9, 3, true, false))).is_equal(SnapshotDecoder.Status.OK)   # LAST = index 3
	assert_int(_dec.store.complete_tick).is_equal(0)                          # index 1 lost: loss, not malformed
	assert_int(_dec.malformed).is_equal(1)
	assert_int(_dec.decode(_part(6, 1, false, false))).is_equal(SnapshotDecoder.Status.OK)  # late middle
	assert_int(_dec.store.complete_tick).is_equal(31)
