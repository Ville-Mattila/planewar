class_name KeyframeCodec extends RefCounted
## KEYFRAME (0x86, channel 3, reliable; 04 s2.3, s3.1, s4.3). The message is a list of SNAPSHOT FULL records (gap chain,
## 0xFF, vec3q, quat_s3, vel, hp, flags, +ai_tag for the client's own team) for the client's interest set, with no
## baseline. The gap chain runs over sim slots (0-1,535, projectile slots 4,096-6,143; R0 B.22 A-112): the API and the
## mirror use roster indices (Roster.index_of_slot), and a slot no roster holds (1,536-4,095, >= 6,144) is MALFORMED. `encode` (server) builds it from SnapshotCodec's per-tick cache and resets the client's BaselineStore mirror
## to exactly those records; `decode` (client) validates the whole message, then applies it through
## SnapshotDecoder.accept_keyframe + BaselineFrame.set_full, the calls the mirror used, so both frames are identical.
## Decoding is total: every malformed shape returns MALFORMED, a missing roster entry MISSING_ROSTER (hold and retry
## after ENTITY_META), a keyframe_seq not newer than the last applied one STALE; none of them changes anything.
## Scratch arrays are sized once; `reencode()` rebuilds the bytes of the last OK decode from them (invariant K3).

const HEADER_BYTES: int = 10                # id, seq u16, tick u32, scope u8, count u16
const COUNT_MAX: int = Roster.CAPACITY
## Records one encode writes: (65,535 - 10) / 23 (FULL + own ai_tag + 3-byte escape) keeps any message under
## Protocol.MAX_RELIABLE_BYTES; the interest caps (1,240) stay far below it. Records past it arrive as snapshot FULLs.
const RECORDS_MAX: int = 2848
const OFF_SEQ: int = 1
const OFF_TICK: int = 3
const OFF_SCOPE: int = 7
const OFF_COUNT: int = 8
const _BODY_AFTER_MASK: int = Codec.POS_BYTES + Codec.QUAT_BYTES + Codec.VEL_BYTES + Codec.HP_BYTES + Codec.FLAGS_BYTES   # 17
const _RECORD_MIN: int = 1 + 1 + _BODY_AFTER_MASK                  # gap + mask + body = 19
const _HALF_SEQ: int = 0x8000

enum Status { OK, MALFORMED, STALE, MISSING_ROSTER }

var seq: int = 0                            # keyframe_seq of the last encode / OK decode
var tick: int = 0
var scope: int = 0
var count: int = 0
var malformed: int = 0
var missing: PackedInt32Array = PackedInt32Array()
var _applied_seq: int = -1                  # last applied keyframe_seq; -1 = none (forget())
var _idx: PackedInt32Array = PackedInt32Array()
var _pos: PackedInt64Array = PackedInt64Array()
var _ori: PackedInt64Array = PackedInt64Array()
var _vel: PackedInt32Array = PackedInt32Array()
var _hp: PackedByteArray = PackedByteArray()
var _fl: PackedByteArray = PackedByteArray()
var _ai: PackedInt32Array = PackedInt32Array()       # -1 = no ai_tag byte (not the client's team)


func _init() -> void:
	var _a: int = _idx.resize(COUNT_MAX)
	var _b: int = _pos.resize(COUNT_MAX)
	var _c: int = _ori.resize(COUNT_MAX)
	var _d: int = _vel.resize(COUNT_MAX)
	var _e: int = _hp.resize(COUNT_MAX)
	var _f: int = _fl.resize(COUNT_MAX)
	var _g: int = _ai.resize(COUNT_MAX)


## Message size: header + `records` x 19 B + 1 per own-team record + 2 per 0xFF-escaped gap.
static func size_for(records: int, own_records: int, escapes: int) -> int:
	return HEADER_BYTES + records * _RECORD_MIN + own_records + 2 * escapes


static func seq_of(bytes: PackedByteArray) -> int:
	return bytes.decode_u16(OFF_SEQ) if bytes.size() >= HEADER_BYTES else -1


static func tick_of(bytes: PackedByteArray) -> int:
	return bytes.decode_u32(OFF_TICK) if bytes.size() >= HEADER_BYTES else -1


static func scope_of(bytes: PackedByteArray) -> int:
	return bytes[OFF_SCOPE] if bytes.size() >= HEADER_BYTES else -1


## The next keyframe_seq is accepted whatever the last one was (reconnect).
func forget() -> void:
	_applied_seq = -1


## Server: the KEYFRAME for `indices` (roster indices; any order, duplicates and entities not in this tick's cache are
## skipped) as of `at_tick`, with `store` (the client's mirror) reset to exactly these FULL records, frame `at_tick`.
## Empty when SnapshotCodec.prepare_tick(at_tick) has not run or `keyframe_seq` / `key_scope` is out of range.
func encode(codec: SnapshotCodec, store: BaselineStore, at_tick: int, keyframe_seq: int, key_scope: int,
		indices: PackedInt32Array) -> PackedByteArray:
	if at_tick <= 0 or at_tick != codec.cache_tick or keyframe_seq < 0 or keyframe_seq > 0xFFFF \
			or key_scope < 0 or key_scope > Protocol.KeyframeScope.ROSTER_REPAIR:
		return PackedByteArray()
	var sorted: PackedInt32Array = indices.duplicate()
	sorted.sort()
	var n: int = 0
	var prev: int = -1
	for s: int in sorted:
		if s == prev or s < 0 or s >= SnapshotCodec.CAPACITY or codec.c_tick[s] != at_tick:
			continue
		if n >= RECORDS_MAX:
			break
		prev = s
		_idx[n] = s
		_pos[n] = codec.c_pos[s]
		_ori[n] = codec.c_ori[s]
		_vel[n] = codec.c_vel[s]
		_hp[n] = codec.c_hp[s]
		_fl[n] = codec.c_flags[s]
		_ai[n] = codec.c_ai[s] if codec.c_team[s] == store.team else -1
		n += 1
	count = n
	seq = keyframe_seq
	tick = at_tick
	scope = key_scope
	store.reset()
	var f: BaselineFrame = store.begin(at_tick, 0)
	_fill(f, at_tick)
	return _write()


## Client: validates `bytes`, then resets `dec` to the keyframe (frames, receipts; newest and complete tick = its tick).
func decode(bytes: PackedByteArray, dec: SnapshotDecoder) -> int:
	missing.clear()
	var size: int = bytes.size()
	if size < HEADER_BYTES or size > Protocol.MAX_RELIABLE_BYTES or bytes[0] != Protocol.KEYFRAME:
		return _bad()
	var kseq: int = bytes.decode_u16(OFF_SEQ)
	var ktick: int = bytes.decode_u32(OFF_TICK)
	var kscope: int = bytes[OFF_SCOPE]
	var kcount: int = bytes.decode_u16(OFF_COUNT)
	if ktick == 0 or kscope > Protocol.KeyframeScope.ROSTER_REPAIR or kcount > COUNT_MAX \
			or size < HEADER_BYTES + kcount * _RECORD_MIN:
		return _bad()
	var at: int = _parse(bytes, kcount, dec)
	if at == -2:
		return Status.MISSING_ROSTER
	if at != size:
		return _bad()
	var d: int = (kseq - _applied_seq) & 0xFFFF
	if _applied_seq >= 0 and (d == 0 or d >= _HALF_SEQ):
		return Status.STALE
	seq = kseq
	tick = ktick
	scope = kscope
	count = kcount
	_applied_seq = kseq
	_fill(dec.accept_keyframe(ktick), ktick)
	dec.records_applied += kcount
	return Status.OK


## The bytes of the last OK decode (or encode), rebuilt from the raw fields. Valid until the next decode().
func reencode() -> PackedByteArray:
	return _write()


func _bad() -> int:
	malformed += 1
	return Status.MALFORMED


## Parses `kcount` records into the scratch arrays. Returns the offset after the last record, -1 malformed, -2 missing roster.
func _parse(b: PackedByteArray, kcount: int, dec: SnapshotDecoder) -> int:
	var size: int = b.size()
	var at: int = HEADER_BYTES
	var prev: int = 0
	var roster: Roster = dec.roster
	for k: int in kcount:
		if at >= size:
			return -1
		var g: int = b[at]
		var w: int = prev                   # the wire chain runs over sim slots
		if g == SnapshotCodec.GAP_ESCAPE:
			if at + 3 > size:
				return -1
			w = b.decode_u16(at + 1)
			var step: int = w - prev
			if (k > 0 and w <= prev) or (step >= 1 and step <= SnapshotCodec.GAP_MAX) or (k == 0 and w == 0):
				return -1                   # not ascending, or an escape where the u8 gap form fits
			at += 3
		else:
			if g == 0 and k != 0:
				return -1
			w += g
			at += 1
		var idx: int = Roster.index_of_slot(w)
		if idx < 0:
			return -1
		prev = w
		if roster == null or not roster.has(idx):
			var _m: bool = missing.push_back(idx)
			return -2
		var own: bool = roster.team_of(idx) == dec.store.team
		at = _parse_body(b, at, k, idx, own)
		if at < 0:
			return -1
	return at


func _parse_body(b: PackedByteArray, at: int, k: int, idx: int, own: bool) -> int:
	var body: int = 1 + _BODY_AFTER_MASK + (Codec.AI_TAG_BYTES if own else 0)
	if at + body > b.size() or b[at] != SnapshotCodec.MASK_FULL:
		return -1
	var q: int = Codec.read_pos(b, at + 1)
	if q == Codec.POS_INVALID:
		return -1
	_idx[k] = idx
	_pos[k] = q
	_ori[k] = Codec.read_u32(b, at + 9)
	_vel[k] = Codec.read_u24(b, at + 13)
	_hp[k] = b[at + 16]
	_fl[k] = b[at + 17]
	_ai[k] = b[at + 18] if own else -1
	return at + body


## The scratch records as FULL records of frame `f` (the same call the SNAPSHOT decoder and the server mirror use).
func _fill(f: BaselineFrame, at_tick: int) -> void:
	for k: int in count:
		f.set_full(_idx[k], at_tick, _pos[k], _ori[k], _vel[k], _hp[k], _fl[k], _ai[k])


func _write() -> PackedByteArray:
	var escapes: int = 0
	var own: int = 0
	var prev: int = 0
	for k: int in count:
		var d: int = Roster.slot_of_index(_idx[k]) - prev
		if not ((d >= 1 and d <= SnapshotCodec.GAP_MAX) or (k == 0 and d == 0)):
			escapes += 1
		own += 1 if _ai[k] >= 0 else 0
		prev = Roster.slot_of_index(_idx[k])
	var out: PackedByteArray = PackedByteArray()
	var _r: int = out.resize(size_for(count, own, escapes))
	out[0] = Protocol.KEYFRAME
	out.encode_u16(OFF_SEQ, seq)
	out.encode_u32(OFF_TICK, tick)
	out[OFF_SCOPE] = scope
	out.encode_u16(OFF_COUNT, count)
	var at: int = HEADER_BYTES
	prev = 0
	for k: int in count:
		var w: int = Roster.slot_of_index(_idx[k])
		var d: int = w - prev
		if (d >= 1 and d <= SnapshotCodec.GAP_MAX) or (k == 0 and d == 0):
			out[at] = d
			at += 1
		else:
			out[at] = SnapshotCodec.GAP_ESCAPE
			out.encode_u16(at + 1, w)
			at += 3
		prev = w
		out[at] = SnapshotCodec.MASK_FULL
		at = Codec.write_pos(out, at + 1, _pos[k])
		at = Codec.write_u32(out, at, _ori[k])
		at = Codec.write_u24(out, at, _vel[k])
		out[at] = _hp[k]
		out[at + 1] = _fl[k]
		at += 2
		if _ai[k] >= 0:
			out[at] = _ai[k]
			at += 1
	return out
