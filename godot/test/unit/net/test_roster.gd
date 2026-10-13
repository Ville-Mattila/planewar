extends GdUnitTestSuite
## NET-05: Roster model, ENTITY_META / ROSTER_REMOVE codecs (sizes against Protocol.CATALOGUE), held-record
## logic with the 1 s timeout (04 s3.1), determinism.


func _fill(r: Roster, n: int, tag_every: int = 0) -> PackedInt32Array:
	var slots: PackedInt32Array = PackedInt32Array()
	for i: int in n:
		var tag: String = "pilot%d" % i if tag_every > 0 and i % tag_every == 0 else ""
		var _ok: bool = r.add(i * 3, i + 1, 100 + i, i % 8, i % 2, tag)
		slots.append(i * 3)
	return slots


func test_add_remove_every_reason() -> void:
	var r: Roster = Roster.new()
	for reason: int in [Protocol.RosterRemoveReason.DEATH, Protocol.RosterRemoveReason.OUT_OF_VISION, Protocol.RosterRemoveReason.LEFT_INTEREST]:
		assert_bool(r.add(7, 1, 2, 3, 1, "x")).is_true()
		assert_bool(r.has(7)).is_true()
		assert_int(r.removal_reason_of(7)).is_equal(Roster.NEVER)
		assert_bool(r.remove(7, reason)).is_true()
		assert_bool(r.has(7)).is_false()
		assert_int(r.removal_reason_of(7)).is_equal(reason)
		assert_int(r.count()).is_equal(0)


func test_remove_rejects_bad_input() -> void:
	var r: Roster = Roster.new()
	assert_bool(r.remove(5, Protocol.RosterRemoveReason.DEATH)).is_false()
	var _ok: bool = r.add(5, 1, 1, 0, 0)
	assert_bool(r.remove(5, 3)).is_false()
	assert_bool(r.remove(5, -1)).is_false()
	assert_bool(r.remove(Roster.CAPACITY, 0)).is_false()
	assert_bool(r.has(5)).is_true()
	assert_bool(r.add(Roster.CAPACITY, 1, 1, 0, 0)).is_false()
	assert_bool(r.add(-1, 1, 1, 0, 0)).is_false()


func test_add_replaces_recycled_slot() -> void:
	var r: Roster = Roster.new()
	var _ok: bool = r.add(9, 1, 10, 2, 0, "a")
	_ok = r.add(9, 2, 11, 3, 1, "b")
	assert_int(r.count()).is_equal(1)
	assert_int(r.generation_of(9)).is_equal(2)
	assert_int(r.def_of(9)).is_equal(11)
	assert_str(r.tag_of(9)).is_equal("b")


func test_meta_roundtrip_and_sizes() -> void:
	var src: Roster = Roster.new()
	var slots: PackedInt32Array = _fill(src, 40, 4)
	var out: Array[PackedByteArray] = []
	var packets: int = RosterCodec.encode_meta(src, slots, out)
	var dst: Roster = Roster.new()
	var got: PackedInt32Array = PackedInt32Array()
	var total: int = 0
	for p: PackedByteArray in out:
		assert_int(p[0]).is_equal(Protocol.ENTITY_META)
		assert_int(p.size()).is_less_equal(Protocol.max_bytes(Protocol.ENTITY_META))
		var n: int = RosterCodec.decode_meta(p, dst, got)
		assert_int(n).is_equal(p[1])
		total += n
	assert_int(packets).is_equal(out.size())
	assert_int(total).is_equal(40)
	assert_int(dst.state_hash()).is_equal(src.state_hash())
	for s: int in slots:
		assert_int(dst.generation_of(s)).is_equal(src.generation_of(s))
		assert_str(dst.tag_of(s)).is_equal(src.tag_of(s))


func test_meta_entry_sizes() -> void:
	var r: Roster = Roster.new()
	var _ok: bool = r.add(1, 1, 1, 0, 0)
	_ok = r.add(2, 1, 1, 0, 0, "0123456789ABCDEFXXXX")   # clipped to 16 B
	var out: Array[PackedByteArray] = []
	var _n: int = RosterCodec.encode_meta(r, PackedInt32Array([1]), out)
	assert_int(out[0].size()).is_equal(2 + 9)                          # 04 s5.6: 9 B per tag-less entry
	out.clear()
	_n = RosterCodec.encode_meta(r, PackedInt32Array([2]), out)
	assert_int(out[0].size()).is_equal(2 + 9 + 16)
	assert_str(_decode_tag(out[0])).is_equal("0123456789ABCDEF")


func _decode_tag(p: PackedByteArray) -> String:
	var r: Roster = Roster.new()
	var s: PackedInt32Array = PackedInt32Array()
	var _n: int = RosterCodec.decode_meta(p, r, s)
	return r.tag_of(s[0])


func test_meta_splits_below_1200() -> void:
	var src: Roster = Roster.new()
	for i: int in 400:
		var _ok: bool = src.add(i, 1, 1, 0, 0, "0123456789ABCDEF")
	var slots: PackedInt32Array = PackedInt32Array()
	for i: int in 400:
		slots.append(i)
	var out: Array[PackedByteArray] = []
	assert_int(RosterCodec.encode_meta(src, slots, out)).is_greater(1)
	var dst: Roster = Roster.new()
	var got: PackedInt32Array = PackedInt32Array()
	for p: PackedByteArray in out:
		assert_int(p.size()).is_less_equal(Protocol.MAX_UNRELIABLE_BYTES)
		assert_int(RosterCodec.decode_meta(p, dst, got)).is_greater(0)
	assert_int(dst.count()).is_equal(400)


func test_meta_malformed_applies_nothing() -> void:
	var src: Roster = Roster.new()
	var slots: PackedInt32Array = _fill(src, 5, 1)
	var out: Array[PackedByteArray] = []
	var _n: int = RosterCodec.encode_meta(src, slots, out)
	var good: PackedByteArray = out[0]
	var dst: Roster = Roster.new()
	var got: PackedInt32Array = PackedInt32Array()
	assert_int(RosterCodec.decode_meta(good.slice(0, good.size() - 1), dst, got)).is_equal(-1)
	var extra: PackedByteArray = good.duplicate()
	extra.append(0)
	assert_int(RosterCodec.decode_meta(extra, dst, got)).is_equal(-1)
	var bad_slot: PackedByteArray = good.duplicate()
	bad_slot.encode_u16(2, Roster.CAPACITY)
	assert_int(RosterCodec.decode_meta(bad_slot, dst, got)).is_equal(-1)
	var wrong_id: PackedByteArray = good.duplicate()
	wrong_id[0] = Protocol.ROSTER_REMOVE
	assert_int(RosterCodec.decode_meta(wrong_id, dst, got)).is_equal(-1)
	assert_int(RosterCodec.decode_meta(PackedByteArray(), dst, got)).is_equal(-1)
	assert_int(dst.count()).is_equal(0)


func test_remove_roundtrip_with_reasons() -> void:
	var src: Roster = Roster.new()
	var slots: PackedInt32Array = _fill(src, 6)
	var reasons: PackedInt32Array = PackedInt32Array([0, 1, 2, 0, 1, 2])
	var dst: Roster = Roster.new()
	_fill(dst, 6)
	var out: Array[PackedByteArray] = []
	assert_int(RosterCodec.encode_remove(slots, reasons, out)).is_equal(1)
	assert_int(out[0].size()).is_equal(2 + 6 * 3)
	var got: PackedInt32Array = PackedInt32Array()
	assert_int(RosterCodec.decode_remove(out[0], dst, got)).is_equal(6)
	for i: int in 6:
		assert_bool(dst.has(slots[i])).is_false()
		assert_int(dst.removal_reason_of(slots[i])).is_equal(reasons[i])
	# A duplicate packet is harmless.
	got.clear()
	assert_int(RosterCodec.decode_remove(out[0], dst, got)).is_equal(6)
	assert_int(got.size()).is_equal(0)


func test_remove_encoder_skips_invalid_reason_and_splits() -> void:
	var slots: PackedInt32Array = PackedInt32Array([1, 2, 3])
	var reasons: PackedInt32Array = PackedInt32Array([0, 9, 2])
	var out: Array[PackedByteArray] = []
	var _n: int = RosterCodec.encode_remove(slots, reasons, out)
	assert_int(out[0][1]).is_equal(2)
	var big_s: PackedInt32Array = PackedInt32Array()
	var big_r: PackedInt32Array = PackedInt32Array()
	for i: int in 600:
		big_s.append(i)
		big_r.append(i % 3)
	out.clear()
	assert_int(RosterCodec.encode_remove(big_s, big_r, out)).is_equal(3)
	for p: PackedByteArray in out:
		assert_int(p.size()).is_less_equal(Protocol.max_bytes(Protocol.ROSTER_REMOVE))


func test_remove_malformed() -> void:
	var dst: Roster = Roster.new()
	_fill(dst, 3)
	var got: PackedInt32Array = PackedInt32Array()
	assert_int(RosterCodec.decode_remove(PackedByteArray([Protocol.ROSTER_REMOVE, 1, 0, 0, 3]), dst, got)).is_equal(-1)   # reason 3
	assert_int(RosterCodec.decode_remove(PackedByteArray([Protocol.ROSTER_REMOVE, 2, 0, 0, 0]), dst, got)).is_equal(-1)   # short
	assert_int(RosterCodec.decode_remove(PackedByteArray([Protocol.ROSTER_REMOVE, 1, 0, 0x05, 0]), dst, got)).is_equal(-1)   # slot 1280
	assert_int(dst.count()).is_equal(3)


func test_request_keyframe_size() -> void:
	var p: PackedByteArray = RosterCodec.encode_request_keyframe(Protocol.KeyframeRequest.ROSTER_GAP)
	assert_int(p.size()).is_equal(Protocol.max_bytes(Protocol.REQUEST_KEYFRAME))
	assert_int(p[0]).is_equal(Protocol.REQUEST_KEYFRAME)
	assert_int(p[1]).is_equal(Protocol.KeyframeRequest.ROSTER_GAP)


func test_determinism() -> void:
	var a: Roster = Roster.new()
	var b: Roster = Roster.new()
	var sa: PackedInt32Array = _fill(a, 50, 5)
	var sb: PackedInt32Array = _fill(b, 50, 5)
	assert_int(a.state_hash()).is_equal(b.state_hash())
	var oa: Array[PackedByteArray] = []
	var ob: Array[PackedByteArray] = []
	var _n: int = RosterCodec.encode_meta(a, sa, oa)
	_n = RosterCodec.encode_meta(b, sb, ob)
	assert_array(oa).is_equal(ob)
	var _ok: bool = b.remove(3, 0)
	assert_int(a.state_hash()).is_not_equal(b.state_hash())
