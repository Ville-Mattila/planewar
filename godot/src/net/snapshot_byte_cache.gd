class_name SnapshotByteCache extends RefCounted
## Client-independent record bytes for SnapshotCodec (R0 B.10 A-40, NET-49), indexed by roster index and
## stamped with the tick they were built for: built on the first client that needs them in a tick, copied by
## every other. A FULL body is three words plus the coarse orientation BaselineFrame.set_full derives; a C-BLIP
## carries the bucket position BaselineFrame.set_blip derives. A/B DELTA bodies depend on each client's
## baseline and are never cached. Packed arrays only, no allocation after _init.

const CAPACITY: int = Roster.CAPACITY

## FULL body bytes 0-7 (0xFF mask, vec3q bytes 0-6) as a little-endian s64.
var w0: PackedInt64Array = PackedInt64Array()
## FULL body bytes 8-15 (vec3q byte 7, quat_s3 u32, vel u24) as a little-endian s64.
var w1: PackedInt64Array = PackedInt64Array()
## hp | flags << 8 | ai_tag << 16 (bytes 16, 17 and the own-team byte 18).
var w2: PackedInt32Array = PackedInt32Array()
## BaselineFrame.coarse_of_full(ori) for the FULL body.
var oc: PackedInt32Array = PackedInt32Array()
var _full_tick: PackedInt32Array = PackedInt32Array()
var _bpos: PackedInt64Array = PackedInt64Array()
var _bpos_tick: PackedInt32Array = PackedInt32Array()


func _init() -> void:
	var _a: int = w0.resize(CAPACITY)
	var _b: int = w1.resize(CAPACITY)
	var _c: int = w2.resize(CAPACITY)
	var _d: int = oc.resize(CAPACITY)
	var _e: int = _full_tick.resize(CAPACITY)
	var _f: int = _bpos.resize(CAPACITY)
	var _g: int = _bpos_tick.resize(CAPACITY)
	_full_tick.fill(-1)
	_bpos_tick.fill(-1)


## Builds w0 / w1 / w2 / oc for roster index `s` unless they already hold tick `tick`.
func full(s: int, tick: int, pos_q: int, ori_bits: int, vel_bits: int, hp_flags_ai: int) -> void:
	if _full_tick[s] == tick:
		return
	# Little-endian byte order of put_full: the shift drops vec3q's top byte from w0 into w1 (int wraps at 64 bits).
	w0[s] = SnapshotCodec.MASK_FULL | (pos_q << 8)
	w1[s] = ((pos_q >> 56) & 0xFF) | ((ori_bits & 0xFFFFFFFF) << 8) | ((vel_bits & 0xFFFFFF) << 40)
	w2[s] = hp_flags_ai
	oc[s] = BaselineFrame.coarse_of_full(ori_bits)
	_full_tick[s] = tick


## DeadReckon.blip_pos(cell of `pos_q`, `blip`) for roster index `s`, built once per tick.
func blip_pos(s: int, tick: int, pos_q: int, blip: int) -> int:
	if _bpos_tick[s] != tick:
		_bpos[s] = DeadReckon.blip_pos(Codec.pos_cell(pos_q), blip)
		_bpos_tick[s] = tick
	return _bpos[s]
