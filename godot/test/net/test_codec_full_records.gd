extends GdUnitTestSuite
## NET-02, net layer: 400 FULL-record bodies (04 s3.4: vec3q, quat_s3, vel, hp, flags, ai_tag for own
## team) written back to back with the Codec byte helpers, then read back. Sizes match 04, every field
## decodes within its 04 s3.3 bound, and reads at every offset of a truncated buffer return the
## sentinel instead of erroring.

const N: int = 400
const BODY: int = Codec.POS_BYTES + Codec.QUAT_BYTES + Codec.VEL_BYTES + Codec.HP_BYTES + Codec.FLAGS_BYTES


func _write_body(buf: PackedByteArray, at: int, p: Vector3, q: Quaternion, v: Vector3, hp: float, flags: int) -> int:
	var qp: int = Codec.quantize_pos(p)
	var o: int = Codec.write_pos(buf, at, qp)
	o = Codec.write_u32(buf, o, Codec.quantize_quat(q))
	o = Codec.write_u24(buf, o, Codec.quantize_vel(v, Codec.pos_cell(qp)))
	buf[o] = Codec.quantize_hp(hp)
	buf[o + 1] = flags
	return o + 2


func test_400_full_records_round_trip() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 2
	var pos: PackedVector3Array = PackedVector3Array()
	var vel: PackedVector3Array = PackedVector3Array()
	var rot: Array[Quaternion] = []
	var buf: PackedByteArray = PackedByteArray()
	var _r: int = buf.resize(N * (BODY + Codec.AI_TAG_BYTES))
	var at: int = 0
	for i: int in N:
		var p: Vector3 = Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized() \
				* (Sphere.PLANET_RADIUS + rng.randf_range(Sphere.RELIEF_MIN, 800.0))
		var v: Vector3 = Vector3(rng.randf_range(-150.0, 150.0), rng.randf_range(-150.0, 150.0), rng.randf_range(-60.0, 60.0))
		var q: Quaternion = Quaternion(rng.randfn(), rng.randfn(), rng.randfn(), rng.randfn()).normalized()
		var _a: bool = pos.push_back(p)
		var _b: bool = vel.push_back(v)
		rot.append(q)
		at = _write_body(buf, at, p, q, v, float(i % 101) / 100.0, Codec.make_flags(i % 3, (i * 4) & 0xFC))
		buf[at] = Codec.quantize_ai_tag(i & 0xFF)
		at += Codec.AI_TAG_BYTES
	assert_int(BODY + 2).is_equal(Codec.FULL_RECORD_BYTES)
	assert_int(at).is_equal(N * (Codec.FULL_RECORD_BYTES - 2 + Codec.AI_TAG_BYTES))
	var worst_p: float = 0.0
	var worst_q: float = 0.0
	var worst_v: float = 0.0
	var wrong: int = 0
	at = 0
	for i: int in N:
		var qp: int = Codec.read_pos(buf, at)
		var cell: int = Codec.pos_cell(qp)
		worst_p = maxf(worst_p, Codec.dequantize_pos(qp).distance_to(pos[i]))
		var q: Quaternion = Codec.dequantize_quat(Codec.read_u32(buf, at + Codec.POS_BYTES))
		worst_q = maxf(worst_q, rad_to_deg(2.0 * acos(minf(1.0, absf(q.dot(rot[i]))))))
		var v: Vector3 = Codec.dequantize_vel(Codec.read_u24(buf, at + Codec.POS_BYTES + Codec.QUAT_BYTES), cell)
		var dv: Vector3 = Codec.cell_frame(cell).transposed() * (v - vel[i])
		worst_v = maxf(worst_v, maxf(absf(dv.x), maxf(absf(dv.y), absf(dv.z))))
		var o: int = at + Codec.POS_BYTES + Codec.QUAT_BYTES + Codec.VEL_BYTES
		if absf(Codec.dequantize_hp(buf[o]) - float(i % 101) / 100.0) > 0.5 / 255.0 + 1e-6:
			wrong += 1
		if Codec.flags_control(buf[o + 1]) != i % 3 or buf[o + 2] != i & 0xFF:
			wrong += 1
		at += BODY + Codec.AI_TAG_BYTES
	assert_int(wrong).is_equal(0)
	# 3-D bounds: sqrt(2 * (half e/n quantum)^2 + (half u quantum)^2) + float32 slack; quat 0.4 deg; vel 1 m/s.
	var he: float = Codec.POS_EN_QUANTUM * 0.5
	var hu: float = Codec.POS_U_QUANTUM * 0.5
	assert_float(worst_p).is_less_equal(sqrt(2.0 * he * he + hu * hu) + 0.001)
	assert_float(worst_q).is_less_equal(0.4)
	assert_float(worst_v).is_less_equal(1.001)


func test_reads_on_truncated_buffers_return_sentinels() -> void:
	var buf: PackedByteArray = PackedByteArray()
	for size: int in 12:
		var _r: int = buf.resize(size)
		buf.fill(0x01)
		for at: int in range(-2, size + 2):
			var fits_pos: bool = at >= 0 and at + Codec.POS_BYTES <= size
			assert_bool(Codec.read_pos(buf, at) != Codec.POS_INVALID).is_equal(fits_pos)
			assert_bool(Codec.read_u32(buf, at) >= 0).is_equal(at >= 0 and at + 4 <= size)
			assert_bool(Codec.read_u24(buf, at) >= 0).is_equal(at >= 0 and at + 3 <= size)
