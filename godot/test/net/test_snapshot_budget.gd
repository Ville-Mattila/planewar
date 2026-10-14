extends GdUnitTestSuite
## NET-06 packet budget and system properties: no packet over 1,200 B with splitting (FULL storm after a
## teleport, 255-record sections), bandwidth at 400 entities against 04 s4.6 (<= 30 KB/s per client at 100 and
## 167 ms ack delay incl. 38 B/packet transport overhead), determinism, one prepare_tick per tick for 8 clients,
## and the held-record path when ENTITY_META is late (NET-05 RosterSync). NET-48 (A-36): packet index in flags
## bits 6-7, a split tick is a baseline once acked, a tick missing its middle packet is never acked.

const OVERHEAD: int = 38                    # UDP 8 + IPv4 20 + ENet 10 (04 s4.6)

var _rig: SnapRig
var _a: PackedInt32Array = PackedInt32Array()
var _b: PackedInt32Array = PackedInt32Array()
var _c: PackedInt32Array = PackedInt32Array()


func before_test() -> void:
	_rig = SnapRig.new()


func _pilot() -> PilotBlock:
	var p: PilotBlock = PilotBlock.new()
	p.fuel_ds = 1500 - _rig.tick % 100
	p.ammo = 300
	p.hull = 100
	return p


## Encodes the current tick for one client, decodes every packet, acks immediately. Returns the packets.
func _round(store: BaselineStore, dec: SnapshotDecoder, k: int, pilot: PilotBlock) -> Array[PackedByteArray]:
	_rig.lists(k, _a, _b, _c)
	var out: Array[PackedByteArray] = []
	var _n: int = _rig.codec.encode(store, _rig.tick, _a, _b, _c, pilot, out)
	for p: PackedByteArray in out:
		assert_int(p.size()).is_less_equal(Protocol.MAX_UNRELIABLE_BYTES)
		assert_int(dec.decode(p)).is_equal(SnapshotDecoder.Status.OK)
	store.ack(dec.store.complete_tick)
	return out


func test_full_storm_splits_under_1200_and_converges() -> void:
	_rig.build(Vector3i(40, 200, 160), Vector3i(24, 70, 60), 4, 3)
	_rig.codec.max_packets = SnapshotCodec.MAX_PACKETS_PER_TICK
	var store: BaselineStore = BaselineStore.new(0)
	var dec: SnapshotDecoder = _rig.new_decoder(0)
	for t: int in 59:
		_rig.step()
		var _o: Array[PackedByteArray] = _round(store, dec, 0, _pilot())
	_rig.teleport(0.6)
	_rig.step()                                        # tick 60: A, B and C all scheduled
	var full0: int = _rig.codec.n_full
	var out: Array[PackedByteArray] = _round(store, dec, 0, _pilot())
	assert_int(out.size()).is_equal(SnapshotCodec.MAX_PACKETS_PER_TICK)
	assert_int(_rig.codec.deferred).is_greater(0)
	for i: int in out.size():
		var fl: int = out[i][9]
		var last: bool = i == out.size() - 1
		assert_bool((fl & Protocol.SNAP_LAST) != 0).is_equal(last)
		assert_bool((fl & Protocol.SNAP_CONTINUED) != 0).is_equal(not last)
		assert_bool((fl & Protocol.SNAP_HAS_PILOT) != 0).is_equal(i == 0)
		assert_int(fl >> 6).is_equal(i)                                  # A-36 packet index
		assert_int(out[i].decode_u32(1)).is_equal(60)
	assert_int(_rig.codec.n_full - full0).is_greater(200)
	assert_bool(store.frame_at(60).usable).is_true()
	assert_int(store.acked_tick).is_equal(60)                          # a complete split tick is a baseline
	# The deferred FULLs follow (C only on its 1-in-15 ticks); afterwards the client holds every entity.
	for t: int in 240:
		_rig.step()
		var _o: Array[PackedByteArray] = _round(store, dec, 0, _pilot())
	var cur: BaselineFrame = dec.current()
	assert_bool(cur.same_state(store.frame_at(_rig.tick))).is_true()
	for i: int in _rig.frame.count:
		assert_int(Codec.pos_cell(cur.pos[i])).is_equal(Codec.pos_cell(Codec.quantize_pos(_rig.frame.pos[i])))


## A-36 acceptance: tick 60 goes out as 4 packets, index 1 is lost. The client never completes (so never acks)
## tick 60, the server keeps encoding against tick 59, and the next complete tick becomes the baseline.
func test_lost_middle_packet_never_acked_next_complete_tick_is_baseline() -> void:
	_rig.build(Vector3i(40, 200, 160), Vector3i(24, 70, 60), 4, 3)
	var store: BaselineStore = BaselineStore.new(0)
	var dec: SnapshotDecoder = _rig.new_decoder(0)
	for t: int in 59:
		_rig.step()
		var _o: Array[PackedByteArray] = _round(store, dec, 0, _pilot())
	assert_int(store.acked_tick).is_equal(59)
	_rig.teleport(0.6)
	_rig.step()
	_rig.lists(0, _a, _b, _c)
	var out: Array[PackedByteArray] = []
	assert_int(_rig.codec.encode(store, 60, _a, _b, _c, _pilot(), out)).is_greater_equal(3)
	for i: int in out.size():
		if i != 1:
			assert_int(dec.decode(out[i])).is_equal(SnapshotDecoder.Status.OK)   # loss, not malformation
	assert_int(dec.store.newest_tick).is_equal(60)
	assert_int(dec.store.complete_tick).is_equal(59)
	store.ack(dec.store.complete_tick)
	assert_int(store.acked_tick).is_equal(59)
	var bases: PackedInt32Array = PackedInt32Array()
	for t: int in 4:
		_rig.step()
		var sent: Array[PackedByteArray] = _round(store, dec, 0, _pilot())
		var _p: bool = bases.push_back(sent[0].decode_u32(5))
		assert_bool(dec.current().same_state(store.frame_at(_rig.tick))).is_true()
	assert_int(bases[0]).is_equal(59)                                  # tick 61 against 59, never 60
	assert_int(bases[1]).is_equal(61)                                  # tick 61 was complete and acked
	assert_int(bases[3]).is_equal(63)


func test_section_count_255_splits() -> void:
	_rig.build(Vector3i(300, 0, 0), Vector3i(0, 0, 0), 0, 4)
	_rig.codec.max_packets = 2
	var store: BaselineStore = BaselineStore.new(0)
	var dec: SnapshotDecoder = _rig.new_decoder(0)
	for t: int in 30:
		_rig.step()
		var _o: Array[PackedByteArray] = _round(store, dec, 0, null)
	_rig.tick += 1
	_rig.frame.tick = _rig.tick
	_rig.frame.hp01.fill(0.5)                          # 300 HP-only deltas: 3 B each, 900 B, one section
	_rig.codec.prepare_tick(_rig.frame)
	var out: Array[PackedByteArray] = _round(store, dec, 0, null)
	assert_int(out.size()).is_equal(2)
	assert_int(out[0][SnapshotCodec.HEADER_BYTES]).is_equal(SnapshotCodec.SECTION_MAX)
	assert_int(out[1][SnapshotCodec.HEADER_BYTES]).is_equal(300 - SnapshotCodec.SECTION_MAX)
	assert_int(dec.current().hp[299]).is_equal(Codec.quantize_hp(0.5))


## Snapshot bytes per second for one client on the 400-entity scene with `delay` ticks of ack latency and
## `loss` packet loss. Returns (payload B/s, link B/s incl. 38 B per packet).
func _bandwidth(delay: int, loss: float) -> Vector2:
	_rig = SnapRig.new()
	_rig.build(Vector3i(40, 200, 160), Vector3i(24, 70, 60), 4, 17)
	var store: BaselineStore = BaselineStore.new(0)
	var dec: SnapshotDecoder = _rig.new_decoder(0)
	var drop: RandomNumberGenerator = RandomNumberGenerator.new()
	drop.seed = 5
	var acks: Array[Vector2i] = []
	var bytes: int = 0
	var packets: int = 0
	for t: int in 660:
		_rig.step()
		_rig.lists(0, _a, _b, _c)
		var out: Array[PackedByteArray] = []
		var _n: int = _rig.codec.encode(store, _rig.tick, _a, _b, _c, _pilot(), out)
		for p: PackedByteArray in out:
			if t >= 60:
				bytes += p.size()
				packets += 1
			if drop.randf() >= loss:
				var _s: int = dec.decode(p)
		acks.append(Vector2i(_rig.tick + delay, dec.store.complete_tick))
		while acks.size() > 0 and acks[0].x <= _rig.tick:
			store.ack(acks[0].y)
			acks.remove_at(0)
	var secs: float = 600.0 / SnapRig.HZ
	var cd: SnapshotCodec = _rig.codec
	print("BANDWIDTH_MIX full=%d delta=%d blip=%d pos_small=%d pos_large=%d packets=%d" % [cd.n_full, cd.n_delta,
			cd.n_blip, cd.n_pos_small, cd.n_pos_large, packets])
	return Vector2(bytes / secs, (bytes + packets * OVERHEAD) / secs)


func test_bandwidth_400_entities_under_30_kbps() -> void:
	for row: Vector2 in [Vector2(3, 0.0), Vector2(5, 0.03)]:
		var bw: Vector2 = _bandwidth(int(row.x), row.y)
		print("BANDWIDTH ack_delay_ticks=%d loss=%.2f payload_Bps=%d link_Bps=%d" % [int(row.x), row.y, int(bw.x), int(bw.y)])
		assert_float(bw.y).is_less_equal(30000.0)


func test_determinism_identical_bytes() -> void:
	var digests: PackedStringArray = PackedStringArray()
	for run: int in 2:
		_rig = SnapRig.new()
		_rig.build(Vector3i(30, 80, 60), Vector3i(20, 30, 20), 3, 77)
		var stores: Array[BaselineStore] = [BaselineStore.new(0), BaselineStore.new(1)]
		var decs: Array[SnapshotDecoder] = [_rig.new_decoder(0), _rig.new_decoder(1)]
		var ctx: HashingContext = HashingContext.new()
		var _st: int = ctx.start(HashingContext.HASH_SHA256)
		for t: int in 300:
			_rig.step()
			for k: int in 2:
				for p: PackedByteArray in _round(stores[k], decs[k], k, _pilot() if k == 0 else null):
					var _u: int = ctx.update(p)
		var tail: String = str(decs[0].current().state_hash()) + ":" + str(decs[1].current().state_hash())
		var _a1: bool = digests.push_back(ctx.finish().hex_encode() + tail)
	assert_str(digests[0]).is_equal(digests[1])


func test_one_prepare_tick_per_tick_for_8_clients() -> void:
	_rig.build(Vector3i(20, 40, 40), Vector3i(10, 20, 10), 2, 9)
	var stores: Array[BaselineStore] = []
	var decs: Array[SnapshotDecoder] = []
	for k: int in 8:
		stores.append(BaselineStore.new(k % 3))
		decs.append(_rig.new_decoder(k % 3))
	for t: int in 60:
		_rig.step()
		for k: int in 8:
			var _o: Array[PackedByteArray] = _round(stores[k], decs[k], k, null)
	assert_int(_rig.codec.prepare_count).is_equal(60)
	var out: Array[PackedByteArray] = []
	assert_int(_rig.codec.encode(stores[0], _rig.tick + 1, _a, _b, _c, null, out)).is_equal(0)   # not prepared
	assert_int(out.size()).is_equal(0)
	assert_array(Array(_rig.codec.team_visible(1))).is_equal(Array(_rig.codec.team_visible(2)))   # mask 0x7
	assert_int(_rig.codec.team_visible(0).size()).is_equal(100)


func test_late_entity_meta_holds_then_applies() -> void:
	_rig.build(Vector3i(12, 0, 0), Vector3i(6, 0, 0), 0, 2)
	var sync: RosterSync = RosterSync.new()
	sync.roster = _rig.roster_without(5)
	var store: BaselineStore = BaselineStore.new(0)
	var dec: SnapshotDecoder = SnapshotDecoder.new(SnapRig.G, SnapRig.HZ, 0, sync.roster)
	_rig.step()
	_rig.lists(0, _a, _b, _c)
	var out: Array[PackedByteArray] = []
	var _n: int = _rig.codec.encode(store, _rig.tick, _a, _b, _c, null, out)
	assert_int(dec.decode(out[0])).is_equal(SnapshotDecoder.Status.MISSING_ROSTER)
	assert_array(Array(dec.missing)).is_equal([5])
	assert_int(dec.store.newest_tick).is_equal(0)                  # nothing applied
	sync.hold(_rig.tick, _rig.tick, out[0], dec.missing)
	var meta: Array[PackedByteArray] = []
	var _m: int = RosterCodec.encode_meta(_rig.roster, PackedInt32Array([5]), meta)
	assert_int(sync.on_meta(meta[0])).is_equal(1)
	var ticks: PackedInt32Array = PackedInt32Array()
	var held: Array[PackedByteArray] = []
	assert_int(sync.take_ready(ticks, held)).is_equal(1)
	assert_int(dec.decode(held[0])).is_equal(SnapshotDecoder.Status.OK)
	assert_bool(dec.current().same_state(store.frame_at(_rig.tick))).is_true()
