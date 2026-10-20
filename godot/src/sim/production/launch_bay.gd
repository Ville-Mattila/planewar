class_name LaunchBay extends RefCounted
## Rally points and the 3 s launch of 02 s6.4 / s2.3 (GD-17). A produced ship is parked DOCKED tail-down on its
## Shipyard's launch pad (`dock`), leaves `economy.launch_delay_s` later at `launch_speed_mps` along the pad normal
## (LAUNCHED event, DOCKED cleared) and then takes `ORDERED: move to rally` when the factory has a rally point; a
## produced ground unit takes the rally order at once. Rally points are per factory slot; pending launches are a short
## compact list in dock order (swap removal, deterministic). No Nodes, signals or RNG.

const _STATE: PackedStringArray = ["rally", "rally_set", "l_ship", "l_due", "l_pad"]

var rally: PackedVector3Array = PackedVector3Array()   ## per factory slot: the rally point
var rally_set: PackedByteArray = PackedByteArray()     ## per factory slot: 1 once SET_RALLY landed
var l_ship: PackedInt32Array = PackedInt32Array()      ## pending launches: ship EntityId
var l_due: PackedInt32Array = PackedInt32Array()       ## ... tick at which it leaves
var l_pad: PackedInt32Array = PackedInt32Array()       ## ... the pad (Shipyard) EntityId

var _store: EntityStore
var _defs: WorldDefs
var _events: SimEvents
var _applier: CommandApplier
var _delay_ticks: int = 0


func _init(store: EntityStore, defs: WorldDefs, events: SimEvents, applier: CommandApplier, hz: int) -> void:
	_store = store
	_defs = defs
	_events = events
	_applier = applier
	var eco: EconomyDef = defs.economy if defs.economy != null else EconomyDef.new()
	_delay_ticks = ceili(eco.launch_delay_s * float(hz))
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


func pending() -> int:
	return l_ship.size()


## The factory died: its rally point goes with it. Ships already parked on its pad still leave on schedule.
func forget(factory: int) -> void:
	rally[factory] = Vector3.ZERO
	rally_set[factory] = 0


## Parks the fresh ship slot `u` tail-down (nose along the pad normal) on the launch pad of factory slot `f`.
func dock(u: int, f: int, tick: int) -> void:
	var pad_up: Vector3 = _store.up[f]
	_store.fwd[u] = pad_up
	_store.up[u] = _store.fwd[f]
	_store.vel[u] = Vector3.ZERO
	_store.flags[u] |= EntityStore.F_DOCKED
	_store.link[u] = _store.id_of(f)
	var _a: bool = l_ship.push_back(_store.id_of(u))
	var _b: bool = l_due.push_back(tick + _delay_ticks)
	var _c: bool = l_pad.push_back(_store.id_of(f))


## A produced ground unit goes to its factory's rally point (if any).
func send_ground(u: int, f: int, owner: int, tick: int) -> void:
	if rally_set[f] != 0:
		_applier.order_move(u, owner, rally[f], tick)


## Step 10: every parked ship whose time has come leaves its pad.
func step(t: int) -> void:
	var i: int = 0
	while i < l_ship.size():
		if not _store.alive(l_ship[i]):
			_drop(i)
		elif t >= l_due[i]:
			_launch(i, t)
			_drop(i)
		else:
			i += 1


func write_state(buf: StreamPeerBuffer) -> void:
	StateIO.put_props(buf, self, _STATE)


func read_state(buf: StreamPeerBuffer) -> bool:
	if not StateIO.get_props(buf, self, _STATE):
		return false
	var n: int = l_ship.size()
	return rally.size() == EntityId.WRECK_SLOT_MIN and rally_set.size() == EntityId.WRECK_SLOT_MIN \
			and l_due.size() == n and l_pad.size() == n


func _launch(i: int, t: int) -> void:
	var u: int = EntityId.slot(l_ship[i])
	var pad: int = EntityId.slot(l_pad[i])
	_store.flags[u] &= ~EntityStore.F_DOCKED
	_store.link[u] = 0
	_store.vel[u] = _store.fwd[u] * _defs.common.launch_speed_mps
	_store.dirty[u] |= EntityStore.DIRTY_POSE | EntityStore.DIRTY_CONTROL
	var _e: SimEvent = _events.emit(SimEvent.Kind.LAUNCHED, l_ship[i], l_pad[i], _store.pos[u], 0.0, _store.team[u])
	if _store.alive(l_pad[i]) and rally_set[pad] != 0:
		_applier.order_move(u, _store.owner[u], rally[pad], t)


# Swap removal keeps the list compact and deterministic.
func _drop(i: int) -> void:
	var last: int = l_ship.size() - 1
	l_ship[i] = l_ship[last]
	l_due[i] = l_due[last]
	l_pad[i] = l_pad[last]
	var _a: int = l_ship.resize(last)
	var _b: int = l_due.resize(last)
	var _c: int = l_pad.resize(last)
