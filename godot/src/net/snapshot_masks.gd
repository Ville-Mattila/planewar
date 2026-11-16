class_name SnapshotMasks extends RefCounted
## DELTA record masks and residual helpers of the SNAPSHOT codec (04 s3.4-s3.5), split out of SnapshotCodec (400-line cap,
## NET-60); SnapshotCodec re-exports the constants and the four statics unchanged.

const MASK_POS_SMALL: int = 0x01            # 3 x i8 residual at 4 quanta
const MASK_POS_LARGE: int = 0x02            # 3 x i16 residual at 1 quantum
const MASK_ORI: int = 0x04
const MASK_VEL: int = 0x08
const MASK_HP: int = 0x10
const MASK_FLAGS: int = 0x20                # A: flags (+ ai_tag own team); B: AI_TAG (own team)
const SMALL_SHIFT: int = 2
const SMALL_MAX: int = 127
const POS_SEND_MIN: int = 1 << SMALL_SHIFT
const LARGE_MAX: int = 32767


## POS mask bits for residual `res` (levels): 0 when every axis is under POS_SEND_MIN, POS_SMALL, POS_LARGE,
## or -1 when even i16 cannot carry it (FULL).
static func pos_mask(res: Vector3i) -> int:
	if absi(res.x) < POS_SEND_MIN and absi(res.y) < POS_SEND_MIN and absi(res.z) < POS_SEND_MIN:
		return 0
	var rs: Vector3i = Vector3i(res.x + 2, res.y + 2, res.z + 2)
	rs = Vector3i(rs.x >> SMALL_SHIFT, rs.y >> SMALL_SHIFT, rs.z >> SMALL_SHIFT)
	if absi(rs.x) <= SMALL_MAX and absi(rs.y) <= SMALL_MAX and absi(rs.z) <= SMALL_MAX:
		return MASK_POS_SMALL
	if absi(res.x) <= LARGE_MAX and absi(res.y) <= LARGE_MAX and absi(res.z) <= LARGE_MAX:
		return MASK_POS_LARGE
	return -1


## The residual as written on the wire for `mask` (POS_SMALL in 4-quanta steps).
static func wire_residual(mask: int, res: Vector3i) -> Vector3i:
	if mask & MASK_POS_SMALL:
		return Vector3i((res.x + 2) >> SMALL_SHIFT, (res.y + 2) >> SMALL_SHIFT, (res.z + 2) >> SMALL_SHIFT)
	return res if mask & MASK_POS_LARGE else Vector3i.ZERO


## Levels added to the dead-reckoned position by a record with `mask` and level residual `res`.
static func applied_residual(mask: int, res: Vector3i) -> Vector3i:
	if mask & MASK_POS_SMALL:
		return wire_residual(mask, res) * (1 << SMALL_SHIFT)
	return res if mask & MASK_POS_LARGE else Vector3i.ZERO


## Body bytes (mask .. last group) of an A- or B-DELTA record.
static func delta_body_bytes(mask: int, tier_b: bool, own: bool) -> int:
	var n: int = 1
	n += 3 if mask & MASK_POS_SMALL else 0
	n += 6 if mask & MASK_POS_LARGE else 0
	if mask & MASK_ORI:
		n += Codec.QUAT_COARSE_BYTES if tier_b else Codec.QUAT_BYTES
	n += Codec.VEL_BYTES if mask & MASK_VEL else 0
	n += Codec.HP_BYTES if mask & MASK_HP else 0
	if mask & MASK_FLAGS:
		n += Codec.AI_TAG_BYTES if tier_b else Codec.FLAGS_BYTES + (Codec.AI_TAG_BYTES if own else 0)
	return n
