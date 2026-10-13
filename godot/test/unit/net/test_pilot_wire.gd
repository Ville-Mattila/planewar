extends GdUnitTestSuite
## NET-03: PilotWire byte round trip, reserved bytes (R0 C2-09), INPUT packet shape and V-INP shape checks.


func _mk(t: float, p: float, y: float, r: float, b: int) -> PilotInput:
	var i: PilotInput = PilotInput.new()
	i.thrust = t
	i.pitch = p
	i.yaw = y
	i.roll = r
	i.buttons = b
	return i


func test_all_wire_bytes_round_trip_bit_exact() -> void:
	# every byte value of every field survives bytes -> input -> bytes
	for v: int in 256:
		var b: PackedByteArray = PackedByteArray([v, v, v, v, v & 0x7F, 0, 0, 77])
		var p: PilotInput = PilotWire.from_wire(b, 0)
		var back: PackedByteArray = PilotWire.to_wire(p, 77)
		var expect: PackedByteArray = b.duplicate()
		for k: int in [1, 2, 3]:
			if v == 128:
				expect[k] = 129          # i8 -128 is not produced by the encoder; decodes as -1.0 = -127
		assert_array(back).is_equal(expect)


func test_quantised_values_and_clamping() -> void:
	var b: PackedByteArray = PilotWire.to_wire(_mk(2.0, -3.0, 0.5, -0.5, 0xFF), 300)
	assert_int(b.size()).is_equal(8)
	assert_int(b[0]).is_equal(255)
	assert_int(b[1]).is_equal(0x81)                 # -127
	assert_int(b[2]).is_equal(64)                   # round(63.5) = 64
	assert_int(b[3]).is_equal(0xC0)                 # -64
	assert_int(b[4]).is_equal(0x7F)                 # bit 7 reserved, masked
	assert_int(b[5]).is_equal(0)
	assert_int(b[6]).is_equal(0)
	assert_int(b[7]).is_equal(300 & 0xFF)
	var p: PilotInput = PilotWire.quantized(_mk(0.3, 0.3, -0.3, 1.0, PilotInput.FIRE1))
	assert_float(p.thrust).is_equal_approx(0.3, 1.0 / 255.0)
	assert_float(p.pitch).is_equal_approx(0.3, 1.0 / 127.0)
	assert_float(p.roll).is_equal(1.0)
	var again: PilotInput = PilotWire.quantized(p)
	assert_float(again.thrust).is_equal(p.thrust)    # idempotent: prediction == server view
	assert_float(again.yaw).is_equal(p.yaw)


func test_short_buffers() -> void:
	assert_object(PilotWire.from_wire(PackedByteArray([1, 2, 3]), 0)).is_null()
	assert_object(PilotWire.from_wire(PilotWire.to_wire(PilotInput.new(), 0), 1)).is_null()
	var small: PackedByteArray = PackedByteArray()
	assert_int(PilotWire.write_into(small, 0, PilotInput.new(), 0)).is_equal(-1)


func _packet(base: int, n: int) -> PackedByteArray:
	var arr: Array[PilotInput] = []
	for i: int in n:
		arr.append(_mk(0.5, 0.1 * float(i), 0.0, 0.0, 0))
	return InputCodec.encode(9, base, 1234, arr, n)


func test_input_packet_layout_and_size() -> void:
	var b: PackedByteArray = _packet(1000, 3)
	assert_int(b.size()).is_equal(36)                          # 04 s2.3 INPUT max
	assert_int(b.size()).is_equal(Protocol.max_bytes(Protocol.INPUT))
	assert_int(b[0]).is_equal(Protocol.INPUT)
	assert_int(InputCodec.epoch_of(b)).is_equal(9)
	assert_int(InputCodec.base_tick_of(b)).is_equal(1000)
	assert_int(InputCodec.ack_tick_of(b)).is_equal(1234)
	assert_int(InputCodec.count_of(b)).is_equal(3)
	assert_int(InputCodec.validate(b)).is_equal(InputCodec.Status.OK)
	assert_int(_packet(5, 1).size()).is_equal(20)
	assert_int(_packet(5, 4).size()).is_equal(0)
	assert_int(_packet(5, 0).size()).is_equal(0)


func test_validate_rejects_reserved_bytes_tick_lo_count_and_length() -> void:
	for off: int in [5, 6]:
		for k: int in 3:
			var b: PackedByteArray = _packet(1000, 3)
			b[InputCodec.HEADER_BYTES + k * 8 + off] = 1
			assert_int(InputCodec.validate(b)).is_equal(InputCodec.Status.MALFORMED)
	var t: PackedByteArray = _packet(1000, 3)
	t[InputCodec.HEADER_BYTES + 8 + 7] += 1
	assert_int(InputCodec.validate(t)).is_equal(InputCodec.Status.MALFORMED)
	var c: PackedByteArray = _packet(1000, 3)
	c[InputCodec.OFF_COUNT] = 4
	assert_int(InputCodec.validate(c)).is_equal(InputCodec.Status.MALFORMED)
	c[InputCodec.OFF_COUNT] = 0
	assert_int(InputCodec.validate(c)).is_equal(InputCodec.Status.MALFORMED)
	var s: PackedByteArray = _packet(1000, 3)
	var _r: Error = s.resize(35)
	assert_int(InputCodec.validate(s)).is_equal(InputCodec.Status.MALFORMED)
	var w: PackedByteArray = _packet(1000, 3)
	w[0] = Protocol.PING
	assert_int(InputCodec.validate(w)).is_equal(InputCodec.Status.MALFORMED)
	assert_int(InputCodec.validate(PackedByteArray())).is_equal(InputCodec.Status.MALFORMED)


func test_validate_survives_random_mutations() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 3
	var buf: InputBuffer = InputBuffer.new()
	buf.begin_epoch(9)
	for n: int in 20000:
		var b: PackedByteArray = _packet(1000, 1 + n % 3)
		for m: int in 1 + n % 4:
			b[rng.randi() % b.size()] = rng.randi() & 0xFF
		if n % 7 == 0:
			var _r: Error = b.resize(rng.randi() % 40)
		var _s: int = buf.submit(b, 1000)
	assert_int(buf.rejected_malformed + buf.rejected_epoch + buf.accepted + buf.duplicates + buf.rejected_window).is_greater(0)
