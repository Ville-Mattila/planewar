extends GdUnitTestSuite
## Command builders and CommandPayload readers (TA-18): the sim form of 04 s2.5 round-trips exactly (f64 positions
## and pilot axes), malformed payloads are detected, the builders set kind / player / target.


func test_order_round_trip_move_and_patrol() -> void:
	var p: Vector3 = Vector3(6100.125, -3.5, 12.0625)
	var cmd: Command = Command.order(2, PackedInt32Array([EntityId.make(7, 3), EntityId.make(1279, EntityId.GEN_MAX)]),
		OrderSpec.make(OrderSpec.Kind.MOVE, EntityId.make(9, 1), p, OrderSpec.FLAG_QUEUE))
	assert_int(cmd.kind).is_equal(Command.Kind.ORDER)
	assert_int(cmd.player).is_equal(2)
	var spec: OrderSpec = OrderSpec.new()
	var ids: PackedInt32Array = PackedInt32Array()
	assert_bool(CommandPayload.read_order(cmd, spec, ids)).is_true()
	assert_int(ids[0]).is_equal(EntityId.make(7, 3))
	assert_int(ids[1]).is_equal(EntityId.make(1279, EntityId.GEN_MAX))   # bit 31 clear: i32 storage is exact (A-48)
	assert_int(EntityId.gen(ids[1])).is_equal(EntityId.GEN_MAX)
	assert_int(EntityId.slot(ids[1])).is_equal(1279)
	assert_int(spec.kind).is_equal(OrderSpec.Kind.MOVE)
	assert_int(spec.flags).is_equal(OrderSpec.FLAG_QUEUE)
	assert_int(spec.target).is_equal(EntityId.make(9, 1))
	assert_vector(spec.point).is_equal(p)
	var patrol: OrderSpec = OrderSpec.make(OrderSpec.Kind.PATROL)
	patrol.points = PackedVector3Array([Vector3(1, 2, 3), Vector3(4, 5, 6), Vector3(7, 8, 9)])
	assert_bool(CommandPayload.read_order(Command.order(0, PackedInt32Array([5]), patrol), spec, ids)).is_true()
	assert_array(Array(spec.points)).is_equal([Vector3(1, 2, 3), Vector3(4, 5, 6), Vector3(7, 8, 9)])
	assert_vector(spec.point).is_equal(Vector3.ZERO)


func test_order_malformed_payloads() -> void:
	var spec: OrderSpec = OrderSpec.new()
	var ids: PackedInt32Array = PackedInt32Array()
	var good: Command = Command.order(0, PackedInt32Array([5]), OrderSpec.make(OrderSpec.Kind.HOLD))
	var short: Command = CommandPayload.simple(0, Command.Kind.ORDER, 0)
	short.payload = good.payload.slice(0, good.payload.size() - 1)
	assert_bool(CommandPayload.read_order(short, spec, ids)).is_false()
	var none: Command = Command.order(0, PackedInt32Array(), OrderSpec.make(OrderSpec.Kind.HOLD))
	assert_bool(CommandPayload.read_order(none, spec, ids)).is_false()
	var big: Command = Command.order(0, PackedInt32Array([5]), OrderSpec.make(OrderSpec.Kind.HOLD))
	big.payload[0] = OrderSpec.KIND_COUNT
	assert_bool(CommandPayload.read_order(big, spec, ids)).is_false()


func test_pilot_round_trip_is_exact() -> void:
	var inp: PilotInput = PilotInput.new()
	inp.thrust = 0.123456789
	inp.pitch = -0.987654321
	inp.yaw = 1.0 / 3.0
	inp.roll = -1.0
	inp.buttons = PilotInput.BOOST | PilotInput.FIRE2 | PilotInput.RELEASE
	var cmd: Command = Command.pilot(3, 1234, inp)
	assert_int(cmd.tick).is_equal(1234)
	var out: PilotInput = PilotInput.new()
	assert_bool(CommandPayload.read_pilot(cmd, out)).is_true()
	assert_float(out.thrust).is_equal(inp.thrust)
	assert_float(out.pitch).is_equal(inp.pitch)
	assert_float(out.yaw).is_equal(inp.yaw)
	assert_float(out.roll).is_equal(inp.roll)
	assert_int(out.buttons).is_equal(inp.buttons)
	cmd.payload.resize(10)
	assert_bool(CommandPayload.read_pilot(cmd, out)).is_false()


func test_builders_and_scalar_readers() -> void:
	var b: Command = Command.build(1, 600, 123456, 3)
	assert_int(CommandPayload.u16_at(b, 0)).is_equal(600)
	assert_int(CommandPayload.u32_at(b, 2)).is_equal(123456)
	assert_int(CommandPayload.u8_at(b, 6)).is_equal(3)
	assert_int(CommandPayload.u8_at(b, 7)).is_equal(-1)
	assert_int(CommandPayload.u32_at(b, 5)).is_equal(-1)
	var pr: Command = Command.produce(0, EntityId.make(3, 1), 2, 4)
	assert_int(pr.target).is_equal(EntityId.make(3, 1))
	assert_int(CommandPayload.u16_at(pr, 0)).is_equal(2)
	assert_int(CommandPayload.u8_at(pr, 2)).is_equal(4)
	assert_int(Command.possess(4, 77).target).is_equal(77)
	assert_int(Command.release(4).kind).is_equal(Command.Kind.RELEASE)
	var adj: Command = Command.set_adjutant(1, true, 2, 9)
	assert_array(Array(adj.payload)).is_equal([1, 2, 9])
	var h: Command = CommandPayload.handover(0, 55, 6)
	assert_int(h.kind).is_equal(Command.Kind.HANDOVER)
	assert_int(CommandPayload.u8_at(h, 0)).is_equal(6)
	var cp: Command = CommandPayload.cancel_produce(0, 9, 2)
	assert_int(cp.kind).is_equal(Command.Kind.CANCEL_PRODUCE)
	var sp: Command = CommandPayload.debug_spawn(0, 1, 2, 3, Vector3(1.5, 2.5, 3.5), Vector3(-1, 0, 1), Vector3(0, 1, 0))
	assert_int(sp.payload.size()).is_equal(CommandPayload.DEBUG_SPAWN_BYTES)
	assert_vector(CommandPayload.v3_at(sp.payload, 4)).is_equal(Vector3(1.5, 2.5, 3.5))
	assert_vector(CommandPayload.v3_at(sp.payload, 28)).is_equal(Vector3(-1, 0, 1))
	var ds: Command = CommandPayload.debug_set(0, 12, CommandPayload.SET_FUEL, 7.25)
	assert_int(ds.payload.size()).is_equal(CommandPayload.DEBUG_SET_BYTES)
	assert_float(ds.payload.decode_double(1)).is_equal(7.25)
