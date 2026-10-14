class_name ProjectileStore extends RefCounted
## Projectile pool, 03 s3.3 (TA-11): 14 packed arrays, 62 B per slot, SLOT_COUNT slots that map
## to EntityId slots PROJECTILE_SLOT_MIN + index (03 s3.1). Arrays are indexed by the local
## index; `live` holds live local indices in ascending order. Same free stack + quarantine ring
## scheme as EntityStore (S2). `live_cap` is MatchRules.caps.projectiles (CapsDef), enforced here
## because the projectile cap is global, not per player; the layout never shrinks.

const SLUG: int = 0
const BOMB: int = 1
const ROCKET: int = 2
const FLAK: int = 3
const RAIL: int = 4
const SIEGE_SHELL: int = 5
const CANISTER: int = 6   # reserved, SL-5 (v1 stretch)

const F_ALIVE: int = 1
const F_ARMED: int = 2
const F_GUIDED: int = 4

const NONE_U8: int = 255
## Owner decision 2026-10-13 (03 s3.1 amended): projectiles quarantine 0 ticks, not 64. The
## generation bump keeps ids unique; 64 ticks strands ~3,700 slots and even 1-2 ticks overflow the 48 spare slots at the 2,000 cap.
const QUARANTINE_TICKS: int = 0
## 03 s3.1 range PROJECTILE_SLOT_MIN .. PROJECTILE_SLOT_END - 1 (R0 B.9 A-20).
const SLOT_COUNT: int = EntityId.PROJECTILE_SLOT_END - EntityId.PROJECTILE_SLOT_MIN
## Every array, the live list, cap, free stack and quarantine ring, in serialization order (S4, TA-18).
const _STATE: PackedStringArray = ["generation", "pos", "vel", "prev_pos", "kind", "projectile_def", "weapon_def", "owner",
	"team", "flags", "shooter", "target", "ttl", "hash_cell", "live", "live_cap", "_free", "_free_n", "_q_slot", "_q_tick",
	"_q_head", "_q_n", "_q_last"]

var generation: PackedInt32Array
var pos: PackedVector3Array
var vel: PackedVector3Array
var prev_pos: PackedVector3Array
var kind: PackedByteArray
var projectile_def: PackedByteArray
var weapon_def: PackedByteArray
var owner: PackedByteArray
var team: PackedByteArray
var flags: PackedByteArray
var shooter: PackedInt32Array
var target: PackedInt32Array   ## ROCKET: lock target EntityId; FLAK: timed-fuse burst tick (GD-36); 0 = none
var ttl: PackedFloat32Array
var hash_cell: PackedInt32Array

const _SLOT_ARRAYS: int = 14   ## the first 14 names of _STATE are the per-slot arrays

## Live local indices, ascending. Read-only for callers.
var live: PackedInt32Array = PackedInt32Array()
var live_cap: int = SLOT_COUNT

var _quarantine: int = QUARANTINE_TICKS
var _free: PackedInt32Array = PackedInt32Array()
var _free_n: int = 0
var _q_slot: PackedInt32Array = PackedInt32Array()
var _q_tick: PackedInt32Array = PackedInt32Array()
var _q_head: int = 0
var _q_n: int = 0
var _q_last: int = 0


## cap_live: MatchRules.caps.projectiles (clamped to SLOT_COUNT). quarantine_ticks: tests only.
func _init(cap_live: int, quarantine_ticks: int = QUARANTINE_TICKS) -> void:
	live_cap = clampi(cap_live, 0, SLOT_COUNT)
	_quarantine = quarantine_ticks
	var n: int = SLOT_COUNT
	var e: int = 0
	e |= generation.resize(n) | pos.resize(n) | vel.resize(n) | prev_pos.resize(n) | kind.resize(n)
	e |= projectile_def.resize(n) | weapon_def.resize(n) | owner.resize(n) | team.resize(n)
	e |= flags.resize(n) | shooter.resize(n) | target.resize(n) | ttl.resize(n) | hash_cell.resize(n)
	e |= _free.resize(n) | _q_slot.resize(n) | _q_tick.resize(n)
	assert(e == OK)
	generation.fill(1)
	for i: int in n:
		clear_slot(i)
		_free[i] = n - 1 - i   # lowest index on top of the stack
	_free_n = n


## Allocates a projectile of `projectile_kind` at `tick`; NULL_ID at live_cap or with no free slot.
## The caller writes the remaining fields (projectile_def, weapon_def, pos, vel, ttl, ...).
func alloc(projectile_kind: int, tick: int) -> int:
	if projectile_kind < SLUG or projectile_kind > CANISTER or live.size() >= live_cap:
		return EntityId.NULL_ID
	_release_due(tick)
	if _free_n == 0:
		return EntityId.NULL_ID
	_free_n -= 1
	var i: int = _free[_free_n]
	kind[i] = projectile_kind
	flags[i] = F_ALIVE
	var e: int = live.insert(live.bsearch(i), i)
	assert(e == OK)
	return EntityId.make(EntityId.PROJECTILE_SLOT_MIN + i, generation[i])


## Allocates and fills one projectile in a single call (Combat's weapon fire, GD-36): the writes go through this
## object's own members, so a caller never copies a pool array (03 s12.2 rule 11). `prev_pos` = `p`; `extra_flags`
## are OR-ed onto F_ALIVE (F_GUIDED for a locked rocket). NULL_ID at live_cap or with no free slot.
func spawn(projectile_kind: int, tick: int, p: Vector3, v: Vector3, ttl_s: float, projectile_local: int,
		weapon_local: int, owner_slot: int, team_id: int, shooter_id: int, target_id: int, extra_flags: int) -> int:
	var id: int = alloc(projectile_kind, tick)
	if id == EntityId.NULL_ID:
		return id
	var i: int = index_of(id)
	pos[i] = p
	prev_pos[i] = p
	vel[i] = v
	ttl[i] = ttl_s
	projectile_def[i] = projectile_local
	weapon_def[i] = weapon_local
	owner[i] = owner_slot
	team[i] = team_id
	shooter[i] = shooter_id
	target[i] = target_id
	flags[i] = F_ALIVE | extra_flags
	return id


## Frees a live local index at `tick` (generation bump, clear, quarantine). False if not live.
func free_slot(index: int, tick: int) -> bool:
	if index < 0 or index >= SLOT_COUNT or (flags[index] & F_ALIVE) == 0:
		return false
	live.remove_at(live.bsearch(index))
	generation[index] = EntityId.bump_gen(generation[index])
	clear_slot(index)
	_q_last = maxi(tick, _q_last)
	var at: int = _q_head + _q_n
	if at >= SLOT_COUNT:
		at -= SLOT_COUNT
	_q_slot[at] = index
	_q_tick[at] = _q_last
	_q_n += 1
	return true


func alive(id: int) -> bool:
	var i: int = index_of(id)
	return i >= 0 and generation[i] == EntityId.gen(id) and (flags[i] & F_ALIVE) != 0


## Local index of a projectile EntityId (generation not checked), or -1 outside the range.
func index_of(id: int) -> int:
	var i: int = EntityId.slot(id) - EntityId.PROJECTILE_SLOT_MIN
	return i if i >= 0 and i < SLOT_COUNT else -1


func id_of(index: int) -> int:
	return EntityId.make(EntityId.PROJECTILE_SLOT_MIN + index, generation[index])


## Resets every field except `generation` (owner/team to NONE_U8, the rest to zero).
func clear_slot(i: int) -> void:
	pos[i] = Vector3.ZERO
	vel[i] = Vector3.ZERO
	prev_pos[i] = Vector3.ZERO
	kind[i] = 0
	projectile_def[i] = 0
	weapon_def[i] = 0
	owner[i] = NONE_U8
	team[i] = NONE_U8
	flags[i] = 0
	shooter[i] = 0
	target[i] = 0
	ttl[i] = 0.0
	hash_cell[i] = 0


func live_count() -> int:
	return live.size()


func free_count() -> int:
	return _free_n


func quarantined_count() -> int:
	return _q_n


## Appends the whole pool (S4) to `buf`.
func write_state(buf: StreamPeerBuffer) -> void:
	StateIO.put_props(buf, self, _STATE)


## Replaces the whole pool from `write_state` bytes; false on a type or size mismatch.
func read_state(buf: StreamPeerBuffer) -> bool:
	return StateIO.get_props(buf, self, _STATE) and _state_ok()


# Range checks of a restored pool: array sizes, counters, free and quarantined indices, the live list.
func _state_ok() -> bool:
	var n: int = SLOT_COUNT
	if not StateIO.sizes_ok(self, _STATE.slice(0, _SLOT_ARRAYS), n) or not StateIO.sizes_ok(self, ["_free", "_q_slot", "_q_tick"], n):
		return false
	if _free_n < 0 or _q_n < 0 or _free_n + _q_n > n or _q_head < 0 or _q_head >= n or live_cap < 0 or live_cap > n:
		return false
	if not StateIO.ints_in(_free, _free_n, 0, n - 1) or live.size() > n:
		return false
	for i: int in _q_n:
		if _q_slot[(_q_head + i) % n] < 0 or _q_slot[(_q_head + i) % n] >= n:
			return false
	var prev: int = -1
	for i: int in live:
		if i <= prev or i >= n or (flags[i] & F_ALIVE) == 0 or kind[i] > CANISTER:
			return false
		prev = i
	return true


func _release_due(tick: int) -> void:
	while _q_n > 0 and _q_tick[_q_head] + _quarantine <= tick:
		_free[_free_n] = _q_slot[_q_head]
		_free_n += 1
		_q_head += 1
		if _q_head == SLOT_COUNT:
			_q_head = 0
		_q_n -= 1
