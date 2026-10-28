class_name SnapshotCodec extends RefCounted
## Server half of the SNAPSHOT codec (04 s3.4-s3.5, R0 C1-02, C1-18). prepare_tick(frame) quantises every entity once per
## tick into the shared cache (indexed by roster index, Roster.index_of_slot; projectile entities in the block, R0 B.22
## A-112) and the per-team visible lists; encode() does per-client work only: gap ids, FULL / A-DELTA / B-DELTA / C-BLIP
## records against that client's acked baseline (gravity-aware dead reckoning), the 15-byte pilot block, splitting at
## 1,200 B into <= 4 indexed packets (A-36). Records reach the client's mirror through the BaselineFrame calls the decoder
## makes, so both stay identical. FULL / C-BLIP bytes come from SnapshotByteCache (A-40); no allocation per entity.

const HEADER_BYTES: int = 10
const MAX_PACKET_BYTES: int = Protocol.MAX_UNRELIABLE_BYTES
const MAX_PACKETS_PER_TICK: int = 4         # upper bound for `max_packets`
const SECTION_MAX: int = 255                # section count is u8
const TEAM_MAX: int = 8
const CAPACITY: int = Roster.CAPACITY
const MASK_POS_SMALL: int = 0x01            # 3 x i8 residual at 4 quanta
const MASK_POS_LARGE: int = 0x02            # 3 x i16 residual at 1 quantum
const MASK_ORI: int = 0x04
const MASK_VEL: int = 0x08
const MASK_HP: int = 0x10
const MASK_FLAGS: int = 0x20                # A: flags (+ ai_tag own team); B: AI_TAG (own team)
const MASK_CELL_CHANGED: int = 0x40         # never set in a DELTA (a cell change is a FULL record)
const MASK_FULL: int = 0xFF
const GAP_MAX: int = 254
const GAP_ESCAPE: int = 0xFF
const SMALL_SHIFT: int = 2
const SMALL_MAX: int = 127
## Residuals under one POS_SMALL step (4 quanta per axis) are not sent: smaller ones chatter on the +-2 quanta it leaves.
const POS_SEND_MIN: int = 1 << SMALL_SHIFT
const LARGE_MAX: int = 32767
const FULL_BODY_BYTES: int = 1 + Codec.POS_BYTES + Codec.QUAT_BYTES + Codec.VEL_BYTES + 2   # mask .. flags = 18
enum Tier { A, B, C }
enum Kind { NONE, FULL, DELTA, BLIP }

var gravity: float = 0.0
var dt: float = 0.0
var prepare_count: int = 0
var cache_tick: int = -1
## Packets per tick per client (1..MAX_PACKETS_PER_TICK); records past it are deferred (not in the mirror, re-planned
## later). Default 4 (A-36): a split tick is a baseline once complete and acked.
var max_packets: int = MAX_PACKETS_PER_TICK
var deferred: int = 0                       # records deferred by the packet cap in the last encode()
var cache_bytes: bool = true                # false: the pre-NET-49 FULL / C-BLIP path (same bytes, more cost)
var append_frame: bool = false              # true: encode() continues the frame begun for `tick` (replay chunks, NET-25)
var n_full: int = 0                         # cumulative record counters (tests, perf notes, NET-09 governor)
var n_delta: int = 0
var n_blip: int = 0
var n_pos_small: int = 0
var n_pos_large: int = 0
var c_tick: PackedInt32Array = PackedInt32Array()
var c_pos: PackedInt64Array = PackedInt64Array()
var c_ori: PackedInt64Array = PackedInt64Array()
var c_coarse: PackedInt32Array = PackedInt32Array()      # 24 bits: coarse quaternion + A-24 tier-B flags (lazy)
var c_vel: PackedInt32Array = PackedInt32Array()
var c_fine: PackedInt64Array = PackedInt64Array()        # c_vel as a DeadReckon fine velocity
var c_hp: PackedByteArray = PackedByteArray()
var c_flags: PackedByteArray = PackedByteArray()
var c_ai: PackedByteArray = PackedByteArray()
var c_team: PackedByteArray = PackedByteArray()
var c_grav: PackedByteArray = PackedByteArray()
var c_blip: PackedInt32Array = PackedInt32Array()        # lazy
var c_vmask: PackedInt32Array = PackedInt32Array()       # team bits incl. own; projectile: + shooter's, target's (A-112)
var c_gen: PackedInt32Array = PackedInt32Array()         # generation last seen per index (SnapshotFrame.gen; 0 unknown)
var _born: PackedInt32Array = PackedInt32Array()         # projectile block: first tick of the current generation
var _prow: PackedInt32Array = PackedInt32Array()         # projectile rows of this frame (second prepare pass)
var _coarse_tick: PackedInt32Array = PackedInt32Array()
var _blip_tick: PackedInt32Array = PackedInt32Array()
var _row: PackedInt32Array = PackedInt32Array()          # entity row in _frame
var _bc: SnapshotByteCache = SnapshotByteCache.new()    # FULL / C-BLIP bytes per entity per tick (A-40)
var _enc_id: int = 0
var _force: PackedInt32Array = PackedInt32Array()        # == _enc_id: rolling-refresh FULL in this encode
var _c_list: PackedInt32Array = PackedInt32Array()
var _frame: SnapshotFrame = null
var _vis: VisibleSets = VisibleSets.new()
var _w: SnapshotWriter = SnapshotWriter.new()
var _k_kind: int = Kind.NONE
var _k_mask: int = 0
var _k_body: int = 0
var _k_res: Vector3i = Vector3i.ZERO
var _k_pos: int = 0
var _k_vel: int = 0
var _tick: int = 0
var _capped: bool = false


func _init(gravity_mps2: float, tick_hz: int) -> void:
	gravity = gravity_mps2
	dt = 1.0 / float(maxi(tick_hz, 1))
	var n: int = CAPACITY
	var e: int = c_tick.resize(n) | c_coarse.resize(n) | c_vel.resize(n) | c_blip.resize(n) | c_fine.resize(n)
	e |= _coarse_tick.resize(n) | _blip_tick.resize(n) | _row.resize(n) | _force.resize(n) | c_pos.resize(n) | c_ori.resize(n)
	e |= c_hp.resize(n) | c_flags.resize(n) | c_ai.resize(n) | c_team.resize(n) | c_grav.resize(n) | c_vmask.resize(n)
	e |= c_gen.resize(n) | _born.resize(n) | _prow.resize(n)
	assert(e == OK)
	_force.fill(0)
	_coarse_tick.fill(-1)
	_blip_tick.fill(-1)
	c_tick.fill(-1)
	c_gen.fill(-1)


## Quantises every entity of `frame` once (R0 C1-02): rows whose slot no roster holds, and projectiles of kinds that never
## enter a roster (slug, flak, rail), are skipped (SnapshotFrame.index_of_row). Call once per tick before any encode().
func prepare_tick(frame: SnapshotFrame) -> void:
	prepare_count += 1
	cache_tick = frame.tick
	_frame = frame
	_vis.clear()
	var has_gen: bool = frame.gen.size() >= frame.count
	var np: int = 0
	for i: int in frame.count:
		var s: int = frame.slot[i]
		if s < 0 or s >= Roster.ENTITY_SLOTS:               # the projectile block (or no roster index)
			s = frame.index_of_row(i)
			if s < 0:
				continue
		_cache_entity(frame, i, s)
		var g: int = frame.gen[i] if has_gen else 0
		if s >= Roster.PROJECTILE_INDEX_MIN:
			if g != c_gen[s]:
				_born[s] = cache_tick
			_prow[np] = i
			np += 1
		c_gen[s] = g
		c_vmask[s] = frame.visible_mask[i] | (1 << (frame.team[i] % TEAM_MAX))
		if s < Roster.PROJECTILE_INDEX_MIN:
			_vis.add(s, c_vmask[s])
	for k: int in np:                       # projectiles after every entity: shooter / target bits are final (A-112)
		var i: int = _prow[k]
		var s: int = frame.index_of_row(i)
		var m: int = VisibleSets.entity_mask(frame.shooter[i], cache_tick, c_tick, c_gen, c_vmask)
		c_vmask[s] |= m | VisibleSets.entity_mask(frame.target[i], cache_tick, c_tick, c_gen, c_vmask)
		_vis.add(s, c_vmask[s])


func _cache_entity(frame: SnapshotFrame, i: int, s: int) -> void:
	var p: Vector3 = frame.pos[i]
	var q: int = Codec.quantize_pos(p)
	var r4: Vector4 = frame.rot[i]
	var vb: int = Codec.quantize_vel(frame.vel[i], q & 0xFFFF)
	_row[s] = i
	c_tick[s] = cache_tick
	c_pos[s] = q
	c_ori[s] = Codec.quantize_quat(Quaternion(r4.x, r4.y, r4.z, r4.w))
	c_vel[s] = vb
	c_fine[s] = DeadReckon.fine_from_bits(vb)
	c_hp[s] = Codec.quantize_hp(frame.hp01[i])
	c_flags[s] = frame.flags[i]
	c_ai[s] = frame.ai_tag[i]
	c_team[s] = frame.team[i]
	c_grav[s] = frame.gravity[i]


## Coarse orientation (17 bits) with the A-24 tier-B flags in its spare bits, for roster index `s` this tick.
func coarse_of(s: int) -> int:
	if _coarse_tick[s] != cache_tick:
		var r4: Vector4 = _frame.rot[_row[s]]
		c_coarse[s] = Codec.quantize_quat_coarse(Quaternion(r4.x, r4.y, r4.z, r4.w), Codec.flags_to_spare(c_flags[s]))
		_coarse_tick[s] = cache_tick
	return c_coarse[s]


## C-BLIP u24 for roster index `s` this tick.
func blip_of(s: int) -> int:
	if _blip_tick[s] != cache_tick:
		var i: int = _row[s]
		var fl: int = c_flags[s]
		var st: int = DeadReckon.BlipState.MOVING
		if fl & Codec.FLAG_DYING:
			st = DeadReckon.BlipState.DYING
		elif _frame.under_fire[i] != 0:
			st = DeadReckon.BlipState.UNDER_FIRE
		elif c_vel[s] == 0 or (fl & Codec.FLAG_DOCKED) != 0:
			st = DeadReckon.BlipState.STATIC
		c_blip[s] = DeadReckon.make_blip(c_pos[s], _frame.pos[i].length() - Sphere.PLANET_RADIUS, st)
		_blip_tick[s] = cache_tick
	return c_blip[s]


## Roster indices visible to `team` this tick, ascending (the tier-C candidate set, 04 s4.1).
func team_visible(team: int) -> PackedInt32Array:
	return _vis.sorted(team)


## Encodes tick `tick` for one client: tier lists `a`, `b`, `c` (roster indices; sorted here), `pilot` (null = none),
## `refresh` = rolling-refresh indices of the client's C set (04 s4.3, chosen by NET-07), each a FULL in section C.
## Appends <= MAX_PACKETS_PER_TICK packets of <= 1,200 B to `out` and builds the client's mirror frame in `store`.
## Returns the packet count (0 when prepare_tick was not called for `tick`).
func encode(store: BaselineStore, tick: int, a: PackedInt32Array, b: PackedInt32Array, c: PackedInt32Array,
		pilot: PilotBlock, out: Array[PackedByteArray], refresh: PackedInt32Array = PackedInt32Array()) -> int:
	if tick != cache_tick or tick <= 0:
		return 0
	_tick = tick
	_enc_id += 1
	deferred = 0
	var frame: BaselineFrame = store.frame_at(tick) if append_frame else null
	var base_tick: int = frame.base_tick if frame != null else store.base_for(tick)
	var base: BaselineFrame = store.frame_at(base_tick)
	frame = frame if frame != null else store.begin(tick, base_tick)
	_w.start(tick, base_tick, pilot, out, clampi(max_packets, 1, MAX_PACKETS_PER_TICK))
	_capped = false
	_encode_tier(a, Tier.A, base, frame, store.team)
	_encode_tier(b, Tier.B, base, frame, store.team)
	_encode_tier(_with_refresh(c, refresh), Tier.C, base, frame, store.team)
	frame.usable = true                     # A-36: the client acks only complete ticks
	return _w.finish()


func _encode_tier(list: PackedInt32Array, tier: int, base: BaselineFrame, frame: BaselineFrame, team: int) -> void:
	var sorted: PackedInt32Array = list.duplicate()
	sorted.sort()
	for s: int in sorted:
		if s < 0 or s >= CAPACITY or c_tick[s] != cache_tick:
			continue
		var own: bool = c_team[s] == team
		if not _plan(s, tier, base, own):
			continue
		if _capped or not _w.place(s, tier, _k_body):
			_capped = true
			deferred += 1
			continue
		_apply(frame, s, tier, own)
		_write_body(s, tier, own)
		_count()


## `c` plus the refresh indices (marked in _force for this encode); `c` itself when there are none.
func _with_refresh(c: PackedInt32Array, refresh: PackedInt32Array) -> PackedInt32Array:
	if refresh.is_empty():
		return c
	_c_list = c.duplicate()
	for s: int in refresh:
		if s >= 0 and s < CAPACITY and _force[s] != _enc_id:
			_force[s] = _enc_id
			if not c.has(s):
				var _p: bool = _c_list.push_back(s)
	return _c_list


func _plan(s: int, tier: int, base: BaselineFrame, own: bool) -> bool:
	if base == null or base.present[s] == 0 or Codec.pos_cell(base.pos[s]) != Codec.pos_cell(c_pos[s]) \
			or _force[s] == _enc_id or (s >= Roster.PROJECTILE_INDEX_MIN and base.etick[s] < _born[s]):
		return _plan_full(s, own)
	if tier == Tier.C:
		if blip_of(s) == base.shown_blip(s, _tick, c_grav[s] != 0, gravity, dt):    # NET-54: DR'd when unknown
			return false
		_k_kind = Kind.BLIP
		_k_body = 3
		return true
	return _plan_delta(s, tier, base, own)


func _plan_full(s: int, own: bool) -> bool:
	_k_kind = Kind.FULL
	_k_mask = MASK_FULL
	_k_body = FULL_BODY_BYTES + (Codec.AI_TAG_BYTES if own else 0)
	_k_pos = c_pos[s]
	_k_vel = c_vel[s]
	return true


func _plan_delta(s: int, tier: int, base: BaselineFrame, own: bool) -> bool:
	var bq: int = base.pos[s]
	var cq: int = c_pos[s]
	var dtk: int = _tick - base.etick[s]
	var grav: bool = base.base_grav(s, c_grav[s] != 0)       # A-103: false for a known blip
	var mask: int = 0
	var lv: Vector3i = Vector3i((bq >> 16) & 0xFFFF, (bq >> 32) & 0xFFFF, (bq >> 48) & 0xFFFF)
	if cq != bq or grav or base.vel[s] != 0:
		var dr: Vector3i = base.shown_levels(s, _tick, c_grav[s] != 0, gravity, dt)
		var res: Vector3i = Vector3i((cq >> 16) & 0xFFFF, (cq >> 32) & 0xFFFF, (cq >> 48) & 0xFFFF) - dr
		mask = SnapshotCodec.pos_mask(res)
		if mask < 0 or not DeadReckon.levels_ok(dr):
			return _plan_full(s, own)
		_k_res = SnapshotCodec.wire_residual(mask, res)
		lv = dr + (_k_res * (1 << SMALL_SHIFT) if mask == MASK_POS_SMALL else (res if mask == MASK_POS_LARGE else Vector3i.ZERO))
		if not DeadReckon.levels_ok(lv):
			return _plan_full(s, own)
	mask |= _plan_vel(s, bq, dtk, grav, base)
	if c_hp[s] != base.hp[s]:
		mask |= MASK_HP
	mask |= _plan_ori_flags(s, tier, base, own)
	if mask == 0:
		return false
	_k_kind = Kind.DELTA
	_k_mask = mask
	_k_body = SnapshotCodec.delta_body_bytes(mask, tier == Tier.B, own)
	_k_pos = Codec.pack_pos(cq & 0xFFFF, lv.x, lv.y, lv.z)
	return true


## Sets _k_vel to the entry's next fine velocity; MASK_VEL when the quantised velocity has to be sent.
func _plan_vel(s: int, bq: int, dtk: int, grav: bool, base: BaselineFrame) -> int:
	if not grav:
		_k_vel = base.vel[s]
		if c_fine[s] == _k_vel:
			return 0
		_k_vel = c_fine[s]
		return MASK_VEL
	_k_vel = DeadReckon.dr_fine(bq, base.vel[s], dtk, grav, gravity, dt)
	var vdr: int = DeadReckon.bits_from_fine(_k_vel)
	if c_vel[s] == vdr or DeadReckon.vel_close(c_vel[s], vdr):
		return 0
	_k_vel = c_fine[s]
	return MASK_VEL


func _plan_ori_flags(s: int, tier: int, base: BaselineFrame, own: bool) -> int:
	var m: int = 0
	if tier == Tier.A:
		if c_ori[s] != base.ori[s]:
			m |= MASK_ORI
		if c_flags[s] != base.flags[s] or (own and c_ai[s] != base.ai[s]):
			m |= MASK_FLAGS
	else:
		if (coarse_of(s) & 0x1FFFF) != base.ori_c[s] \
				or Codec.flags_to_spare(c_flags[s]) != Codec.flags_to_spare(base.flags[s]):
			m |= MASK_ORI
		if own and c_ai[s] != base.ai[s]:
			m |= MASK_FLAGS
	return m


func _count() -> void:
	n_full += 1 if _k_kind == Kind.FULL else 0
	n_blip += 1 if _k_kind == Kind.BLIP else 0
	if _k_kind == Kind.DELTA:
		n_delta += 1
		n_pos_small += _k_mask & MASK_POS_SMALL
		n_pos_large += (_k_mask & MASK_POS_LARGE) >> 1


func _apply(frame: BaselineFrame, s: int, tier: int, own: bool) -> void:
	var ai_tag: int = c_ai[s] if own else -1
	if _k_kind == Kind.FULL and cache_bytes:
		_bc.full(s, cache_tick, c_pos[s], c_ori[s], c_vel[s], c_hp[s] | (c_flags[s] << 8) | (c_ai[s] << 16))
		frame.set_full_cached(s, _tick, c_pos[s], c_ori[s], _bc.oc[s], c_fine[s], c_hp[s], c_flags[s], ai_tag)
	elif _k_kind == Kind.FULL:
		frame.set_full(s, _tick, c_pos[s], c_ori[s], c_vel[s], c_hp[s], c_flags[s], ai_tag)
	elif _k_kind == Kind.BLIP and cache_bytes:
		frame.set_blip_at(s, _tick, c_blip[s], _bc.blip_pos(s, cache_tick, c_pos[s], c_blip[s]))
	elif _k_kind == Kind.BLIP:
		frame.set_blip(s, _tick, c_blip[s])
	else:
		var ori_bits: int = c_coarse[s] if tier == Tier.B else c_ori[s]
		frame.set_delta(s, _tick, tier == Tier.B, _k_mask, _k_pos, _k_vel, ori_bits, c_hp[s], c_flags[s], ai_tag)


func _write_body(s: int, tier: int, own: bool) -> void:
	if _k_kind == Kind.FULL and cache_bytes:
		_w.put_full_words(_bc.w0[s], _bc.w1[s], _bc.w2[s], own)
	elif _k_kind == Kind.FULL:
		_w.put_full(c_pos[s], c_ori[s], c_vel[s], c_hp[s], c_flags[s], c_ai[s] if own else -1)
	elif _k_kind == Kind.BLIP:
		_w.put_u24(c_blip[s])
	else:
		var b: bool = tier == Tier.B
		_w.put_delta(_k_mask, _k_res, c_coarse[s] if b else c_ori[s], b, c_vel[s], c_hp[s], c_flags[s],
				c_ai[s] if own else -1)


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
