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
var target: PackedInt32Array
var ttl: PackedFloat32Array
var hash_cell: PackedInt32Array

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


func _release_due(tick: int) -> void:
	while _q_n > 0 and _q_tick[_q_head] + _quarantine <= tick:
		_free[_free_n] = _q_slot[_q_head]
		_free_n += 1
		_q_head += 1
		if _q_head == SLOT_COUNT:
			_q_head = 0
		_q_n -= 1
