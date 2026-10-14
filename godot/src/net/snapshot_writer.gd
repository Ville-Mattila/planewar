class_name SnapshotWriter extends RefCounted
## Packet assembly for SnapshotCodec.encode (04 s3.4): 10-byte header (id, tick u32, baseline_tick u32, flags),
## sections A, B, C each opened lazily with a u8 count, roster-index gaps (u8 1-254, 0 only for index 0 as the
## packet's first record, 0xFF + u16 escape), the pilot block at the end of the first packet, and a split into
## CONTINUED packets when the next record would pass 1,200 B or a section count would pass 255; flags bits 6-7
## carry the packet index within the tick, LAST on the highest (R0 B.10 A-36). The gap
## chain runs across sections within a packet (04 s3.5: section B's first gap continues from section A).

var packets: int = 0
var _buf: PackedByteArray = PackedByteArray()
var _at: int = 0
var _prev: int = 0
var _first: bool = true
var _sec_at: int = -1
var _sec_tier: int = -1
var _flags: int = 0
var _tick: int = 0
var _base: int = 0
var _limit: int = 1
var _pilot: PilotBlock = null
var _out: Array[PackedByteArray] = []


func _init() -> void:
	var _r: int = _buf.resize(SnapshotCodec.MAX_PACKET_BYTES)


func start(tick: int, base_tick: int, pilot: PilotBlock, out: Array[PackedByteArray], limit: int) -> void:
	_tick = tick
	_base = base_tick
	_pilot = pilot
	_out = out
	_limit = maxi(limit, 1)
	packets = 0
	_reset_packet()


func _reset_packet() -> void:
	_at = SnapshotCodec.HEADER_BYTES
	_prev = 0
	_first = true
	_sec_at = -1
	_sec_tier = -1
	_flags = 0


func _avail() -> int:
	var reserve: int = PilotBlock.BYTES if packets == 0 and _pilot != null else 0
	return SnapshotCodec.MAX_PACKET_BYTES - _at - reserve


func _gap_bytes(s: int) -> int:
	var d: int = s - _prev
	return 1 if (d >= 1 and d <= SnapshotCodec.GAP_MAX) or (_first and s == 0) else 3


## Reserves room for a record of `body` bytes at roster index `s` in section `tier` and writes its gap.
## Splits into a new packet when needed; false when the packet cap is reached (nothing written).
func place(s: int, tier: int, body: int) -> bool:
	var need: int = _gap_bytes(s) + body + (1 if _sec_tier != tier else 0)
	var full: bool = _sec_tier == tier and _buf[_sec_at] >= SnapshotCodec.SECTION_MAX
	if need > _avail() or full:
		if packets + 1 >= _limit:
			return false
		_emit(false)
	if _sec_tier != tier:
		_sec_tier = tier
		_sec_at = _at
		_buf[_at] = 0
		_at += 1
		_flags |= Protocol.SNAP_HAS_A << tier
	_buf[_sec_at] += 1
	var d: int = s - _prev
	if (d >= 1 and d <= SnapshotCodec.GAP_MAX) or (_first and s == 0):
		_buf[_at] = d
		_at += 1
	else:
		_buf[_at] = SnapshotCodec.GAP_ESCAPE
		_buf.encode_u16(_at + 1, s)
		_at += 3
	_prev = s
	_first = false
	return true


## Emits the open packet as LAST. Returns the packet count of this tick.
func finish() -> int:
	_emit(true)
	return packets


func _emit(last: bool) -> void:
	if packets == 0 and _pilot != null:
		_at = _pilot.write(_buf, _at)
		_flags |= Protocol.SNAP_HAS_PILOT
	_flags |= (Protocol.SNAP_LAST if last else Protocol.SNAP_CONTINUED) | (packets << Protocol.SNAP_INDEX_SHIFT)
	_buf[0] = Protocol.SNAPSHOT
	_buf.encode_u32(1, _tick)
	_buf.encode_u32(5, _base)
	_buf[9] = _flags
	_out.append(_buf.slice(0, _at))
	packets += 1
	_reset_packet()


func put_u24(v: int) -> void:
	_at = Codec.write_u24(_buf, _at, v)


## FULL body: mask 0xFF, vec3q, quat_s3, vel, hp, flags, [ai_tag when >= 0].
func put_full(pos_q: int, ori: int, vel: int, hp: int, flags: int, ai_tag: int) -> void:
	_buf[_at] = SnapshotCodec.MASK_FULL
	_at = Codec.write_pos(_buf, _at + 1, pos_q)
	_at = Codec.write_u32(_buf, _at, ori)
	_at = Codec.write_u24(_buf, _at, vel)
	_buf[_at] = hp
	_buf[_at + 1] = flags
	_at += 2
	if ai_tag >= 0:
		_buf[_at] = ai_tag
		_at += 1


## DELTA body in mask-bit order; `res` is the wire residual.
func put_delta(mask: int, res: Vector3i, ori: int, tier_b: bool, vel: int, hp: int, flags: int, ai_tag: int) -> void:
	_buf[_at] = mask
	_at += 1
	if mask & SnapshotCodec.MASK_POS_SMALL:
		_buf[_at] = res.x & 0xFF
		_buf[_at + 1] = res.y & 0xFF
		_buf[_at + 2] = res.z & 0xFF
		_at += 3
	elif mask & SnapshotCodec.MASK_POS_LARGE:
		_buf.encode_s16(_at, res.x)
		_buf.encode_s16(_at + 2, res.y)
		_buf.encode_s16(_at + 4, res.z)
		_at += 6
	if mask & SnapshotCodec.MASK_ORI:
		_at = Codec.write_u24(_buf, _at, ori) if tier_b else Codec.write_u32(_buf, _at, ori)
	if mask & SnapshotCodec.MASK_VEL:
		_at = Codec.write_u24(_buf, _at, vel)
	if mask & SnapshotCodec.MASK_HP:
		_buf[_at] = hp
		_at += 1
	if mask & SnapshotCodec.MASK_FLAGS:
		if not tier_b:
			_buf[_at] = flags
			_at += 1
		if ai_tag >= 0:
			_buf[_at] = ai_tag
			_at += 1
