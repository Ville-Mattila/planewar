class_name ProjectileBatch
## PROJECTILE_BATCH (0x8F, channel 2) codec (04 s2.3, s3.6; R0 C2-35). Packet: id u8, tick u32, count u8,
## items[] x (shooter roster u16, weapon_slot u8 (bit7 HAS_FUSE), seed u8, yaw i8, pitch i8, [fuse_ticks u8]).
## Direction = yaw / pitch around the weapon boresight in DIR_STEP_RAD steps (0.5 deg, +-63.5 deg). The decoder
## validates the whole packet first and returns -1 on anything malformed (wrong id, count 0, truncation, trailing
## bytes); it never throws and appends nothing then.

const HEADER_BYTES: int = 6
const ITEM_BYTES: int = 6
const ITEM_FUSE_BYTES: int = 7
const DIR_STEP_RAD: float = 0.008726646259971648     # 0.5 degree
const COUNT_MAX: int = 170                            # (1,200 - 6) / 7


static func quantize_yaw(boresight: Basis, dir: Vector3) -> int:
	var d: Vector3 = dir.normalized()
	return clampi(roundi(atan2(d.dot(boresight.x), d.dot(boresight.z)) / DIR_STEP_RAD), -127, 127)


static func quantize_pitch(boresight: Basis, dir: Vector3) -> int:
	var d: Vector3 = dir.normalized()
	return clampi(roundi(asin(clampf(d.dot(boresight.y), -1.0, 1.0)) / DIR_STEP_RAD), -127, 127)


## Unit fire direction for quantised yaw / pitch around `boresight`.
static func dequantize_dir(boresight: Basis, yaw: int, pitch: int) -> Vector3:
	var y: float = yaw * DIR_STEP_RAD
	var p: float = pitch * DIR_STEP_RAD
	var cp: float = cos(p)
	return (boresight.x * (sin(y) * cp) + boresight.y * sin(p) + boresight.z * (cos(y) * cp)).normalized()


static func item_bytes(fuse_ticks: int) -> int:
	return ITEM_BYTES if fuse_ticks < 0 else ITEM_FUSE_BYTES


## Writes items [from, to) of `shots` with roster indices `refs[i]` (skipping entries whose ref is 0xFFFF is the
## caller's job: pass only valid ones). Returns the packet.
static func encode(tick: int, shots: ShotBuffer, refs: PackedInt32Array, from: int, to: int) -> PackedByteArray:
	var size: int = HEADER_BYTES
	for i: int in range(from, to):
		size += item_bytes(shots.fuse[i])
	var buf: PackedByteArray = PackedByteArray()
	var _r: Error = buf.resize(size)
	buf[0] = Protocol.PROJECTILE_BATCH
	var _n: int = Codec.write_u32(buf, 1, tick)
	buf[5] = to - from
	var at: int = HEADER_BYTES
	for i: int in range(from, to):
		buf.encode_u16(at, refs[i])
		var has_fuse: bool = shots.fuse[i] >= 0
		buf[at + 2] = shots.weapon_slot[i] | (Protocol.PROJ_HAS_FUSE if has_fuse else 0)
		buf[at + 3] = shots.seed_byte[i]
		buf[at + 4] = shots.yaw_q[i] & 0xFF
		buf[at + 5] = shots.pitch_q[i] & 0xFF
		if has_fuse:
			buf[at + 6] = shots.fuse[i]
		at += item_bytes(shots.fuse[i])
	return buf


## Validates then fills `out` (cleared first; `out.tick` = packet tick, `out.shooter` = roster indices). Returns the
## item count, or -1 and leaves `out` empty.
static func decode(bytes: PackedByteArray, out: ShotBuffer) -> int:
	out.clear()
	var n: int = _validate(bytes)
	if n < 0:
		return -1
	out.tick = Codec.read_u32(bytes, 1)
	var at: int = HEADER_BYTES
	for _i: int in n:
		var slot_byte: int = bytes[at + 2]
		var has_fuse: bool = (slot_byte & Protocol.PROJ_HAS_FUSE) != 0
		out.add_q(bytes.decode_u16(at), slot_byte & 0x7F, bytes[at + 3], _sext8(bytes[at + 4]), _sext8(bytes[at + 5]),
				bytes[at + 6] if has_fuse else -1)
		at += ITEM_FUSE_BYTES if has_fuse else ITEM_BYTES
	return n


static func _validate(bytes: PackedByteArray) -> int:
	var total: int = bytes.size()
	if total < HEADER_BYTES + ITEM_BYTES or total > Protocol.MAX_UNRELIABLE_BYTES or bytes[0] != Protocol.PROJECTILE_BATCH:
		return -1
	var n: int = bytes[5]
	if n == 0:
		return -1
	var at: int = HEADER_BYTES
	for _i: int in n:
		if at + ITEM_BYTES > total:
			return -1
		at += ITEM_FUSE_BYTES if (bytes[at + 2] & Protocol.PROJ_HAS_FUSE) != 0 else ITEM_BYTES
		if at > total:
			return -1
	return n if at == total else -1


static func _sext8(v: int) -> int:
	return v - 256 if v > 127 else v
