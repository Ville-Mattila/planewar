extends GdUnitTestSuite
## NET-02 codec_roundtrip_test: every quantiser of net/codec.gd round-trips within its 04 s3.2/s3.3 bound
## at 10,000 random samples plus structured cases (cell corners and edge midpoints of all 384 interest
## cells, cube edges and corners, adversarial quaternions) over the whole flight envelope, RELIEF_MIN to
## rules.json ceiling_hard_m (R0 B.9 A-23). Bounds:
##   e, n <= 2.0 cm (half of 3.906 cm), u <= 3.1 cm (half of 6.25 cm), full quat <= 0.4 deg,
##   coarse quat <= 6 deg, velocity <= 1 m/s per ENU axis, hp <= 0.5/255.
## Position errors are measured on the decoded float32 Vector3, so they include float32 storage at
## |p| <= 8,192 m (half-ulp 0.24 mm per component, <= 0.42 mm on any axis): F32_SLACK. The e/n bound is
## the flat 2.0 cm of A-23 (1.953 cm + 0.42 mm fits under it).

const SAMPLES: int = 10000
const F32_SLACK: float = 0.0005
const EN_BOUND: float = 0.020                                       # A-23: horizontal error <= 2.0 cm
const U_BOUND: float = Codec.POS_U_QUANTUM * 0.5 + F32_SLACK       # 3.125 cm (04: "<= 3.1 cm") + slack
const RULES_JSON: String = "res://content/defs/rules.json"
const FULL_DEG: float = 0.4
const COARSE_DEG: float = 6.0

var _rng: RandomNumberGenerator
var _ceiling: float = Sphere.CEILING_HARD


func before_test() -> void:
	_rng = RandomNumberGenerator.new()
	_rng.seed = 0x5EED
	_ceiling = _rules_ceiling_hard()


## ceiling_hard_m from rules.json (the def is the source of truth; Sphere.CEILING_HARD mirrors it).
func _rules_ceiling_hard() -> float:
	var f: FileAccess = FileAccess.open(RULES_JSON, FileAccess.READ)
	if f == null:
		return Sphere.CEILING_HARD
	var d: Variant = JSON.parse_string(f.get_as_text())
	if d is Dictionary:
		var dict: Dictionary = d
		return float(dict.get("ceiling_hard_m", Sphere.CEILING_HARD))
	return Sphere.CEILING_HARD


func _rand_dir() -> Vector3:
	var z: float = _rng.randf_range(-1.0, 1.0)
	var lon: float = _rng.randf_range(-PI, PI)
	var r: float = sqrt(maxf(0.0, 1.0 - z * z))
	return Vector3(r * cos(lon), r * sin(lon), z)


func _rand_quat() -> Quaternion:
	# Uniform on S3 (Gaussian components, normalised).
	return Quaternion(_rng.randfn(), _rng.randfn(), _rng.randfn(), _rng.randfn()).normalized()


func _angle_deg(a: Quaternion, b: Quaternion) -> float:
	return rad_to_deg(2.0 * acos(minf(1.0, absf(a.dot(b)))))


## Max per-axis ENU error of a round trip, in the frame of the cell the encoder chose. Returns
## Vector3(e_err, n_err, u_err).
func _pos_err(p: Vector3) -> Vector3:
	var q: int = Codec.quantize_pos(p)
	var back: Vector3 = Codec.dequantize_pos(q)
	var f: Basis = Codec.cell_frame(Codec.pos_cell(q))
	var d: Vector3 = back - p
	return Vector3(absf(d.dot(f.x)), absf(d.dot(f.y)), absf(d.dot(f.z)))


func _check_points(points: PackedVector3Array, what: String) -> void:
	var worst: Vector3 = Vector3.ZERO
	var out_of_range: int = 0
	for p: Vector3 in points:
		if not Codec.pos_in_range(p):
			out_of_range += 1
		var e: Vector3 = _pos_err(p)
		worst = Vector3(maxf(worst.x, e.x), maxf(worst.y, e.y), maxf(worst.z, e.z))
	assert_int(out_of_range).override_failure_message(what + " points outside the vec3q box").is_equal(0)
	assert_float(worst.x).override_failure_message(what + " e").is_less_equal(EN_BOUND)
	assert_float(worst.y).override_failure_message(what + " n").is_less_equal(EN_BOUND)
	assert_float(worst.z).override_failure_message(what + " u").is_less_equal(U_BOUND)


# --- position (04 s3.2) ---------------------------------------------------------------------------

func test_pos_constants_match_04() -> void:
	assert_float(Codec.POS_EN_HALF).is_equal(1280.0)
	assert_float(Codec.POS_U_MIN).is_equal(-768.0)
	assert_float(Codec.POS_U_SPAN).is_equal(4096.0)
	assert_float(Codec.POS_EN_QUANTUM).is_equal(2560.0 / 65536.0)   # 3.906 cm
	assert_float(Codec.POS_U_QUANTUM).is_equal(0.0625)
	assert_int(Codec.CELL_COUNT).is_equal(384)
	# u covers the terrain floor and the hard ceiling above the cell centre.
	assert_float(Codec.POS_U_MIN).is_less(Sphere.RELIEF_MIN)
	assert_float(Codec.POS_U_MIN + Codec.POS_U_SPAN).is_greater(Sphere.CEILING_HARD)


func test_pos_roundtrip_10000_random_points() -> void:
	var pts: PackedVector3Array = PackedVector3Array()
	for i: int in SAMPLES:
		var _a: bool = pts.push_back(_rand_dir() * (Sphere.PLANET_RADIUS + _rng.randf_range(Sphere.RELIEF_MIN, _ceiling)))
	_check_points(pts, "random")
	# The encoder's cell is Sphere.cell_of(p, GRID_INTEREST) (04 s3.2 step 1).
	for i: int in 200:
		assert_int(Codec.pos_cell(Codec.quantize_pos(pts[i]))).is_equal(Sphere.cell_of(pts[i], Sphere.GRID_INTEREST))


func test_pos_cell_corners_and_edge_midpoints() -> void:
	var pts: PackedVector3Array = PackedVector3Array()
	var n: int = Sphere.GRID_INTEREST
	for cell: int in Codec.CELL_COUNT:
		var face: int = Sphere.cell_face(cell, n)
		var i: int = Sphere.cell_i(cell, n)
		var j: int = Sphere.cell_j(cell, n)
		for k: int in 9:
			var u: float = (float(i) + 0.5 * float(k % 3)) / float(n)
			var v: float = (float(j) + 0.5 * float(floori(float(k) / 3.0))) / float(n)
			var d: Vector3 = Sphere.face_uv_to_dir(face, u, v)
			for h: float in [Sphere.RELIEF_MIN, 0.0, _ceiling]:
				var _a: bool = pts.push_back(d * (Sphere.PLANET_RADIUS + h))
	assert_int(pts.size()).is_equal(384 * 9 * 3)
	_check_points(pts, "corners")


func test_pos_cube_edges_and_corners() -> void:
	var pts: PackedVector3Array = PackedVector3Array()
	for face: int in 6:
		for k: int in 200:
			var t: float = _rng.randf()
			var h: float = _rng.randf_range(Sphere.RELIEF_MIN, _ceiling)
			for uv: Vector2 in [Vector2(t, 0.0), Vector2(t, 1.0), Vector2(0.0, t), Vector2(1.0, t)]:
				var _a: bool = pts.push_back(Sphere.face_uv_to_dir(face, uv.x, uv.y) * (Sphere.PLANET_RADIUS + h))
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				var _b: bool = pts.push_back(Vector3(sx, sy, sz).normalized() * Sphere.PLANET_RADIUS)
	# Straddling a boundary by +-1 cm still round-trips (whichever cell cell_of picks).
	var base: Vector3 = Sphere.face_uv_to_dir(0, 0.25, 0.5) * Sphere.PLANET_RADIUS
	var across: Vector3 = Sphere.tangent_frame(base).x * 0.01
	var _c: bool = pts.push_back(base + across)
	var _d: bool = pts.push_back(base - across)
	_check_points(pts, "cube edges")


func test_pos_envelope_to_ceiling_hard() -> void:
	# A-23: every cell corner from RELIEF_MIN (-500 m) to ceiling_hard_m lies inside the vec3q box, both in
	# the frame of the cell the encoder picks (pos_in_range) and in the cell's own frame; round trips <= 2.0 cm.
	assert_float(_ceiling).is_equal(Sphere.CEILING_HARD)
	var pts: PackedVector3Array = PackedVector3Array()
	var worst_own: float = 0.0
	for cell: int in Codec.CELL_COUNT:
		var f: Basis = Codec.cell_frame(cell)
		for corner: Vector3 in Sphere.cell_bounds_dirs(cell, Sphere.GRID_INTEREST):
			for h: float in [Sphere.RELIEF_MIN, 0.0, 827.0, Sphere.CEILING_SOFT, _ceiling]:
				var p: Vector3 = corner * (Sphere.PLANET_RADIUS + h)
				var _a: bool = pts.push_back(p)
				var d: Vector3 = p - Codec.cell_centre(cell)
				worst_own = maxf(worst_own, maxf(absf(d.dot(f.x)), absf(d.dot(f.y))))
	_check_points(pts, "envelope corners")
	# Cube-corner cells reach ~1,200 m at the ceiling: inside 1,280 m with margin, and past the old 1,024 m.
	assert_float(worst_own).is_less(Codec.POS_EN_HALF - 60.0)
	assert_float(worst_own).is_greater(1150.0)
	var p_old_cq1: Vector3 = Sphere.face_uv_to_dir(0, 0.125, 0.0) * (Sphere.PLANET_RADIUS + _ceiling)
	assert_bool(Codec.pos_in_range(p_old_cq1)).is_true()
	# Above the hard ceiling clamping stays deterministic and finite.
	var high: Vector3 = Sphere.face_uv_to_dir(0, 0.0, 0.0) * (Sphere.PLANET_RADIUS + 3.0 * _ceiling)
	var back: Vector3 = Codec.dequantize_pos(Codec.quantize_pos(high))
	assert_bool(back.is_finite()).is_true()
	assert_int(Codec.quantize_pos(high)).is_equal(Codec.quantize_pos(high))


func test_pos_bit_packing_and_wire_bytes() -> void:
	var q: int = Codec.pack_pos(383, 0xFFFF, 0x1234, 0xFFFF)
	assert_array([Codec.pos_cell(q), Codec.pos_e(q), Codec.pos_n(q), Codec.pos_u(q)]).is_equal([383, 0xFFFF, 0x1234, 0xFFFF])
	var buf: PackedByteArray = PackedByteArray()
	var _r: int = buf.resize(Codec.POS_BYTES + 1)
	assert_int(Codec.write_pos(buf, 1, q)).is_equal(1 + Codec.POS_BYTES)
	# Little-endian cell u16, e u16, n u16, u u16 (04 s2.3 vec3q).
	assert_array(Array(buf)).is_equal([0, 0x7F, 0x01, 0xFF, 0xFF, 0x34, 0x12, 0xFF, 0xFF])
	assert_int(Codec.read_pos(buf, 1)).is_equal(q)
	assert_int(Codec.read_pos(buf, 2)).is_equal(Codec.POS_INVALID)       # short buffer
	assert_int(Codec.write_pos(buf, 2, q)).is_equal(-1)
	assert_int(Codec.read_pos(buf, -1)).is_equal(Codec.POS_INVALID)
	buf.encode_u16(1, Codec.CELL_COUNT)                                    # cell id 384 is invalid
	assert_int(Codec.read_pos(buf, 1)).is_equal(Codec.POS_INVALID)
	assert_bool(Codec.dequantize_pos(Codec.pack_pos(Codec.CELL_COUNT, 0, 0, 0)) == Vector3.ZERO).is_true()
	# A real point survives the byte round trip bit-exactly.
	var p: Vector3 = Sphere.from_lat_lon(0.4, -2.1, Sphere.PLANET_RADIUS + 321.0)
	var qp: int = Codec.quantize_pos(p)
	var _w: int = Codec.write_pos(buf, 0, qp)
	assert_int(Codec.read_pos(buf, 0)).is_equal(qp)


# --- orientation (04 s3.3) ------------------------------------------------------------------------

func test_quat_full_roundtrip_10000() -> void:
	var worst: float = 0.0
	for i: int in SAMPLES:
		var q: Quaternion = _rand_quat()
		var bits: int = Codec.quantize_quat(q)
		assert_int(bits).is_between(0, 0xFFFFFFFF)
		worst = maxf(worst, _angle_deg(q, Codec.dequantize_quat(bits)))
	assert_float(worst).is_less_equal(FULL_DEG)


func test_quat_coarse_roundtrip_10000_and_adversarial() -> void:
	var worst: float = 0.0
	for i: int in SAMPLES:
		var q: Quaternion = _rand_quat()
		var bits: int = Codec.quantize_quat_coarse(q, 0)
		assert_int(bits).is_between(0, (1 << 17) - 1)
		worst = maxf(worst, _angle_deg(q, Codec.dequantize_quat_coarse(bits)))
	# Near the S3 "corner" (all |components| ~ 1/2) rounding error is amplified most.
	for i: int in SAMPLES:
		var q: Quaternion = Quaternion(0.5 + _rng.randf_range(-0.03, 0.03), 0.5 + _rng.randf_range(-0.03, 0.03),
			-0.5 + _rng.randf_range(-0.03, 0.03), 0.5 + _rng.randf_range(-0.03, 0.03)).normalized()
		worst = maxf(worst, _angle_deg(q, Codec.dequantize_quat_coarse(Codec.quantize_quat_coarse(q, 0))))
		worst = maxf(worst, _angle_deg(q, Codec.dequantize_quat(Codec.quantize_quat(q))))
	assert_float(worst).is_less_equal(COARSE_DEG)


func test_quat_canonical_sign_and_index() -> void:
	for i: int in 2000:
		var q: Quaternion = _rand_quat()
		var neg: Quaternion = -q
		assert_int(Codec.quantize_quat(neg)).is_equal(Codec.quantize_quat(q))
		assert_int(Codec.quantize_quat_coarse(neg, 5)).is_equal(Codec.quantize_quat_coarse(q, 5))
		var comps: PackedFloat32Array = PackedFloat32Array([absf(q.x), absf(q.y), absf(q.z), absf(q.w)])
		var idx: int = Codec.quantize_quat(q) & 3
		for k: int in 4:
			assert_bool(comps[idx] >= comps[k]).is_true()
		# The decoded dropped component is the positive one.
		var d: Quaternion = Codec.dequantize_quat(Codec.quantize_quat(q))
		var dropped: float = [d.x, d.y, d.z, d.w][idx]
		assert_float(dropped).is_greater(0.0)
	# Ties go to the lowest index; both signs of a tie encode identically.
	var tie: Quaternion = Quaternion(sqrt(0.5), 0.0, 0.0, sqrt(0.5))
	assert_int(Codec.quantize_quat(tie) & 3).is_equal(0)
	assert_int(Codec.quantize_quat(-tie)).is_equal(Codec.quantize_quat(tie))
	assert_float(_angle_deg(tie, Codec.dequantize_quat(Codec.quantize_quat(tie)))).is_less_equal(FULL_DEG)
	assert_int(Codec.quantize_quat(Quaternion.IDENTITY)).is_equal(3)


func test_quat_coarse_spare_bits() -> void:
	var q: Quaternion = Quaternion(Vector3(0.3, 0.8, -0.2).normalized(), 1.1)
	var plain: int = Codec.quantize_quat_coarse(q, 0)
	for spare: int in 128:
		var bits: int = Codec.quantize_quat_coarse(q, spare)
		assert_int(bits).is_between(0, 0xFFFFFF)
		assert_int(Codec.coarse_spare(bits)).is_equal(spare)
		assert_int(bits & 0x1FFFF).is_equal(plain)
	assert_int(Codec.coarse_spare(Codec.quantize_quat_coarse(q, 0x1FF))).is_equal(0x7F)


func test_quat_decoders_total_on_any_bits() -> void:
	var bad: int = 0
	for bits: int in 1 << 17:
		if not Codec.dequantize_quat_coarse(bits).is_normalized():
			bad += 1
	for i: int in SAMPLES:
		var bits: int = _rng.randi()
		if not Codec.dequantize_quat(bits).is_normalized() or not Codec.dequantize_quat(bits | (0xFF << 32)).is_normalized():
			bad += 1
	assert_int(bad).is_equal(0)


# --- velocity, hp, flags, ai_tag (04 s3.3) --------------------------------------------------------

func test_vel_roundtrip_and_clamp() -> void:
	var worst: float = 0.0
	for i: int in SAMPLES:
		var p: Vector3 = _rand_dir() * Sphere.PLANET_RADIUS
		var cell: int = Sphere.cell_of(p, Sphere.GRID_INTEREST)
		var f: Basis = Codec.cell_frame(cell)
		var enu: Vector3 = Vector3(_rng.randf_range(-254.0, 254.0), _rng.randf_range(-254.0, 254.0), _rng.randf_range(-254.0, 254.0))
		var v: Vector3 = f * enu
		var bits: int = Codec.quantize_vel(v, cell)
		assert_int(bits).is_between(0, 0xFFFFFF)
		var d: Vector3 = Codec.dequantize_vel(bits, cell) - v
		worst = maxf(worst, maxf(absf(d.dot(f.x)), maxf(absf(d.dot(f.y)), absf(d.dot(f.z)))))
	assert_float(worst).is_less_equal(Codec.VEL_UNIT * 0.5 + 0.001)
	# 04 s3.5 worked example: bytes 37 00 F4 = (+55, 0, -12) x 2 m/s = (110, 0, -24) m/s east/north/up.
	var cell0: int = 27
	var ex: Vector3 = Codec.cell_frame(cell0).transposed() * Codec.dequantize_vel(0xF40037, cell0)
	assert_float(ex.distance_to(Vector3(110.0, 0.0, -24.0))).is_less(0.001)
	assert_int(Codec.quantize_vel(Codec.cell_frame(cell0) * Vector3(110.0, 0.0, -24.0), cell0)).is_equal(0xF40037)
	# Out of range clamps to +-127 steps; an invalid cell decodes to zero.
	assert_int(Codec.quantize_vel(Codec.cell_frame(cell0) * Vector3(400.0, -400.0, 0.0), cell0)).is_equal(0x00817F)
	assert_bool(Codec.dequantize_vel(0x123456, Codec.CELL_COUNT) == Vector3.ZERO).is_true()
	assert_int(Codec.quantize_vel(Vector3.ONE, Codec.CELL_COUNT)).is_equal(0)
	assert_int(Codec.quantize_vel(Vector3.ONE, -1)).is_equal(0)
	assert_bool(Codec.cell_frame(-1) == Basis.IDENTITY and Codec.cell_centre(Codec.CELL_COUNT) == Vector3.ZERO).is_true()


func test_hp_roundtrip() -> void:
	for i: int in 1001:
		var hp: float = float(i) / 1000.0
		var b: int = Codec.quantize_hp(hp)
		assert_int(b).is_between(0, Codec.HP_MAX)
		assert_float(absf(Codec.dequantize_hp(b) - hp)).is_less_equal(0.5 / 255.0 + 1e-6)
	assert_int(Codec.quantize_hp(-0.5)).is_equal(0)
	assert_int(Codec.quantize_hp(7.0)).is_equal(255)
	assert_float(Codec.dequantize_hp(255)).is_equal(1.0)


func test_flags_and_ai_tag() -> void:
	assert_array([Codec.FLAG_DOCKED, Codec.FLAG_FIRING, Codec.FLAG_BOOSTING, Codec.FLAG_BRAKING,
		Codec.FLAG_CLASS_BIT, Codec.FLAG_DYING]).is_equal([4, 8, 16, 32, 64, 128])
	for cs: int in 3:
		for bits: int in 64:
			var f: int = Codec.make_flags(cs, bits << 2)
			assert_int(f).is_between(0, 255)
			assert_int(Codec.flags_control(f)).is_equal(cs)
			assert_int(f >> 2).is_equal(bits)
	assert_int(Codec.flags_control(Codec.make_flags(Protocol.ControlState.POSSESSED, Codec.FLAG_DYING))).is_equal(2)
	for tag: int in 256:
		assert_int(Codec.quantize_ai_tag(tag)).is_equal(tag)
	assert_int(Codec.quantize_ai_tag(-3)).is_equal(0)
	assert_int(Codec.quantize_ai_tag(300)).is_equal(255)


func test_tier_b_flag_mapping_a24() -> void:
	# R0 B.9 A-24: spare 0-4 = flags 0-4, spare 5 = flags bit 6, spare 6 = flags bit 7; BRAKING dropped.
	assert_int(Codec.FLAGS_DROPPED_BY_B).is_equal(Codec.FLAG_BRAKING)
	assert_int(Codec.flags_to_spare(Codec.FLAG_CLASS_BIT)).is_equal(Codec.SPARE_CLASS_BIT)
	assert_int(Codec.flags_to_spare(Codec.FLAG_DYING)).is_equal(Codec.SPARE_DYING)
	assert_int(Codec.flags_to_spare(Codec.FLAG_BRAKING)).is_equal(0)
	for f: int in 256:
		var s: int = Codec.flags_to_spare(f)
		assert_int(s).is_between(0, Codec.QUAT_COARSE_SPARE_MASK)
		assert_int(Codec.spare_to_flags(s)).is_equal(f & ~Codec.FLAG_BRAKING)
		var bits: int = Codec.quantize_quat_coarse(Quaternion.IDENTITY, s)
		assert_int(Codec.spare_to_flags(Codec.coarse_spare(bits))).is_equal(f & ~Codec.FLAG_BRAKING)
	for s7: int in 128:
		assert_int(Codec.flags_to_spare(Codec.spare_to_flags(s7))).is_equal(s7)


# --- sizes and byte helpers (04 s2.3 legend, s3.3, s3.4) ------------------------------------------

func test_byte_sizes_match_04() -> void:
	assert_int(Codec.POS_BYTES).is_equal(8)                 # vec3q
	assert_int(Codec.QUAT_BYTES).is_equal(4)                # quat_s3
	assert_int(Codec.QUAT_COARSE_BYTES).is_equal(3)         # 17 bits + 7 spare
	assert_int(Codec.VEL_BYTES).is_equal(3)
	assert_int(Codec.HP_BYTES + Codec.FLAGS_BYTES + Codec.AI_TAG_BYTES).is_equal(3)
	assert_int(Codec.FULL_RECORD_BYTES).is_equal(19)        # 04 s3.4 FULL record
	assert_int(Codec.FULL_RECORD_BYTES + Codec.AI_TAG_BYTES).is_equal(20)   # KEYFRAME own-team record
	var buf: PackedByteArray = PackedByteArray()
	var _r: int = buf.resize(7)
	assert_int(Codec.write_u32(buf, 0, 0x714C2F9A)).is_equal(4)
	assert_array(Array(buf.slice(0, 4))).is_equal([0x9A, 0x2F, 0x4C, 0x71])  # 04 s3.5 bytes; idx = 2
	assert_int(Codec.read_u32(buf, 0) & 3).is_equal(2)
	assert_int(Codec.write_u24(buf, 4, 0xF40037)).is_equal(7)
	assert_array(Array(buf.slice(4, 7))).is_equal([0x37, 0x00, 0xF4])
	assert_int(Codec.read_u24(buf, 4)).is_equal(0xF40037)
	assert_int(Codec.write_u24(buf, 5, 1)).is_equal(-1)
	assert_int(Codec.read_u24(buf, 5)).is_equal(-1)
	assert_int(Codec.write_u32(buf, 4, 1)).is_equal(-1)
	assert_int(Codec.read_u32(buf, 4)).is_equal(-1)
	assert_array(Array(buf.slice(4, 7))).is_equal([0x37, 0x00, 0xF4])       # failed writes left it intact
