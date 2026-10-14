class_name CommandApplier extends RefCounted
## Tick-order step 1 (R0 B.5) and the control transitions that belong to it, as an interim stand-in for 05's
## `ControlMachine` (`sim/control/`, AI-02): POSSESS (05 C6), RELEASE / implicit release (C9), disconnect (C12),
## match end (C16), death (C15, from the deferred death list of step 9), the ceiling release (C11, control check
## before the AI hook), ORDER intake into `OrderQueue` (C1-C3, C7; AI-15 refines), SET_ADJUTANT and the DEBUG kinds.
## Every applied command is re-checked with `CommandValidator.check`; a command that fails it has no effect (S10).
## Kinds whose system has not landed (BUILD, CANCEL_*, PRODUCE, SET_RALLY, TOGGLE_AUTO_REPLENISH, REQUEST_POSSESS,
## HANDOVER, SURRENDER) are validated and then left to their owners (Build TA-19, Production, ControlMachine AI-02).

## Control state, overlay and ReleaseReason ordinals (sim/MODULE.md Enumerations; `ControlMachine` takes them over).
const CS_AUTO: int = 0
const CS_ORDERED: int = 1
const CS_POSSESSED: int = 2
const OV_NONE: int = 0
const OV_SAFETY: int = 1
const OV_RECOVER_CEILING: int = 2
const OV_LINK_BRIDGE: int = 3
const RR_PLAYER: int = 0
const RR_DEATH: int = 1
const RR_CEILING: int = 2
const RR_HANDOVER: int = 3
const RR_DISCONNECT: int = 4
const RR_MATCH: int = 5
const RR_INVALID: int = 6
const RR_ADMIN: int = 7
const DEATH_CAUSE_DEBUG: int = 0

var dying: PackedInt32Array = PackedInt32Array()   ## deferred frees of this tick (03 s4.1 rule 6), drained in step 9

var _store: EntityStore
var _orders: OrderQueue
var _players: PlayerTable
var _inputs: InputSlots
var _events: SimEvents
var _defs: WorldDefs
var _validator: CommandValidator
var _spec: OrderSpec = OrderSpec.new()
var _ids: PackedInt32Array = PackedInt32Array()
var _pilot: PilotInput = PilotInput.new()


func _init(store: EntityStore, orders: OrderQueue, players: PlayerTable, inputs: InputSlots, events: SimEvents,
		defs: WorldDefs, validator: CommandValidator) -> void:
	_store = store
	_orders = orders
	_players = players
	_inputs = inputs
	_events = events
	_defs = defs
	_validator = validator


## Stores a PILOT_INPUT into the player's input slot (S1's one immediate mutation, at apply_command time).
func store_pilot(cmd: Command) -> void:
	if CommandPayload.read_pilot(cmd, _pilot):
		_inputs.set_player(cmd.player, _pilot)


## Applies one queued command in step 1 of `tick`.
func apply(cmd: Command, tick: int) -> void:
	if _validator.check(cmd) != CommandResult.Code.ACCEPTED:
		return
	var p: int = cmd.player
	match cmd.kind:
		Command.Kind.POSSESS:
			possess(p, EntityId.slot(cmd.target))
		Command.Kind.RELEASE:
			release_player(p, RR_PLAYER)
		Command.Kind.ORDER:
			_apply_order(cmd, tick)
		Command.Kind.SET_ADJUTANT:
			_players.adjutant_profile[p] = cmd.payload[1] if cmd.payload[0] != 0 else -1
			_players.adjutant_toggles[p] = cmd.payload[2]
		Command.Kind.DEBUG_SPAWN:
			_debug_spawn(cmd, tick)
		Command.Kind.DEBUG_SET:
			_debug_set(cmd)


## 05 C6: `p` takes `s`; a previous possession of `p` is released first (C9) in the same tick.
func possess(p: int, s: int) -> void:
	release_player(p, RR_PLAYER)
	_store.possessor[s] = p
	_store.control_state[s] = CS_POSSESSED
	_store.overlay[s] = OV_NONE
	_store.dirty[s] |= EntityStore.DIRTY_CONTROL
	_orders.clear(s, OrderQueue.PENDING)
	_inputs.clear_entity(s)
	_inputs.clear_player(p)
	var id: int = _store.id_of(s)
	_players.possessed[p] = id
	var _e: SimEvent = _events.emit(SimEvent.Kind.POSSESSED, id, p, _store.pos[s], 0.0, _store.team[s])


## 05 C9 (and C11, C12, C15, C16 by `reason`): releases whatever `p` possesses; no-op when nothing.
func release_player(p: int, reason: int) -> void:
	var id: int = _players.possessed[p]
	if id == 0:
		return
	_players.possessed[p] = 0
	_inputs.clear_player(p)
	if not _store.alive(id):
		return
	var s: int = EntityId.slot(id)
	_store.possessor[s] = EntityStore.NONE_U8
	var _c: bool = _orders.commit_pending(s)
	_store.control_state[s] = CS_ORDERED if _orders.count(s, OrderQueue.STANDING) > 0 else CS_AUTO
	_store.overlay[s] = OV_RECOVER_CEILING if reason == RR_CEILING else (OV_SAFETY if reason == RR_PLAYER else OV_NONE)
	_store.dirty[s] |= EntityStore.DIRTY_CONTROL
	_inputs.clear_entity(s)
	var _e: SimEvent = _events.emit(SimEvent.Kind.RELEASED, id, p, _store.pos[s], 0.0, _store.team[s], reason)
	if reason == RR_CEILING:
		var _f: SimEvent = _events.emit(SimEvent.Kind.CEILING_RELEASE, id, p, _store.pos[s], 0.0, _store.team[s])


## Step 1 control check: possessions of disconnected players end (05 C12, after `SimWorld.remove_player`).
func release_disconnected() -> void:
	for p: int in PlayerTable.SLOTS:
		if _players.possessed[p] != 0 and _players.connected[p] == 0:
			release_player(p, RR_DISCONNECT)


## Releases every possession with `reason` (05 C16 at match end).
func release_all(reason: int) -> void:
	for p: int in PlayerTable.SLOTS:
		release_player(p, reason)


## Step 3 control check (05 C11): a possessed entity at or above `ceiling_hard_m` is released to RECOVER_CEILING.
func ceiling_check(ceiling_r: float) -> void:
	for p: int in PlayerTable.SLOTS:
		var id: int = _players.possessed[p]
		if id != 0 and _store.alive(id) and _store.pos[EntityId.slot(id)].length() >= ceiling_r:
			release_player(p, RR_CEILING)


## Marks `s` for the deferred free at the end of step 9 (03 s4.1 rule 6); idempotent within a tick.
func kill(s: int) -> void:
	if not dying.has(s):
		var _a: bool = dying.push_back(s)


## End of step 9: every dying entity is released (C15), freed into quarantine (S2) and reported by DEATH.
func resolve_deaths(tick: int) -> void:
	for s: int in dying:
		if (_store.flags[s] & EntityStore.F_ALIVE) == 0:
			continue
		var id: int = _store.id_of(s)
		var who: int = _store.possessor[s]
		if who != EntityStore.NONE_U8:
			release_player(who, RR_DEATH)
		var _e: SimEvent = _events.emit(SimEvent.Kind.DEATH, id, _store.attacker[s], _store.pos[s], 0.0, _store.team[s],
			DEATH_CAUSE_DEBUG)
		if s < InputSlots.ENTITY_SLOTS:
			_orders.clear_slot(s)
			_inputs.clear_entity(s)
		var _f: bool = _store.free_slot(s, tick)
	var _r: int = dying.resize(0)


## 05 C1-C3, C7: standing queue, or the pending queue of a POSSESSED entity (with a PENDING_ORDER alert).
func _apply_order(cmd: Command, tick: int) -> void:
	if not CommandPayload.read_order(cmd, _spec, _ids):
		return
	_spec.issuer = cmd.player
	_spec.issue_tick = tick
	for id: int in _ids:
		var s: int = EntityId.slot(id)
		if _store.control_state[s] == CS_POSSESSED:
			if _orders.push(s, OrderQueue.PENDING, _spec) == OrderQueue.Push.OK:
				var _e: SimEvent = _events.emit(SimEvent.Kind.ALERT, AlertKind.Kind.PENDING_ORDER, id, _store.pos[s],
					0.0, _store.team[s])
		elif _orders.push(s, OrderQueue.STANDING, _spec) == OrderQueue.Push.OK:
			_store.control_state[s] = CS_ORDERED
			_store.dirty[s] |= EntityStore.DIRTY_CONTROL


func _debug_spawn(cmd: Command, tick: int) -> void:
	var b: PackedByteArray = cmd.payload
	var d: int = b.decode_u16(0)
	var s: int = spawn(d, b.decode_u8(2), b.decode_u8(3), CommandPayload.v3_at(b, 4), CommandPayload.v3_at(b, 28),
		CommandPayload.v3_at(b, 52), tick)
	if s < 0:
		var _e: SimEvent = _events.emit(SimEvent.Kind.CAP_REACHED, cmd.player, d, Vector3.ZERO, 0.0, -1)


## Allocates and fills one entity of `def_id` (flip and boost ready, full HP / fuel / ammo); SPAWN event. -1 when
## the range is full. Production and Build (later tasks) spawn through here as well.
func spawn(def_id: int, owner: int, team: int, p: Vector3, v: Vector3, fwd_in: Vector3, tick: int) -> int:
	var k: int = _defs.entity_kind(def_id)
	var id: int = _store.alloc(k, tick)
	if id == EntityId.NULL_ID:
		return -1
	var s: int = EntityId.slot(id)
	var n: Vector3 = p.normalized()
	var f: Vector3 = fwd_in.normalized() if fwd_in.length_squared() > 0.0 else Sphere.tangent_frame(p).x
	var u: Vector3 = n - f * n.dot(f)
	u = u.normalized() if u.length_squared() > 0.0 else Sphere.tangent_frame(p).y
	_store.def_id[s] = def_id
	_store.owner[s] = owner
	_store.team[s] = team
	_store.pos[s] = p
	_store.vel[s] = v
	_store.fwd[s] = f
	_store.up[s] = u
	_store.radius[s] = _defs.radius_of(def_id)
	_store.hp[s] = _defs.hp_max(owner, def_id)
	if _defs.possessable(def_id):
		_store.flags[s] |= EntityStore.F_POSSESSABLE
	var sd: ShipDef = _defs.ship(owner, def_id)
	if sd != null:
		_store.fuel[s] = sd.fuel_s
		_store.ammo[s] = sd.primary_ammo
		_store.rockets[s] = clampi(sd.secondary_count, 0, 255)
		_store.flip_time[s] = -sd.flip_cooldown_s
		_store.boost_time[s] = -sd.boost_cooldown_s
	var _e: SimEvent = _events.emit(SimEvent.Kind.SPAWN, id, def_id, p, 0.0, team)
	return s


func _debug_set(cmd: Command) -> void:
	var s: int = EntityId.slot(cmd.target)
	var field: int = cmd.payload.decode_u8(0)
	var value: float = cmd.payload.decode_double(1)
	if field == CommandPayload.SET_HP:
		_store.hp[s] = value
		_store.dirty[s] |= EntityStore.DIRTY_VITALS
		if value <= 0.0:
			kill(s)
	elif field == CommandPayload.SET_FUEL:
		_store.fuel[s] = value
		_store.dirty[s] |= EntityStore.DIRTY_VITALS
	else:
		kill(s)
