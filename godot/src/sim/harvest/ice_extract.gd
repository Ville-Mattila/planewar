class_name IceExtract extends RefCounted
## Ice extraction and logistics of tick-order step 10 (GD-14; 02 s8.3). A finished Ice Extractor standing in a Cold Trap fills
## its own `buffer_ice` at the node rate (`cargo` of the structure, `cargo_kind` ICE); a friendly finished Refinery within
## its `pipe_radius_m` pipes the buffer into the stockpile continuously; otherwise a Hauler (a ship with `cargo_ice` > 0)
## within `radius + salvage_deliver_m` of the Extractor takes `hauler_transfer_per_s` Ice per second from the buffer into its
## hold, and unloads the hold at the same rate at a friendly Refinery. The Hauler's route is the brain's (05). State lives in
## `EntityStore` (`cargo`, `cargo_kind`) and `IceNodes.amount`; the lists below are derived. No Nodes, no signals, no RNG.

const _CARGO_ICE: int = 2                  ## `cargo_kind` ICE (03 s3.4)

var nodes: IceNodes = IceNodes.new()

var ship_scans: int = 0                    ## diagnostic hard counter (not state): ship passes run so far

var _store: EntityStore
var _defs: WorldDefs
var _economy: Economy
var _score: ScoreKeeper
var _deliver: float = 0.0
var _transfer: float = 0.0
var _ext: PackedInt32Array = PackedInt32Array()        ## derived: structures with `buffer_ice` > 0, ascending slot
var _ext_node: PackedInt32Array = PackedInt32Array()   ## derived, parallel to `_ext`: its Cold Trap index, -1 for none
var _ext_reach2: PackedFloat32Array = PackedFloat32Array()   ## derived, parallel to `_ext`: (radius + salvage_deliver_m)^2
var _refs: PackedInt32Array = PackedInt32Array()       ## derived: structures with `docks` > 0, ascending slot
var _refs_reach2: PackedFloat32Array = PackedFloat32Array()  ## derived, parallel to `_refs`
var _loaded: int = 0                                   ## Extractors holding Ice after this pass's extraction (a Hauler has nothing to load at 0)
var _epoch: int = -1
var _count: int = -1
var _nodes_n: int = -1


func _init(store: EntityStore, defs: WorldDefs, economy: Economy, score: ScoreKeeper) -> void:
	_store = store
	_defs = defs
	_economy = economy
	_score = score
	if defs.economy != null:
		_deliver = defs.economy.salvage_deliver_m
		_transfer = defs.economy.hauler_transfer_per_s


## Step 10: every Extractor in ascending slot order (extract, pipe), then every Hauler in ascending slot order.
func step(dt: float) -> void:
	_refresh()
	if _ext.is_empty() and _refs.is_empty():
		return
	_loaded = 0
	for i: int in _ext.size():
		_extract(_ext[i], _ext_node[i], dt)
		if _store.cargo[_ext[i]] > 0.0:
			_loaded += 1
	ship_scans += 1
	for s: int in _store.ships:
		_haul(s, dt)


## The friendly finished Refinery within its `pipe_radius_m` of `extractor` (the first in slot order); -1 for none.
func refinery_for(extractor: int) -> int:
	if extractor < 0 or extractor >= InputSlots.ENTITY_SLOTS:
		return -1
	_refresh()
	var p: Vector3 = _store.pos[extractor]
	var team: int = _store.team[extractor]
	for r: int in _refs:
		if _store.team[r] != team or not _finished(r):
			continue
		var sd: StructureDef = _defs.base.structure(_store.def_id[r])
		if sd != null and sd.pipe_radius_m > 0.0 and p.distance_squared_to(_store.pos[r]) <= sd.pipe_radius_m * sd.pipe_radius_m:
			return r
	return -1


# Node -> buffer for a finished Extractor, then the pipe when a whole Ice is waiting.
func _extract(e: int, node: int, dt: float) -> void:
	if not _finished(e):
		return
	if node >= 0:
		var sd: StructureDef = _defs.base.structure(_store.def_id[e])
		var room: float = maxf(float(sd.buffer_ice) - _store.cargo[e], 0.0)
		var take: float = minf(minf(nodes.rate_per_s[node] * dt, nodes.amount[node]), room)
		if take > 0.0:
			nodes.amount[node] -= take
			_store.cargo[e] += take
			_store.cargo_kind[e] = _CARGO_ICE
	if _store.cargo[e] >= 1.0:
		var r: int = refinery_for(e)
		if r >= 0:
			_pipe(e)


func _pipe(e: int) -> void:
	var team: int = _store.team[e]
	var room: int = _economy.caps(team).y - _economy.stockpile(team).y
	var n: int = mini(floori(_store.cargo[e]), room)
	if n <= 0:
		return
	_economy.credit(team, 0, n, _store.owner[e])
	_store.cargo[e] -= float(n)
	if _store.cargo[e] <= 0.0:
		_store.cargo_kind[e] = 0
	if _score != null:
		_score.ice_delivered(_store.owner[e], n, false)


# One Hauler: unload at a Refinery in reach when it holds Ice, else load from the first Extractor in reach with Ice.
func _haul(s: int, dt: float) -> void:
	var sd: ShipDef = _defs.ship(_store.owner[s], _store.def_id[s])
	if sd == null or sd.cargo_ice <= 0:
		return
	var p: Vector3 = _store.pos[s]
	var team: int = _store.team[s]
	if _store.cargo[s] > 0.0:
		if _in_reach(_refs, _refs_reach2, p, team, false) >= 0:
			_unload(s, dt)
			return
	if _loaded > 0 and _store.cargo[s] < float(sd.cargo_ice):
		var e: int = _in_reach(_ext, _ext_reach2, p, team, true)
		if e >= 0:
			_load(s, e, float(sd.cargo_ice), dt)


# The first slot of `list` within `radius + salvage_deliver_m` of `p`, friendly and finished (and holding Ice if `full`).
func _in_reach(list: PackedInt32Array, reach2: PackedFloat32Array, p: Vector3, team: int, full: bool) -> int:
	for i: int in list.size():
		var r: int = list[i]
		if p.distance_squared_to(_store.pos[r]) > reach2[i]:
			continue
		if _store.team[r] == team and _finished(r) and not (full and _store.cargo[r] <= 0.0):
			return r
	return -1


func _load(s: int, e: int, hold: float, dt: float) -> void:
	var take: float = minf(minf(_transfer * dt, _store.cargo[e]), maxf(hold - _store.cargo[s], 0.0))
	if take <= 0.0:
		return
	_store.cargo[e] -= take
	_store.cargo[s] += take
	_store.cargo_kind[s] = _CARGO_ICE
	if _store.cargo[e] <= 0.0:
		_store.cargo_kind[e] = 0


# Hold -> stockpile at `hauler_transfer_per_s`; whole Ice is credited as the rounded hold falls (sums to round(load)).
func _unload(s: int, dt: float) -> void:
	var team: int = _store.team[s]
	var room: int = _economy.caps(team).y - _economy.stockpile(team).y
	var before: float = _store.cargo[s]
	var amt: float = minf(minf(_transfer * dt, before), float(maxi(room, 0)))
	if amt <= 0.0:
		return
	var after: float = before - amt
	_store.cargo[s] = after
	_store.cargo_kind[s] = _CARGO_ICE if after > 0.0 else 0
	var n: int = roundi(before) - roundi(after)
	if n <= 0:
		return
	_economy.credit(team, 0, n, _store.owner[s])
	if _score != null:
		_score.ice_delivered(_store.owner[s], n, _store.possessor[s] != EntityStore.NONE_U8)


func _finished(s: int) -> bool:
	return (_store.flags[s] & (EntityStore.F_ALIVE | EntityStore.F_BUILDING)) == EntityStore.F_ALIVE \
			and _store.kind[s] == EntityStore.K_STRUCTURE


# The Extractor and Refinery lists, rebuilt when the structure set (Economy.structure_epoch / count) or the node table changes.
func _refresh() -> void:
	var count: int = _store.structures.size()
	if _epoch == _economy.structure_epoch and _count == count and _nodes_n == nodes.count():
		return
	_epoch = _economy.structure_epoch
	_count = count
	_nodes_n = nodes.count()
	var _a: int = _ext.resize(0)
	var _b: int = _ext_node.resize(0)
	var _c: int = _refs.resize(0)
	var _g: int = _ext_reach2.resize(0)
	var _h: int = _refs_reach2.resize(0)
	for s: int in _store.structures:
		var sd: StructureDef = _defs.base.structure(_store.def_id[s])
		if sd == null:
			continue
		if sd.buffer_ice > 0:
			var _d: bool = _ext.push_back(s)
			var _e: bool = _ext_node.push_back(nodes.node_at(_store.pos[s].normalized()))
			var _i: bool = _ext_reach2.push_back(_reach2(s))
		if sd.docks > 0:
			var _f: bool = _refs.push_back(s)
			var _j: bool = _refs_reach2.push_back(_reach2(s))


func _reach2(s: int) -> float:
	var d: float = _store.radius[s] + _deliver
	return d * d
