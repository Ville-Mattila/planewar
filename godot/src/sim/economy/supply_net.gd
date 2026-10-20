class_name SupplyNet extends RefCounted
## The supply network (02 s5.4, GD-18). Roots: finished Cores and Outposts. Links: a finished Relay Pylon whose centre is
## inside the build radius of a root or of an already linked Pylon (same team; a teammate network counts for the
## team). A finished structure is **supplied** when its centre is inside the build radius of a connected node of its team
## (a root or linked Pylon is supplied itself). `unsupplied[slot]` = 1 for every other finished structure; sites read 0.
## Supplied towers refill `tower.ammo_refill_per_s` rounds into `ammo` up to `tower.ammo_pool`; `WeaponFire` fires
## unsupplied towers at `economy.unsupplied_rate_mult` and `SelfRepair` skips unsupplied structures.
## Derived, never saved (S4): the flags are a function of the finished structures. In the step-10 pass, when that set
## changed (`Economy.mark_dirty` epoch on BUILD_DONE, deaths and the start kit, or a different structure count), a changed
## node (Core, Outpost, Pylon) rebuilds the whole graph; a changed consumer (tower, Solar, ...) only evaluates itself.
## So a Pylon that dies in step 9 unsupplies its downstream towers in step 10 of the same tick, seen by the next fire pass.
## Neighbour search: nodes sorted by team, then the x of their unit centre (int64 keys, native sort + bsearch); a probe scans the
## band `|dx| <= build_radius / R` (an upper bound of the arc) and tests `dot >= cos(r / R)`.
## The refill is a pure function of the tick (floor of the cumulative rate), no accumulator.
## No Nodes, no signals, no RNG.

const MILLI: int = 1000
const QUANT: int = 1 << 20   ## quanta of x per unit in the node band search

## 1 = a finished structure outside the network; per entity slot, rewritten by `step`.
var unsupplied: PackedByteArray = PackedByteArray()
## Full graph rebuilds so far (diagnostic for tests and perf notes, not state).
var rebuilds: int = 0
## false stops the tower refill (fixtures that count shots by ammo drops); not state, never set by the sim.
var refill: bool = true

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
var _towers: PackedInt32Array = PackedInt32Array()      ## supplied, finished, living towers (slots)
# Last seen finished structures, by slot: entity id (0 = none) and def, plus the list; diffed on every change.
var _seen_id: PackedInt32Array = PackedInt32Array()
var _seen_def: PackedInt32Array = PackedInt32Array()
var _seen: PackedInt32Array = PackedInt32Array()
var _mark: PackedInt32Array = PackedInt32Array()
var _stamp: int = 0
var _cur: PackedInt32Array = PackedInt32Array()
var _added: PackedInt32Array = PackedInt32Array()
# Node scratch (Cores, Outposts, Pylons) of the last graph: slot, team, unit centre, cos(r / R), band half width in
# quanta of x, connected flag, and the x-sorted keys ((team << 24 | quantised x) << 16 | node index).
var _n_slot: PackedInt32Array = PackedInt32Array()
var _n_team: PackedByteArray = PackedByteArray()
var _n_dir: PackedVector3Array = PackedVector3Array()
var _n_cos: PackedFloat64Array = PackedFloat64Array()
var _n_hw: PackedInt32Array = PackedInt32Array()
var _n_on: PackedByteArray = PackedByteArray()
var _keys: PackedInt64Array = PackedInt64Array()
var _r_hw: PackedInt32Array = PackedInt32Array()        ## per owner * 3 + (Core, Outpost, Pylon): band half width, -1 = no def
var _r_cos: PackedFloat64Array = PackedFloat64Array()
var _node_of: PackedInt32Array = PackedInt32Array()     ## by entity slot: index into the node arrays, -1 = not a node
var _hw_max: int = 0
var _queue: PackedInt32Array = PackedInt32Array()


func _init(store: EntityStore, defs: WorldDefs, hz: int) -> void:
	_store = store
	_defs = defs
	_hz = maxi(hz, 1)
	var n: int = InputSlots.ENTITY_SLOTS
	var e: int = unsupplied.resize(n) | _pool.resize(DefRanges.WEAPON_BASE) | _milli.resize(DefRanges.WEAPON_BASE)
	e |= _r_hw.resize((WorldDefs.NEUTRAL + 1) * 3) | _r_cos.resize((WorldDefs.NEUTRAL + 1) * 3)
	e |= _seen_id.resize(n) | _seen_def.resize(n) | _mark.resize(n) | _node_of.resize(n)
	assert(e == OK)
	unsupplied.fill(0)
	_pool.fill(0)
	_milli.fill(0)
	_seen_id.fill(0)
	_seen_def.fill(0)
	_mark.fill(0)
	_node_of.fill(-1)
	var idx: Dictionary = defs.content.entity_index
	_core_def = idx.get(&"core", -1)
	_outpost_def = idx.get(&"outpost", -1)
	_pylon_def = idx.get(&"relay_pylon", -1)
	for sd: StructureDef in defs.content.structures:
		var d: int = idx.get(sd.id, -1)
		if sd.is_tower() and d >= 0 and d < _pool.size():
			_pool[d] = roundi(Def.num(sd.tower.get("ammo_pool", 0.0)))
			_milli[d] = roundi(Def.num(sd.tower.get("ammo_refill_per_s", 0.0)) * float(MILLI))


## Step 10: update the flags when the structure set changed (`epoch` = `Economy.structure_epoch`, or a different live
## structure count), then refill the supplied towers for this tick.
func step(tick: int, epoch: int) -> void:
	if epoch != _epoch or _store.structures.size() != _n_struct:
		_epoch = epoch
		_n_struct = _store.structures.size()
		_update()
	_refill(tick)


## True when finished structure `slot` is inside the supply network.
func is_supplied(slot: int) -> bool:
	return slot >= 0 and slot < unsupplied.size() and unsupplied[slot] == 0


func _is_node(d: int) -> bool:
	return d == _core_def or d == _outpost_def or d == _pylon_def


# Diff the finished live structures against the last pass. A node added or removed rebuilds the graph; consumers only
# clear (removed) or evaluate (added) their own flag.
func _update() -> void:
	_stamp += 1
	_cur.clear()
	_added.clear()
	var node_changed: bool = false
	var gen: PackedInt32Array = _store.generation
	var fl: PackedByteArray = _store.flags
	var hp: PackedFloat32Array = _store.hp
	for s: int in _store.structures:
		if (fl[s] & EntityStore.F_BUILDING) != 0 or hp[s] <= 0.0:
			continue
		var _p: bool = _cur.push_back(s)
		_mark[s] = _stamp
		if _seen_id[s] != gen[s] + 1:
			_p = _added.push_back(s)
			node_changed = node_changed or _is_node(_store.def_id[s])
	for s: int in _seen:
		if _mark[s] != _stamp or _seen_id[s] != gen[s] + 1:
			node_changed = node_changed or _is_node(_seen_def[s])
			unsupplied[s] = 0
	if node_changed:
		_rebuild()
	else:
		for s: int in _added:
			unsupplied[s] = 0 if _covered(s) else 1
	_commit()


# Remembers this pass (`_seen_id` = generation + 1, 0 = none) and lists the supplied towers; `_cur` becomes `_seen`.
func _commit() -> void:
	var gen: PackedInt32Array = _store.generation
	for s: int in _seen:
		_seen_id[s] = 0
	var old: PackedInt32Array = _seen
	_seen = _cur
	_cur = old
	_towers.clear()
	for s: int in _seen:
		var d: int = _store.def_id[s]
		_seen_id[s] = gen[s] + 1
		_seen_def[s] = d
		if _pool[d] > 0 and unsupplied[s] == 0:
			var _t: bool = _towers.push_back(s)


func _rebuild() -> void:
	rebuilds += 1
	_collect_nodes()
	_link_pylons()
	for s: int in _cur:
		var i: int = _node_of[s]
		if i >= 0:
			unsupplied[s] = 0 if _n_on[i] != 0 else 1       # a node is supplied exactly when it is connected
		else:
			unsupplied[s] = 0 if _covered(s) else 1


func _collect_nodes() -> void:
	var m: int = _cur.size()
	var e: int = _n_slot.resize(m) | _n_team.resize(m) | _n_dir.resize(m) | _n_cos.resize(m) | _n_hw.resize(m) | _n_on.resize(m) | _keys.resize(m)
	assert(e == OK)
	_node_of.fill(-1)
	_radii()
	var n: int = 0
	for s: int in _cur:
		var d: int = _store.def_id[s]
		if not _is_node(d):
			continue
		var r: int = mini(_store.owner[s], WorldDefs.NEUTRAL) * 3 + (0 if d == _core_def else (1 if d == _outpost_def else 2))
		if _r_hw[r] < 0:
			continue
		var dir: Vector3 = _store.pos[s].normalized()
		var team: int = _store.team[s]
		var hw: int = _r_hw[r]
		_keys[n] = (((team << 24) + _xq(dir.x)) << 16) | n
		_n_slot[n] = s
		_n_team[n] = team
		_n_dir[n] = dir
		_n_cos[n] = _r_cos[r]
		_n_hw[n] = hw
		_n_on[n] = 0 if d == _pylon_def else 1
		_node_of[s] = n
		n += 1
	e = _n_slot.resize(n) | _n_team.resize(n) | _n_dir.resize(n) | _n_cos.resize(n) | _n_hw.resize(n) | _n_on.resize(n) | _keys.resize(n)
	assert(e == OK)
	_keys.sort()


# Build radius of Core / Outpost / Pylon per owner from the owner resolved defs: band half width in quanta and cos.
func _radii() -> void:
	_hw_max = 0
	for o: int in WorldDefs.NEUTRAL + 1:
		var r: ResolvedDefs = _defs.resolved(o)
		for k: int in 3:
			var sd: StructureDef = r.structure(_core_def if k == 0 else (_outpost_def if k == 1 else _pylon_def))
			var i: int = o * 3 + k
			_r_hw[i] = -1 if sd == null else int(sd.build_radius / Sphere.PLANET_RADIUS * float(QUANT)) + 2
			_r_cos[i] = 0.0 if sd == null else cos(sd.build_radius / Sphere.PLANET_RADIUS)
			_hw_max = maxi(_hw_max, _r_hw[i])


func _xq(x: float) -> int:
	return int((x + 1.0) * float(QUANT))


# Breadth-first from the roots: a not yet connected Pylon of the same team inside a connected node radius joins.
# Keys carry the team above the x quanta, so a band scan only meets its own team (and a little of the one below).
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
		var q: int = (_n_team[i] << 24) + _xq(_n_dir[i].x)
		var k: int = _keys.bsearch(maxi(q - _n_hw[i], 0) << 16)
		var hi: int = q + _n_hw[i]
		while k < n and (_keys[k] >> 16) <= hi:
			var j: int = int(_keys[k] & 0xFFFF)
			k += 1
			if _n_on[j] == 0 and _n_team[j] == _n_team[i] and _n_dir[j].dot(_n_dir[i]) >= _n_cos[i]:
				_n_on[j] = 1
				var _q2: bool = _queue.push_back(j)


# A consumer is supplied when a connected node of its team covers its centre.
func _covered(s: int) -> bool:
	var dir: Vector3 = _store.pos[s].normalized()
	var team: int = _store.team[s]
	var q: int = (team << 24) + _xq(dir.x)
	var n: int = _keys.size()
	var k: int = _keys.bsearch(maxi(q - _hw_max, 0) << 16)
	var hi: int = q + _hw_max
	while k < n and (_keys[k] >> 16) <= hi:
		var i: int = int(_keys[k] & 0xFFFF)
		k += 1
		if _n_on[i] != 0 and _n_team[i] == team and dir.dot(_n_dir[i]) >= _n_cos[i]:
			return true
	return false


# Whole rounds this tick: floor(rate * (t + 1)) - floor(rate * t) with the rate in milli-rounds per s, in integers.
# Only supplied towers are listed, so the pass costs a few reads per tower.
func _refill(tick: int) -> void:
	if not refill:
		return
	var denom: int = _hz * MILLI
	for s: int in _towers:
		var d: int = _store.def_id[s]
		var add: int = MathX.floori_div(_milli[d] * (tick + 1), denom) - MathX.floori_div(_milli[d] * tick, denom)
		if add > 0:
			_store.ammo[s] = mini(_store.ammo[s] + add, _pool[d])
