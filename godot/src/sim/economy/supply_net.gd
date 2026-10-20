class_name SupplyNet extends RefCounted
## The supply network (02 s5.4, GD-18). Roots: finished Cores and Outposts. Links: a finished Relay Pylon whose centre is
## inside the build radius of a root or of an already linked Pylon (same team; a teammate's network counts for the
## team). A finished structure is **supplied** when its centre is inside the build radius of a connected node of its team
## (a root or linked Pylon is supplied itself). `unsupplied[slot]` = 1 for every other finished structure; sites read 0.
## Supplied towers refill `tower.ammo_refill_per_s` rounds into `ammo` up to `tower.ammo_pool`; `WeaponFire` fires
## unsupplied towers at `economy.unsupplied_rate_mult` and `SelfRepair` skips unsupplied structures.
## Derived, never saved (S4): the graph is a function of the finished structures, rebuilt (O(nodes x structures)) in the
## step-10 pass whenever that set changes (`Economy.mark_dirty` epoch on BUILD_DONE, deaths and the start kit, or a different
## structure count), so a Pylon that dies in step 9 unsupplies its downstream towers
## on the next tick's fire pass. The refill is a pure function of the tick (floor of the cumulative rate), no accumulator.
## No Nodes, no signals, no RNG.

const MILLI: int = 1000

## 1 = a finished structure outside the network; per entity slot, rewritten by `step`.
var unsupplied: PackedByteArray = PackedByteArray()
## Graph rebuilds so far (diagnostic for tests and perf notes, not state).
var rebuilds: int = 0

var _store: EntityStore
var _defs: WorldDefs
var _hz: int
var _core_def: int = -1
var _outpost_def: int = -1
var _pylon_def: int = -1
var _pool: PackedInt32Array = PackedInt32Array()        ## by def_id: tower ammo_pool, 0 = no pool
var _milli: PackedInt32Array = PackedInt32Array()       ## by def_id: ammo_refill_per_s * MILLI, rounded
var _epoch: int = -1
var _n_struct: int = -1
var _towers: PackedInt32Array = PackedInt32Array()      ## finished, living towers (slots), rebuilt with the graph
# Node scratch (roots and Pylons), rebuilt per graph: slot, team, unit centre, cos(build_radius / R), connected, root.
var _n_slot: PackedInt32Array = PackedInt32Array()
var _n_team: PackedByteArray = PackedByteArray()
var _n_dir: PackedVector3Array = PackedVector3Array()
var _n_cos: PackedFloat64Array = PackedFloat64Array()
var _n_on: PackedByteArray = PackedByteArray()
var _queue: PackedInt32Array = PackedInt32Array()


func _init(store: EntityStore, defs: WorldDefs, hz: int) -> void:
	_store = store
	_defs = defs
	_hz = maxi(hz, 1)
	var e: int = unsupplied.resize(InputSlots.ENTITY_SLOTS) | _pool.resize(DefRanges.WEAPON_BASE) | _milli.resize(DefRanges.WEAPON_BASE)
	assert(e == OK)
	unsupplied.fill(0)
	_pool.fill(0)
	_milli.fill(0)
	var idx: Dictionary = defs.content.entity_index
	_core_def = idx.get(&"core", -1)
	_outpost_def = idx.get(&"outpost", -1)
	_pylon_def = idx.get(&"relay_pylon", -1)
	for sd: StructureDef in defs.content.structures:
		var d: int = idx.get(sd.id, -1)
		if sd.is_tower() and d >= 0 and d < _pool.size():
			_pool[d] = roundi(Def.num(sd.tower.get("ammo_pool", 0.0)))
			_milli[d] = roundi(Def.num(sd.tower.get("ammo_refill_per_s", 0.0)) * float(MILLI))


## Step 10: rebuild the graph when the structure set changed (`epoch` = `Economy.structure_epoch`, or a different live
## structure count), then refill the supplied towers for this tick.
func step(tick: int, epoch: int) -> void:
	if epoch != _epoch or _store.structures.size() != _n_struct:
		_epoch = epoch
		_n_struct = _store.structures.size()
		_rebuild()
	_refill(tick)


## True when finished structure `slot` is inside the supply network.
func is_supplied(slot: int) -> bool:
	return slot >= 0 and slot < unsupplied.size() and unsupplied[slot] == 0


func _rebuild() -> void:
	rebuilds += 1
	unsupplied.fill(0)
	_collect_nodes()
	_link_pylons()
	_towers.clear()
	for s: int in _store.structures:
		if (_store.flags[s] & EntityStore.F_BUILDING) != 0 or _store.hp[s] <= 0.0:
			continue
		if not _supplied(s):
			unsupplied[s] = 1
		elif _pool[_store.def_id[s]] > 0:
			var _t: bool = _towers.push_back(s)


func _collect_nodes() -> void:
	_n_slot.clear()
	_n_team.clear()
	_n_dir.clear()
	_n_cos.clear()
	_n_on.clear()
	for s: int in _store.structures:
		var d: int = _store.def_id[s]
		if (_store.flags[s] & EntityStore.F_BUILDING) != 0 or _store.hp[s] <= 0.0 or (d != _core_def and d != _outpost_def and d != _pylon_def):
			continue
		var sd: StructureDef = _defs.resolved(_store.owner[s]).structure(d)
		if sd == null:
			continue
		var _p: bool = _n_slot.push_back(s)
		_p = _n_team.push_back(_store.team[s])
		_p = _n_dir.push_back(_store.pos[s].normalized())
		_p = _n_cos.push_back(cos(sd.build_radius / Sphere.PLANET_RADIUS))
		_p = _n_on.push_back(0 if d == _pylon_def else 1)


# Breadth-first from the roots: a not yet connected Pylon of the same team inside a connected node's radius joins.
func _link_pylons() -> void:
	_queue.clear()
	var n: int = _n_slot.size()
	for i: int in n:
		if _n_on[i] != 0:
			var _q: bool = _queue.push_back(i)
	var head: int = 0
	while head < _queue.size():
		var i: int = _queue[head]
		head += 1
		for j: int in n:
			if _n_on[j] == 0 and _n_team[j] == _n_team[i] and _n_dir[j].dot(_n_dir[i]) >= _n_cos[i]:
				_n_on[j] = 1
				var _q2: bool = _queue.push_back(j)


# Supplied: a connected node of the structure's team covers its centre. A Pylon that never connected is not covered
# by any connected node (else it would have linked), so this one rule serves nodes and consumers alike.
func _supplied(s: int) -> bool:
	var dir: Vector3 = _store.pos[s].normalized()
	var team: int = _store.team[s]
	for i: int in _n_slot.size():
		if _n_on[i] != 0 and _n_team[i] == team and dir.dot(_n_dir[i]) >= _n_cos[i]:
			return true
	return false


# Whole rounds this tick: floor(rate * (t + 1)) - floor(rate * t) with the rate in milli-rounds per s, in integers.
# Only supplied towers are listed, so the pass costs a few reads per tower.
func _refill(tick: int) -> void:
	var denom: int = _hz * MILLI
	for s: int in _towers:
		var d: int = _store.def_id[s]
		var add: int = MathX.floori_div(_milli[d] * (tick + 1), denom) - MathX.floori_div(_milli[d] * tick, denom)
		if add > 0:
			_store.ammo[s] = mini(_store.ammo[s] + add, _pool[d])
