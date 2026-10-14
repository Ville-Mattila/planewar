class_name InterestClient extends RefCounted
## One client's interest state and the per-client half of Interest.assign (04 s4.1; NET-08). Inputs: team (or
## spectator), possessed / target / followed slot, INTEREST_HINT camera tier and focus cell, schedule key k.
## Each tick: A = possessed + target + visible entities within 600 m (great circle) of the anchor, cap 40 by
## distance; B (on (tick + k) % b_period == 0) = visible entities of the focus cell and its ring 1 (ring 2 at the
## Commander camera) not in A, cap 200 by distance to the focus; C (on (tick + k) % c_period == 0) = V \ A \ B,
## cap 1,000. Hysteresis: promotions are immediate, a demotion waits until the entity has been in its tier for
## STICKY_TICKS (inside the cap). Roster: an entity joins (`added`, send ENTITY_META first) when first tiered or
## when its generation changes; one that leaves V stays as a ghost and re-enters without a new ENTITY_META until
## GHOST_TICKS (30 s, checked on the client's C ticks) have passed, then `removed` (ROSTER_REMOVE OUT_OF_VISION);
## gone from the frame = DEATH; visible but never tiered for GHOST_TICKS = LEFT_INTEREST. Allocation-free per entity.

enum CameraTier { CHASE, TACTICAL, COMMANDER }      # INTEREST_HINT.camera_tier (04 s2.3)
enum Tier { NONE, A, B, C }
const NONE: int = -1
const A_RADIUS_M: float = 600.0
const A_CAP: int = 40
const B_CAP: int = 200
const C_CAP: int = 1000
const B_PERIOD: int = 2
const C_PERIOD: int = 15
const STICKY_TICKS: int = 15
const GHOST_TICKS: int = 900                        # 30 s at 30 Hz
const CAPACITY: int = Roster.CAPACITY
const _KEY_SHIFT: int = 11                          # slot bits of a sort key (CAPACITY <= 2048)
const _KEY_MASK: int = (1 << _KEY_SHIFT) - 1
const _KEY_SCALE: float = 1099511627776.0           # 2^40: squared unit chord (<= 4) to integer key bits

var key: int = 0
var team: int = 0
var spectator: bool = false
var possessed: int = NONE
var target: int = NONE
var follow: int = NONE
var camera_tier: int = CameraTier.CHASE
var focus_cell: int = NONE
var a_cap: int = A_CAP                              # rate governor knobs (04 s4.2, NET-09)
var b_cap: int = B_CAP
var c_cap: int = C_CAP
var b_period: int = B_PERIOD
var c_period: int = C_PERIOD
var a: PackedInt32Array = PackedInt32Array()        # encode lists this tick (b / c empty off their schedule)
var b: PackedInt32Array = PackedInt32Array()
var c: PackedInt32Array = PackedInt32Array()
var c_set: PackedInt32Array = PackedInt32Array()    # C as of the client's last C tick (NET-07 rolling refresh)
var cells: PackedInt32Array = PackedInt32Array()    # focus cell + ring of the last B tick (EventAudience cells)
var added: PackedInt32Array = PackedInt32Array()    # roster joins this tick (ENTITY_META before the snapshot)
var removed: PackedInt32Array = PackedInt32Array()  # roster leaves this tick (ROSTER_REMOVE)
var removed_reason: PackedInt32Array = PackedInt32Array()   # Protocol.RosterRemoveReason per removed slot
var b_tick: bool = false
var c_tick: bool = false
var _tier: PackedByteArray = PackedByteArray()
var _in: PackedByteArray = PackedByteArray()
var _since: PackedInt32Array = PackedInt32Array()
var _last_vis: PackedInt32Array = PackedInt32Array()
var _last_tier: PackedInt32Array = PackedInt32Array()
var _rgen: PackedInt32Array = PackedInt32Array()
var _a_mark: PackedInt32Array = PackedInt32Array()
var _b_mark: PackedInt32Array = PackedInt32Array()
var _cand: PackedInt32Array = PackedInt32Array()
var _members: PackedInt32Array = PackedInt32Array()
var _keys: PackedInt64Array = PackedInt64Array()
var _buf: PackedInt32Array = PackedInt32Array()
var _n_members: int = 0
var _cand_id: int = 0
var _b_last: int = -1
var _a_prev: PackedInt32Array = PackedInt32Array()
var _b_prev: PackedInt32Array = PackedInt32Array()
var _chord2_a: float = 0.0
var _anchor_ok: bool = false
var _anchor_dir: Vector3 = Vector3.ZERO
var _anchor_cell: int = NONE


func _init(schedule_key: int = 0, team_id: int = 0) -> void:
	key = schedule_key
	team = team_id
	var _r: int = _since.resize(CAPACITY)       # typed members, resized one by one (R0 C1-19)
	_r = _last_vis.resize(CAPACITY)
	_r = _last_tier.resize(CAPACITY)
	_r = _rgen.resize(CAPACITY)
	_r = _a_mark.resize(CAPACITY)
	_r = _b_mark.resize(CAPACITY)
	_r = _cand.resize(CAPACITY)
	_r = _members.resize(CAPACITY)
	_r = _buf.resize(CAPACITY)
	var _a: int = _tier.resize(CAPACITY)
	var _b: int = _in.resize(CAPACITY)
	var _c: int = _keys.resize(CAPACITY + 2)
	var half: float = A_RADIUS_M / (2.0 * Sphere.PLANET_RADIUS)
	_chord2_a = 4.0 * sin(half) * sin(half)
	reset()


## Forgets the roster and every tier (keyframe, reconnect): the next assign() re-adds what it tiers.
func reset() -> void:
	_tier.fill(Tier.NONE)
	_in.fill(0)
	_a_mark.fill(-1)
	_b_mark.fill(-1)
	_cand.fill(0)
	_n_members = 0
	_b_last = -1
	_a_prev = PackedInt32Array()
	_b_prev = PackedInt32Array()
	c_set = PackedInt32Array()


func in_roster(s: int) -> bool:
	return s >= 0 and s < CAPACITY and _in[s] != 0


func tier_of(s: int) -> int:
	return _tier[s] if s >= 0 and s < CAPACITY else Tier.NONE


func roster_count() -> int:
	return _n_members


## The per-client half of Interest.assign (call that); `it` has run begin_tick for this tick.
func assign(it: Interest) -> void:
	var t: int = it.tick
	added = PackedInt32Array()
	removed = PackedInt32Array()
	removed_reason = PackedInt32Array()
	_set_anchor(it)
	_select_a(it, t)
	b_tick = posmod(t + key, maxi(b_period, 1)) == 0
	c_tick = posmod(t + key, maxi(c_period, 1)) == 0
	b = _select_b(it, t) if b_tick else PackedInt32Array()
	c = PackedInt32Array()
	if c_tick:
		_select_c(it, t)
		c = c_set
		_sweep(it, t)


func _vteam() -> int:
	return -1 if spectator else team


func _set_anchor(it: Interest) -> void:
	var s: int = NONE
	if it.present(possessed):
		s = possessed
	elif it.visible(follow, _vteam()):
		s = follow
	_anchor_ok = true
	if s != NONE:
		_anchor_dir = it.dir[s]
		_anchor_cell = it.cell[s]
	elif camera_tier != CameraTier.COMMANDER and focus_cell >= 0 and focus_cell < Interest.CELLS:
		_anchor_dir = it.cell_dir[focus_cell]
		_anchor_cell = focus_cell
	else:
		_anchor_ok = false


func _select_a(it: Interest, t: int) -> void:
	_cand_id += 1
	var vt: int = _vteam()
	var n: int = _force(it, possessed, 0, vt)
	n = _force(it, target, n, vt)
	if _anchor_ok:
		n = _scan(it, _anchor_cell, _anchor_dir, n, _chord2_a, t, false)
		for j: int in Interest.RING1_STRIDE:
			var nb: int = it.ring1[_anchor_cell * Interest.RING1_STRIDE + j]
			if nb >= 0:
				n = _scan(it, nb, _anchor_dir, n, _chord2_a, t, false)
	n = _cap(n, a_cap)
	n = _sticky(it, t, Tier.A, n, a_cap, _a_prev)
	a = _commit(it, t, Tier.A, n, _a_prev)
	_a_prev = a


func _select_b(it: Interest, t: int) -> PackedInt32Array:
	_cand_id += 1
	var hinted: bool = focus_cell >= 0 and focus_cell < Interest.CELLS
	var focus: int = focus_cell if hinted else (_anchor_cell if _anchor_ok else NONE)
	if focus == NONE:
		cells = PackedInt32Array()
		_b_prev = _commit(it, t, Tier.B, 0, _b_prev)
		_b_last = t
		return _b_prev
	var fdir: Vector3 = it.cell_dir[focus] if hinted else _anchor_dir
	var ring: PackedInt32Array = it.ring2 if camera_tier == CameraTier.COMMANDER else it.ring1
	var stride: int = Interest.RING2_STRIDE if camera_tier == CameraTier.COMMANDER else Interest.RING1_STRIDE
	cells = PackedInt32Array([focus])
	var n: int = _scan(it, focus, fdir, 0, INF, t, true)
	for j: int in stride:
		var nb: int = ring[focus * stride + j]
		if nb >= 0:
			var _p: bool = cells.push_back(nb)
			n = _scan(it, nb, fdir, n, INF, t, true)
	n = _cap(n, b_cap)
	n = _sticky(it, t, Tier.B, n, b_cap, _b_prev)
	_b_prev = _commit(it, t, Tier.B, n, _b_prev)
	_b_last = t
	return _b_prev


## Candidates of cell `cell` within `limit` (squared unit chord) of `d0`, visible, not yet candidates; with
## `skip_a`, not in A this tick. Keys sort by distance, then slot.
func _scan(it: Interest, cell: int, d0: Vector3, n: int, limit: float, t: int, skip_a: bool) -> int:
	var vt: int = _vteam()
	var ids: PackedInt32Array = it.cell_ids               # locals: one property lookup per call, not per entity
	var vm: PackedInt32Array = it.vmask
	var dirs: PackedVector3Array = it.dir
	var a_t: int = t if skip_a else -2
	for idx: int in range(it.cell_start[cell], it.cell_start[cell + 1]):
		var s: int = ids[idx]
		if _cand[s] == _cand_id or _a_mark[s] == a_t or (vt >= 0 and ((vm[s] >> vt) & 1) == 0):
			continue
		var d2: float = (dirs[s] - d0).length_squared()
		if d2 > limit:
			continue
		_cand[s] = _cand_id
		_keys[n] = ((int(d2 * _KEY_SCALE) + 1) << _KEY_SHIFT) | s
		n += 1
	return n


## Possessed / target: always A when present and visible (key 0 + slot sorts ahead of every distance).
func _force(it: Interest, s: int, n: int, vt: int) -> int:
	if not it.visible(s, vt) or _cand[s] == _cand_id:
		return n
	_cand[s] = _cand_id
	_keys[n] = s
	return n + 1


## Keys [0, n) -> slots in _buf, nearest `cap` when over the cap (deterministic: distance, then slot).
func _cap(n: int, cap: int) -> int:
	var m: int = mini(n, maxi(cap, 0))
	if n > m:
		var part: PackedInt64Array = _keys.slice(0, n)
		part.sort()
		for i: int in m:
			_buf[i] = part[i] & _KEY_MASK
			_cand[_buf[i]] = _cand_id
		for i: int in range(m, n):
			_cand[part[i] & _KEY_MASK] = 0
	else:
		for i: int in m:
			_buf[i] = _keys[i] & _KEY_MASK
	return m


## Hysteresis: last list's members still visible, in `tier` for < STICKY_TICKS, fill the list up to the cap.
func _sticky(it: Interest, t: int, tier: int, n: int, cap: int, prev: PackedInt32Array) -> int:
	var vt: int = _vteam()
	for s: int in prev:
		if n >= cap:
			break
		if _cand[s] == _cand_id or _tier[s] != tier or t - _since[s] >= STICKY_TICKS or not it.visible(s, vt):
			continue
		if tier == Tier.B and _a_mark[s] == t:
			continue
		_cand[s] = _cand_id
		_buf[n] = s
		n += 1
	return n


## _buf[0, n) becomes the `tier` list: tier / since / marks / roster; `prev` members left out are demoted to C.
func _commit(it: Interest, t: int, tier: int, n: int, prev: PackedInt32Array) -> PackedInt32Array:
	var marks: PackedInt32Array = _a_mark if tier == Tier.A else _b_mark   # packed arrays: shared, not copied
	var gens: PackedInt32Array = it.gen
	for i: int in n:
		var s: int = _buf[i]
		if _tier[s] != tier:
			_tier[s] = tier
			_since[s] = t
		marks[s] = t
		_last_tier[s] = t
		_last_vis[s] = t
		if _in[s] == 0 or _rgen[s] != gens[s]:
			_admit(it, s)
	for s: int in prev:
		if marks[s] != t and _tier[s] == tier:
			_tier[s] = Tier.C
			_since[s] = t
	return _buf.slice(0, n)


func _admit(it: Interest, s: int) -> void:
	var g: int = it.gen[s]
	if _in[s] != 0 and _rgen[s] == g:
		return
	if _in[s] == 0:
		_members[_n_members] = s
		_n_members += 1
	_in[s] = 1
	_rgen[s] = g
	var _p: bool = added.push_back(s)


## C = V \ A \ B (B = the last B list), ascending slot; over the cap, the nearest to the focus / anchor. Marks
## _last_vis = t for all of V, which _sweep reads as "visible now".
func _select_c(it: Interest, t: int) -> void:
	_cand_id += 1
	var n: int = 0
	var b_last: int = _b_last
	for s: int in it.team_list(_vteam()):
		_last_vis[s] = t
		if _a_mark[s] == t or (_b_mark[s] == b_last and _tier[s] == Tier.B):
			continue
		_buf[n] = s
		n += 1
	if n > c_cap:
		n = _cap_c(it, n)
	var gens: PackedInt32Array = it.gen
	for i: int in n:
		var s: int = _buf[i]
		if _tier[s] != Tier.C:
			_tier[s] = Tier.C
			_since[s] = t
		_last_tier[s] = t
		if _in[s] == 0 or _rgen[s] != gens[s]:
			_admit(it, s)
	c_set = _buf.slice(0, n)


## Over the C cap: the c_cap nearest to the focus (or anchor) stay, ascending slot in _buf.
func _cap_c(it: Interest, n: int) -> int:
	var d0: Vector3 = it.cell_dir[focus_cell] if focus_cell >= 0 and focus_cell < Interest.CELLS else _anchor_dir
	for i: int in n:
		var s: int = _buf[i]
		_keys[i] = ((int((it.dir[s] - d0).length_squared() * _KEY_SCALE) + 1) << _KEY_SHIFT) | s
	var m: int = _cap(n, c_cap)
	var part: PackedInt32Array = _buf.slice(0, m)
	part.sort()
	for i: int in m:
		_buf[i] = part[i]
	return m


## Roster pruning on C ticks (after _select_c): gone or re-used slot -> DEATH; visible but untiered for
## GHOST_TICKS -> LEFT_INTEREST; a ghost unseen for GHOST_TICKS -> OUT_OF_VISION.
func _sweep(it: Interest, t: int) -> void:
	var stamp: PackedInt32Array = it.stamp
	var gens: PackedInt32Array = it.gen
	var m: int = 0
	for i: int in _n_members:
		var s: int = _members[i]
		var reason: int = NONE
		if stamp[s] != t or gens[s] != _rgen[s]:
			reason = Protocol.RosterRemoveReason.DEATH
		elif _last_vis[s] == t:
			if t - _last_tier[s] >= GHOST_TICKS:
				reason = Protocol.RosterRemoveReason.LEFT_INTEREST
		elif t - _last_vis[s] >= GHOST_TICKS:
			reason = Protocol.RosterRemoveReason.OUT_OF_VISION
		if reason == NONE:
			_members[m] = s
			m += 1
			continue
		_in[s] = 0
		_tier[s] = Tier.NONE
		var _p: bool = removed.push_back(s)
		var _q: bool = removed_reason.push_back(reason)
	_n_members = m
