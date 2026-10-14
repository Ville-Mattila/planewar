class_name Roster extends RefCounted
## Per-client roster (04 s3.1): up to CAPACITY entries binding a roster index to (generation, def_id, owner,
## team, tag). The roster index IS the sim slot number (04 s3.1: indices reuse slots inside KEYFRAME and
## ENTITY_META). Built by KEYFRAME / ENTITY_META, pruned by ROSTER_REMOVE. Packed arrays only; no Nodes.

const CAPACITY: int = 1536                  # 04 s3.1: one entry per EntityStore slot 0-1,535 (R0 B.11 A-54)
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
