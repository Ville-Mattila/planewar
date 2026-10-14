extends GdUnitTestSuite
## NET-10 event_codec_test: every SimEvent.Kind 0-33 round-trips through EventRouter -> EVENTS -> EventCodec.decode
## with the payload of 04 s3.6 (sizes included); HIT damage is u16; malformed packets are rejected.

var _rig: EventRig


func before_test() -> void:
	_rig = EventRig.new()


func _x(bytes: Array) -> PackedByteArray:
	return PackedByteArray(bytes)


## [event, expected field values in table order (POS slot ignored), bytes incl. kind+size (04 s3.6 "B" column)]
func _cases() -> Array:
	var i5: int = EventRig.id(5)
	var i6: int = EventRig.id(6)
	var p: Vector3 = _rig.site
	return [
		[EventRig.ev(SimEvent.Kind.SPAWN, i5, 77), [5, 77, 2], 7],
		[EventRig.ev(SimEvent.Kind.DEATH, i5, i6, 0.0, 0, _x([3])), [5, 6, 3], 7],
		[EventRig.ev(SimEvent.Kind.HIT, i5, i6, 1234.4, 0, _x([4, 9])), [5, 6, 9, 1234, 4], 10],
		[EventRig.ev(SimEvent.Kind.BOMB_IMPACT, 3, 12, 0.0, 0, _x([]), p), [0, 12, 3], 13],
		[EventRig.ev(SimEvent.Kind.DOCKED, i5, i6), [5, 6], 6],
		[EventRig.ev(SimEvent.Kind.SERVICED, i5, i6, 0.0, 0, _x([5])), [5, 6, 5], 7],
		[EventRig.ev(SimEvent.Kind.LAUNCHED, i5, i6), [5, 6], 6],
		[EventRig.ev(SimEvent.Kind.ORDER_DONE, i5, 2), [5, 2], 5],
		[EventRig.ev(SimEvent.Kind.ORDER_FAILED, i5, 2, 0.0, 0, _x([6])), [5, 2, 6], 6],
		[EventRig.ev(SimEvent.Kind.POSSESSED, i5, 2), [5, 2], 5],
		[EventRig.ev(SimEvent.Kind.RELEASED, i5, 2, 0.0, 0, _x([4])), [5, 2, 4], 6],
		[EventRig.ev(SimEvent.Kind.BUILD_STARTED, i5, 301, 0.0, 0, _x([2])), [5, 301, 2], 7],
		[EventRig.ev(SimEvent.Kind.BUILD_DONE, i5, 301), [5, 301], 6],
		[EventRig.ev(SimEvent.Kind.STRUCTURE_LOST, i5, i6, 0.0, 0, _x([0x2D, 0x01])), [5, 301, 6], 8],
		[EventRig.ev(SimEvent.Kind.LOW_POWER, 0, 0, 0.5), [0, 128], 4],
		[EventRig.ev(SimEvent.Kind.ALERT, 3, i6, 2.0, 0, _x([]), p), [3, 6, 0, 2], 14],
		[EventRig.ev(SimEvent.Kind.CORE_EXPOSURE, 0, 0, 0.0, -1), [255], 3],
		[EventRig.ev(SimEvent.Kind.CAP_REACHED, 2, 1, 0.0, -1), [2, 1], 4],
		[EventRig.ev(SimEvent.Kind.WRECK_SPAWNED, i5, 90, 1500.0), [5, 90, 1500], 8],
		[EventRig.ev(SimEvent.Kind.WRECK_SALVAGED, i5, i6, 40.0), [5, 6, 40], 8],
		[EventRig.ev(SimEvent.Kind.CEILING_RELEASE, i5, 2), [5, 2], 5],
		[EventRig.ev(SimEvent.Kind.HANDOVER, i5, 2, 0.0, 0, _x([3])), [5, 2, 3], 6],
		[EventRig.ev(SimEvent.Kind.PLAYER_ELIMINATED, 4, 1, 0.0, 1), [4, 1], 4],
		[EventRig.ev(SimEvent.Kind.LOCK_ACQUIRED, i6, i5), [6, 5], 6],
		[EventRig.ev(SimEvent.Kind.LOCK_BROKEN, i6, i5), [6, 5], 6],
		[EventRig.ev(SimEvent.Kind.CAPTURE_PROGRESS, i5, 1, 0.5), [5, 1, 128], 6],
		[EventRig.ev(SimEvent.Kind.CAPTURED, i5, 1, 0.0, 1), [5, 1], 5],
		[EventRig.ev(SimEvent.Kind.SALVAGE_DELIVERED, i5, i6, 300.0), [5, 6, 300], 8],
		[EventRig.ev(SimEvent.Kind.LANDING, i5, i6, 0.0, 0, _x([4, 200, 3, 25, 80])), [5, 6, 4, 200, 3, 25, 80], 11],
		[EventRig.ev(SimEvent.Kind.SHIELD_COLLAPSE, i5, 0), [5], 4],
		[EventRig.ev(SimEvent.Kind.POSSESS_REQUESTED, i5, 3), [5, 3], 5],
		[EventRig.ev(SimEvent.Kind.CANISTER_DEPLOYED, i5, 2), [5, 2], 5],
		[EventRig.ev(SimEvent.Kind.CANISTER_COLLECTED, i5, i6), [5, 6], 6],
	]


func test_every_kind_round_trips_with_table_sizes() -> void:
	var seen: PackedInt32Array = PackedInt32Array()
	for c: Array in _cases():
		var e: SimEvent = c[0]
		var want: Array = c[1]
		var out: Array[WireEvent] = EventRig.roundtrip([e], _rig.aud)
		assert_int(out.size()).is_equal(1)
		var w: WireEvent = out[0]
		assert_int(w.kind).is_equal(e.kind)
		assert_int(w.tick).is_equal(7)
		assert_int(w.count).is_equal(want.size())
		for f: int in want.size():
			if EventCodec.SCHEMA[e.kind * EventCodec.ROW + f] == EventCodec.POS:
				assert_float(w.pos.distance_to(e.pos)).is_less(0.1)
			else:
				assert_int(w.v[f]).is_equal(want[f] as int)
		assert_int(EventCodec.payload_bytes(e.kind) + EventCodec.EVENT_HEADER_BYTES).is_equal(c[2] as int)
		var _a: bool = seen.append(e.kind)
	assert_int(seen.size()).is_equal(33)                         # 0-33 without MATCH_END (message 0x8E)
	assert_bool(seen.has(SimEvent.Kind.MATCH_END)).is_false()


func test_match_end_never_travels_in_events() -> void:
	var e: SimEvent = EventRig.ev(SimEvent.Kind.MATCH_END, 1, 0, 0.0, -1)
	assert_int(EventRig.roundtrip([e], _rig.aud).size()).is_equal(0)
	assert_bool(EventCodec.is_valid_kind(SimEvent.Kind.MATCH_END)).is_false()


func test_hit_damage_is_u16_and_clamped() -> void:
	var i5: int = EventRig.id(5)
	var hi: SimEvent = EventRig.ev(SimEvent.Kind.HIT, i5, i5, 65535.0, 0, PackedByteArray([0, 1]))
	var over: SimEvent = EventRig.ev(SimEvent.Kind.HIT, i5, i5, 70000.0, 0, PackedByteArray([0, 1]))
	var neg: SimEvent = EventRig.ev(SimEvent.Kind.HIT, i5, i5, -3.0, 0, PackedByteArray([0, 1]))
	var out: Array[WireEvent] = EventRig.roundtrip([hi, over, neg], _rig.aud)
	assert_int(out[0].v[3]).is_equal(65535)
	assert_int(out[1].v[3]).is_equal(65535)
	assert_int(out[2].v[3]).is_equal(0)


func test_schema_covers_every_kind_and_matches_enum() -> void:
	assert_int(EventCodec.KIND_COUNT).is_equal(SimEvent.Kind.CANISTER_COLLECTED + 1)
	assert_int(EventCodec.SCHEMA.size()).is_equal(EventCodec.KIND_COUNT * EventCodec.ROW)
	assert_int(EventRouter.SOURCES.size()).is_equal(EventCodec.SCHEMA.size())
	assert_int(EventRouter.SCOPES.size()).is_equal(EventCodec.KIND_COUNT)
	assert_int(Protocol.EventKind.CANISTER_COLLECTED).is_equal(EventCodec.KIND_COUNT - 1)


func test_malformed_packets_rejected_without_output() -> void:
	var good: PackedByteArray = PackedByteArray()
	var out: Array[WireEvent] = EventRig.roundtrip([EventRig.ev(SimEvent.Kind.HIT, EventRig.id(5), EventRig.id(6), 10.0)], _rig.aud)
	assert_int(out.size()).is_equal(1)
	var buf: PackedByteArray = PackedByteArray()
	var _r: Error = buf.resize(16)
	var at: int = EventCodec.write_header(buf, 9)
	var vals: PackedInt32Array = PackedInt32Array([5, 6, 1, 10, 0, 0, 0, 0])
	at = EventCodec.write_event(buf, at, SimEvent.Kind.HIT, vals, 0)
	buf[5] = 1
	good = buf.slice(0, at)
	var sink: Array[WireEvent] = []
	assert_int(EventCodec.decode(good, sink)).is_equal(1)
	sink.clear()
	var cases: Array[PackedByteArray] = []
	cases.append(PackedByteArray())
	cases.append(good.slice(0, good.size() - 1))                              # truncated
	var longer: PackedByteArray = good.duplicate()
	longer.append(0)
	cases.append(longer)                                                      # trailing byte
	var wrong_id: PackedByteArray = good.duplicate()
	wrong_id[0] = Protocol.ENTITY_META
	cases.append(wrong_id)
	var zero_count: PackedByteArray = good.duplicate()
	zero_count[5] = 0
	cases.append(zero_count)
	var bad_kind: PackedByteArray = good.duplicate()
	bad_kind[6] = SimEvent.Kind.MATCH_END
	cases.append(bad_kind)
	var unknown: PackedByteArray = good.duplicate()
	unknown[6] = 34
	cases.append(unknown)
	var bad_size: PackedByteArray = good.duplicate()
	bad_size[7] = 7
	cases.append(bad_size)
	var two: PackedByteArray = good.duplicate()
	two[5] = 2                                                                # count larger than content
	cases.append(two)
	for c: PackedByteArray in cases:
		assert_int(EventCodec.decode(c, sink)).is_equal(-1)
	assert_int(sink.size()).is_equal(0)


func test_invalid_position_cell_rejected() -> void:
	var out: Array[WireEvent] = EventRig.roundtrip([EventRig.ev(SimEvent.Kind.BOMB_IMPACT, 1, 2, 0.0, 0, PackedByteArray(), _rig.site)], _rig.aud)
	assert_int(out.size()).is_equal(1)
	var router: EventRouter = EventRouter.new()
	var auds: Array[EventAudience] = [_rig.aud]
	router.route(7, [EventRig.ev(SimEvent.Kind.BOMB_IMPACT, 1, 2, 0.0, 0, PackedByteArray(), _rig.site)], auds)
	var pkt: PackedByteArray = _rig.aud.outbox[0].duplicate()
	pkt.encode_u16(8, Codec.CELL_COUNT)                                       # pos cell field of event 0
	var sink: Array[WireEvent] = []
	assert_int(EventCodec.decode(pkt, sink)).is_equal(-1)


func test_fuzz_mutations_never_throw_and_never_partially_apply() -> void:
	var evs: Array[SimEvent] = []
	for c: Array in _cases():
		evs.append(c[0])
	var router: EventRouter = EventRouter.new()
	var auds: Array[EventAudience] = [_rig.aud]
	router.route(7, evs, auds)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 1010
	var ok: int = 0
	for _n: int in 3000:
		var p: PackedByteArray = _rig.aud.outbox[rng.randi() % _rig.aud.outbox.size()].duplicate()
		for _m: int in 1 + rng.randi() % 4:
			match rng.randi() % 3:
				0:
					p[rng.randi() % p.size()] = rng.randi() & 0xFF
				1:
					p = p.slice(0, rng.randi() % p.size())
				2:
					p.append(rng.randi() & 0xFF)
			if p.is_empty():
				p.append(0)
		var sink: Array[WireEvent] = []
		var r: int = EventCodec.decode(p, sink)
		assert_int(sink.size()).is_equal(maxi(r, 0))
		if r > 0:
			ok += 1
	assert_int(ok).is_greater_equal(0)
