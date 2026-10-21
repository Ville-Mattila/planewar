class_name SnapshotDecoder extends RefCounted
## Client half of the SNAPSHOT codec (04 s3.4). decode() validates the whole packet into scratch arrays first
## (header, sections, gaps, masks, ranges, dead-reckoned levels, pilot block, exact length) and only then applies
## it to the BaselineStore frame of its tick, through the same BaselineFrame calls the server mirror uses. A
## malformed packet changes nothing and never errors. Records for roster indices without ENTITY_META stop the
## decode with MISSING_ROSTER and `missing` filled, so the caller can RosterSync.hold() the bytes (04 s3.1).
## Packet index (flags bits 6-7, R0 B.10 A-36): per tick the decoder records which indices arrived and the LAST
## index; HAS_PILOT off index 0, CONTINUED on index 3, or an index above the tick's LAST is MALFORMED, a repeated
## index is STALE, a missing index is loss. A tick is complete when 0 .. LAST all arrived; only then does
## `store.complete_tick` (the ack the client sends) advance.

enum Status { OK, MALFORMED, STALE, NO_BASELINE, MISSING_ROSTER }
const MAX_RECORDS: int = 512

var store: BaselineStore
var roster: Roster
var gravity_def: PackedByteArray = PackedByteArray()   # by def id: 1 = def gravity:true (bomb, siege shell)
var gravity: float = 0.0
var dt: float = 0.0
var pilot: PilotBlock = PilotBlock.new()
var pilot_tick: int = 0                     # tick of the last pilot block received
var missing: PackedInt32Array = PackedInt32Array()
var malformed: int = 0
var records_applied: int = 0
var _n: int = 0
var _idx: PackedInt32Array = PackedInt32Array()
var _kind: PackedByteArray = PackedByteArray()
var _mask: PackedInt32Array = PackedInt32Array()
var _pos: PackedInt64Array = PackedInt64Array()
var _ori: PackedInt64Array = PackedInt64Array()
var _vel: PackedInt64Array = PackedInt64Array()   # FULL: wire bits; DELTA: fine velocity
var _hp: PackedByteArray = PackedByteArray()
var _fl: PackedByteArray = PackedByteArray()
var _ai: PackedInt32Array = PackedInt32Array()
var _gap_idx: int = 0
var _tick: int = 0
# packets received per tick, ring keyed by tick % BaselineStore.DEPTH (A-36)
var _rx_tick: PackedInt32Array = PackedInt32Array()
var _rx_got: PackedByteArray = PackedByteArray()          # bit k = packet index k arrived
var _rx_last: PackedInt32Array = PackedInt32Array()       # index of the LAST packet, -1 not yet seen


func _init(gravity_mps2: float, tick_hz: int, team_id: int, roster_ref: Roster) -> void:
	gravity = gravity_mps2
	dt = 1.0 / float(maxi(tick_hz, 1))
	store = BaselineStore.new(team_id)
	roster = roster_ref
	var _r0: int = _idx.resize(MAX_RECORDS)
	var _r1: int = _kind.resize(MAX_RECORDS)
	var _r2: int = _mask.resize(MAX_RECORDS)
	var _r3: int = _pos.resize(MAX_RECORDS)
	var _r4: int = _ori.resize(MAX_RECORDS)
	var _r5: int = _vel.resize(MAX_RECORDS)
	var _r6: int = _hp.resize(MAX_RECORDS)
	var _r7: int = _fl.resize(MAX_RECORDS)
	var _r8: int = _ai.resize(MAX_RECORDS)
	var _r9: int = _rx_tick.resize(BaselineStore.DEPTH)
	var _ra: int = _rx_got.resize(BaselineStore.DEPTH)
	var _rb: int = _rx_last.resize(BaselineStore.DEPTH)
	_rx_tick.fill(0)


## The newest decoded frame (the client's current replicated state), or null.
func current() -> BaselineFrame:
	return store.frame_at(store.newest_tick)


## Replay playback (NET-25): forget which packet indices of `tick` arrived, so a second chunk of the same tick (its own
## index 0 .. LAST run) is accepted instead of STALE. Records already applied stay.
func forget_tick(tick: int) -> void:
	_rx_tick[tick % BaselineStore.DEPTH] = 0


## Replay seek (NET-25): drop every frame and receipt; the next packet must be a FULL tick (base 0).
func reset() -> void:
	store.reset()
	_rx_tick.fill(0)
	pilot_tick = 0
	malformed = 0
	records_applied = 0


## KEYFRAME (NET-07, KeyframeCodec.decode): forget every frame and packet receipt, begin the frame of `tick` against
## nothing and make `tick` the newest and the complete (acked) tick. The caller sets the frame's records with set_full.
## A SNAPSHOT of `tick` itself afterwards is STALE (the keyframe carries that tick's state). Returns the new frame.
func accept_keyframe(tick: int) -> BaselineFrame:
	store.reset()
	_rx_tick.fill(0)
	var f: BaselineFrame = store.begin(tick, 0)
	store.newest_tick = tick
	_mark(tick, 0, true)
	return f


## Decodes one SNAPSHOT packet. Returns a Status; only OK changes state.
func decode(bytes: PackedByteArray) -> int:
	var size: int = bytes.size()
	if size < SnapshotCodec.HEADER_BYTES or size > SnapshotCodec.MAX_PACKET_BYTES or bytes[0] != Protocol.SNAPSHOT:
		return _bad()
	var tick: int = bytes.decode_u32(1)
	var base: int = bytes.decode_u32(5)
	var fl: int = bytes[9]
	if tick == 0 or (base != 0 and base >= tick) or not _index_ok(tick, fl):
		return _bad()
	if tick < store.newest_tick:
		return Status.STALE
	var cur: BaselineFrame = store.frame_at(tick)
	if cur != null and cur.base_tick != base:
		return _bad()
	var src: BaselineFrame = cur if cur != null else store.frame_at(base)
	if base != 0 and src == null:
		return Status.NO_BASELINE
	_tick = tick
	var end: int = _parse(bytes, fl, src)
	if end == -2:
		return Status.MISSING_ROSTER
	var want: int = end + (PilotBlock.BYTES if fl & Protocol.SNAP_HAS_PILOT else 0)
	if end < 0 or want != size:
		return _bad()
	var k: int = fl >> Protocol.SNAP_INDEX_SHIFT
	if _got(tick) & (1 << k):
		return Status.STALE                 # this index of this tick was already applied
	if cur == null:
		cur = store.begin(tick, base)
	_apply_all(cur)
	if fl & Protocol.SNAP_HAS_PILOT:
		var _ok: bool = pilot.read(bytes, end)
		pilot_tick = tick
	store.newest_tick = tick
	_mark(tick, k, (fl & Protocol.SNAP_LAST) != 0)
	return Status.OK


## Header flag rules: exactly one of CONTINUED / LAST; the A-36 packet index against what this tick already saw.
func _index_ok(tick: int, fl: int) -> bool:
	var ends: int = fl & (Protocol.SNAP_CONTINUED | Protocol.SNAP_LAST)
	if ends == 0 or ends == (Protocol.SNAP_CONTINUED | Protocol.SNAP_LAST):
		return false
	var k: int = fl >> Protocol.SNAP_INDEX_SHIFT
	if (fl & Protocol.SNAP_HAS_PILOT) != 0 and k != 0:
		return false
	var got: int = _got(tick)
	var last: int = _rx_last[tick % BaselineStore.DEPTH] if got != 0 else -1
	if ends == Protocol.SNAP_LAST:
		return (got >> (k + 1)) == 0 and (last < 0 or last == k)
	return k < SnapshotCodec.MAX_PACKETS_PER_TICK - 1 and (last < 0 or k < last)


## Packet indices of `tick` received so far (bit mask; 0 when none or the ring slot holds another tick).
func _got(tick: int) -> int:
	var r: int = tick % BaselineStore.DEPTH
	return _rx_got[r] if _rx_tick[r] == tick else 0


func _mark(tick: int, k: int, last: bool) -> void:
	var r: int = tick % BaselineStore.DEPTH
	if _rx_tick[r] != tick:
		_rx_tick[r] = tick
		_rx_got[r] = 0
		_rx_last[r] = -1
	_rx_got[r] |= 1 << k
	if last:
		_rx_last[r] = k
	if _rx_last[r] >= 0 and _rx_got[r] == (1 << (_rx_last[r] + 1)) - 1 and tick > store.complete_tick:
		store.complete_tick = tick


func _bad() -> int:
	malformed += 1
	return Status.MALFORMED


## Offset after the last section, -1 malformed, -2 missing roster entry.
func _parse(b: PackedByteArray, fl: int, src: BaselineFrame) -> int:
	_n = 0
	missing.clear()
	var at: int = SnapshotCodec.HEADER_BYTES
	_gap_idx = 0
	var first: bool = true
	for tier: int in 3:
		if (fl & (Protocol.SNAP_HAS_A << tier)) == 0:
			continue
		if at >= b.size() or b[at] == 0:
			return -1
		var count: int = b[at]
		at += 1
		for _k: int in count:
			at = _parse_gap(b, at, first)
			first = false
			if at < 0:
				return -1
			if roster == null or not roster.has(_gap_idx):
				var _m: bool = missing.push_back(_gap_idx)
				return -2
			at = _parse_record(b, at, tier, src)
			if at < 0:
				return -1
	return at


func _parse_gap(b: PackedByteArray, at: int, first: bool) -> int:
	if at >= b.size() or _n >= MAX_RECORDS:
		return -1
	var g: int = b[at]
	var idx: int
	if g == SnapshotCodec.GAP_ESCAPE:
		if at + 3 > b.size():
			return -1
		idx = b.decode_u16(at + 1)
		at += 3
		if not first and idx == _gap_idx:
			return -1
	else:
		if g == 0 and not first:
			return -1
		idx = _gap_idx + g
		at += 1
	if idx >= Roster.CAPACITY:
		return -1
	_gap_idx = idx
	return at


func _parse_record(b: PackedByteArray, at: int, tier: int, src: BaselineFrame) -> int:
	if at >= b.size():
		return -1
	var i: int = _gap_idx
	var own: bool = roster.team_of(i) == store.team
	_idx[_n] = i
	_ai[_n] = -1
	var m: int = b[at]
	if m == SnapshotCodec.MASK_FULL:
		at = _parse_full(b, at + 1, own)
	elif src == null or src.present[i] == 0:
		return -1
	elif tier == SnapshotCodec.Tier.C:
		if at + 3 > b.size():
			return -1
		_kind[_n] = SnapshotCodec.Kind.BLIP
		_ori[_n] = Codec.read_u24(b, at)
		at += 3
	else:
		at = _parse_delta(b, at, tier == SnapshotCodec.Tier.B, src, own)
	if at >= 0:
		_n += 1
	return at


func _parse_full(b: PackedByteArray, at: int, own: bool) -> int:
	var body: int = SnapshotCodec.FULL_BODY_BYTES - 1 + (Codec.AI_TAG_BYTES if own else 0)
	if at + body > b.size():
		return -1
	var q: int = Codec.read_pos(b, at)
	if q == Codec.POS_INVALID:
		return -1
	_kind[_n] = SnapshotCodec.Kind.FULL
	_pos[_n] = q
	_ori[_n] = Codec.read_u32(b, at + 8)
	_vel[_n] = Codec.read_u24(b, at + 12)
	_hp[_n] = b[at + 15]
	_fl[_n] = b[at + 16]
	if own:
		_ai[_n] = b[at + 17]
	return at + body


func _parse_delta(b: PackedByteArray, at: int, tier_b: bool, src: BaselineFrame, own: bool) -> int:
	var m: int = b[at]
	if (m & 0xC0) != 0 or m == 0 or (m & 3) == 3 or ((m & SnapshotCodec.MASK_FLAGS) != 0 and tier_b and not own):
		return -1
	if at + SnapshotCodec.delta_body_bytes(m, tier_b, own) > b.size():
		return -1
	var i: int = _gap_idx
	var bq: int = src.pos[i]
	var dtk: int = _tick - src.etick[i]
	var def_id: int = roster.def_of(i)
	var grav: bool = (def_id >= 0 and def_id < gravity_def.size() and gravity_def[def_id] != 0) \
			or (src.flags[i] & Codec.FLAG_DYING) != 0
	var dr: Vector3i = DeadReckon.dr_levels(bq, src.vel[i], dtk, grav, gravity, dt)
	at += 1
	var res: Vector3i = Vector3i.ZERO
	if m & SnapshotCodec.MASK_POS_SMALL:
		res = Vector3i(_s8(b[at]), _s8(b[at + 1]), _s8(b[at + 2])) * (1 << SnapshotCodec.SMALL_SHIFT)
		at += 3
	elif m & SnapshotCodec.MASK_POS_LARGE:
		res = Vector3i(b.decode_s16(at), b.decode_s16(at + 2), b.decode_s16(at + 4))
		at += 6
	var lv: Vector3i = dr + res
	if not DeadReckon.levels_ok(dr) or not DeadReckon.levels_ok(lv):
		return -1
	_kind[_n] = SnapshotCodec.Kind.DELTA
	_mask[_n] = m | (0x100 if tier_b else 0)
	_pos[_n] = Codec.pack_pos(Codec.pos_cell(bq), lv.x, lv.y, lv.z)
	_vel[_n] = DeadReckon.dr_fine(bq, src.vel[i], dtk, grav, gravity, dt)
	return _parse_groups(b, at, m, tier_b, own)


func _parse_groups(b: PackedByteArray, at: int, m: int, tier_b: bool, own: bool) -> int:
	if m & SnapshotCodec.MASK_ORI:
		_ori[_n] = Codec.read_u24(b, at) if tier_b else Codec.read_u32(b, at)
		at += Codec.QUAT_COARSE_BYTES if tier_b else Codec.QUAT_BYTES
	if m & SnapshotCodec.MASK_VEL:
		_vel[_n] = DeadReckon.fine_from_bits(Codec.read_u24(b, at))
		at += 3
	if m & SnapshotCodec.MASK_HP:
		_hp[_n] = b[at]
		at += 1
	if m & SnapshotCodec.MASK_FLAGS:
		if not tier_b:
			_fl[_n] = b[at]
			at += 1
		if own:
			_ai[_n] = b[at]
			at += 1
	return at


static func _s8(v: int) -> int:
	return ((v & 0xFF) ^ 0x80) - 0x80


func _apply_all(cur: BaselineFrame) -> void:
	for k: int in _n:
		var i: int = _idx[k]
		var kind: int = _kind[k]
		if kind == SnapshotCodec.Kind.FULL:
			cur.set_full(i, _tick, _pos[k], _ori[k], _vel[k], _hp[k], _fl[k], _ai[k])
		elif kind == SnapshotCodec.Kind.BLIP:
			cur.set_blip(i, _tick, _ori[k])
		else:
			var m: int = _mask[k]
			cur.set_delta(i, _tick, (m & 0x100) != 0, m & 0xFF, _pos[k], _vel[k], _ori[k], _hp[k], _fl[k], _ai[k])
	records_applied += _n
