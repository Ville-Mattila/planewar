extends GdUnitTestSuite
## NET-61 (R0 B.31 A-152): the ground barrel elevation on the wire. One `barrel u8` = round((e - min) / (max - min) * 255)
## for an entity whose def has a barrel: the last byte of every FULL record (after flags and the own-team ai_tag; SNAPSHOT
## in any section and KEYFRAME), and the A-DELTA group of mask bit 6 (MASK_BARREL, after the FLAGS group). A client holds
## the value only from a section-A record: a B or C record clears it (one forced record when the entity leaves A), a
## KEYFRAME leaves it unknown, and the next A record re-sends it. An entity without a barrel pays zero bytes.
## PROTOCOL_VERSION 2.

const G: float = 6.0
const HZ: int = 30
const DEF_SHIP: int = 2
const DEF_CRAWLER: int = 4
const CRAWLER: int = 5                  # own team (0)
const ENEMY: int = 9                    # team 1 crawler
const DART: int = 12                    # team 1, no barrel
const LO: float = 0.0
const HI: float = PI / 4.0              # the Siege Crawler's 0-45 deg (ground_units.json, R0 B.31 A-151)
const KNOWN: int = BaselineFrame.BARREL_KNOWN

var _roster: Roster
var _codec: SnapshotCodec
var _frame: SnapshotFrame
var _tick: int = 0


func before_test() -> void:
	_tick = 0
	_roster = Roster.new()
	var _a: bool = _roster.add(CRAWLER, 1, DEF_CRAWLER, 0, 0)
	var _b: bool = _roster.add(ENEMY, 1, DEF_CRAWLER, 1, 1)
	var _c: bool = _roster.add(DART, 1, DEF_SHIP, 1, 1)
	_codec = SnapshotCodec.new(G, HZ)
	_frame = SnapshotFrame.new()
	_frame.resize(3)
	var slots: PackedInt32Array = PackedInt32Array([CRAWLER, ENEMY, DART])
	for r: int in 3:
		var p: Vector3 = Sphere.from_lat_lon(0.3, 1.1 + 0.001 * float(r), Sphere.PLANET_RADIUS + (0.0 if r < 2 else 400.0))
		_frame.set_entity(r, slots[r], p, Vector3.ZERO, Quaternion.IDENTITY, 1.0, 0, _roster.team_of(slots[r]), 3)


func _step(own_deg: float, enemy_deg: float) -> void:
	_tick += 1
	_frame.tick = _tick
	_frame.set_barrel(0, Codec.quantize_barrel(deg_to_rad(own_deg), LO, HI))
	_frame.set_barrel(1, Codec.quantize_barrel(deg_to_rad(enemy_deg), LO, HI))
	_codec.prepare_tick(_frame)


func _decoder(team: int) -> SnapshotDecoder:
	var d: SnapshotDecoder = SnapshotDecoder.new(G, HZ, team, _roster)
	var _r: int = d.barrel_def.resize(8)
	d.barrel_def[DEF_CRAWLER] = 1
	return d


## Encodes this tick for one client, decodes it, acks it and checks the mirror; returns the single packet.
func _send(store: BaselineStore, dec: SnapshotDecoder, a: Array, b: Array, c: Array) -> PackedByteArray:
	var out: Array[PackedByteArray] = []
	var _n: int = _codec.encode(store, _tick, PackedInt32Array(a), PackedInt32Array(b), PackedInt32Array(c), null, out)
	assert_int(out.size()).is_equal(1)
	assert_int(dec.decode(out[0])).is_equal(SnapshotDecoder.Status.OK)
	store.ack(dec.store.complete_tick)
	assert_bool(dec.current().same_state(store.frame_at(_tick))).is_true()
	return out[0]


func _byte(deg: float) -> int:
	return Codec.quantize_barrel(deg_to_rad(deg), LO, HI)


func test_protocol_version_is_bumped() -> void:
	assert_int(Protocol.PROTOCOL_VERSION).is_equal(2)
	assert_int(Codec.BARREL_BYTES).is_equal(1)
	assert_int(SnapshotCodec.MASK_BARREL).is_equal(0x40)
	assert_int(SnapshotMasks.MASK_BARREL).is_equal(0x40)
	assert_int(SnapshotCodec.delta_body_bytes(SnapshotCodec.MASK_BARREL, false, false)).is_equal(2)
	assert_int(SnapshotCodec.delta_body_bytes(SnapshotCodec.MASK_BARREL | SnapshotCodec.MASK_FLAGS, false, true)).is_equal(4)


func test_quantiser_round_trips_within_half_a_quantum() -> void:
	var half: float = (HI - LO) / 255.0 * 0.5
	for k: int in 4501:
		var e: float = deg_to_rad(float(k) * 0.01)
		var b: int = Codec.quantize_barrel(e, LO, HI)
		assert_bool(b >= 0 and b <= 255).is_true()
		assert_float(absf(Codec.dequantize_barrel(b, LO, HI) - e)).is_less_equal(half + 1e-9)
	assert_int(_byte(17.0)).is_equal(96)                       # round(17 / 45 * 255) = round(96.33)
	assert_int(_byte(45.0)).is_equal(255)
	assert_int(_byte(0.0)).is_equal(0)
	assert_int(Codec.quantize_barrel(-1.0, LO, HI)).is_equal(0)        # clamped
	assert_int(Codec.quantize_barrel(2.0, LO, HI)).is_equal(255)
	assert_float(Codec.dequantize_barrel(0x1FF, LO, HI)).is_equal(Codec.dequantize_barrel(255, LO, HI))
	var lo2: float = deg_to_rad(-30.0)
	var hi2: float = deg_to_rad(85.0)
	for k: int in 1151:
		var e2: float = deg_to_rad(-30.0 + float(k) * 0.1)
		assert_float(absf(Codec.dequantize_barrel(Codec.quantize_barrel(e2, lo2, hi2), lo2, hi2) - e2)).is_less_equal(
				(hi2 - lo2) / 510.0 + 1e-9)
	assert_int(Codec.quantize_barrel(0.3, 0.2, 0.2)).is_equal(0)       # fixed barrel: no span
	assert_float(Codec.dequantize_barrel(200, 0.2, 0.2)).is_equal(0.2)


func test_full_records_end_with_the_barrel_byte() -> void:
	_step(17.0, 30.0)
	var store: BaselineStore = BaselineStore.new(0)
	var dec: SnapshotDecoder = _decoder(0)
	var pkt: PackedByteArray = _send(store, dec, [CRAWLER, ENEMY, DART], [], [])
	# header 10, count 1; own crawler gap + 18 + ai_tag + barrel; enemy crawler gap + 18 + barrel; dart gap + 18
	assert_int(pkt.size()).is_equal(10 + 1 + 21 + 20 + 19)
	assert_int(pkt[12]).is_equal(SnapshotCodec.MASK_FULL)
	assert_int(pkt[30]).is_equal(3)                             # own-team ai_tag
	assert_int(pkt[31]).is_equal(_byte(17.0))
	assert_int(pkt[51]).is_equal(_byte(30.0))
	assert_int(dec.current().barrel[CRAWLER]).is_equal(KNOWN | _byte(17.0))
	assert_int(dec.current().barrel[ENEMY]).is_equal(KNOWN | _byte(30.0))
	assert_int(dec.current().barrel[DART]).is_equal(0)


func test_a_delta_sends_bit_6_only_when_the_byte_changes() -> void:
	var store: BaselineStore = BaselineStore.new(0)
	var dec: SnapshotDecoder = _decoder(0)
	_step(17.0, 30.0)
	var _p0: PackedByteArray = _send(store, dec, [CRAWLER, ENEMY, DART], [], [])
	_step(17.0, 30.0)
	assert_int(_send(store, dec, [CRAWLER, ENEMY, DART], [], []).size()).is_equal(SnapshotCodec.HEADER_BYTES)
	_step(18.0, 30.0)
	var pkt: PackedByteArray = _send(store, dec, [CRAWLER, ENEMY, DART], [], [])
	assert_int(pkt.size()).is_equal(10 + 1 + 3)                 # count, gap, mask 0x40, barrel
	assert_int(pkt[12]).is_equal(SnapshotCodec.MASK_BARREL)
	assert_int(pkt[13]).is_equal(_byte(18.0))
	assert_int(dec.current().barrel[CRAWLER]).is_equal(KNOWN | _byte(18.0))


func test_tier_b_and_c_records_clear_the_barrel_and_tier_a_resends_it() -> void:
	var store: BaselineStore = BaselineStore.new(0)
	var dec: SnapshotDecoder = _decoder(0)
	_step(17.0, 30.0)
	var _p0: PackedByteArray = _send(store, dec, [CRAWLER, ENEMY, DART], [], [])
	_step(17.0, 30.0)
	var pkt: PackedByteArray = _send(store, dec, [ENEMY, DART], [CRAWLER], [])
	assert_int(pkt.size()).is_equal(10 + 1 + 3)                 # one forced B-DELTA: gap, mask HP, hp
	assert_int(pkt[12]).is_equal(SnapshotCodec.MASK_HP)
	assert_int(dec.current().barrel[CRAWLER]).is_equal(0)
	_step(20.0, 30.0)
	assert_int(_send(store, dec, [ENEMY, DART], [CRAWLER], []).size()).is_equal(SnapshotCodec.HEADER_BYTES)
	_step(20.0, 30.0)
	pkt = _send(store, dec, [DART], [CRAWLER], [ENEMY])
	assert_int(pkt.size()).is_equal(10 + 1 + 4)                 # one forced C-BLIP for the enemy crawler
	assert_int(dec.current().barrel[ENEMY]).is_equal(0)
	_step(20.0, 30.0)
	pkt = _send(store, dec, [CRAWLER, ENEMY, DART], [], [])
	assert_int(pkt[11]).is_equal(CRAWLER)                       # back from B: gap, mask 0x40, barrel (same byte, re-sent)
	assert_int(pkt[12]).is_equal(SnapshotCodec.MASK_BARREL)
	assert_int(pkt[13]).is_equal(_byte(20.0))
	assert_int(pkt[15] & SnapshotCodec.MASK_BARREL).is_equal(SnapshotCodec.MASK_BARREL)   # the enemy, back from C (+ POS)
	assert_int(dec.current().barrel[CRAWLER]).is_equal(KNOWN | _byte(20.0))
	assert_int(dec.current().barrel[ENEMY]).is_equal(KNOWN | _byte(30.0))


func test_a_full_outside_section_a_carries_the_byte_but_leaves_it_unknown() -> void:
	_step(17.0, 30.0)
	var store: BaselineStore = BaselineStore.new(1)
	var dec: SnapshotDecoder = _decoder(1)
	var pkt: PackedByteArray = _send(store, dec, [DART], [ENEMY], [CRAWLER])
	# A: dart (own, + ai_tag); B: own enemy crawler, escaped gap (9 < 12), + ai_tag + barrel; C: crawler, escaped, + barrel
	assert_int(pkt.size()).is_equal(10 + (1 + 20) + (1 + 3 + 18 + 2) + (1 + 3 + 18 + 1))
	assert_int(dec.current().barrel[CRAWLER]).is_equal(0)
	assert_int(dec.current().barrel[ENEMY]).is_equal(0)


func test_decoder_rejects_the_barrel_bit_where_it_cannot_appear() -> void:
	var store: BaselineStore = BaselineStore.new(0)
	var dec: SnapshotDecoder = _decoder(0)
	_step(17.0, 30.0)
	var _p0: PackedByteArray = _send(store, dec, [CRAWLER, ENEMY, DART], [], [])
	var before: int = dec.current().state_hash()
	for bad: Array in [[Protocol.SNAP_HAS_A, DART], [Protocol.SNAP_HAS_B, CRAWLER], [Protocol.SNAP_HAS_B, ENEMY]]:
		var p: PackedByteArray = PackedByteArray([Protocol.SNAPSHOT, 0, 0, 0, 0, 0, 0, 0, 0, int(bad[0]) | Protocol.SNAP_LAST])
		p.encode_u32(1, _tick + 1)
		p.encode_u32(5, _tick)
		p.append_array(PackedByteArray([1, int(bad[1]), SnapshotCodec.MASK_BARREL, 7]))
		assert_int(dec.decode(p)).is_equal(SnapshotDecoder.Status.MALFORMED)
		assert_int(dec.current().state_hash()).is_equal(before)
	var ok: PackedByteArray = PackedByteArray([Protocol.SNAPSHOT, 0, 0, 0, 0, 0, 0, 0, 0, Protocol.SNAP_HAS_A | Protocol.SNAP_LAST])
	ok.encode_u32(1, _tick + 1)
	ok.encode_u32(5, _tick)
	ok.append_array(PackedByteArray([1, CRAWLER, SnapshotCodec.MASK_BARREL, 7]))
	assert_int(dec.decode(ok)).is_equal(SnapshotDecoder.Status.OK)
	assert_int(dec.current().barrel[CRAWLER]).is_equal(KNOWN | 7)


func test_keyframe_records_carry_the_byte_and_leave_it_unknown() -> void:
	_step(17.0, 30.0)
	var kc: KeyframeCodec = KeyframeCodec.new()
	var store: BaselineStore = BaselineStore.new(0)
	var msg: PackedByteArray = kc.encode(_codec, store, _tick, 1, Protocol.KeyframeScope.ALL, PackedInt32Array([CRAWLER, ENEMY, DART]))
	assert_int(msg.size()).is_equal(KeyframeCodec.size_for(3, 1, 0, 2))
	assert_int(msg.size()).is_equal(10 + 3 * 19 + 1 + 2)
	assert_int(msg[30]).is_equal(_byte(17.0))                   # gap 10, mask 11, flags 28, ai_tag 29, barrel 30
	var dec: SnapshotDecoder = _decoder(0)
	assert_int(kc.decode(msg, dec)).is_equal(KeyframeCodec.Status.OK)
	assert_bool(dec.current().same_state(store.frame_at(_tick))).is_true()
	assert_int(dec.current().barrel[CRAWLER]).is_equal(0)
	assert_bool(kc.reencode() == msg).is_true()
	assert_int(KeyframeCodec.RECORD_WORST_BYTES).is_equal(23)   # the A-134 spare byte is the barrel byte
	assert_int(KeyframeCodec.RECORDS_MAX).is_equal(2848)
	var cut: PackedByteArray = msg.slice(0, msg.size() - 1)
	assert_int(KeyframeCodec.new().decode(cut, _decoder(0))).is_equal(KeyframeCodec.Status.MALFORMED)


func test_byte_cache_path_writes_the_same_bytes() -> void:
	for cached: bool in [true, false]:
		before_test()
		_codec.cache_bytes = cached
		_step(17.0, 30.0)
		var pkt: PackedByteArray = _send(BaselineStore.new(0), _decoder(0), [CRAWLER, ENEMY, DART], [], [])
		assert_int(pkt[31]).is_equal(_byte(17.0))
		assert_int(pkt.size()).is_equal(10 + 1 + 21 + 20 + 19)
