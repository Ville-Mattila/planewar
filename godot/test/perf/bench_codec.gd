extends SceneTree
## NET-02 micro-benchmark: quantise and dequantise 400 entities (position, full and coarse orientation,
## velocity, hp, flags) through net/codec.gd, i.e. one FULL record's fields per entity, plus the byte
## writes/reads of a 19-byte FULL body. godot --headless --path godot -s res://test/perf/bench_codec.gd
## Prints: BENCH_CODEC n=400 enc_us=.. dec_us=.. enc_per_entity_us=.. dec_per_entity_us=.. (best of ROUNDS)
## plus the measured round-trip maxima over the same 400 entities.

const ROUNDS: int = 30
const N: int = 400


func _init() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 400
	var pos: PackedVector3Array = PackedVector3Array()
	var vel: PackedVector3Array = PackedVector3Array()
	var rot: Array[Quaternion] = []
	var hp: PackedFloat32Array = PackedFloat32Array()
	for i: int in N:
		var d: Vector3 = Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized()
		var _a: bool = pos.push_back(d * (Sphere.PLANET_RADIUS + rng.randf_range(Sphere.RELIEF_MIN, 800.0)))
		var _b: bool = vel.push_back(Vector3(rng.randf_range(-200.0, 200.0), rng.randf_range(-200.0, 200.0), rng.randf_range(-50.0, 50.0)))
		rot.append(Quaternion(rng.randfn(), rng.randfn(), rng.randfn(), rng.randfn()).normalized())
		var _c: bool = hp.push_back(rng.randf())
	# Shared-cache shape (R0 C1-02): packed ints per entity.
	var q_pos: PackedInt64Array = PackedInt64Array()
	var q_rot: PackedInt64Array = PackedInt64Array()
	var q_rotc: PackedInt64Array = PackedInt64Array()
	var q_misc: PackedInt64Array = PackedInt64Array()            # vel | hp << 24 | flags << 32
	var _r1: int = q_pos.resize(N)
	var _r2: int = q_rot.resize(N)
	var _r3: int = q_rotc.resize(N)
	var _r4: int = q_misc.resize(N)
	var buf: PackedByteArray = PackedByteArray()
	var _s: int = buf.resize(N * Codec.FULL_RECORD_BYTES)
	var out_p: PackedVector3Array = PackedVector3Array()
	var _t: int = out_p.resize(N)
	var best_enc: int = 1 << 30
	var best_dec: int = 1 << 30
	for round_i: int in ROUNDS:
		var t0: int = Time.get_ticks_usec()
		for i: int in N:
			var qp: int = Codec.quantize_pos(pos[i])
			q_pos[i] = qp
			q_rot[i] = Codec.quantize_quat(rot[i])
			q_rotc[i] = Codec.quantize_quat_coarse(rot[i], 0)
			q_misc[i] = Codec.quantize_vel(vel[i], qp & 0xFFFF) | (Codec.quantize_hp(hp[i]) << 24) \
					| (Codec.make_flags(1, Codec.FLAG_FIRING) << 32)
			var at: int = i * Codec.FULL_RECORD_BYTES + 2
			at = Codec.write_pos(buf, at, qp)
			at = Codec.write_u32(buf, at, q_rot[i])
			at = Codec.write_u24(buf, at, q_misc[i])
			buf[at] = (q_misc[i] >> 24) & 0xFF
			buf[at + 1] = (q_misc[i] >> 32) & 0xFF
		var t1: int = Time.get_ticks_usec()
		for i: int in N:
			var at: int = i * Codec.FULL_RECORD_BYTES + 2
			var qp: int = Codec.read_pos(buf, at)
			out_p[i] = Codec.dequantize_pos(qp)
			var _q: Quaternion = Codec.dequantize_quat(Codec.read_u32(buf, at + 8))
			var _qc: Quaternion = Codec.dequantize_quat_coarse(q_rotc[i])
			var _v: Vector3 = Codec.dequantize_vel(Codec.read_u24(buf, at + 12), qp & 0xFFFF)
			var _h: float = Codec.dequantize_hp(buf[at + 15])
		var t2: int = Time.get_ticks_usec()
		best_enc = mini(best_enc, t1 - t0)
		best_dec = mini(best_dec, t2 - t1)
	var wp: float = 0.0
	var wq: float = 0.0
	var wc: float = 0.0
	for i: int in N:
		wp = maxf(wp, out_p[i].distance_to(pos[i]))
		wq = maxf(wq, rad_to_deg(2.0 * acos(minf(1.0, absf(rot[i].dot(Codec.dequantize_quat(q_rot[i])))))))
		wc = maxf(wc, rad_to_deg(2.0 * acos(minf(1.0, absf(rot[i].dot(Codec.dequantize_quat_coarse(q_rotc[i])))))))
	print("BENCH_CODEC n=%d enc_us=%d dec_us=%d enc_per_entity_us=%.2f dec_per_entity_us=%.2f max_pos_err_m=%.4f max_quat_deg=%.3f max_coarse_deg=%.3f" % [
		N, best_enc, best_dec, float(best_enc) / N, float(best_dec) / N, wp, wq, wc])
	quit(0)
