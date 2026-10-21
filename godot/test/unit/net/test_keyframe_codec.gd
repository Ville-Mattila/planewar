extends GdUnitTestSuite
## NET-07 KEYFRAME (0x86) codec contract (net/keyframe/MODULE.md, 04 s2.3, s3.1, s4.3): layout and size, ALL and
## ROSTER_REPAIR scopes, server mirror == client frame, delta snapshots after a keyframe, every malformed shape
## rejected with nothing applied, MISSING_ROSTER, keyframe_seq staleness, and a seeded mutation sweep in which every
## non-null decode re-encodes to the identical bytes (the NET-04 review standard). NET-23 owns the 100,000 fuzz.

var _rig: SnapRig
var _kc: KeyframeCodec
var _store: BaselineStore
var _dec: SnapshotDecoder


func before_test() -> void:
	_rig = SnapRig.new()
	_kc = KeyframeCodec.new()
	_store = BaselineStore.new(0)


func _scene(sizes: Vector3i, seed_value: int, ticks: int = 3) -> void:
	_rig.build(sizes, Vector3i(MathX.floori_div(sizes.x, 2), MathX.floori_div(sizes.y, 2), MathX.floori_div(sizes.z, 2)), 2, seed_value)
	for t: int in ticks:
		_rig.step()
	_dec = _rig.new_decoder(0)


func _all() -> PackedInt32Array:
	var r: PackedInt32Array = PackedInt32Array()
	for i: int in _rig.frame.count:
		r.append(i)
	return r


func _own(i: int) -> bool:
	return _rig.roster.team_of(i) == 0


## Byte offset of record k of a dense message of the whole scene (gap 1 each, own team +1).
func _rec_at(k: int) -> int:
	var at: int = KeyframeCodec.HEADER_BYTES
	for j: int in k:
		at += 19 + (1 if _own(j) else 0)
	return at


func _encode(scope: int = Protocol.KeyframeScope.ALL, seq: int = 1, idx: PackedInt32Array = PackedInt32Array()) -> PackedByteArray:
	return _kc.encode(_rig.codec, _store, _rig.tick, seq, scope, _all() if idx.is_empty() else idx)


func test_layout_and_size_of_a_dense_all_keyframe() -> void:
	_scene(Vector3i(10, 10, 10), 11)
	var msg: PackedByteArray = _encode(Protocol.KeyframeScope.ALL, 7)
	var own: int = 0
	for i: int in 30:
		own += 1 if _own(i) else 0
	assert_int(msg.size()).is_equal(KeyframeCodec.size_for(30, own, 0))
	assert_int(msg.size()).is_equal(10 + 30 * 19 + own)
	assert_int(msg[0]).is_equal(Protocol.KEYFRAME)
	assert_int(msg.decode_u16(1)).is_equal(7)
	assert_int(msg.decode_u32(3)).is_equal(_rig.tick)
	assert_int(msg[7]).is_equal(Protocol.KeyframeScope.ALL)
	assert_int(msg.decode_u16(8)).is_equal(30)
	assert_int(msg[10]).is_equal(0)                      # first record is index 0: gap 0
	assert_int(msg[11]).is_equal(SnapshotCodec.MASK_FULL)
	assert_int(msg[10 + 19 + 1]).is_equal(1)             # record 1 (own team 0 + 1 B ai_tag precedes it): gap 1
	assert_int(KeyframeCodec.seq_of(msg)).is_equal(7)
	assert_int(KeyframeCodec.tick_of(msg)).is_equal(_rig.tick)
	assert_int(KeyframeCodec.scope_of(msg)).is_equal(0)
	assert_int(KeyframeCodec.seq_of(PackedByteArray([0x86, 1]))).is_equal(-1)
	assert_int(msg.size()).is_less_equal(Protocol.max_bytes(Protocol.KEYFRAME))


func test_round_trip_all_server_mirror_equals_client_frame() -> void:
	_scene(Vector3i(10, 10, 10), 12)
	var msg: PackedByteArray = _encode()
	assert_int(_kc.decode(msg, _dec)).is_equal(KeyframeCodec.Status.OK)
	var cur: BaselineFrame = _dec.current()
	assert_object(cur).is_not_null()
	assert_int(cur.tick).is_equal(_rig.tick)
	assert_bool(cur.same_state(_store.frame_at(_rig.tick))).is_true()
	assert_int(_dec.store.complete_tick).is_equal(_rig.tick)
	assert_int(_dec.store.newest_tick).is_equal(_rig.tick)
	assert_int(_kc.count).is_equal(30)
	assert_int(_kc.seq).is_equal(1)
	for i: int in 30:
		assert_int(cur.present[i]).is_equal(1)
		assert_int(Codec.pos_cell(cur.pos[i])).is_equal(Codec.pos_cell(Codec.quantize_pos(_rig.frame.pos[i])))
	assert_int(_store.acked_tick).is_equal(0)            # nothing is acked until the client says so
	assert_bool(_store.frame_at(_rig.tick).usable).is_true()


func test_encode_resets_the_server_mirror() -> void:
	_scene(Vector3i(10, 10, 10), 13, 6)
	var out: Array[PackedByteArray] = []
	var a: PackedInt32Array = _all()
	var _n: int = _rig.codec.encode(_store, _rig.tick, a, PackedInt32Array(), PackedInt32Array(), null, out)
	_store.ack(_rig.tick)
	assert_int(_store.acked_tick).is_equal(_rig.tick)
	_rig.step()
	var msg: PackedByteArray = _encode()
	assert_int(msg.size()).is_greater(0)
	assert_int(_store.acked_tick).is_equal(0)
	assert_int(_store.base_for(_rig.tick + 1)).is_equal(0)
	assert_object(_store.frame_at(_rig.tick - 1)).is_null()


func test_snapshots_after_an_acked_keyframe_keep_baselines_identical() -> void:
	_scene(Vector3i(10, 10, 10), 14)
	assert_int(_kc.decode(_encode(), _dec)).is_equal(KeyframeCodec.Status.OK)
	_store.ack(_dec.store.complete_tick)                 # the client acks the keyframe tick
	assert_int(_store.base_for(_rig.tick + 1)).is_equal(_rig.tick)
	var a: PackedInt32Array = PackedInt32Array()
	var b: PackedInt32Array = PackedInt32Array()
	var c: PackedInt32Array = PackedInt32Array()
	for t: int in 60:
		_rig.step()
		_rig.lists(0, a, b, c)
		var out: Array[PackedByteArray] = []
		var _n: int = _rig.codec.encode(_store, _rig.tick, a, b, c, null, out)
		for p: PackedByteArray in out:
			assert_int(_dec.decode(p)).is_equal(SnapshotDecoder.Status.OK)
		_store.ack(_dec.store.complete_tick)
		assert_bool(_dec.current().same_state(_store.frame_at(_rig.tick))).is_true()
	assert_int(_rig.codec.n_delta).is_greater(100)


func test_roster_repair_subset_with_escape_gaps() -> void:
	_scene(Vector3i(300, 300, 300), 15, 2)
	var idx: PackedInt32Array = PackedInt32Array([0, 2, 500, 899])
	var msg: PackedByteArray = _encode(Protocol.KeyframeScope.ROSTER_REPAIR, 3, idx)
	var own: int = 0
	for i: int in idx:
		own += 1 if _own(i) else 0
	assert_int(msg.size()).is_equal(KeyframeCodec.size_for(4, own, 1))   # 500 - 2 = 498 needs the 0xFF escape
	assert_int(KeyframeCodec.scope_of(msg)).is_equal(Protocol.KeyframeScope.ROSTER_REPAIR)
	assert_int(_kc.decode(msg, _dec)).is_equal(KeyframeCodec.Status.OK)
	assert_int(_kc.scope).is_equal(Protocol.KeyframeScope.ROSTER_REPAIR)
	var cur: BaselineFrame = _dec.current()
	for i: int in 900:
		assert_int(cur.present[i]).is_equal(1 if i in idx else 0)
	assert_bool(cur.same_state(_store.frame_at(_rig.tick))).is_true()


func test_unsorted_and_duplicate_indices_are_normalised() -> void:
	_scene(Vector3i(10, 10, 10), 16)
	var msg: PackedByteArray = _encode(Protocol.KeyframeScope.ALL, 1, PackedInt32Array([9, 4, 4, 0, 29, 9]))
	assert_int(_kc.decode(msg, _dec)).is_equal(KeyframeCodec.Status.OK)
	assert_int(_kc.count).is_equal(4)


func test_encode_refuses_unprepared_tick_bad_scope_bad_seq_and_out_of_range_indices() -> void:
	_scene(Vector3i(10, 10, 10), 17)
	assert_int(_kc.encode(_rig.codec, _store, _rig.tick + 1, 1, 0, _all()).size()).is_equal(0)
	assert_int(_kc.encode(_rig.codec, _store, _rig.tick, 1, 2, _all()).size()).is_equal(0)
	assert_int(_kc.encode(_rig.codec, _store, _rig.tick, 1, -1, _all()).size()).is_equal(0)
	assert_int(_kc.encode(_rig.codec, _store, _rig.tick, 65536, 0, _all()).size()).is_equal(0)
	assert_int(_kc.encode(_rig.codec, _store, _rig.tick, -1, 0, _all()).size()).is_equal(0)
	var msg: PackedByteArray = _encode(0, 1, PackedInt32Array([-5, 3, 99999, 5000]))   # out of range / unknown entities skipped
	assert_int(msg.decode_u16(8)).is_equal(1)
	assert_int(_encode(0, 1, PackedInt32Array([-5, 99999])).decode_u16(8)).is_equal(0)  # an empty keyframe is legal


func test_empty_keyframe_resets_the_client() -> void:
	_scene(Vector3i(10, 10, 10), 18)
	var msg: PackedByteArray = _kc.encode(_rig.codec, _store, _rig.tick, 1, 0, PackedInt32Array([99999]))
	assert_int(msg.size()).is_equal(KeyframeCodec.HEADER_BYTES)
	assert_int(_kc.decode(msg, _dec)).is_equal(KeyframeCodec.Status.OK)
	assert_int(_dec.current().present.count(1)).is_equal(0)


func test_malformed_messages_are_rejected_and_change_nothing() -> void:
	_scene(Vector3i(10, 10, 10), 19)
	var good: PackedByteArray = _encode()
	assert_int(_kc.decode(good, _dec)).is_equal(KeyframeCodec.Status.OK)
	var hash0: int = _dec.current().state_hash()
	var newest0: int = _dec.store.newest_tick
	var bad: Array[PackedByteArray] = []
	for n: int in good.size():                             # every truncation
		bad.append(good.slice(0, n))
	bad.append(good + PackedByteArray([0]))                # trailing byte
	var m: PackedByteArray = good.duplicate()
	m[0] = Protocol.SNAPSHOT
	bad.append(m)                                          # wrong id
	m = good.duplicate()
	m[7] = 2
	bad.append(m)                                          # scope 2
	m = good.duplicate()
	m[7] = 255
	bad.append(m)
	m = good.duplicate()
	m.encode_u32(3, 0)
	bad.append(m)                                          # tick 0
	m = good.duplicate()
	m.encode_u16(8, 29)
	bad.append(m)                                          # count below the records
	m = good.duplicate()
	m.encode_u16(8, 31)
	bad.append(m)                                          # count above the records
	m = good.duplicate()
	m.encode_u16(8, 1537)
	bad.append(m)                                          # count above the roster
	m = good.duplicate()
	m.encode_u16(8, 65535)
	bad.append(m)
	m = good.duplicate()
	m[_rec_at(3)] = 0                                      # gap 0 in the middle
	bad.append(m)
	m = good.duplicate()
	m[_rec_at(3)] = SnapshotCodec.GAP_ESCAPE               # escape where a u8 gap fits (not canonical)
	bad.append(m)
	m = good.duplicate()
	m[_rec_at(1) + 1] = 0x7F                               # mask is not FULL
	bad.append(m)
	m = good.duplicate()
	m[_rec_at(1) + 1] = 0x00
	bad.append(m)
	m = good.duplicate()
	m.encode_u16(_rec_at(2) + 2, 400)                      # cell >= 384
	bad.append(m)
	bad.append(_hand([[5, -1], [-1, 5]]))                  # equal index through an escape
	bad.append(_hand([[5, -1], [-1, 3]]))                  # descending
	bad.append(_hand([[-1, 1536]]))                        # index at the roster capacity
	bad.append(_hand([[-1, 65535]]))
	for b: PackedByteArray in bad:
		var before: int = _kc.malformed
		_kc.forget()
		assert_int(_kc.decode(b, _dec)).is_equal(KeyframeCodec.Status.MALFORMED)
		assert_int(_kc.malformed).is_equal(before + 1)
		assert_int(_dec.store.newest_tick).is_equal(newest0)
		assert_int(_dec.current().state_hash()).is_equal(hash0)


## A hand-built message of FULL records: each entry [gap, escape_index]; escape_index >= 0 writes 0xFF + u16.
func _hand(recs: Array) -> PackedByteArray:
	var b: PackedByteArray = PackedByteArray([Protocol.KEYFRAME, 1, 0, 9, 0, 0, 0, 0, recs.size(), 0])
	for r: Array in recs:
		if r[1] >= 0:
			b.append(SnapshotCodec.GAP_ESCAPE)
			b.append(r[1] & 0xFF)
			b.append(r[1] >> 8)
		else:
			b.append(r[0])
		b.append(SnapshotCodec.MASK_FULL)
		var body: PackedByteArray = PackedByteArray()
		var _r: int = body.resize(17)
		body.encode_s64(0, Codec.quantize_pos(Vector3(0.0, 6100.0, 0.0)))
		b.append_array(body)
	return b


func test_hand_built_message_is_the_reference_layout() -> void:
	_scene(Vector3i(10, 10, 10), 26)
	var ok: PackedByteArray = _hand([[5, -1], [-1, 300]])   # gap 5 -> index 5, escape -> index 300 (not in this roster)
	var wrong_team: SnapshotDecoder = SnapshotDecoder.new(SnapRig.G, SnapRig.HZ, 2, _rig.roster)
	assert_int(_kc.decode(_hand([[5, -1]]), wrong_team)).is_equal(KeyframeCodec.Status.MALFORMED)   # index 5 is team 2: own there, so its ai_tag byte is missing
	assert_int(_kc.decode(ok, _dec)).is_equal(KeyframeCodec.Status.MISSING_ROSTER)


func test_missing_roster_entry_reports_indices_and_applies_nothing() -> void:
	_scene(Vector3i(10, 10, 10), 20)
	var msg: PackedByteArray = _encode()
	var short_dec: SnapshotDecoder = SnapshotDecoder.new(SnapRig.G, SnapRig.HZ, 0, _rig.roster_without(7))
	assert_int(_kc.decode(msg, short_dec)).is_equal(KeyframeCodec.Status.MISSING_ROSTER)
	assert_array(_kc.missing).is_equal(PackedInt32Array([7]))
	assert_int(short_dec.store.newest_tick).is_equal(0)
	assert_object(short_dec.current()).is_null()
	short_dec.roster.add(7, 1, 2, 1, 1)                    # the META arrives; the held message now applies
	assert_int(_kc.decode(msg, short_dec)).is_equal(KeyframeCodec.Status.OK)
	assert_int(_kc.missing.size()).is_equal(0)


func test_keyframe_seq_must_be_newer_with_u16_wrap() -> void:
	_scene(Vector3i(10, 10, 10), 21)
	assert_int(_kc.decode(_encode(0, 65534), _dec)).is_equal(KeyframeCodec.Status.OK)
	assert_int(_kc.decode(_encode(0, 65534), _dec)).is_equal(KeyframeCodec.Status.STALE)    # repeat
	assert_int(_kc.decode(_encode(0, 65000), _dec)).is_equal(KeyframeCodec.Status.STALE)    # older
	assert_int(_kc.decode(_encode(0, 65535), _dec)).is_equal(KeyframeCodec.Status.OK)
	assert_int(_kc.decode(_encode(0, 0), _dec)).is_equal(KeyframeCodec.Status.OK)           # wraps to newer
	assert_int(_kc.decode(_encode(0, 5), _dec)).is_equal(KeyframeCodec.Status.OK)
	_kc.forget()
	assert_int(_kc.decode(_encode(0, 5), _dec)).is_equal(KeyframeCodec.Status.OK)          # reconnect: anything goes
	assert_int(_kc.decode(_encode(0, 5), _dec)).is_equal(KeyframeCodec.Status.STALE)


func test_stale_keyframe_changes_nothing() -> void:
	_scene(Vector3i(10, 10, 10), 22)
	assert_int(_kc.decode(_encode(0, 9), _dec)).is_equal(KeyframeCodec.Status.OK)
	var h: int = _dec.current().state_hash()
	_rig.step()
	assert_int(_kc.decode(_encode(0, 8), _dec)).is_equal(KeyframeCodec.Status.STALE)
	assert_int(_dec.current().state_hash()).is_equal(h)
	assert_int(_dec.store.newest_tick).is_equal(_rig.tick - 1)


func test_a_keyframe_older_than_decoded_snapshots_is_still_applied() -> void:
	# Channel 3 may be slower than channel 2: snapshots newer than the keyframe tick can arrive first.
	_scene(Vector3i(10, 10, 10), 23)
	var msg: PackedByteArray = _encode(0, 2)
	var kf_tick: int = _rig.tick
	var a: PackedInt32Array = _all()
	for t: int in 4:
		_rig.step()
		var out: Array[PackedByteArray] = []
		var _n: int = _rig.codec.encode(BaselineStore.new(0), _rig.tick, a, PackedInt32Array(), PackedInt32Array(), null, out)
		assert_int(_dec.decode(out[0])).is_equal(SnapshotDecoder.Status.OK)
	assert_int(_dec.store.newest_tick).is_equal(kf_tick + 4)
	assert_int(_kc.decode(msg, _dec)).is_equal(KeyframeCodec.Status.OK)
	assert_int(_dec.store.newest_tick).is_equal(kf_tick)
	assert_int(_dec.store.complete_tick).is_equal(kf_tick)


func _mutate(rng: RandomNumberGenerator, src: PackedByteArray) -> PackedByteArray:
	var b: PackedByteArray = src.duplicate()
	var rounds: int = rng.randi_range(1, 3)
	for _r: int in rounds:
		match rng.randi_range(0, 5):
			0:
				b[rng.randi_range(0, b.size() - 1)] = rng.randi() & 0xFF
			1:
				var at: int = rng.randi_range(0, b.size() - 1)
				b[at] = b[at] ^ (1 << rng.randi_range(0, 7))
			2:
				b = b.slice(0, rng.randi_range(0, b.size()))
			3:
				b.append(rng.randi() & 0xFF)
			4:
				if b.size() > 12:
					var at2: int = rng.randi_range(KeyframeCodec.HEADER_BYTES - 1, b.size() - 1)
					b.remove_at(at2)
			_:
				b[rng.randi_range(0, mini(b.size() - 1, 11))] = rng.randi() & 0xFF   # header-biased
		if b.is_empty():
			b.append(0)
	return b


## Seeded sweep: byte flips, truncations, insertions and removals of valid ALL and sparse REPAIR messages. Never throws; a
## non-OK result changes nothing; every OK re-encodes to the identical bytes and that re-decodes to the same frame.
func test_mutation_sweep_reencodes_equal() -> void:
	_scene(Vector3i(300, 300, 300), 24, 2)
	var seeds: Array[PackedByteArray] = [
		_encode(0, 1, PackedInt32Array([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11])),
		_encode(1, 2, PackedInt32Array([0, 2, 500, 899, 900 - 1])),
		_encode(0, 3, PackedInt32Array([5, 6, 300, 301, 302, 700])),
	]
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 20261021
	var other: SnapshotDecoder = _rig.new_decoder(0)
	var accepted: int = 0
	var rejected: int = 0
	for src: PackedByteArray in seeds:
		for i: int in 7000:
			var m: PackedByteArray = _mutate(rng, src)
			_kc.forget()
			var newest0: int = other.store.newest_tick
			var applied0: int = other.store.complete_tick
			var st: int = _kc.decode(m, other)
			if st != KeyframeCodec.Status.OK:
				rejected += 1
				assert_int(other.store.newest_tick).is_equal(newest0)
				assert_int(other.store.complete_tick).is_equal(applied0)
				continue
			accepted += 1
			var again: PackedByteArray = _kc.reencode()
			assert_array(again).is_equal(m)
			var h: int = other.current().state_hash()
			_kc.forget()
			assert_int(_kc.decode(again, other)).is_equal(KeyframeCodec.Status.OK)
			assert_int(other.current().state_hash()).is_equal(h)
	assert_int(accepted).is_greater(200)
	assert_int(rejected).is_greater(5000)


func test_random_bytes_never_throw() -> void:
	_scene(Vector3i(10, 10, 10), 25)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 5
	for i: int in 5000:
		var b: PackedByteArray = PackedByteArray()
		var _r: int = b.resize(rng.randi_range(0, 400))
		for j: int in b.size():
			b[j] = rng.randi() & 0xFF
		if b.size() >= 10 and (i & 1) == 0:
			b[0] = Protocol.KEYFRAME
			b[7] = rng.randi_range(0, 1)
			b.encode_u16(8, rng.randi_range(0, 30))
		_kc.forget()
		var _s: int = _kc.decode(b, _dec)
		var _q: int = KeyframeCodec.seq_of(b) + KeyframeCodec.tick_of(b) + KeyframeCodec.scope_of(b)
	assert_int(_kc.decode(PackedByteArray(), _dec)).is_equal(KeyframeCodec.Status.MALFORMED)
