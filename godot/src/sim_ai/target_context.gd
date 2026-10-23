class_name TargetContext extends RefCounted
## Per-team facts the choice points need beyond `SimView` (05 s6.2, s6.8): which enemies attacked a friendly recently
## (fed from HIT events by the brain), how many friendly units already target each enemy, and the enemy towers whose
## envelopes penalise a target. Arrays are indexed by entity slot and preallocated; nothing here allocates per think.

const MAX_TOWERS: int = 64

var attacked_until: PackedInt32Array = PackedInt32Array()   ## tick until which the slot counts as "attacked a friendly"
var guard_until: PackedInt32Array = PackedInt32Array()      ## AI-17: tick until which the slot counts as an attacker of the GUARDed structure
var targeted_by: PackedByteArray = PackedByteArray()        ## friendly units currently targeting the slot (saturates 255)
var tower_count: int = 0
var tower_pos: PackedVector3Array = PackedVector3Array()
var tower_range: PackedFloat32Array = PackedFloat32Array()
var tower_env: Array[TowerEnvelope] = []
var scores: PackedFloat32Array = PackedFloat32Array()       ## scratch, aligned with the candidate ids


func _init(slots: int = EntityStore.SLOT_COUNT) -> void:
	var _r: Array[int] = [attacked_until.resize(slots), guard_until.resize(slots), targeted_by.resize(slots), tower_pos.resize(MAX_TOWERS),
		tower_range.resize(MAX_TOWERS), scores.resize(slots)]
	var _e: int = tower_env.resize(MAX_TOWERS)


func clear_towers() -> void:
	tower_count = 0


## Registers an enemy tower for the "inside an enemy envelope" test; false when the list is full.
func add_tower(pos: Vector3, range_m: float, env: TowerEnvelope) -> bool:
	if tower_count >= MAX_TOWERS:
		return false
	tower_pos[tower_count] = pos
	tower_range[tower_count] = range_m
	tower_env[tower_count] = env
	tower_count += 1
	return true


## A HIT by enemy `id` on a friendly at `tick`: it counts as an attacker until `tick + window_ticks`.
func mark_attacker(id: int, tick: int, window_ticks: int) -> void:
	attacked_until[EntityId.slot(id)] = tick + window_ticks


func attacked_recently(id: int, tick: int) -> bool:
	return attacked_until[EntityId.slot(id)] > tick


func guard_attacked(id: int, tick: int) -> bool:
	return guard_until[EntityId.slot(id)] > tick


func add_targeter(id: int) -> void:
	var s: int = EntityId.slot(id)
	targeted_by[s] = mini(targeted_by[s] + 1, 255)


func remove_targeter(id: int) -> void:
	var s: int = EntityId.slot(id)
	targeted_by[s] = maxi(targeted_by[s] - 1, 0)


## True when `p_t` (a target of def `def_id`) is inside the envelope and range of any registered enemy tower.
func under_tower(p_t: Vector3, def_id: int, terrain_h: float) -> bool:
	for i: int in tower_count:
		if tower_env[i].eligible(tower_pos[i], p_t, def_id, tower_range[i], terrain_h):
			return true
	return false
