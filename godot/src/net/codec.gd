class_name Codec
## Field quantisers of the snapshot codec (04 s3.2-s3.3): per-cell ENU position (vec3q), smallest-three
## orientation (full 4 B and coarse 3 B), velocity, hp, flags and ai_tag. All static and allocation-free:
## quantisers return packed ints (the shared per-tick cache stores them, R0 C1-02) and the byte helpers
## write/read them little-endian at an offset. Decoders never throw; malformed input yields a defined
## value or an INVALID sentinel. Changing any constant or layout here is a wire change (PROTOCOL_VERSION).

# region position (04 s3.2): cell u16, e u16, n u16, u u16 in the interest cell's ENU frame
const POS_EN_HALF: float = 1280.0           # e, n in [-1280, +1280) m (R0 B.9 A-23)
const POS_U_MIN: float = -768.0             # u in [-768, +3328) m
const POS_U_SPAN: float = 4096.0
const POS_LEVELS: int = 65536
const POS_EN_QUANTUM: float = 2.0 * POS_EN_HALF / POS_LEVELS     # 3.906 cm
const POS_U_QUANTUM: float = POS_U_SPAN / POS_LEVELS              # 6.25 cm
const POS_INVALID: int = -1                 # read_pos on a short buffer or a cell id >= CELL_COUNT
const CELL_COUNT: int = 6 * Sphere.GRID_INTEREST * Sphere.GRID_INTEREST   # 384
# endregion

# region orientation (04 s3.3): 2-bit index of the dropped (largest) component, x y z w order
const QUAT_FULL_MAX: int = 511              # 10-bit two's complement, scaled by 1/sqrt(2)
const QUAT_COARSE_MAX: int = 15             # 5-bit two's complement
const QUAT_COARSE_SPARE_SHIFT: int = 17     # coarse bits 17-23 carry 7 caller bits (tier-B flags)
const QUAT_COARSE_SPARE_MASK: int = 0x7F
# endregion

# region tier-B flag mapping (R0 B.9 A-24): the 7 coarse spare bits carry the flags byte minus bit 5 BRAKING
const SPARE_LOW_MASK: int = 0x1F            # spare 0-4 = flags 0-4 (control state, docked, firing, boosting)
const SPARE_CLASS_BIT: int = 0x20           # spare 5 = flags bit 6 (FLAG_CLASS_BIT)
const SPARE_DYING: int = 0x40               # spare 6 = flags bit 7 (FLAG_DYING)
const FLAGS_DROPPED_BY_B: int = 0x20        # FLAG_BRAKING; tier-B entities read braking as false
# endregion

# region velocity, hp, flags (04 s3.3)
const VEL_UNIT: float = 2.0                 # m/s per i8 step, in the cell's ENU frame; range +-254 m/s
const VEL_MAX: int = 127
const HP_MAX: int = 255
const FLAG_CONTROL_MASK: int = 0x03         # Protocol.ControlState: AUTO, ORDERED, POSSESSED
const FLAG_DOCKED: int = 0x04
const FLAG_FIRING: int = 0x08
const FLAG_BOOSTING: int = 0x10
const FLAG_BRAKING: int = 0x20
const FLAG_CLASS_BIT: int = 0x40            # shield up / cargo loaded / towing, per def class
const FLAG_DYING: int = 0x80                # also selects the gravity dead-reckoning branch (04 s3.4)
# endregion

# region byte sizes (04 s3.3-s3.4)
const POS_BYTES: int = 8
const QUAT_BYTES: int = 4
const QUAT_COARSE_BYTES: int = 3
const VEL_BYTES: int = 3
const HP_BYTES: int = 1
const FLAGS_BYTES: int = 1
const AI_TAG_BYTES: int = 1
## FULL record: gap u8 + mask u8 + vec3q + quat_s3 + vel + hp + flags = 19 (+1 ai_tag own team).
const FULL_RECORD_BYTES: int = 2 + POS_BYTES + QUAT_BYTES + VEL_BYTES + HP_BYTES + FLAGS_BYTES
# endregion

const _EN_INV: float = POS_LEVELS / (2.0 * POS_EN_HALF)
const _U_INV: float = POS_LEVELS / POS_U_SPAN
const _SQRT2: float = 1.4142135623730951
const _FULL_SCALE: float = QUAT_FULL_MAX * _SQRT2              # component -> code
const _FULL_INV: float = 1.0 / _FULL_SCALE
const _COARSE_SCALE: float = QUAT_COARSE_MAX * _SQRT2
const _COARSE_INV: float = 1.0 / _COARSE_SCALE
const _VEL_INV: float = 1.0 / VEL_UNIT

# Per-cell frames at GRID_INTEREST: centre on the datum sphere and ADR-03 ENU axes (Sphere.tangent_frame).
static var _centre: PackedVector3Array = PackedVector3Array()
static var _east: PackedVector3Array = PackedVector3Array()
static var _north: PackedVector3Array = PackedVector3Array()
static var _up: PackedVector3Array = PackedVector3Array()


static func _static_init() -> void:
	var _a: int = _centre.resize(CELL_COUNT)
	var _b: int = _east.resize(CELL_COUNT)
	var _c: int = _north.resize(CELL_COUNT)
	var _d: int = _up.resize(CELL_COUNT)
	for cell: int in CELL_COUNT:
		var c: Vector3 = Sphere.cell_center_dir(cell, Sphere.GRID_INTEREST) * Sphere.PLANET_RADIUS
		var f: Basis = Sphere.tangent_frame(c)
		_centre[cell] = c
		_east[cell] = f.x
		_north[cell] = f.y
		_up[cell] = f.z


## Datum-sphere centre and ENU basis (columns east, north, up) of an interest cell; tests and NET-06.
## Vector3.ZERO / Basis.IDENTITY for an invalid cell id.
static func cell_centre(cell: int) -> Vector3:
	return _centre[cell] if cell >= 0 and cell < CELL_COUNT else Vector3.ZERO


static func cell_frame(cell: int) -> Basis:
	if cell < 0 or cell >= CELL_COUNT:
		return Basis.IDENTITY
	return Basis(_east[cell], _north[cell], _up[cell])


# region position
## p (moon-centred) -> packed vec3q: cell | e << 16 | n << 32 | u << 48. Out-of-range offsets clamp.
static func quantize_pos(p: Vector3) -> int:
	var cell: int = Sphere.cell_of(p, Sphere.GRID_INTEREST)
	var d: Vector3 = p - _centre[cell]
	var e: int = clampi(floori((d.dot(_east[cell]) + POS_EN_HALF) * _EN_INV + 0.5), 0, POS_LEVELS - 1)
	var n: int = clampi(floori((d.dot(_north[cell]) + POS_EN_HALF) * _EN_INV + 0.5), 0, POS_LEVELS - 1)
	var u: int = clampi(floori((d.dot(_up[cell]) - POS_U_MIN) * _U_INV + 0.5), 0, POS_LEVELS - 1)
	return cell | (e << 16) | (n << 32) | (u << 48)


## Exact inverse of quantize_pos; Vector3.ZERO for an invalid cell id.
static func dequantize_pos(q: int) -> Vector3:
	var cell: int = q & 0xFFFF
	if cell >= CELL_COUNT:
		return Vector3.ZERO
	var e: float = float((q >> 16) & 0xFFFF) * POS_EN_QUANTUM - POS_EN_HALF
	var n: float = float((q >> 32) & 0xFFFF) * POS_EN_QUANTUM - POS_EN_HALF
	var u: float = float((q >> 48) & 0xFFFF) * POS_U_QUANTUM + POS_U_MIN
	return _centre[cell] + (_east[cell] * e + _north[cell] * n + _up[cell] * u)


## True when p's tangent offsets lie inside the vec3q ranges (quantize_pos would not clamp).
static func pos_in_range(p: Vector3) -> bool:
	var cell: int = Sphere.cell_of(p, Sphere.GRID_INTEREST)
	var d: Vector3 = p - _centre[cell]
	var e: float = d.dot(_east[cell])
	var n: float = d.dot(_north[cell])
	var u: float = d.dot(_up[cell])
	return e >= -POS_EN_HALF and e < POS_EN_HALF and n >= -POS_EN_HALF and n < POS_EN_HALF \
			and u >= POS_U_MIN and u < POS_U_MIN + POS_U_SPAN


static func pack_pos(cell: int, e: int, n: int, u: int) -> int:
	return (cell & 0xFFFF) | ((e & 0xFFFF) << 16) | ((n & 0xFFFF) << 32) | ((u & 0xFFFF) << 48)


static func pos_cell(q: int) -> int:
	return q & 0xFFFF


static func pos_e(q: int) -> int:
	return (q >> 16) & 0xFFFF


static func pos_n(q: int) -> int:
	return (q >> 32) & 0xFFFF


static func pos_u(q: int) -> int:
	return (q >> 48) & 0xFFFF
# endregion


# region orientation
## Smallest-three, 32 bits: index bits 0-1, the other three components (ascending index) as 10-bit
## two's complement at bits 2, 12, 22, sign-normalised so the dropped component is positive.
static func quantize_quat(q: Quaternion) -> int:
	var s: Vector4 = _smallest3(q)
	var a: int = clampi(roundi(s.y * _FULL_SCALE), -QUAT_FULL_MAX, QUAT_FULL_MAX) & 0x3FF
	var b: int = clampi(roundi(s.z * _FULL_SCALE), -QUAT_FULL_MAX, QUAT_FULL_MAX) & 0x3FF
	var c: int = clampi(roundi(s.w * _FULL_SCALE), -QUAT_FULL_MAX, QUAT_FULL_MAX) & 0x3FF
	return int(s.x) | (a << 2) | (b << 12) | (c << 22)


static func dequantize_quat(bits: int) -> Quaternion:
	return _rebuild(bits & 3, _sext((bits >> 2) & 0x3FF, 10) * _FULL_INV,
			_sext((bits >> 12) & 0x3FF, 10) * _FULL_INV, _sext((bits >> 22) & 0x3FF, 10) * _FULL_INV)


## Coarse (tier B), 24 bits: index bits 0-1, three 5-bit components at bits 2, 7, 12, then `spare7`
## (7 caller bits) at bits 17-23. Encoder-only refinement: after rounding, one component may step to its
## other neighbouring code when that lowers the angular error (|d|^2 + (o.d)^2 / big^2, d = code error);
## this keeps the worst case under 04's 6 degrees, which plain rounding exceeds (~7.4 deg). The decoder
## is the plain smallest-three inverse.
static func quantize_quat_coarse(q: Quaternion, spare7: int) -> int:
	var s: Vector4 = _smallest3(q)
	var o: Vector3 = Vector3(s.y, s.z, s.w)
	var code: Vector3i = Vector3i(clampi(roundi(o.x * _COARSE_SCALE), -QUAT_COARSE_MAX, QUAT_COARSE_MAX),
			clampi(roundi(o.y * _COARSE_SCALE), -QUAT_COARSE_MAX, QUAT_COARSE_MAX),
			clampi(roundi(o.z * _COARSE_SCALE), -QUAT_COARSE_MAX, QUAT_COARSE_MAX))
	var d: Vector3 = Vector3(code) * _COARSE_INV - o
	var ib2: float = 1.0 / maxf(1.0 - o.length_squared(), 0.25)   # big >= 1/2 for a unit quaternion
	var t: float = o.dot(d)
	var best: float = d.length_squared() + t * t * ib2
	var best_k: int = -1
	var best_step: int = 0
	for k: int in 3:
		var step: int = -1 if d[k] > 0.0 else 1
		if absi(code[k] + step) > QUAT_COARSE_MAX:
			continue
		var dk: float = d[k] + step * _COARSE_INV
		var tk: float = t + o[k] * step * _COARSE_INV
		var v: float = d.length_squared() - d[k] * d[k] + dk * dk + tk * tk * ib2
		if v < best:
			best = v
			best_k = k
			best_step = step
	if best_k >= 0:
		code[best_k] += best_step
	return int(s.x) | ((code.x & 0x1F) << 2) | ((code.y & 0x1F) << 7) | ((code.z & 0x1F) << 12) \
			| ((spare7 & QUAT_COARSE_SPARE_MASK) << QUAT_COARSE_SPARE_SHIFT)


static func dequantize_quat_coarse(bits: int) -> Quaternion:
	return _rebuild(bits & 3, _sext((bits >> 2) & 0x1F, 5) * _COARSE_INV,
			_sext((bits >> 7) & 0x1F, 5) * _COARSE_INV, _sext((bits >> 12) & 0x1F, 5) * _COARSE_INV)


static func coarse_spare(bits: int) -> int:
	return (bits >> QUAT_COARSE_SPARE_SHIFT) & QUAT_COARSE_SPARE_MASK


## (index, a, b, c) of unit(q): index of the largest-magnitude component in x y z w order (ties go to the
## lowest index), then the other three ascending, negated when the dropped component is negative so that
## q and -q encode identically (canonical sign).
static func _smallest3(q: Quaternion) -> Vector4:
	var c: Quaternion = q.normalized()
	var ax: float = absf(c.x)
	var ay: float = absf(c.y)
	var az: float = absf(c.z)
	var aw: float = absf(c.w)
	var r: Vector4
	var big: float
	if ax >= ay and ax >= az and ax >= aw:
		r = Vector4(0.0, c.y, c.z, c.w)
		big = c.x
	elif ay >= az and ay >= aw:
		r = Vector4(1.0, c.x, c.z, c.w)
		big = c.y
	elif az >= aw:
		r = Vector4(2.0, c.x, c.y, c.w)
		big = c.z
	else:
		r = Vector4(3.0, c.x, c.y, c.z)
		big = c.w
	if big < 0.0:
		r = Vector4(r.x, -r.y, -r.z, -r.w)
	return r


static func _rebuild(idx: int, a: float, b: float, c: float) -> Quaternion:
	var big: float = sqrt(maxf(0.0, 1.0 - a * a - b * b - c * c))
	var r: Quaternion
	if idx == 0:
		r = Quaternion(big, a, b, c)
	elif idx == 1:
		r = Quaternion(a, big, b, c)
	elif idx == 2:
		r = Quaternion(a, b, big, c)
	else:
		r = Quaternion(a, b, c, big)
	return r.normalized()


static func _sext(v: int, nbits: int) -> int:
	var sign_bit: int = 1 << (nbits - 1)
	return (v ^ sign_bit) - sign_bit
# endregion


# region velocity, hp, flags, ai_tag
## v -> 3 x i8 in the ENU frame of `cell` (the record's position cell), packed e | n << 8 | u << 16;
## 0 for an invalid cell id.
static func quantize_vel(v: Vector3, cell: int) -> int:
	if cell < 0 or cell >= CELL_COUNT:
		return 0
	var e: int = clampi(roundi(v.dot(_east[cell]) * _VEL_INV), -VEL_MAX, VEL_MAX)
	var n: int = clampi(roundi(v.dot(_north[cell]) * _VEL_INV), -VEL_MAX, VEL_MAX)
	var u: int = clampi(roundi(v.dot(_up[cell]) * _VEL_INV), -VEL_MAX, VEL_MAX)
	return (e & 0xFF) | ((n & 0xFF) << 8) | ((u & 0xFF) << 16)


## Vector3.ZERO for an invalid cell id.
static func dequantize_vel(bits: int, cell: int) -> Vector3:
	if cell < 0 or cell >= CELL_COUNT:
		return Vector3.ZERO
	return _east[cell] * (float(_sext(bits & 0xFF, 8)) * VEL_UNIT) \
			+ _north[cell] * (float(_sext((bits >> 8) & 0xFF, 8)) * VEL_UNIT) \
			+ _up[cell] * (float(_sext((bits >> 16) & 0xFF, 8)) * VEL_UNIT)


static func quantize_hp(hp01: float) -> int:
	return clampi(roundi(hp01 * HP_MAX), 0, HP_MAX)


static func dequantize_hp(b: int) -> float:
	return float(b & 0xFF) / HP_MAX


## control_state (Protocol.ControlState) in bits 0-1; `bits` supplies FLAG_DOCKED .. FLAG_DYING.
static func make_flags(control_state: int, bits: int) -> int:
	return (control_state & FLAG_CONTROL_MASK) | (bits & 0xFC)


static func flags_control(f: int) -> int:
	return f & FLAG_CONTROL_MASK


## Flags byte -> the 7 coarse spare bits (A-24): bits 0-4 in place, bit 6 -> spare 5, bit 7 -> spare 6.
static func flags_to_spare(f: int) -> int:
	return (f & SPARE_LOW_MASK) | ((f >> 1) & (SPARE_CLASS_BIT | SPARE_DYING))


## Inverse of flags_to_spare; BRAKING (bit 5) is always clear.
static func spare_to_flags(s: int) -> int:
	return (s & SPARE_LOW_MASK) | ((s & (SPARE_CLASS_BIT | SPARE_DYING)) << 1)


## ai_tag is an exact u8 (R0 C2-07); out-of-range tags clamp.
static func quantize_ai_tag(tag: int) -> int:
	return clampi(tag, 0, 255)
# endregion


# region byte helpers (little-endian; return the next offset, or -1 without writing when it does not fit)
static func write_pos(buf: PackedByteArray, at: int, q: int) -> int:
	if at < 0 or at + POS_BYTES > buf.size():
		return -1
	buf.encode_s64(at, q)
	return at + POS_BYTES


## POS_INVALID on a short buffer or a cell id >= CELL_COUNT.
static func read_pos(buf: PackedByteArray, at: int) -> int:
	if at < 0 or at + POS_BYTES > buf.size():
		return POS_INVALID
	var q: int = buf.decode_s64(at)
	return POS_INVALID if (q & 0xFFFF) >= CELL_COUNT else q


static func write_u32(buf: PackedByteArray, at: int, v: int) -> int:
	if at < 0 or at + 4 > buf.size():
		return -1
	buf.encode_u32(at, v & 0xFFFFFFFF)
	return at + 4


## -1 on a short buffer.
static func read_u32(buf: PackedByteArray, at: int) -> int:
	if at < 0 or at + 4 > buf.size():
		return -1
	return buf.decode_u32(at)


static func write_u24(buf: PackedByteArray, at: int, v: int) -> int:
	if at < 0 or at + 3 > buf.size():
		return -1
	buf[at] = v & 0xFF
	buf[at + 1] = (v >> 8) & 0xFF
	buf[at + 2] = (v >> 16) & 0xFF
	return at + 3


## -1 on a short buffer.
static func read_u24(buf: PackedByteArray, at: int) -> int:
	if at < 0 or at + 3 > buf.size():
		return -1
	return buf[at] | (buf[at + 1] << 8) | (buf[at + 2] << 16)
# endregion
