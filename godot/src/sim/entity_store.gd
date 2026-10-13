class_name EntityStore extends RefCounted
## Structure-of-arrays entity state, 03 s3.1-3.2 (TA-11): 38 packed arrays, 150 B per slot,
## sized once to SLOT_COUNT and never resized. Two slot ranges with their own free stack and
## quarantine ring: MAIN (units and structures) and WRECK. A freed slot is allocatable again only
## QUARANTINE_TICKS after its free (S2); free bumps the generation and resets every field.
## Live-slot lists per kind are kept sorted by slot, so their order is a function of state alone.
## Per-player caps (MatchRules.caps) are enforced by callers before alloc (03 s3.1), not here.

const K_STRUCTURE: int = 0
const K_SHIP: int = 1
const K_GROUND: int = 2
const K_WRECK: int = 3

const F_ALIVE: int = 1
const F_DOCKED: int = 2
const F_LANDED: int = 4
const F_POSSESSABLE: int = 8
const F_BUILDING: int = 16
const F_POWERED: int = 32
const F_CEILING_FORCED: int = 64
const F_TETHERED: int = 128

const DIRTY_POSE: int = 1
const DIRTY_VITALS: int = 2
const DIRTY_CONTROL: int = 4
const DIRTY_CARGO: int = 8
const DIRTY_SPAWNED: int = 16
const DIRTY_DIED: int = 32

## u8 "none" for owner/team (neutral), possessor and order_kind.
const NONE_U8: int = 255
## S2: a slot is never reused within this many ticks of its free.
const QUARANTINE_TICKS: int = 64
const SLOT_COUNT: int = EntityId.WRECK_SLOT_END
const RANGE_MAIN: int = 0
const RANGE_WRECK: int = 1

var generation: PackedInt32Array
var def_id: PackedInt32Array
var kind: PackedByteArray
var flags: PackedByteArray
var owner: PackedByteArray
var team: PackedByteArray
var spawn_tick: PackedInt32Array
var pos: PackedVector3Array
var vel: PackedVector3Array
var fwd: PackedVector3Array
var up: PackedVector3Array
var rates: PackedVector3Array
var radius: PackedFloat32Array
var hash_cell: PackedInt32Array
var control_state: PackedByteArray
var possessor: PackedByteArray
var order_kind: PackedByteArray
var hp: PackedFloat32Array
var fuel: PackedFloat32Array
var ammo: PackedInt32Array
var bombs: PackedByteArray
var rockets: PackedByteArray
var cd_primary: PackedFloat32Array
var cd_secondary: PackedFloat32Array
var boost_time: PackedFloat32Array
var flip_time: PackedFloat32Array
var last_damage_tick: PackedInt32Array
var attacker: PackedInt32Array
var cargo: PackedFloat32Array
var cargo_kind: PackedByteArray
var link: PackedInt32Array
var timer_a: PackedFloat32Array
var timer_b: PackedFloat32Array
var ai_tag: PackedByteArray
var overlay: PackedByteArray
var visible_mask: PackedByteArray
var dirty: PackedByteArray
var anchor_cell: PackedInt32Array

## Live-slot lists, ascending slot order (03 s3.4). Read-only for callers.
var ships: PackedInt32Array = PackedInt32Array()
var ground: PackedInt32Array = PackedInt32Array()
var structures: PackedInt32Array = PackedInt32Array()
var wrecks: PackedInt32Array = PackedInt32Array()

var _quarantine: int = QUARANTINE_TICKS
# Per range r: slots [_first[r], _first[r] + _cap[r]); its region of _free/_q_* starts at _base[r].
var _first: PackedInt32Array = PackedInt32Array([1, EntityId.WRECK_SLOT_MIN])
var _cap: PackedInt32Array = PackedInt32Array([EntityId.WRECK_SLOT_MIN - 1, EntityId.WRECK_SLOT_END - EntityId.WRECK_SLOT_MIN])
var _base: PackedInt32Array = PackedInt32Array([0, EntityId.WRECK_SLOT_MIN - 1])
var _free_n: PackedInt32Array = PackedInt32Array([0, 0])
var _q_head: PackedInt32Array = PackedInt32Array([0, 0])
var _q_n: PackedInt32Array = PackedInt32Array([0, 0])
var _q_last: PackedInt32Array = PackedInt32Array([0, 0])
var _free: PackedInt32Array = PackedInt32Array()
var _q_slot: PackedInt32Array = PackedInt32Array()
var _q_tick: PackedInt32Array = PackedInt32Array()


## quarantine_ticks overrides S2's 64 for tests only; SimWorld uses the default.
func _init(quarantine_ticks: int = QUARANTINE_TICKS) -> void:
	_quarantine = quarantine_ticks
	var n: int = SLOT_COUNT
	var e: int = 0
	e |= generation.resize(n) | def_id.resize(n) | kind.resize(n) | flags.resize(n)
	e |= owner.resize(n) | team.resize(n) | spawn_tick.resize(n) | pos.resize(n) | vel.resize(n)
	e |= fwd.resize(n) | up.resize(n) | rates.resize(n) | radius.resize(n) | hash_cell.resize(n)
	e |= control_state.resize(n) | possessor.resize(n) | order_kind.resize(n) | hp.resize(n)
	e |= fuel.resize(n) | ammo.resize(n) | bombs.resize(n) | rockets.resize(n) | cd_primary.resize(n)
	e |= cd_secondary.resize(n) | boost_time.resize(n) | flip_time.resize(n)
	e |= last_damage_tick.resize(n) | attacker.resize(n) | cargo.resize(n) | cargo_kind.resize(n)
	e |= link.resize(n) | timer_a.resize(n) | timer_b.resize(n) | ai_tag.resize(n) | overlay.resize(n)
	e |= visible_mask.resize(n) | dirty.resize(n) | anchor_cell.resize(n)
	var ring: int = SLOT_COUNT - 1
	e |= _free.resize(ring) | _q_slot.resize(ring) | _q_tick.resize(ring)
	assert(e == OK)
	generation.fill(1)
	for s: int in n:
		clear_slot(s)
	for r: int in 2:
		var c: int = _cap[r]
		for i: int in c:
			_free[_base[r] + i] = _first[r] + c - 1 - i   # lowest slot on top of the stack
		_free_n[r] = c


## Allocates a slot of `entity_kind` (K_*) at `tick`; NULL_ID when its range has no free slot.
func alloc(entity_kind: int, tick: int) -> int:
	if entity_kind < K_STRUCTURE or entity_kind > K_WRECK:
		return EntityId.NULL_ID
	var r: int = RANGE_WRECK if entity_kind == K_WRECK else RANGE_MAIN
	_release_due(r, tick)
	var n: int = _free_n[r]
	if n == 0:
		return EntityId.NULL_ID
	n -= 1
	_free_n[r] = n
	var s: int = _free[_base[r] + n]
	kind[s] = entity_kind
	flags[s] = F_ALIVE
	spawn_tick[s] = tick
	dirty[s] = DIRTY_SPAWNED
	_list_insert(entity_kind, s)
	return EntityId.make(s, generation[s])


## Frees a live slot at `tick`: generation bump, clear_slot, dirty = DIRTY_DIED, into quarantine.
## Returns false (no effect) for a dead or out-of-range slot.
func free_slot(slot_index: int, tick: int) -> bool:
	var r: int = _range_of(slot_index)
	if r < 0 or (flags[slot_index] & F_ALIVE) == 0:
		return false
	_list_remove(kind[slot_index], slot_index)
	generation[slot_index] = EntityId.bump_gen(generation[slot_index])
	clear_slot(slot_index)
	dirty[slot_index] = DIRTY_DIED
	var c: int = _cap[r]
	var t: int = maxi(tick, _q_last[r])   # keeps the ring ordered by release tick
	_q_last[r] = t
	var at: int = _q_head[r] + _q_n[r]
	if at >= c:
		at -= c
	_q_slot[_base[r] + at] = slot_index
	_q_tick[_base[r] + at] = t
	_q_n[r] += 1
	return true


func alive(id: int) -> bool:
	var s: int = EntityId.slot(id)
	if s < 1 or s >= SLOT_COUNT:
		return false
	return generation[s] == EntityId.gen(id) and (flags[s] & F_ALIVE) != 0


## The current EntityId of a slot (valid only while the slot is alive).
func id_of(slot_index: int) -> int:
	return EntityId.make(slot_index, generation[slot_index])


## Resets every field except `generation` to zero, or to its none sentinel (NONE_U8 for owner,
## team, possessor, order_kind; -1 for anchor_cell). Does not touch live lists or free stacks.
func clear_slot(s: int) -> void:
	def_id[s] = 0
	kind[s] = 0
	flags[s] = 0
	owner[s] = NONE_U8
	team[s] = NONE_U8
	spawn_tick[s] = 0
	pos[s] = Vector3.ZERO
	vel[s] = Vector3.ZERO
	fwd[s] = Vector3.ZERO
	up[s] = Vector3.ZERO
	rates[s] = Vector3.ZERO
	radius[s] = 0.0
	hash_cell[s] = 0
	control_state[s] = 0
	possessor[s] = NONE_U8
	order_kind[s] = NONE_U8
	hp[s] = 0.0
	fuel[s] = 0.0
	ammo[s] = 0
	bombs[s] = 0
	rockets[s] = 0
	cd_primary[s] = 0.0
	cd_secondary[s] = 0.0
	boost_time[s] = 0.0
	flip_time[s] = 0.0
	_clear_tail(s)


func free_count(range_id: int) -> int:
	return _free_n[range_id]


func quarantined_count(range_id: int) -> int:
	return _q_n[range_id]


func live_count() -> int:
	return ships.size() + ground.size() + structures.size() + wrecks.size()


func _clear_tail(s: int) -> void:
	last_damage_tick[s] = 0
	attacker[s] = 0
	cargo[s] = 0.0
	cargo_kind[s] = 0
	link[s] = 0
	timer_a[s] = 0.0
	timer_b[s] = 0.0
	ai_tag[s] = 0
	overlay[s] = 0
	visible_mask[s] = 0
	dirty[s] = 0
	anchor_cell[s] = -1


func _range_of(s: int) -> int:
	if s >= 1 and s < EntityId.WRECK_SLOT_MIN:
		return RANGE_MAIN
	if s >= EntityId.WRECK_SLOT_MIN and s < EntityId.WRECK_SLOT_END:
		return RANGE_WRECK
	return -1


## Moves quarantined slots of range r whose release tick + quarantine <= tick onto the free stack.
func _release_due(r: int, tick: int) -> void:
	var qn: int = _q_n[r]
	if qn == 0:
		return
	var base: int = _base[r]
	var c: int = _cap[r]
	var head: int = _q_head[r]
	var fn: int = _free_n[r]
	while qn > 0 and _q_tick[base + head] + _quarantine <= tick:
		_free[base + fn] = _q_slot[base + head]
		fn += 1
		head += 1
		if head == c:
			head = 0
		qn -= 1
	_q_head[r] = head
	_q_n[r] = qn
	_free_n[r] = fn


func _list_insert(k: int, s: int) -> void:
	var e: int = OK
	match k:
		K_SHIP:
			e = ships.insert(ships.bsearch(s), s)
		K_GROUND:
			e = ground.insert(ground.bsearch(s), s)
		K_STRUCTURE:
			e = structures.insert(structures.bsearch(s), s)
		_:
			e = wrecks.insert(wrecks.bsearch(s), s)
	assert(e == OK)


func _list_remove(k: int, s: int) -> void:
	match k:
		K_SHIP:
			ships.remove_at(ships.bsearch(s))
		K_GROUND:
			ground.remove_at(ground.bsearch(s))
		K_STRUCTURE:
			structures.remove_at(structures.bsearch(s))
		_:
			wrecks.remove_at(wrecks.bsearch(s))
