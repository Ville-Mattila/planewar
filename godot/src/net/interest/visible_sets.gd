class_name VisibleSets extends RefCounted
## The per-team visible sets V of one tick (04 s4.1), filled by SnapshotCodec.prepare_tick: TEAM_MAX lists of roster
## indices in one preallocated TEAM_MAX x CAPACITY array, so a tick allocates nothing per entity. A projectile entity's
## mask is its own team plus its shooter's and target's masks (R0 B.22 A-112; `entity_mask`).

const TEAM_MAX: int = 8
const CAPACITY: int = Roster.CAPACITY

var _vis: PackedInt32Array = PackedInt32Array()
var _n: PackedInt32Array = PackedInt32Array()


func _init() -> void:
	var e: int = _vis.resize(TEAM_MAX * CAPACITY) | _n.resize(TEAM_MAX)
	assert(e == OK)


func clear() -> void:
	_n.fill(0)


## Adds roster index `s` to the list of every team whose bit is set in `mask`.
func add(s: int, mask: int) -> void:
	for t: int in TEAM_MAX:
		if mask & (1 << t):
			_vis[t * CAPACITY + _n[t]] = s
			_n[t] += 1


## Team `team`'s list, ascending (a new array); empty for a team outside 0 .. TEAM_MAX - 1.
func sorted(team: int) -> PackedInt32Array:
	if team < 0 or team >= TEAM_MAX:
		return PackedInt32Array()
	var r: PackedInt32Array = _vis.slice(team * CAPACITY, team * CAPACITY + _n[team])
	r.sort()
	return r


## `vmask[s]` of the unit / structure / wreck `id` when its index was cached at `tick` with its generation (a 0
## generation in `gens` is unknown and matches), else 0. Projectile ids give 0: a shooter or target is an entity.
static func entity_mask(id: int, tick: int, ticks: PackedInt32Array, gens: PackedInt32Array, vmask: PackedInt32Array) -> int:
	var s: int = EntityId.slot(id) if id > 0 else -1
	if s < 0 or s >= Roster.PROJECTILE_INDEX_MIN or ticks[s] != tick or (gens[s] != 0 and gens[s] != EntityId.gen(id)):
		return 0
	return vmask[s]
