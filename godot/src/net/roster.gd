class_name Roster extends RefCounted
## Per-client roster (04 s3.1): up to CAPACITY entries binding a roster index to (generation, def_id, owner,
## team, tag). The roster index is a pure function of the sim slot (R0 B.22 A-112): index = slot for the EntityStore
## slots 0-1,535 (units, structures, wrecks; A-54) and index = 1,536 + (slot - EntityId.PROJECTILE_SLOT_MIN) for the
## ProjectileStore slots 4,096-6,143 (the projectile block). ENTITY_META / KEYFRAME / ROSTER_REMOVE carry the sim slot,
## SNAPSHOT records the index. Every method below takes a roster index. Packed arrays only; no Nodes.

const CAPACITY: int = 3584                  # 04 s3.1: 1,536 EntityStore slots + the 2,048-entry projectile block (A-112)
const ENTITY_SLOTS: int = EntityId.WRECK_SLOT_END                 # 1,536: indices 0 .. 1,535 equal their slot (A-54)
const PROJECTILE_INDEX_MIN: int = ENTITY_SLOTS                    # first index of the projectile block
const REASON_COUNT: int = 3                 # Protocol.RosterRemoveReason
const NEVER: int = -1

var _present: PackedByteArray = PackedByteArray()
var _gen: PackedInt32Array = PackedInt32Array()
var _def: PackedInt32Array = PackedInt32Array()
var _owner: PackedInt32Array = PackedInt32Array()
var _team: PackedInt32Array = PackedInt32Array()
var _tag: PackedStringArray = PackedStringArray()
var _last_reason: PackedInt32Array = PackedInt32Array()
var _count: int = 0


## Roster index of sim slot `slot`, or -1 for a slot no roster can hold (1,536-4,095, >= 6,144, negative).
static func index_of_slot(slot: int) -> int:
	if slot >= 0 and slot < ENTITY_SLOTS:
		return slot
	if slot >= EntityId.PROJECTILE_SLOT_MIN and slot < EntityId.PROJECTILE_SLOT_END:
		return slot - EntityId.PROJECTILE_SLOT_MIN + PROJECTILE_INDEX_MIN
	return -1


## Sim slot of roster index `index`, or -1 outside 0 .. CAPACITY - 1. Inverse of index_of_slot.
static func slot_of_index(index: int) -> int:
	if index >= 0 and index < ENTITY_SLOTS:
		return index
	if index >= PROJECTILE_INDEX_MIN and index < CAPACITY:
		return index - PROJECTILE_INDEX_MIN + EntityId.PROJECTILE_SLOT_MIN
	return -1


func _init() -> void:
	var _r: int = _present.resize(CAPACITY)
	_r = _gen.resize(CAPACITY)
	_r = _def.resize(CAPACITY)
	_r = _owner.resize(CAPACITY)
	_r = _team.resize(CAPACITY)
	_r = _tag.resize(CAPACITY)
	_r = _last_reason.resize(CAPACITY)
	_last_reason.fill(NEVER)


## Binds `slot`. Replaces any entry already there (a recycled slot has a new generation). False when out of range.
func add(slot: int, generation: int, def_id: int, owner: int, team: int, tag: String = "") -> bool:
	if slot < 0 or slot >= CAPACITY:
		return false
	if _present[slot] == 0:
		_present[slot] = 1
		_count += 1
	_gen[slot] = generation & 0xFFFF
	_def[slot] = def_id & 0xFFFF
	_owner[slot] = owner & 0xFF
	_team[slot] = team & 0xFF
	_tag[slot] = tag
	_last_reason[slot] = NEVER
	return true


## Removes `slot` and records why (Protocol.RosterRemoveReason). False when absent, out of range or reason invalid.
func remove(slot: int, reason: int) -> bool:
	if slot < 0 or slot >= CAPACITY or reason < 0 or reason >= REASON_COUNT or _present[slot] == 0:
		return false
	_present[slot] = 0
	_count -= 1
	_last_reason[slot] = reason
	_tag[slot] = ""
	return true


func has(slot: int) -> bool:
	return slot >= 0 and slot < CAPACITY and _present[slot] != 0


func count() -> int:
	return _count


func generation_of(slot: int) -> int:
	return _gen[slot] if has(slot) else NEVER


func def_of(slot: int) -> int:
	return _def[slot] if has(slot) else NEVER


func owner_of(slot: int) -> int:
	return _owner[slot] if has(slot) else NEVER


func team_of(slot: int) -> int:
	return _team[slot] if has(slot) else NEVER


func tag_of(slot: int) -> String:
	return _tag[slot] if has(slot) else ""


## Reason of the most recent removal of `slot`, or NEVER when present or never removed. Cleared by add().
func removal_reason_of(slot: int) -> int:
	if slot < 0 or slot >= CAPACITY:
		return NEVER
	return _last_reason[slot]


func clear() -> void:
	_present.fill(0)
	_last_reason.fill(NEVER)
	_count = 0


## Order-stable FNV-1a over present entries; equal rosters hash equal (determinism tests).
func state_hash() -> int:
	var h: int = 0x4BF29CE484222325
	for slot: int in CAPACITY:
		if _present[slot] == 0:
			continue
		h = (h ^ slot) * 0x100000001B3
		h = (h ^ _gen[slot]) * 0x100000001B3
		h = (h ^ _def[slot]) * 0x100000001B3
		h = (h ^ (_owner[slot] | (_team[slot] << 8))) * 0x100000001B3
		h = (h ^ _tag[slot].hash()) * 0x100000001B3
	return h
