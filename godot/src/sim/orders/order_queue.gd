class_name OrderQueue extends RefCounted
## The `orders` side table (R0 C2-06, 05 s2.1/s3.1): per entity slot a standing queue and a pending queue of
## at most 8 orders each, stored as packed record arrays (no per-entity objects). The head of the standing queue
## is mirrored into `EntityStore.order_kind` (the head cache, NONE_U8 when empty) by every mutation here, and
## those mutations mark the slot DIRTY_CONTROL. Patrol waypoints live in a shared block pool.
## Callers (SimWorld, control machine) call `clear_slot` when an entity is freed.

enum Push { OK, FULL, NO_POINTS, BAD_SLOT, BAD_SPEC }

const QUEUE_MAX: int = 8
const STANDING: int = 0
const PENDING: int = 1
const SLOTS: int = EntityId.WRECK_SLOT_MIN       # orders exist for main-range slots only
const BLOCK_POINTS: int = OrderSpec.WIRE_MAX_POINTS
const BLOCK_COUNT: int = SLOTS
const NO_BLOCK: int = -1
const _PER_SLOT: int = QUEUE_MAX * 2

## Lower queue_max (from order_rules.json) tightens the cap; storage stays 8 per queue.
var limit: int = QUEUE_MAX

var _store: EntityStore
var _n: PackedByteArray = PackedByteArray()          # [slot * 2 + which]
var _kind: PackedByteArray = PackedByteArray()       # per record, index = slot * 16 + which * 8 + i
var _flags: PackedByteArray = PackedByteArray()
var _haul: PackedByteArray = PackedByteArray()
var _emode: PackedByteArray = PackedByteArray()
var _npts: PackedByteArray = PackedByteArray()
var _target: PackedInt32Array = PackedInt32Array()
var _focus: PackedInt32Array = PackedInt32Array()
var _eslot: PackedInt32Array = PackedInt32Array()
var _issuer: PackedInt32Array = PackedInt32Array()
var _tick: PackedInt32Array = PackedInt32Array()
var _progress: PackedInt32Array = PackedInt32Array()
var _block: PackedInt32Array = PackedInt32Array()
var _point: PackedVector3Array = PackedVector3Array()
var _pts: PackedVector3Array = PackedVector3Array()   # block pool, BLOCK_POINTS per block
var _free: PackedInt32Array = PackedInt32Array()
var _free_n: int = 0


func _init(store: EntityStore) -> void:
	_store = store
	var rec: int = SLOTS * _PER_SLOT
	var e: int = 0
	e |= _n.resize(SLOTS * 2) | _kind.resize(rec) | _flags.resize(rec) | _haul.resize(rec) | _emode.resize(rec)
	e |= _npts.resize(rec) | _target.resize(rec) | _focus.resize(rec) | _eslot.resize(rec) | _issuer.resize(rec)
	e |= _tick.resize(rec) | _progress.resize(rec) | _block.resize(rec) | _point.resize(rec)
	e |= _pts.resize(BLOCK_COUNT * BLOCK_POINTS) | _free.resize(BLOCK_COUNT)
	assert(e == OK)
	reset()


## Empties every queue and the block pool. Does not touch the entity store.
func reset() -> void:
	_n.fill(0)
	_block.fill(NO_BLOCK)
	for i: int in BLOCK_COUNT:
		_free[i] = BLOCK_COUNT - 1 - i
	_free_n = BLOCK_COUNT


func count(slot: int, which: int) -> int:
	return _n[slot * 2 + which] if _valid(slot, which) else 0


## Free patrol blocks left in the pool.
func free_blocks() -> int:
	return _free_n


## Adds `spec` to queue `which` of `slot`: FLAG_QUEUE appends (FULL at the cap), FLAG_PREPEND inserts at the front
## (the tail is dropped when full), neither replaces the queue. Standing changes refresh the head cache.
func push(slot: int, which: int, spec: OrderSpec) -> Push:
	if not _valid(slot, which):
		return Push.BAD_SLOT
	var np: int = spec.points.size()
	var kind_v: int = spec.kind
	if np > BLOCK_POINTS or kind_v < 0 or kind_v >= OrderSpec.KIND_COUNT:
		return Push.BAD_SPEC
	var q: int = slot * 2 + which
	var n: int = _n[q]
	var is_append: bool = (spec.flags & OrderSpec.FLAG_QUEUE) != 0
	var prepend: bool = not is_append and (spec.flags & OrderSpec.FLAG_PREPEND) != 0
	if is_append and n >= limit:
		return Push.FULL
	if np > 0 and _free_n + _reclaimed(slot, which, is_append, prepend) < 1:
		return Push.NO_POINTS
	var at: int = n if is_append else 0
	if not is_append and not prepend:
		_clear_queue(slot, which)
	elif prepend:
		while _n[q] >= limit:
			_remove(slot, which, _n[q] - 1)
		_open_gap(slot, which, 0)
	_write(_rec(slot, which, at), spec)
	_n[q] = _n[q] + 1
	_after(slot, which)
	return Push.OK


## Appends `spec` exactly as given (its flags are stored untouched); for restoring saved queues.
func restore(slot: int, which: int, spec: OrderSpec) -> Push:
	if not _valid(slot, which):
		return Push.BAD_SLOT
	var np: int = spec.points.size()
	var kind_v: int = spec.kind
	if np > BLOCK_POINTS or kind_v < 0 or kind_v >= OrderSpec.KIND_COUNT:
		return Push.BAD_SPEC
	var n: int = _n[slot * 2 + which]
	if n >= QUEUE_MAX:
		return Push.FULL
	if np > 0 and _free_n == 0:
		return Push.NO_POINTS
	_write(_rec(slot, which, n), spec)
	_n[slot * 2 + which] = n + 1
	_after(slot, which)
	return Push.OK


## Fills `out` with order `i` of the queue; false if there is none.
func read(slot: int, which: int, i: int, out: OrderSpec) -> bool:
	if i < 0 or i >= count(slot, which):
		return false
	var r: int = _rec(slot, which, i)
	out.kind = _kind[r] as OrderSpec.Kind
	out.flags = _flags[r]
	out.haul_mode = _haul[r] as OrderSpec.HaulMode
	out.escort_mode = _emode[r] as OrderSpec.EscortMode
	out.target = _target[r]
	out.focus = _focus[r]
	out.escort_slot = _eslot[r]
	out.issuer = _issuer[r]
	out.issue_tick = _tick[r]
	out.progress = _progress[r]
	out.point = _point[r]
	var np: int = _npts[r]
	var _e: int = out.points.resize(np)
	var base: int = _block[r] * BLOCK_POINTS
	for k: int in np:
		out.points[k] = _pts[base + k]
	return true


## Kind ordinal of order `i`, or NONE_U8 when absent.
func kind_at(slot: int, which: int, i: int) -> int:
	if i < 0 or i >= count(slot, which):
		return EntityStore.NONE_U8
	return _kind[_rec(slot, which, i)]


## Issuer slot / issue tick of the standing head (05 s2.1 order_issuer, order_tick); -1 / 0 when empty.
func head_issuer(slot: int) -> int:
	return _issuer[_rec(slot, STANDING, 0)] if count(slot, STANDING) > 0 else -1


func head_tick(slot: int) -> int:
	return _tick[_rec(slot, STANDING, 0)] if count(slot, STANDING) > 0 else 0


func progress(slot: int, which: int, i: int) -> int:
	return _progress[_rec(slot, which, i)] if i >= 0 and i < count(slot, which) else 0


func set_progress(slot: int, which: int, i: int, value: int) -> bool:
	if i < 0 or i >= count(slot, which):
		return false
	_progress[_rec(slot, which, i)] = value
	return true


## Removes the head (completion or failure). False when empty.
func pop_head(slot: int, which: int) -> bool:
	return remove_at(slot, which, 0)


func remove_at(slot: int, which: int, i: int) -> bool:
	if i < 0 or i >= count(slot, which):
		return false
	_remove(slot, which, i)
	_after(slot, which)
	return true


func clear(slot: int, which: int) -> void:
	if _valid(slot, which):
		_clear_queue(slot, which)
		_after(slot, which)


## Both queues empty and the head cache reset (call when the entity is freed).
func clear_slot(slot: int) -> void:
	clear(slot, PENDING)
	clear(slot, STANDING)


## Release hand-back (05 s2): pending orders replace the standing queue. False if nothing was pending.
func commit_pending(slot: int) -> bool:
	if count(slot, PENDING) == 0:
		return false
	_clear_queue(slot, STANDING)
	var n: int = _n[slot * 2 + PENDING]
	for i: int in n:
		_move(_rec(slot, STANDING, i), _rec(slot, PENDING, i))
		_block[_rec(slot, PENDING, i)] = NO_BLOCK
	_n[slot * 2 + STANDING] = n
	_n[slot * 2 + PENDING] = 0
	_after(slot, STANDING)
	return true


## Rewrites `order_kind` of every slot from the standing heads (after a restore). No dirty marks.
func resync_heads() -> void:
	for s: int in range(1, SLOTS):
		_store.order_kind[s] = _kind[_rec(s, STANDING, 0)] if _n[s * 2] > 0 else EntityStore.NONE_U8


## True when every slot's `order_kind` equals the kind of its standing head (NONE_U8 when empty).
func head_cache_ok() -> bool:
	for s: int in range(1, SLOTS):
		var want: int = _kind[_rec(s, STANDING, 0)] if _n[s * 2] > 0 else EntityStore.NONE_U8
		if _store.order_kind[s] != want:
			return false
	return true


func _valid(slot: int, which: int) -> bool:
	return slot >= 1 and slot < SLOTS and (which == STANDING or which == PENDING)


func _rec(slot: int, which: int, i: int) -> int:
	return slot * _PER_SLOT + which * QUEUE_MAX + i


## Blocks that the push will free before it needs one: the whole queue on replace, the tail on a full prepend.
func _reclaimed(slot: int, which: int, is_append: bool, prepend: bool) -> int:
	var n: int = _n[slot * 2 + which]
	if is_append or n == 0:
		return 0
	if prepend:
		return 1 if n >= limit and _block[_rec(slot, which, n - 1)] != NO_BLOCK else 0
	var total: int = 0
	for i: int in n:
		total += 1 if _block[_rec(slot, which, i)] != NO_BLOCK else 0
	return total


func _after(slot: int, which: int) -> void:
	if which != STANDING:
		return
	_store.order_kind[slot] = _kind[_rec(slot, STANDING, 0)] if _n[slot * 2] > 0 else EntityStore.NONE_U8
	_store.dirty[slot] = _store.dirty[slot] | EntityStore.DIRTY_CONTROL


func _clear_queue(slot: int, which: int) -> void:
	var q: int = slot * 2 + which
	for i: int in _n[q]:
		_release(_rec(slot, which, i))
	_n[q] = 0


func _release(r: int) -> void:
	var b: int = _block[r]
	if b != NO_BLOCK:
		_free[_free_n] = b
		_free_n += 1
		_block[r] = NO_BLOCK
	_npts[r] = 0


func _remove(slot: int, which: int, i: int) -> void:
	var q: int = slot * 2 + which
	var n: int = _n[q]
	_release(_rec(slot, which, i))
	for k: int in range(i, n - 1):
		_move(_rec(slot, which, k), _rec(slot, which, k + 1))
	_block[_rec(slot, which, n - 1)] = NO_BLOCK
	_n[q] = n - 1


## Shifts records [at, n) up by one (n < QUEUE_MAX); the gap at `at` has no block.
func _open_gap(slot: int, which: int, at: int) -> void:
	var n: int = _n[slot * 2 + which]
	for k: int in range(n - 1, at - 1, -1):
		_move(_rec(slot, which, k + 1), _rec(slot, which, k))
	_block[_rec(slot, which, at)] = NO_BLOCK


func _move(dst: int, src: int) -> void:
	_kind[dst] = _kind[src]
	_flags[dst] = _flags[src]
	_haul[dst] = _haul[src]
	_emode[dst] = _emode[src]
	_npts[dst] = _npts[src]
	_target[dst] = _target[src]
	_focus[dst] = _focus[src]
	_eslot[dst] = _eslot[src]
	_issuer[dst] = _issuer[src]
	_tick[dst] = _tick[src]
	_progress[dst] = _progress[src]
	_block[dst] = _block[src]
	_point[dst] = _point[src]


func _write(r: int, spec: OrderSpec) -> void:
	_kind[r] = spec.kind
	_flags[r] = spec.flags & 0xFF
	_haul[r] = spec.haul_mode
	_emode[r] = spec.escort_mode
	_target[r] = spec.target
	_focus[r] = spec.focus
	_eslot[r] = spec.escort_slot
	_issuer[r] = spec.issuer
	_tick[r] = spec.issue_tick
	_progress[r] = spec.progress
	_point[r] = spec.point
	var np: int = spec.points.size()
	_npts[r] = np
	_block[r] = NO_BLOCK
	if np == 0:
		return
	_free_n -= 1
	var b: int = _free[_free_n]
	_block[r] = b
	for k: int in np:
		_pts[b * BLOCK_POINTS + k] = spec.points[k]
