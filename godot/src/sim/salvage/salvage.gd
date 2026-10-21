class_name Salvage extends RefCounted
## Wrecks, salvage pods, tow slots and delivery credit (GD-19; 02 s13, 03 s5.7, R0 C3-17; contract: sim/salvage/MODULE.md).
## `EconomyHub.on_death` calls `on_death` in step 9 (before the deferred free) and `EconomyHub.step` calls `step` in
## step 10. No state of its own: a wreck is an `EntityStore` entity (`hp` = Ore, `spawn_tick`, `link` = the towing
## Hauler's EntityId, F_TETHERED on both ends), so S4 needs no section. The tether follow motion is GD-37's.
## No Nodes, no signals, no RNG; the pass is one loop over the live wreck list and one over the ships.

enum Hook { OK, NOT_HAULER, NO_SLOT, BAD_WRECK, TOO_FAR }

const CAUSE_EXPIRED: int = 1   ## DEATH cause of an expired wreck (0 is DEBUG, CommandApplier)

var orders: OrderQueue = null  ## set by SimWorld: the head standing order of a ship decides the auto-hook
var cap: int = 0               ## live wreck cap (`caps.wrecks`); 0 = the whole wreck range

var _store: EntityStore
var _defs: WorldDefs
var _economy: Economy
var _events: SimEvents
var _terrain: Terrain
var _life_ticks: int = 0
var _reach: float = 0.0
var _pod_max: int = 1
var _gone: PackedInt32Array = PackedInt32Array()      ## scratch: wreck slots to free after the pass
var _touched: PackedInt32Array = PackedInt32Array()   ## scratch: hauler slots whose F_TETHERED needs a refresh
var _load: PackedByteArray = PackedByteArray()        ## scratch, per main slot: wrecks a ship tows during the pass (zeroed via `_loaded`)
var _loaded: PackedInt32Array = PackedInt32Array()    ## scratch: slots with a non-zero `_load`
var _refs: PackedInt32Array = PackedInt32Array()      ## derived: finished Refinery slots (rebuilt on epoch / count change)
var _refs_epoch: int = -1
var _refs_count: int = -1
var _spec: OrderSpec = OrderSpec.new()


func _init(store: EntityStore, defs: WorldDefs, economy: Economy, events: SimEvents, terrain: Terrain, hz: int,
		wreck_cap: int) -> void:
	_store = store
	_defs = defs
	_economy = economy
	_events = events
	_terrain = terrain
	cap = wreck_cap
	var _r: int = _load.resize(EntityId.WRECK_SLOT_MIN)
	_load.fill(0)
	if defs.economy != null:
		_life_ticks = roundi(defs.economy.wreck_lifetime_s * float(hz))
		_pod_max = maxi(defs.economy.salvage_pod_max_ore, 1)
	if defs.common != null:
		_reach = defs.common.tether_len_m + defs.common.tether_drop_m


## W1: Ore value of the wrecks `def_id` leaves (from the undoctrined defs); 0 = none.
static func value_of(defs: WorldDefs, def_id: int) -> int:
	if defs.economy == null or def_id < 0:
		return 0
	var base: int = defs.cost(WorldDefs.NEUTRAL, def_id).x
	if base <= 0:
		var sd: StructureDef = defs.base.structure(def_id)
		if sd != null and not sd.integrated_shield.is_empty() and defs.content.match_rules != null:
			base = defs.content.match_rules.core_value
	return roundi(float(maxi(base, 0)) * defs.economy.wreck_fraction)


## W2: `ceil(value / pod_max)` pods, at least 1.
static func pods_of(value: int, pod_max: int) -> int:
	return maxi(ceili(float(value) / float(maxi(pod_max, 1))), 1)


## W2: the Ore of pod `i` of `pods`: `value / pods` rounded down, +1 for the first `value mod pods` pods.
static func pod_value(value: int, pods: int, i: int) -> int:
	var each: int = floori(float(value) / float(pods))
	return each + (1 if i < value - each * pods else 0)


func reach_m() -> float:
	return _reach


## Step 9, before the deferred free of `s`: its wrecks (W1-W3, W5). Returns how many were created.
func on_death(s: int, tick: int) -> int:
	var f: int = _store.flags[s]
	var k: int = _store.kind[s]
	if (f & EntityStore.F_ALIVE) == 0 or k == EntityStore.K_WRECK or (f & EntityStore.F_BUILDING) != 0:
		return 0
	var def: int = _store.def_id[s]
	var value: int = value_of(_defs, def)
	if value <= 0:
		return 0
	var pods: int = pods_of(value, _pod_max) if k == EntityStore.K_STRUCTURE else 1
	var made: int = 0
	for i: int in pods:
		if not _room() or not _spawn(s, def, pod_value(value, pods, i), i, pods, tick):
			break
		made += 1
	return made


## Step 10: expiry (W4), release and delivery of tows (W7, W8), then the auto-hook (W6).
func step(t: int) -> void:
	if _store.wrecks.is_empty():
		return
	_refresh_refineries()
	for h: int in _loaded:
		_load[h] = 0
	var _n: int = _loaded.resize(0)
	_n = _gone.resize(0)
	_n = _touched.resize(0)
	var born: PackedInt32Array = _store.spawn_tick
	var flags: PackedByteArray = _store.flags
	var cutoff: int = t - _life_ticks
	for s: int in _store.wrecks:
		var tethered: bool = (flags[s] & EntityStore.F_TETHERED) != 0
		if born[s] <= cutoff:
			_expire(s, tethered)
		elif tethered:
			_tow_pass(s)
	for k: int in _gone.size():
		var _f: bool = _store.free_slot(_gone[k], t)
	for h: int in _touched:
		_sync_flag(h)
	if not _store.wrecks.is_empty() and orders != null:
		_hook_pass()


func towed_count(hauler: int) -> int:
	if hauler < 1 or hauler >= EntityId.WRECK_SLOT_MIN or (_store.flags[hauler] & EntityStore.F_ALIVE) == 0:
		return 0
	var id: int = _store.id_of(hauler)
	var n: int = 0
	for w: int in _store.wrecks:
		if _store.link[w] == id and (_store.flags[w] & EntityStore.F_TETHERED) != 0:
			n += 1
	return n


func tow_slots_of(hauler: int) -> int:
	if hauler < 1 or hauler >= EntityId.WRECK_SLOT_MIN or (_store.flags[hauler] & EntityStore.F_ALIVE) == 0:
		return 0
	if _store.kind[hauler] != EntityStore.K_SHIP:
		return 0
	var sd: ShipDef = _defs.ship(_store.owner[hauler], _store.def_id[hauler])
	return sd.tow_slots if sd != null else 0


## W6: hooks `wreck` to `hauler` (entity slots) when the ship has a free slot and the wreck is free and in reach.
func try_attach(hauler: int, wreck: int) -> Hook:
	if tow_slots_of(hauler) <= 0 or (_store.flags[hauler] & EntityStore.F_DOCKED) != 0:
		return Hook.NOT_HAULER
	if towed_count(hauler) >= tow_slots_of(hauler):
		return Hook.NO_SLOT
	if wreck < EntityId.WRECK_SLOT_MIN or wreck >= EntityId.WRECK_SLOT_END or (_store.flags[wreck] & EntityStore.F_ALIVE) == 0 \
			or (_store.flags[wreck] & EntityStore.F_TETHERED) != 0:
		return Hook.BAD_WRECK
	if _store.pos[hauler].distance_squared_to(_store.pos[wreck]) > _reach * _reach:
		return Hook.TOO_FAR
	_link(hauler, wreck)
	return Hook.OK


# The checked hook: both ends flagged, `_load` counted.
func _link(hauler: int, wreck: int) -> void:
	_store.link[wreck] = _store.id_of(hauler)
	_store.flags[wreck] |= EntityStore.F_TETHERED
	_store.flags[hauler] |= EntityStore.F_TETHERED
	_store.dirty[wreck] |= EntityStore.DIRTY_CONTROL
	_store.dirty[hauler] |= EntityStore.DIRTY_CONTROL
	_count(hauler, 1)


func _count(hauler: int, by: int) -> void:
	if _load[hauler] == 0 and by > 0:
		var _a: bool = _loaded.push_back(hauler)
	_load[hauler] = maxi(_load[hauler] + by, 0)


## W7: releases every wreck of `hauler`; returns the count.
func drop(hauler: int) -> int:
	var id: int = _store.id_of(hauler) if hauler > 0 and hauler < EntityId.WRECK_SLOT_MIN else 0
	var n: int = 0
	for w: int in _store.wrecks:
		if id != 0 and _store.link[w] == id and (_store.flags[w] & EntityStore.F_TETHERED) != 0:
			_release(w)
			n += 1
	if n > 0:
		_sync_flag(hauler)
	return n


func _room() -> bool:
	if _store.wrecks.size() >= (cap if cap > 0 else EntityId.WRECK_SLOT_END - EntityId.WRECK_SLOT_MIN):
		return false
	return _store.free_count(EntityStore.RANGE_WRECK) > 0


# One pod / wreck of `value` Ore for the dying slot `s`: ring position i of n, snapped to the terrain surface.
func _spawn(s: int, def: int, value: int, i: int, n: int, tick: int) -> bool:
	var id: int = _store.alloc(EntityStore.K_WRECK, tick)
	if id == EntityId.NULL_ID:
		return false
	var w: int = EntityId.slot(id)
	var p: Vector3 = _store.pos[s]
	if n > 1:
		var a: float = TAU * float(i) / float(n)
		var fr: Basis = Sphere.tangent_frame(p)
		p += (fr.x * cos(a) + fr.y * sin(a)) * (_store.radius[s] * 0.5)
	var at: Vector3 = _terrain.surface_point(p)
	_store.def_id[w] = def
	_store.pos[w] = at
	_store.up[w] = at.normalized()
	_store.fwd[w] = Sphere.tangent_frame(at).y
	_store.radius[w] = _store.radius[s] / float(n)
	_store.hp[w] = float(value)
	var _e: SimEvent = _events.emit(SimEvent.Kind.WRECK_SPAWNED, id, def, at, float(value), -1)
	return true


func _expire(s: int, tethered: bool) -> void:
	var _e: SimEvent = _events.emit(SimEvent.Kind.DEATH, _store.id_of(s), 0, _store.pos[s], 0.0, -1, CAUSE_EXPIRED)
	var _a: bool = _gone.push_back(s)
	if tethered:
		_touch(_store.link[s])


# A tethered wreck: release it when its Hauler is gone, deliver it when the Hauler is at a friendly Refinery.
func _tow_pass(s: int) -> void:
	var hid: int = _store.link[s]
	if not _store.alive(hid) or _store.kind[EntityId.slot(hid)] != EntityStore.K_SHIP:
		_release(s)
		return
	var h: int = EntityId.slot(hid)
	_count(h, 1)
	var r: int = _refinery_near(h)
	if r < 0:
		return
	var ore: int = roundi(_store.hp[s])
	_economy.credit(_store.team[h], ore, 0, _store.owner[h])
	var team: int = _store.team[h]
	var _a: SimEvent = _events.emit(SimEvent.Kind.WRECK_SALVAGED, _store.id_of(s), hid, _store.pos[s], float(ore), team)
	var _b: SimEvent = _events.emit(SimEvent.Kind.SALVAGE_DELIVERED, hid, _store.id_of(r), _store.pos[h], float(ore), team)
	var _g: bool = _gone.push_back(s)
	_count(h, -1)
	_touch(hid)


func _release(w: int) -> void:
	var hid: int = _store.link[w]
	_store.link[w] = 0
	_store.flags[w] &= ~EntityStore.F_TETHERED
	_store.dirty[w] |= EntityStore.DIRTY_CONTROL
	_touch(hid)


func _touch(hauler_id: int) -> void:
	if _store.alive(hauler_id) and not _touched.has(EntityId.slot(hauler_id)):
		var _a: bool = _touched.push_back(EntityId.slot(hauler_id))


# F_TETHERED on a ship = it tows at least one wreck (W7). Freed wrecks are already out of the list.
func _sync_flag(h: int) -> void:
	if (_store.flags[h] & EntityStore.F_ALIVE) == 0:
		return
	var on: bool = towed_count(h) > 0
	if on != ((_store.flags[h] & EntityStore.F_TETHERED) != 0):
		_store.flags[h] = (_store.flags[h] | EntityStore.F_TETHERED) if on else (_store.flags[h] & ~EntityStore.F_TETHERED)
		_store.dirty[h] |= EntityStore.DIRTY_CONTROL


# W6: ships whose head order is HAUL / TOW hook the order's target, then (holding a tow) neighbours, up to their slots.
func _hook_pass() -> void:
	var kinds: PackedByteArray = _store.order_kind
	for h: int in _store.ships:
		if kinds[h] != OrderSpec.Kind.HAUL or (_store.flags[h] & EntityStore.F_DOCKED) != 0:
			continue
		var slots: int = tow_slots_of(h)
		if slots <= 0 or _load[h] >= slots or not orders.read(h, OrderQueue.STANDING, 0, _spec) 				or _spec.haul_mode != OrderSpec.HaulMode.TOW:
			continue
		if EntityId.is_wreck(_spec.target) and _store.alive(_spec.target) and _can_hook(h, EntityId.slot(_spec.target)):
			_link(h, EntityId.slot(_spec.target))
		if _load[h] > 0 and _load[h] < slots:
			_hook_neighbours(h, slots)


func _can_hook(h: int, w: int) -> bool:
	return (_store.flags[w] & EntityStore.F_TETHERED) == 0 and _store.pos[h].distance_squared_to(_store.pos[w]) <= _reach * _reach


func _hook_neighbours(h: int, slots: int) -> void:
	for w: int in _store.wrecks:
		if _load[h] >= slots:
			return
		if _can_hook(h, w):
			_link(h, w)


# W8 data: the finished docking structures (Refineries), derived; rebuilt when the structure set changes (E9).
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


func _refinery_near(h: int) -> int:
	var p: Vector3 = _store.pos[h]
	var team: int = _store.team[h]
	for r: int in _refs:
		if _store.team[r] != team or (_store.flags[r] & (EntityStore.F_ALIVE | EntityStore.F_BUILDING)) != EntityStore.F_ALIVE:
			continue
		var d: float = _store.radius[r] + _reach
		if p.distance_squared_to(_store.pos[r]) <= d * d:
			return r
	return -1
