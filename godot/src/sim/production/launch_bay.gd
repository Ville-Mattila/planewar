class_name LaunchBay extends RefCounted
## Rally points and the launch of 02 s2.3 / s6.4 (GD-17, R0 B.9 A-19). A produced ship spawns DOCKED tail-down on its
## Shipyard's launch pad (`dock`; `link` = the Shipyard) and leaves on the next step by the normal launch rule: DOCKED
## cleared, `launch_speed_mps` along the pad normal, one LAUNCHED event, then `ORDERED: move to rally` when the factory
## has a rally point. Until the ship has cleared the Shipyard's bounding sphere it keeps `link` (Collision never rams a
## ship against the structure it is linked to) and stays on the departing list. A produced ground unit takes the rally
## order at once. How fast the climb passes 20 m AGL ("about 3 s after completion") is the ship's thrust, not a timer
## here. Rally points are per factory slot; the lists are short and compact (swap removal, deterministic).

const _LISTS: PackedStringArray = ["l_ship", "l_pad", "l_out"]

var rally: PackedVector3Array = PackedVector3Array()   ## per factory slot: the rally point
var rally_set: PackedByteArray = PackedByteArray()     ## per factory slot: 1 once SET_RALLY landed
var l_ship: PackedInt32Array = PackedInt32Array()      ## ships parked or departing: EntityId
var l_pad: PackedInt32Array = PackedInt32Array()       ## ... the Shipyard EntityId
var l_out: PackedByteArray = PackedByteArray()         ## ... 0 parked (launches next step), 1 launched and still inside the Shipyard sphere

var _store: EntityStore
var _defs: WorldDefs
var _events: SimEvents
var _applier: CommandApplier


func _init(store: EntityStore, defs: WorldDefs, events: SimEvents, applier: CommandApplier) -> void:
	_store = store
	_defs = defs
	_events = events
	_applier = applier
	var e: int = rally.resize(EntityId.WRECK_SLOT_MIN) | rally_set.resize(EntityId.WRECK_SLOT_MIN)
	assert(e == OK)
	rally.fill(Vector3.ZERO)
	rally_set.fill(0)


func set_rally(factory: int, p: Vector3) -> void:
	rally[factory] = p
	rally_set[factory] = 1


func has_rally(factory: int) -> bool:
	return rally_set[factory] != 0


func rally_of(factory: int) -> Vector3:
	return rally[factory]


## Ships parked on a pad or still leaving one.
func pending() -> int:
	return l_ship.size()


## The factory died: its rally point goes with it. Ships already parked on its pad still leave.
func forget(factory: int) -> void:
	rally[factory] = Vector3.ZERO
	rally_set[factory] = 0


## Parks the fresh ship slot `u` tail-down (nose along the pad normal) on the launch pad of factory slot `f`.
func dock(u: int, f: int) -> void:
	_store.fwd[u] = _store.up[f]
	_store.up[u] = _store.fwd[f]
	_store.vel[u] = Vector3.ZERO
	_store.flags[u] |= EntityStore.F_DOCKED
	_store.link[u] = _store.id_of(f)
	var _a: bool = l_ship.push_back(_store.id_of(u))
	var _b: bool = l_pad.push_back(_store.id_of(f))
	var _c: bool = l_out.push_back(0)


## A produced ground unit goes to its factory's rally point (if any).
func send_ground(u: int, f: int, owner: int, tick: int) -> void:
	if rally_set[f] != 0:
		_applier.order_move(u, owner, rally[f], tick)


## Step 10: parked ships leave; departing ships that cleared the Shipyard sphere drop their link.
func step(t: int) -> void:
	var i: int = 0
	while i < l_ship.size():
		var keep: bool = _store.alive(l_ship[i])
		if keep and l_out[i] == 0:
			keep = _launch(i, t)
		elif keep and _cleared(i):
			_store.link[EntityId.slot(l_ship[i])] = 0
			keep = false
		if keep:
			i += 1
		else:
			_drop(i)


func write_state(buf: StreamPeerBuffer) -> void:
	var n: int = 0
	for f: int in rally_set.size():
		n += rally_set[f]
	buf.put_32(n)
	for f: int in rally_set.size():
		if rally_set[f] != 0:
			buf.put_32(f)
			buf.put_var(rally[f])
	StateIO.put_props(buf, self, _LISTS)


func read_state(buf: StreamPeerBuffer) -> bool:
	rally.fill(Vector3.ZERO)
	rally_set.fill(0)
	var n: int = buf.get_32()
	if n < 0 or n > rally.size():
		return false
	for _k: int in n:
		var f: int = buf.get_32()
		var v: Variant = buf.get_var()
		if f < 0 or f >= rally.size() or typeof(v) != TYPE_VECTOR3:
			return false
		rally[f] = v
		rally_set[f] = 1
	return StateIO.get_props(buf, self, _LISTS) and l_pad.size() == l_ship.size() and l_out.size() == l_ship.size()


# Leave the pad; false (leave the list) for a ship someone possessed in the meantime: it stays docked for the pilot's own
# launch (GD-15) and its velocity is not touched.
func _launch(i: int, t: int) -> bool:
	var u: int = EntityId.slot(l_ship[i])
	if _store.control_state[u] == ControlMachine.State.POSSESSED:
		return false
	var pad: int = EntityId.slot(l_pad[i])
	_store.flags[u] &= ~EntityStore.F_DOCKED
	_store.vel[u] = _store.fwd[u] * _defs.common.launch_speed_mps
	_store.dirty[u] |= EntityStore.DIRTY_POSE | EntityStore.DIRTY_CONTROL
	l_out[i] = 1
	var _e: SimEvent = _events.emit(SimEvent.Kind.LAUNCHED, l_ship[i], l_pad[i], _store.pos[u], 0.0, _store.team[u])
	if _store.alive(l_pad[i]) and rally_set[pad] != 0:
		_applier.order_move(u, _store.owner[u], rally[pad], t)
	return true


# True once the ship is outside the Shipyard's bounding sphere (or the Shipyard is gone).
func _cleared(i: int) -> bool:
	if not _store.alive(l_pad[i]):
		return true
	var u: int = EntityId.slot(l_ship[i])
	var pad: int = EntityId.slot(l_pad[i])
	var reach: float = _store.radius[pad] + _store.radius[u]
	return _store.pos[u].distance_squared_to(_store.pos[pad]) > reach * reach


# Swap removal keeps the lists compact and deterministic.
func _drop(i: int) -> void:
	var last: int = l_ship.size() - 1
	l_ship[i] = l_ship[last]
	l_pad[i] = l_pad[last]
	l_out[i] = l_out[last]
	var _a: int = l_ship.resize(last)
	var _b: int = l_pad.resize(last)
	var _c: int = l_out.resize(last)
