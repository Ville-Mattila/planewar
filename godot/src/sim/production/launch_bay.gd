class_name LaunchBay extends RefCounted
## Rally points and the launch of 02 s2.3 / s6.4 (GD-17, R0 B.9 A-19, A-82, A-87). A produced ship spawns DOCKED tail-down on
## its Shipyard's launch pad (`dock`; `link` = the Shipyard) and leaves on the next step by the normal launch rule: DOCKED
## and `link` cleared in the same tick, `launch_speed_mps` along the pad normal, one LAUNCHED event, then `ORDERED: move to
## rally` when the factory has a rally point; the ship is forgotten at LAUNCHED. A produced ground unit takes the rally
## order at once. How fast the climb passes 20 m AGL ("about 3 s after completion") is the ship's thrust, not a timer
## here. Rally points are per factory slot; the list of parked ships is short (dock order).

const _LISTS: PackedStringArray = ["l_ship", "l_pad"]

var rally: PackedVector3Array = PackedVector3Array()   ## per factory slot: the rally point
var rally_set: PackedByteArray = PackedByteArray()     ## per factory slot: 1 once SET_RALLY landed
var l_ship: PackedInt32Array = PackedInt32Array()      ## ships parked on a pad (launch next step): EntityId
var l_pad: PackedInt32Array = PackedInt32Array()       ## ... the Shipyard EntityId

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


## Ships parked on a pad, waiting for their launch.
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


## A produced ground unit goes to its factory's rally point (if any).
func send_ground(u: int, f: int, owner: int, tick: int) -> void:
	if rally_set[f] != 0:
		_applier.order_move(u, owner, rally[f], tick)


## Step 10: every parked ship launches (dead or possessed ones are just forgotten).
func step(t: int) -> void:
	for i: int in l_ship.size():
		if _store.alive(l_ship[i]):
			_launch(i, t)
	var _a: int = l_ship.resize(0)
	var _b: int = l_pad.resize(0)


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
	return StateIO.get_props(buf, self, _LISTS) and l_pad.size() == l_ship.size()


# Leave the pad; a ship someone possessed in the meantime stays docked for the pilot's own launch (GD-15) and its velocity
# is not touched.
func _launch(i: int, t: int) -> void:
	var u: int = EntityId.slot(l_ship[i])
	if _store.control_state[u] == ControlMachine.State.POSSESSED:
		return
	var pad: int = EntityId.slot(l_pad[i])
	_store.flags[u] &= ~EntityStore.F_DOCKED
	_store.link[u] = 0
	_store.vel[u] = _store.fwd[u] * _defs.common.launch_speed_mps
	_store.dirty[u] |= EntityStore.DIRTY_POSE | EntityStore.DIRTY_CONTROL
	var _e: SimEvent = _events.emit(SimEvent.Kind.LAUNCHED, l_ship[i], l_pad[i], _store.pos[u], 0.0, _store.team[u])
	if _store.alive(l_pad[i]) and rally_set[pad] != 0:
		_applier.order_move(u, _store.owner[u], rally[pad], t)
