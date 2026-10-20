extends GdUnitTestSuite
## NET-04: COMMAND payload codecs for all 16 kinds (04 s2.5, R0 B.11 A-60, B.14 A-85). Wire bytes must match the sim
## `Command` builders byte for byte wherever the forms coincide; positions are vec3q on the wire, f64 in the sim.


func _q(dir: Vector3, alt: float) -> Vector3:
	return Codec.dequantize_pos(Codec.quantize_pos(dir.normalized() * (Sphere.PLANET_RADIUS + alt)))


func _wire(cmd: Command) -> PackedByteArray:
	var out: PackedByteArray = PackedByteArray()
	assert_bool(CommandCodec.encode_payload(cmd, out)).is_true()
	return out


## sim -> wire -> sim: kind, target and size survive; bytes are identical wherever no position is quantised.
func _round_trip(cmd: Command) -> Command:
	var back: Command = CommandCodec.decode_payload(cmd.kind, cmd.target, _wire(cmd))
	assert_object(back).is_not_null()
	assert_int(back.kind).is_equal(cmd.kind)
	assert_int(back.target).is_equal(cmd.target)
	assert_int(back.payload.size()).is_equal(cmd.payload.size())
	assert_array(_wire(back)).is_equal(_wire(cmd))   # wire bytes are a fixed point of sim -> wire -> sim -> wire
	if cmd.kind != Command.Kind.ORDER and cmd.kind != Command.Kind.SET_RALLY:
		assert_array(back.payload).is_equal(cmd.payload)
	return back


func _ids(n: int) -> PackedInt32Array:
	var ids: PackedInt32Array = PackedInt32Array()
	for i: int in n:
		ids.append(0x10000 + i)
	return ids


func _pts(n: int) -> PackedVector3Array:
	var p: PackedVector3Array = PackedVector3Array()
	for i: int in n:
		p.append(_q(Vector3(1.0, 0.05 + 0.07 * float(i), 0.3), 400.0 + float(i)))
	return p


func _patrol(np: int) -> OrderSpec:
	var s: OrderSpec = OrderSpec.make(OrderSpec.Kind.PATROL)
	s.points = _pts(np)
	return s


func _bytes_with_points(np: int) -> PackedByteArray:
	var b: PackedByteArray = PackedByteArray()
	var _r: int = b.resize(9 + 4 + 8 * np)
	b[3] = 1
	b[8 + 4] = np
	return b


func test_order_move_round_trips() -> void:
	var s: OrderSpec = OrderSpec.make(OrderSpec.Kind.MOVE, 77, _q(Vector3(0.2, 1.0, 0.4), 300.0), OrderSpec.FLAG_QUEUE)
	var cmd: Command = Command.order(1, _ids(5), s)
	var w: PackedByteArray = _wire(cmd)
	assert_int(w.size()).is_equal(CommandCodec.order_wire_size(5, 1, false))
	assert_int(w[0]).is_equal(OrderSpec.Kind.MOVE)
	assert_int(w[3]).is_equal(5)
	var back: Command = _round_trip(cmd)
	assert_float(CommandPayload.v3_at(back.payload, 9 + 4 * 5).distance_to(s.point)).is_less(0.01)


## The field list sums to 9 + 4n + 8p (04 s2.5 prints 8): at 32 ids the 256 B limit allows 14 points, not 15.
func test_order_32_ids_boundary() -> void:
	var ok: Command = Command.order(1, _ids(32), _patrol(14))
	assert_int(_wire(ok).size()).is_equal(249)
	var _b: Command = _round_trip(ok)
	var out: PackedByteArray = PackedByteArray()
	assert_bool(CommandCodec.encode_payload(Command.order(1, _ids(32), _patrol(15)), out)).is_false()
	assert_bool(CommandCodec.order_fits(32, 14, false)).is_true()
	assert_bool(CommandCodec.order_fits(32, 15, false)).is_false()
	assert_bool(CommandCodec.order_fits(32, 16, false)).is_false()
	assert_bool(CommandCodec.order_fits(33, 0, false)).is_false()


func test_order_16_points_with_few_ids_round_trips_17_refused() -> void:
	var _b: Command = _round_trip(Command.order(1, _ids(1), _patrol(16)))
	assert_object(CommandCodec.decode_payload(0, 0, _bytes_with_points(17))).is_null()


func test_escort_trailer() -> void:
	var s: OrderSpec = OrderSpec.make(OrderSpec.Kind.ESCORT, 55)
	s.escort_mode = OrderSpec.EscortMode.FOCUS
	s.escort_slot = 1
	s.focus = 0x30042
	var cmd: Command = Command.order(1, _ids(3), s)
	var w: PackedByteArray = _wire(cmd)
	assert_int(w.size()).is_equal(CommandCodec.order_wire_size(3, 0, true))
	assert_int(w[w.size() - 6]).is_equal(OrderSpec.EscortMode.FOCUS)
	assert_int(w[w.size() - 5]).is_equal(1)
	assert_int(w.decode_u32(w.size() - 4)).is_equal(0x30042)
	var _b: Command = _round_trip(cmd)
	var spec: OrderSpec = OrderSpec.new()
	var ids: PackedInt32Array = PackedInt32Array()
	var back: Command = CommandCodec.decode_payload(0, 0, w)
	assert_bool(CommandPayload.read_order(back, spec, ids)).is_true()
	assert_int(spec.escort_slot).is_equal(1)
	assert_int(spec.focus).is_equal(0x30042)


func test_escort_32_ids_is_143_bytes_and_slot_none() -> void:
	var cmd: Command = Command.order(1, _ids(32), OrderSpec.make(OrderSpec.Kind.ESCORT, 55))
	var w: PackedByteArray = _wire(cmd)
	assert_int(w.size()).is_equal(143)
	assert_int(w[w.size() - 5]).is_equal(0xFF)
	var _b: Command = _round_trip(cmd)


func test_trailer_mismatch_is_null() -> void:
	var move: PackedByteArray = _wire(Command.order(1, _ids(2), OrderSpec.make(OrderSpec.Kind.MOVE, 0, _q(Vector3(1.0, 0.2, 0.1), 100.0))))
	move.append_array(PackedByteArray([0, 0xFF, 0, 0, 0, 0]))
	assert_object(CommandCodec.decode_payload(0, 0, move)).is_null()
	var esc: PackedByteArray = _wire(Command.order(1, _ids(2), OrderSpec.make(OrderSpec.Kind.ESCORT, 5)))
	assert_object(CommandCodec.decode_payload(0, 0, esc.slice(0, esc.size() - 6))).is_null()
	assert_object(CommandCodec.decode_payload(0, 0, esc.slice(0, esc.size() - 1))).is_null()


func test_escort_mode_above_break_is_null_slot_is_not() -> void:
	var w: PackedByteArray = _wire(Command.order(1, _ids(1), OrderSpec.make(OrderSpec.Kind.ESCORT, 5)))
	w[w.size() - 6] = 3
	assert_object(CommandCodec.decode_payload(0, 0, w)).is_null()
	w[w.size() - 6] = 2
	w[w.size() - 5] = 200   # out-of-range slot: the sim answers REJECTED_INVALID_ORDER, not a decode failure
	assert_object(CommandCodec.decode_payload(0, 0, w)).is_not_null()


func test_order_malformed_shapes() -> void:
	var good: PackedByteArray = _wire(Command.order(1, _ids(2), OrderSpec.make(OrderSpec.Kind.HOLD)))
	assert_object(CommandCodec.decode_payload(0, 0, good)).is_not_null()
	var zero: PackedByteArray = good.duplicate()
	zero[3] = 0
	assert_object(CommandCodec.decode_payload(0, 0, zero)).is_null()
	var many: PackedByteArray = good.duplicate()
	many[3] = 33
	assert_object(CommandCodec.decode_payload(0, 0, many)).is_null()
	var kind: PackedByteArray = good.duplicate()
	kind[0] = 12
	assert_object(CommandCodec.decode_payload(0, 0, kind)).is_null()
	var haul: PackedByteArray = good.duplicate()
	haul[2] = 3
	assert_object(CommandCodec.decode_payload(0, 0, haul)).is_null()
	assert_object(CommandCodec.decode_payload(0, 0, good.slice(0, good.size() - 1))).is_null()
	assert_object(CommandCodec.decode_payload(0, 0, PackedByteArray())).is_null()
	var cell: PackedByteArray = _wire(Command.order(1, _ids(1), OrderSpec.make(OrderSpec.Kind.MOVE, 0, _q(Vector3(0.1, 1.0, 0.2), 100.0))))
	cell.encode_u16(cell.size() - 8, 0xFFFF)   # invalid interest cell
	assert_object(CommandCodec.decode_payload(0, 0, cell)).is_null()


func test_build_produce_cancel_handover() -> void:
	var _a: Command = _round_trip(Command.build(1, 12, 99999, 3))
	var _b: Command = _round_trip(Command.produce(1, 0x20005, 7, 5))
	var _c: Command = _round_trip(CommandPayload.cancel_build(1, 0x20006))
	var _d: Command = _round_trip(CommandPayload.cancel_produce(1, 0x20006, 4))
	var _e: Command = _round_trip(CommandPayload.handover(1, 0x20007, 3))
	var bad_rot: PackedByteArray = _wire(Command.build(1, 12, 5, 3))
	bad_rot[6] = 4
	assert_object(CommandCodec.decode_payload(Command.Kind.BUILD, 0, bad_rot)).is_null()
	var cnt: PackedByteArray = _wire(Command.produce(1, 5, 7, 1))
	cnt[2] = 9   # count legality (queue_max) belongs to the sim validator, not the codec
	assert_object(CommandCodec.decode_payload(Command.Kind.PRODUCE, 5, cnt)).is_not_null()
	assert_object(CommandCodec.decode_payload(Command.Kind.PRODUCE, 5, cnt.slice(0, 2))).is_null()
	assert_object(CommandCodec.decode_payload(Command.Kind.CANCEL_PRODUCE, 5, PackedByteArray())).is_null()


func test_empty_payload_kinds() -> void:
	for k: Command.Kind in [Command.Kind.POSSESS, Command.Kind.RELEASE, Command.Kind.REQUEST_POSSESS, Command.Kind.SURRENDER]:
		var _r: Command = _round_trip(CommandPayload.simple(1, k, 0x20009))
		assert_object(CommandCodec.decode_payload(k, 1, PackedByteArray([0]))).is_null()


func test_set_rally_vec3q_and_sim_form() -> void:
	var p: Vector3 = _q(Vector3(0.3, 0.5, 1.0), 250.0)
	var cmd: Command = Command.set_rally(1, 0x20010, p)
	var w: PackedByteArray = _wire(cmd)
	assert_int(w.size()).is_equal(8)
	assert_int(w.decode_u64(0)).is_equal(Codec.quantize_pos(p))
	var back: Command = _round_trip(cmd)
	assert_bool(CommandPayload.v3_at(back.payload, 0).is_equal_approx(p)).is_true()
	# an unquantised sim position decodes within the 04 s3.2 quanta
	var raw: Vector3 = Vector3(0.3, 0.5, 1.0).normalized() * (Sphere.PLANET_RADIUS + 250.03)
	var q: Command = CommandCodec.decode_payload(Command.Kind.SET_RALLY, 5, _wire(Command.set_rally(1, 5, raw)))
	assert_float(CommandPayload.v3_at(q.payload, 0).distance_to(raw)).is_less(0.1)
	assert_object(CommandCodec.decode_payload(Command.Kind.SET_RALLY, 5, PackedByteArray([1, 2, 3]))).is_null()
	var out: PackedByteArray = PackedByteArray()
	assert_bool(CommandCodec.encode_payload(Command.set_rally(1, 5, Vector3(INF, 0.0, 0.0)), out)).is_false()
	assert_bool(CommandCodec.encode_payload(Command.set_rally(1, 5, Vector3(NAN, 1.0, 1.0)), out)).is_false()


func test_toggle_auto_replenish() -> void:
	var roster: PackedInt32Array = PackedInt32Array([4, 3, 9, 250])
	var _a: Command = _round_trip(Command.toggle_auto_replenish(1, 0x20011, true, roster))
	var _b: Command = _round_trip(Command.toggle_auto_replenish(1, 0x20011, false, PackedInt32Array()))
	var full: PackedInt32Array = PackedInt32Array()
	for i: int in 8:
		full.append_array(PackedInt32Array([i + 1, i + 1]))
	var c: Command = _round_trip(Command.toggle_auto_replenish(1, 0x20011, true, full))
	assert_int(c.payload.size()).is_equal(25)
	full.append_array(PackedInt32Array([9, 9]))
	var out: PackedByteArray = PackedByteArray()
	assert_bool(CommandCodec.encode_payload(Command.toggle_auto_replenish(1, 5, true, full), out)).is_false()
	var w: PackedByteArray = _wire(Command.toggle_auto_replenish(1, 5, true, roster))
	assert_object(CommandCodec.decode_payload(11, 5, w.slice(0, 5))).is_null()
	w[0] = 2
	assert_object(CommandCodec.decode_payload(11, 5, w)).is_null()


func test_set_adjutant() -> void:
	var _a: Command = _round_trip(Command.set_adjutant(1, true, 2, 0x0F))
	var w: PackedByteArray = _wire(Command.set_adjutant(1, true, 1, 3))
	w[0] = 7   # any non-zero byte is enabled, as in the sim
	assert_object(CommandCodec.decode_payload(13, 0, w)).is_not_null()
	w[1] = 3
	assert_object(CommandCodec.decode_payload(13, 0, w)).is_null()
	assert_object(CommandCodec.decode_payload(13, 0, w.slice(0, 2))).is_null()


func test_debug_kinds_round_trip() -> void:
	var _a: Command = _round_trip(CommandPayload.debug_spawn(0, 3, 1, 1, Vector3(1, 2, 3), Vector3.ZERO, Vector3.FORWARD))
	var _b: Command = _round_trip(CommandPayload.debug_set(0, 0x20012, CommandPayload.SET_KILL, 1.5))
	var w: PackedByteArray = _wire(CommandPayload.debug_set(0, 5, 0, 1.0))
	w[0] = 3
	assert_object(CommandCodec.decode_payload(15, 5, w)).is_null()
	assert_object(CommandCodec.decode_payload(14, 0, PackedByteArray([1, 2]))).is_null()


func test_pilot_input_is_never_a_command() -> void:
	var out: PackedByteArray = PackedByteArray()
	assert_bool(CommandCodec.encode_payload(Command.pilot(1, 10, PilotInput.new()), out)).is_false()
	assert_object(CommandCodec.decode_payload(Command.Kind.PILOT_INPUT, 0, PackedByteArray())).is_null()
	assert_object(CommandCodec.decode_payload(16, 0, PackedByteArray())).is_null()
	assert_object(CommandCodec.decode_payload(-1, 0, PackedByteArray())).is_null()


func test_message_envelope() -> void:
	var cmd: Command = Command.produce(1, 0x20005, 7, 2)
	var msg: PackedByteArray = CommandCodec.encode_message(0x1FFFF, 123456, cmd)
	assert_int(msg.size()).is_equal(CommandCodec.HEADER_BYTES + 3)
	assert_int(msg[0]).is_equal(Protocol.COMMAND)
	assert_int(CommandCodec.seq_of(msg)).is_equal(0xFFFF)
	var back: Command = CommandCodec.decode_message(msg)
	assert_object(back).is_not_null()
	assert_int(back.tick).is_equal(123456)
	assert_int(back.target).is_equal(0x20005)
	assert_array(back.payload).is_equal(cmd.payload)
	var big: PackedByteArray = CommandCodec.encode_message(1, 1, Command.order(1, _ids(32), _patrol(14)))
	assert_int(big.size()).is_equal(CommandCodec.HEADER_BYTES + 249)
	assert_bool(big.size() <= Protocol.max_bytes(Protocol.COMMAND)).is_true()
	assert_object(CommandCodec.decode_message(msg.slice(0, msg.size() - 1))).is_null()
	var wrong: PackedByteArray = msg.duplicate()
	wrong[0] = Protocol.INPUT
	assert_object(CommandCodec.decode_message(wrong)).is_null()
	assert_object(CommandCodec.decode_message(PackedByteArray())).is_null()


## Cross-check: every sim builder's bytes survive sim -> wire -> sim unchanged, and for kinds without positions the
## wire bytes are the sim bytes.
func test_every_sim_builder_matches_net_bytes() -> void:
	var cmds: Array[Command] = [
		Command.order(1, _ids(4), OrderSpec.make(OrderSpec.Kind.ATTACK, 9, _q(Vector3(1.0, 0.2, 0.1), 500.0), OrderSpec.FLAG_LOW)),
		Command.order(1, _ids(2), _patrol(5)),
		Command.order(1, _ids(2), OrderSpec.make(OrderSpec.Kind.HAUL, 3)),
		Command.order(1, _ids(2), OrderSpec.make(OrderSpec.Kind.ESCORT, 3)),
		Command.build(1, 5, 77, 2), Command.produce(1, 6, 8, 3), CommandPayload.cancel_build(1, 6),
		CommandPayload.cancel_produce(1, 6, 1), Command.set_rally(1, 6, _q(Vector3.ONE, 100.0)),
		Command.possess(1, 8), Command.release(1), CommandPayload.simple(1, Command.Kind.REQUEST_POSSESS, 9),
		CommandPayload.handover(1, 9, 2), Command.toggle_auto_replenish(1, 6, true, PackedInt32Array([3, 2])),
		CommandPayload.simple(1, Command.Kind.SURRENDER, 0), Command.set_adjutant(1, true, 0, 5),
		CommandPayload.debug_spawn(0, 3, 1, 1, Vector3.ONE, Vector3.ZERO, Vector3.UP), CommandPayload.debug_set(0, 9, 1, 2.0),
	]
	var seen: Dictionary = {}
	for c: Command in cmds:
		seen[c.kind] = true
		var w: PackedByteArray = _wire(c)
		if c.kind != Command.Kind.ORDER and c.kind != Command.Kind.SET_RALLY:
			assert_array(w).is_equal(c.payload)
		var _b: Command = _round_trip(c)
		assert_bool(w.size() <= Protocol.COMMAND_PAYLOAD_MAX).is_true()
	seen[Command.Kind.PILOT_INPUT] = true   # refused both ways: test_pilot_input_is_never_a_command
	assert_int(seen.size()).is_equal(CommandCodec.KIND_COUNT)




## ORDER points keep the 04 s3.2 bounds (N7: e, n <= 2.0 cm, u <= 3.1 cm per axis, so < 0.05 m in 3D) over raw positions.
func test_raw_order_point_error_bound() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 11
	var worst: float = 0.0
	for i: int in 400:
		var dir: Vector3 = Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)).normalized()
		var raw: Vector3 = dir * (Sphere.PLANET_RADIUS + rng.randf_range(-400.0, 3000.0))
		var spec: OrderSpec = OrderSpec.make(OrderSpec.Kind.MOVE, 0, raw)
		var back: Command = CommandCodec.decode_payload(0, 0, _wire(Command.order(1, _ids(1), spec)))
		assert_object(back).is_not_null()
		worst = maxf(worst, CommandPayload.v3_at(back.payload, 13).distance_to(raw))
	assert_float(worst).is_less(0.05)


func _valid_commands() -> Array[Command]:
	var esc: OrderSpec = OrderSpec.make(OrderSpec.Kind.ESCORT, 3)
	esc.escort_mode = OrderSpec.EscortMode.FOCUS
	esc.focus = 0x20001
	var cmds: Array[Command] = [
		Command.order(1, _ids(4), OrderSpec.make(OrderSpec.Kind.ATTACK, 9, _q(Vector3(1.0, 0.2, 0.1), 500.0))),
		Command.order(1, _ids(32), _patrol(5)), Command.order(1, _ids(3), esc),
		Command.build(1, 5, 77, 2), Command.produce(1, 6, 8, 3), CommandPayload.cancel_build(1, 6),
		CommandPayload.cancel_produce(1, 6, 1), Command.set_rally(1, 6, _q(Vector3.ONE, 100.0)),
		Command.possess(1, 8), Command.release(1), CommandPayload.simple(1, Command.Kind.REQUEST_POSSESS, 9),
		CommandPayload.handover(1, 9, 2), Command.toggle_auto_replenish(1, 6, true, PackedInt32Array([3, 2, 4, 1])),
		CommandPayload.simple(1, Command.Kind.SURRENDER, 0), Command.set_adjutant(1, true, 0, 5),
		CommandPayload.debug_spawn(0, 3, 1, 1, Vector3.ONE, Vector3.ZERO, Vector3.UP), CommandPayload.debug_set(0, 9, 1, 2.0),
	]
	return cmds


## Equal sim commands; positions within 0.1 m (a point on a cell border may re-quantise into the neighbour cell).
func _assert_same_command(a: Command, b: Command) -> void:
	assert_object(b).is_not_null()
	assert_int(b.payload.size()).is_equal(a.payload.size())
	if a.kind != Command.Kind.ORDER and a.kind != Command.Kind.SET_RALLY:
		assert_array(b.payload).is_equal(a.payload)
		return
	var head: int = 0
	var np: int = 1
	if a.kind == Command.Kind.ORDER:
		head = 9 + 4 * a.payload[3]
		np = a.payload[head - 1]
	assert_array(b.payload.slice(0, head)).is_equal(a.payload.slice(0, head))
	for k: int in np:
		assert_float(CommandPayload.v3_at(a.payload, head + 24 * k).distance_to(CommandPayload.v3_at(b.payload, head + 24 * k))).is_less(0.1)
	var tail: int = head + 24 * np
	assert_array(b.payload.slice(tail)).is_equal(a.payload.slice(tail))


func _mutate(rng: RandomNumberGenerator, src: PackedByteArray) -> PackedByteArray:
	var b: PackedByteArray = src.duplicate()
	match rng.randi_range(0, 3):
		0:
			for _k: int in rng.randi_range(1, 3):
				if b.size() > 0:
					b[rng.randi_range(0, b.size() - 1)] = rng.randi() & 0xFF
		1:
			var _r: int = b.resize(rng.randi_range(0, b.size()))
		2:
			for _k: int in rng.randi_range(1, 8):
				var _a: bool = b.push_back(rng.randi() & 0xFF)
		_:
			if b.size() > 0:
				var at: int = rng.randi_range(0, b.size() - 1)
				b[at] = b[at] ^ (1 << rng.randi_range(0, 7))
	return b


## Seeded mutation sweep per kind (NET-23 owns the 100,000-per-id run): byte flips, truncations and extensions of valid
## payloads and messages never throw; every non-null result re-encodes, and the re-encoding is a fixed point.
func test_mutation_sweep_per_kind() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 20260421
	var accepted: int = 0
	var rejected: int = 0
	for cmd: Command in _valid_commands():
		var wire: PackedByteArray = _wire(cmd)
		var msg: PackedByteArray = CommandCodec.encode_message(7, 100, cmd)
		for i: int in 2000:
			var c: Command = null
			if (i & 1) == 1:
				c = CommandCodec.decode_message(_mutate(rng, msg))
			else:
				c = CommandCodec.decode_payload(cmd.kind, cmd.target, _mutate(rng, wire))
			if c == null:
				rejected += 1
				continue
			accepted += 1
			var w2: PackedByteArray = PackedByteArray()
			assert_bool(CommandCodec.encode_payload(c, w2)).is_true()
			assert_bool(w2.size() <= Protocol.COMMAND_PAYLOAD_MAX).is_true()
			var c2: Command = CommandCodec.decode_payload(c.kind, c.target, w2)
			assert_object(c2).is_not_null()
			assert_int(c2.kind).is_equal(c.kind)
			assert_int(c2.target).is_equal(c.target)
			assert_int(c2.payload.size()).is_equal(c.payload.size())
			if c.kind != Command.Kind.ORDER and c.kind != Command.Kind.SET_RALLY:
				assert_array(c2.payload).is_equal(c.payload)
			var w3: PackedByteArray = PackedByteArray()
			assert_bool(CommandCodec.encode_payload(c2, w3)).is_true()
			_assert_same_command(c2, CommandCodec.decode_payload(c2.kind, c2.target, w3))
	assert_int(accepted).is_greater(1000)
	assert_int(rejected).is_greater(1000)


## Raw random bytes, with the COMMAND id forced on half of them, never throw.
func test_random_bytes_never_throw() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 4
	for i: int in 3000:
		var b: PackedByteArray = PackedByteArray()
		var _r: int = b.resize(rng.randi_range(0, 300))
		for j: int in b.size():
			b[j] = rng.randi() & 0xFF
		if b.size() > 0 and (i & 1) == 0:
			b[0] = Protocol.COMMAND
		var _c: Command = CommandCodec.decode_payload(rng.randi_range(-2, 18), rng.randi(), b)
		var _m: Command = CommandCodec.decode_message(b)
