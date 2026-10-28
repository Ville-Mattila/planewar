extends GdUnitTestSuite
## NET-50 (R0 B.11 A-54): the roster has 1,536 entries, one per EntityStore slot 0-1,535 (1,280 unit / structure
## slots + 256 wreck slots, 03 s3.1). A wreck in slot 1,535 gets a roster index; WRECK_SPAWNED / WRECK_SALVAGED reach
## a filtered client; ENTITY_META, ROSTER_REMOVE and SNAPSHOT records carry slots up to 1,535; the bytes of a
## non-wreck scene are unchanged by the capacity change (pinned SHA-256 of a canonical-schedule run taken at 1,280).

const LAST_WRECK: int = 1535
## SHA-256 of `_scene_bytes()` measured with Roster.CAPACITY = 1280 (origin/main before NET-50) was a9f7e6be..a58a93585.
## Re-pinned by NET-54: a C-BLIP is skipped while the dead-reckoned mirror entry shows the true blip, so section C
## bytes change (same run on the NET-54 encoder; NET-50's capacity independence is unaffected, no slot >= 1280 is used).
## NET-58 (R0 B.22 A-112, Roster.CAPACITY 1,536 -> 3,584 with the projectile block) leaves this pin untouched.
const NON_WRECK_SHA: String = "664956b6609c3e1dfc39bbf9468d861aeed364194903f870da5ea737de752b5c"

var _a: PackedInt32Array = PackedInt32Array()
var _b: PackedInt32Array = PackedInt32Array()
var _c: PackedInt32Array = PackedInt32Array()


func test_capacity_covers_every_entity_store_slot() -> void:
	assert_int(Roster.ENTITY_SLOTS).is_equal(1536)                            # NET-58 (A-112): the entity part of 3,584
	assert_int(Roster.ENTITY_SLOTS).is_equal(EntityId.WRECK_SLOT_END)
	assert_int(BaselineFrame.CAPACITY).is_equal(Roster.CAPACITY)
	assert_int(SnapshotCodec.CAPACITY).is_equal(Roster.CAPACITY)
	assert_int(SnapshotByteCache.CAPACITY).is_equal(Roster.CAPACITY)
	var r: Roster = Roster.new()
	assert_bool(r.add(LAST_WRECK, 3, 40, 2, 1)).is_true()
	assert_bool(r.has(LAST_WRECK)).is_true()
	assert_int(r.generation_of(LAST_WRECK)).is_equal(3)
	assert_bool(r.add(Roster.CAPACITY, 1, 1, 0, 0)).is_false()
	assert_bool(r.remove(LAST_WRECK, Protocol.RosterRemoveReason.DEATH)).is_true()
	assert_int(r.removal_reason_of(LAST_WRECK)).is_equal(Protocol.RosterRemoveReason.DEATH)


func test_wreck_events_reach_a_filtered_client() -> void:
	var rig: EventRig = EventRig.new()
	var _ok: bool = rig.roster.add(EntityId.WRECK_SLOT_MIN, 2, 41, 2, 0)
	_ok = rig.roster.add(LAST_WRECK, 3, 41, 2, 0)
	assert_bool(rig.aud.unfiltered).is_false()
	var spawned: SimEvent = EventRig.ev(SimEvent.Kind.WRECK_SPAWNED, EventRig.id(LAST_WRECK, 3), 77, 120.0)
	var salvaged: SimEvent = EventRig.ev(SimEvent.Kind.WRECK_SALVAGED, EventRig.id(EntityId.WRECK_SLOT_MIN, 2),
			EventRig.id(5), 60.0)
	var unseen: SimEvent = EventRig.ev(SimEvent.Kind.WRECK_SPAWNED, EventRig.id(1400, 1), 77, 50.0)
	var stale: SimEvent = EventRig.ev(SimEvent.Kind.WRECK_SALVAGED, EventRig.id(LAST_WRECK, 2), EventRig.id(5), 9.0)
	var out: Array[WireEvent] = EventRig.roundtrip([spawned, unseen, salvaged, stale], rig.aud)
	assert_int(out.size()).is_equal(2)
	assert_int(out[0].kind).is_equal(SimEvent.Kind.WRECK_SPAWNED)
	assert_array(Array(out[0].v.slice(0, 3))).is_equal([LAST_WRECK, 77, 120])
	assert_int(out[1].kind).is_equal(SimEvent.Kind.WRECK_SALVAGED)
	assert_array(Array(out[1].v.slice(0, 3))).is_equal([EntityId.WRECK_SLOT_MIN, 5, 60])
	assert_int(EventRouter.ref_of(EventRig.id(LAST_WRECK, 3), rig.aud)).is_equal(LAST_WRECK)
	rig.aud.unfiltered = true
	assert_int(EventRouter.ref_of(EventRig.id(LAST_WRECK, 9), rig.aud)).is_equal(LAST_WRECK)
	assert_int(EventRouter.ref_of(EventRig.id(Roster.CAPACITY, 1), rig.aud)).is_equal(EventCodec.NONE_REF)


func test_entity_meta_and_remove_carry_wreck_slots() -> void:
	var src: Roster = Roster.new()
	var slots: PackedInt32Array = PackedInt32Array([3, 1279, EntityId.WRECK_SLOT_MIN, 1400, LAST_WRECK])
	for s: int in slots:
		var _ok: bool = src.add(s, 5, 40 + (s & 7), 1, 1, "w" if s == LAST_WRECK else "")
	var out: Array[PackedByteArray] = []
	assert_int(RosterCodec.encode_meta(src, slots, out)).is_equal(1)
	var dst: Roster = Roster.new()
	var got: PackedInt32Array = PackedInt32Array()
	assert_int(RosterCodec.decode_meta(out[0], dst, got)).is_equal(slots.size())
	assert_array(Array(got)).is_equal(Array(slots))
	assert_int(dst.state_hash()).is_equal(src.state_hash())
	assert_str(dst.tag_of(LAST_WRECK)).is_equal("w")
	var bad: PackedByteArray = out[0].duplicate()
	bad.encode_u16(2 + 4 * RosterCodec.META_FIXED_BYTES, Roster.CAPACITY)       # last entry's slot -> 1,536
	assert_int(RosterCodec.decode_meta(bad, Roster.new(), got)).is_equal(-1)
	var rm: Array[PackedByteArray] = []
	var reasons: PackedInt32Array = PackedInt32Array([Protocol.RosterRemoveReason.DEATH])
	assert_int(RosterCodec.encode_remove(PackedInt32Array([LAST_WRECK]), reasons, rm)).is_equal(1)
	assert_int(RosterCodec.decode_remove(rm[0], dst, got)).is_equal(1)
	assert_bool(dst.has(LAST_WRECK)).is_false()
	var rm_bad: PackedByteArray = PackedByteArray([Protocol.ROSTER_REMOVE, 1, 0x00, 0x06, 0])   # slot 1,536
	assert_int(RosterCodec.decode_remove(rm_bad, dst, got)).is_equal(-1)


func test_snapshot_records_reach_slot_1535() -> void:
	var codec: SnapshotCodec = SnapshotCodec.new(SnapRig.G, SnapRig.HZ)
	var roster: Roster = Roster.new()
	var f: SnapshotFrame = SnapshotFrame.new()
	f.resize(3)
	f.tick = 40
	var p: Vector3 = Sphere.from_lat_lon(0.2, 0.5, Sphere.PLANET_RADIUS + 3.0)
	var ids: PackedInt32Array = PackedInt32Array([7, 1290, LAST_WRECK])
	for i: int in 3:
		var _ok: bool = roster.add(ids[i], 1, 40, 0, 0)
		f.set_entity(i, ids[i], p + p.normalized().cross(Vector3.UP) * (10.0 * i), Vector3.ZERO, Quaternion.IDENTITY,
				0.5, 0, 0, 0, false, 0x7)
	codec.prepare_tick(f)
	var store: BaselineStore = BaselineStore.new(0)
	var dec: SnapshotDecoder = SnapshotDecoder.new(SnapRig.G, SnapRig.HZ, 0, roster)
	var out: Array[PackedByteArray] = []
	assert_int(codec.encode(store, 40, PackedInt32Array(), ids, PackedInt32Array(), null, out)).is_equal(1)
	assert_int(dec.decode(out[0])).is_equal(SnapshotDecoder.Status.OK)
	assert_int(dec.current().present[LAST_WRECK]).is_equal(1)
	assert_bool(dec.current().same_state(store.frame_at(40))).is_true()
	assert_int(dec.records_applied).is_equal(3)


## Canonical schedule (A-40) for 3 clients, 120 ticks, slots 0-459 only: SHA-256 of every packet.
func _scene_bytes() -> String:
	var rig: SnapRig = SnapRig.new()
	rig.build(Vector3i(40, 120, 300), Vector3i(24, 50, 120), 4, 50)
	var r: PackedInt32Array = PackedInt32Array()
	var stores: Array[BaselineStore] = []
	for k: int in 3:
		stores.append(BaselineStore.new(k))
	var ctx: HashingContext = HashingContext.new()
	var _st: int = ctx.start(HashingContext.HASH_SHA256)
	for t: int in 120:
		rig.step()
		for k: int in 3:
			rig.canonical_lists(k, _a, _b, _c, r)
			var out: Array[PackedByteArray] = []
			var _n: int = rig.codec.encode(stores[k], rig.tick, _a, _b, _c, null, out, r)
			for pkt: PackedByteArray in out:
				var _u: int = ctx.update(pkt)
			stores[k].ack(rig.tick - 2 - k)
	return ctx.finish().hex_encode()


func test_non_wreck_scene_bytes_unchanged() -> void:
	var sha: String = _scene_bytes()
	assert_str(sha).is_equal(NON_WRECK_SHA)
