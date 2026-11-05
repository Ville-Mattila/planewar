class_name Harvest extends RefCounted
## The Harvester cycle of tick-order step 10 (GD-12; 02 s8.2): field regen (stopped at Core Exposure), mining at the
## unit's `mine_rate` while it stands still inside a field with a free `max_miners` slot, and unloading at a friendly
## finished Refinery's `docks` over `unload_time_s`, credited through `Economy.credit`. The driving (path, turn, stop) is
## the autopilot's: it writes the unit's input slot, `GroundMotion` moves it in step 5. A Harvester is a K_GROUND unit
## whose resolved def has `mine_rate` > 0. State lives in `EntityStore` only: `link` = `state << STATE_SHIFT | index + 1`
## (index = field while MINING, Refinery slot while WAITING / UNLOADING), `cargo` = Ore carried, `cargo_kind` = ORE (1)
## while it carries any, `timer_a` = unload seconds left. No Nodes, no signals, no RNG, no allocation per tick.

enum State { TRAVEL = 0, MINING = 1, WAITING = 2, UNLOADING = 3 }

const STATE_SHIFT: int = 24
const _INDEX_MASK: int = (1 << STATE_SHIFT) - 1
const _CARGO_ORE: int = 1                  ## `cargo_kind` ORE (03 s3.4)
const _MIN_CLAIM_ORE: float = 1.0          ## structural: Ore is credited in whole units (`roundi`), so under 1 Ore there is nothing to take

var fields: OreFields = OreFields.new()

var _store: EntityStore
var _defs: WorldDefs
var _rules: MatchRules
var _economy: Economy
var _deliver: float = 0.0
var _refs: PackedInt32Array = PackedInt32Array()    ## derived: finished-or-not Refinery-like structures (docks > 0)
var _refs_epoch: int = -1
var _refs_count: int = -1
var _used: PackedInt32Array = PackedInt32Array()    ## per entity slot: docks in use this pass (Refinery slots only)


func _init(store: EntityStore, defs: WorldDefs, rules: MatchRules, economy: Economy) -> void:
	_store = store
	_defs = defs
	_rules = rules
	_economy = economy
	_deliver = defs.economy.salvage_deliver_m if defs.economy != null else 0.0
	var _n: int = _used.resize(InputSlots.ENTITY_SLOTS)


static func state_of(link: int) -> State:
	return (link >> STATE_SHIFT) as State


static func index_of(link: int) -> int:
	return (link & _INDEX_MASK) - 1


static func pack(state: State, index: int) -> int:
	return (state << STATE_SHIFT) | (index + 1)


## Step 10: regen unless the match is past Core Exposure, then every Harvester in ascending slot order.
func step(t: int, dt: float) -> void:
	if _store.ground.is_empty() and fields.count() == 0:
		return
	if _rules.phase(t) == MatchRules.Phase.PLAYING:
		fields.regen(dt)
	_refresh_refineries()
	_count_miners_and_docks()
	for s: int in _store.ground:
		var hd: GroundUnitDef = _harvester_def(s)
		if hd != null:
			_step_one(s, hd, dt)


func _harvester_def(s: int) -> GroundUnitDef:
	var rd: ResolvedDefs = _defs.resolved(_store.owner[s])
	var hd: GroundUnitDef = rd.ground_unit(_store.def_id[s]) if rd != null else null
	return hd if hd != null and hd.mine_rate > 0.0 and hd.cargo_ore > 0 else null


func _step_one(s: int, hd: GroundUnitDef, dt: float) -> void:
	var stopped: bool = _store.vel[s].is_zero_approx()   # GroundMotion writes an exact zero for a stopped unit
	match state_of(_store.link[s]):
		State.MINING:
			_mine(s, hd, stopped, dt)
		State.WAITING, State.UNLOADING:
			_unload(s, hd, stopped, dt)
		_:
			if stopped:
				_arrive(s, hd)


# Stopped and not mining: a loaded unit at a friendly Refinery docks (or queues); an unfilled one in a field claims a slot.
func _arrive(s: int, hd: GroundUnitDef) -> void:
	var cargo: float = _store.cargo[s]
	if cargo > 0.0:
		var r: int = _refinery_near(s)
		if r >= 0:
			_store.link[s] = pack(State.WAITING, r)
			_start_unload_if_free(s, hd, r)
			return
	if cargo >= float(hd.cargo_ore):
		return
	var f: int = fields.field_at(_store.pos[s].normalized())
	if f >= 0 and fields.miners[f] < fields.max_miners[f] and fields.amount[f] >= _MIN_CLAIM_ORE:
		fields.miners[f] += 1
		_store.link[s] = pack(State.MINING, f)


func _mine(s: int, hd: GroundUnitDef, stopped: bool, dt: float) -> void:
	var f: int = index_of(_store.link[s])
	if f < 0 or f >= fields.count():
		_store.link[s] = 0
		return
	if not stopped:
		_release(s, f)
		return
	var cap: float = float(hd.cargo_ore)
	var take: float = minf(minf(hd.mine_rate * dt, cap - _store.cargo[s]), fields.amount[f])
	_store.cargo[s] += take
	fields.amount[f] -= take
	_store.cargo_kind[s] = _CARGO_ORE if _store.cargo[s] > 0.0 else 0
	if _store.cargo[s] >= cap or fields.amount[f] <= 0.0:
		_release(s, f)                                 # full, or a partial load: the autopilot re-targets


func _release(s: int, f: int) -> void:
	fields.miners[f] = maxi(fields.miners[f] - 1, 0)
	_store.link[s] = 0


func _unload(s: int, hd: GroundUnitDef, stopped: bool, dt: float) -> void:
	var r: int = index_of(_store.link[s])
	var ok: bool = stopped and r >= 0 and r < InputSlots.ENTITY_SLOTS and _refinery_ok(r, _store.team[s]) \
			and _store.cargo[s] > 0.0
	if not ok:
		_store.timer_a[s] = 0.0
		_store.link[s] = 0
		return
	if state_of(_store.link[s]) == State.WAITING:
		_start_unload_if_free(s, hd, r)
		return
	_store.timer_a[s] -= dt
	if _store.timer_a[s] <= 0.0:
		_economy.credit(_store.team[s], roundi(_store.cargo[s]), 0, _store.owner[s])
		_store.cargo[s] = 0.0
		_store.cargo_kind[s] = 0
		_store.timer_a[s] = 0.0
		_store.link[s] = 0
		_used[r] = maxi(_used[r] - 1, 0)


func _start_unload_if_free(s: int, hd: GroundUnitDef, r: int) -> void:
	var sd: StructureDef = _defs.base.structure(_store.def_id[r])
	if sd == null or _used[r] >= sd.docks:
		return
	_used[r] += 1
	_store.link[s] = pack(State.UNLOADING, r)
	_store.timer_a[s] = hd.unload_time_s * _store.cargo[s] / float(hd.cargo_ore)


# A friendly, finished, living structure with docks.
func _refinery_ok(r: int, team: int) -> bool:
	return _store.team[r] == team and (_store.flags[r] & (EntityStore.F_ALIVE | EntityStore.F_BUILDING)) == EntityStore.F_ALIVE \
			and _store.kind[r] == EntityStore.K_STRUCTURE and _refs.has(r)


# The Refinery within `radius + salvage_deliver_m` of `s`: the first with a free dock, else the first in reach; -1 for none.
func _refinery_near(s: int) -> int:
	var p: Vector3 = _store.pos[s]
	var team: int = _store.team[s]
	var first: int = -1
	for r: int in _refs:
		if _store.team[r] != team or (_store.flags[r] & (EntityStore.F_ALIVE | EntityStore.F_BUILDING)) != EntityStore.F_ALIVE:
			continue
		var d: float = _store.radius[r] + _deliver
		if p.distance_squared_to(_store.pos[r]) > d * d:
			continue
		var sd: StructureDef = _defs.base.structure(_store.def_id[r])
		if sd != null and _used[r] < sd.docks:
			return r
		if first < 0:
			first = r
	return first


# Derived each pass: miners per field and docks in use per Refinery, from the units' own state.
func _count_miners_and_docks() -> void:
	fields.miners.fill(0)
	for r: int in _refs:
		_used[r] = 0
	for s: int in _store.ground:
		var link: int = _store.link[s]
		if link == 0:
			continue
		var idx: int = index_of(link)
		match state_of(link):
			State.MINING:
				if idx >= 0 and idx < fields.count():
					fields.miners[idx] += 1
			State.UNLOADING:
				if idx >= 0 and idx < _used.size():
					_used[idx] += 1


# The docking structures (def `docks` > 0), rebuilt when the structure set changes (Economy E9).
func _refresh_refineries() -> void:
	var count: int = _store.structures.size()
	if _refs_epoch == _economy.structure_epoch and _refs_count == count:
		return
	_refs_epoch = _economy.structure_epoch
	_refs_count = count
	var _n: int = _refs.resize(0)
	for s: int in _store.structures:
		var sd: StructureDef = _defs.base.structure(_store.def_id[s])
		if sd != null and sd.docks > 0:
			var _a: bool = _refs.push_back(s)
