class_name CommandApplier extends RefCounted
## Tick-order step 1 (R0 B.5): applies each queued command after re-running `CommandValidator.check` (a command
## that fails it has no effect, S10). Control commands (POSSESS, RELEASE, REQUEST_POSSESS, HANDOVER) and ORDER
## intake go to 05's `ControlMachine` (`sim/control/`, AI-02); SET_ADJUTANT and the DEBUG kinds are applied here.
## Also the spawn path and the deferred death list of step 9 (C15 release through `ControlMachine.on_death`).
## BUILD, CANCEL_BUILD, PRODUCE and CANCEL_PRODUCE are routed to `EconomyHub` by `CommandIntake` (TA-19); the kinds
## whose system has not landed (SET_RALLY, TOGGLE_AUTO_REPLENISH, SURRENDER) are validated and then left to their
## owners (Production GD-17, Economy GD-20).

const DEATH_CAUSE_DEBUG: int = 0

var dying: PackedInt32Array = PackedInt32Array()   ## deferred frees of this tick (03 s4.1 rule 6), drained in step 9

var _store: EntityStore
var _orders: OrderQueue
var _players: PlayerTable
var _inputs: InputSlots
var _events: SimEvents
var _defs: WorldDefs
var _validator: CommandValidator
var _control: ControlMachine
var _spec: OrderSpec = OrderSpec.new()
var _ids: PackedInt32Array = PackedInt32Array()
var _pilot: PilotInput = PilotInput.new()


func _init(store: EntityStore, orders: OrderQueue, players: PlayerTable, inputs: InputSlots, events: SimEvents,
		defs: WorldDefs, validator: CommandValidator, control: ControlMachine) -> void:
	_store = store
	_orders = orders
	_players = players
	_inputs = inputs
	_events = events
	_defs = defs
	_validator = validator
	_control = control


## Stores a PILOT_INPUT into the player's input slot (S1's one immediate mutation, at apply_command time).
func store_pilot(cmd: Command) -> void:
	if CommandPayload.read_pilot(cmd, _pilot):
		_inputs.set_player(cmd.player, _pilot)
		_control.note_input(cmd.player)


## Applies one queued command in step 1 of `tick`.
func apply(cmd: Command, tick: int) -> void:
	if _validator.check(cmd) != CommandResult.Code.ACCEPTED:
		return
	var p: int = cmd.player
	match cmd.kind:
		Command.Kind.POSSESS, Command.Kind.RELEASE, Command.Kind.REQUEST_POSSESS, Command.Kind.HANDOVER:
			_control.apply(cmd)
		Command.Kind.ORDER:
			_apply_order(cmd, tick)
		Command.Kind.SET_ADJUTANT:
			_players.adjutant_profile[p] = cmd.payload[1] if cmd.payload[0] != 0 else -1
			_players.adjutant_toggles[p] = cmd.payload[2]
		Command.Kind.DEBUG_SPAWN:
			_debug_spawn(cmd, tick)
		Command.Kind.DEBUG_SET:
			_debug_set(cmd)


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
		_control.on_death(s)
		var _e: SimEvent = _events.emit(SimEvent.Kind.DEATH, id, _store.attacker[s], _store.pos[s], 0.0, _store.team[s],
			DEATH_CAUSE_DEBUG)
		if s < InputSlots.ENTITY_SLOTS:
			_orders.clear_slot(s)
			_inputs.clear_entity(s)
		var _f: bool = _store.free_slot(s, tick)
	var _r: int = dying.resize(0)


## 05 C1-C3, C7 through `ControlOrders.order` (issuer and tick stamped here).
func _apply_order(cmd: Command, tick: int) -> void:
	if not CommandPayload.read_order(cmd, _spec, _ids):
		return
	_spec.issuer = cmd.player
	_spec.issue_tick = tick
	_control.orders.order(_spec, _ids)


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
		_store.flip_time[s] = -sd.flip_cooldown_s
		_store.boost_time[s] = -sd.boost_cooldown_s
	_load_out(s, owner, def_id)
	var _e: SimEvent = _events.emit(SimEvent.Kind.SPAWN, id, def_id, p, 0.0, team)
	return s


# Rounds of a fresh entity (GD-36): ship primary ammo and its secondary count into `bombs` or `rockets` by the weapon's
# kind, a ground unit's `ammo`, a tower's `ammo_pool` (the tower's pool lives in `ammo`).
func _load_out(s: int, owner: int, def_id: int) -> void:
	var r: ResolvedDefs = _defs.resolved(owner)
	var sd: ShipDef = r.ship(def_id)
	if sd != null:
		_store.ammo[s] = sd.primary_ammo
		var wd: int = _defs.content.weapon_index.get(sd.secondary_weapon, -1)
		var sec: WeaponDef = r.weapon(wd)
		if sec != null and sec.kind == &"bomb":
			_store.bombs[s] = clampi(sd.secondary_count, 0, 255)
		else:
			_store.rockets[s] = clampi(sd.secondary_count, 0, 255)
		return
	var g: GroundUnitDef = r.ground_unit(def_id)
	if g != null:
		_store.ammo[s] = g.ammo
		return
	var t: StructureDef = r.structure(def_id)
	if t != null and t.is_tower():
		var pool: float = t.tower.get("ammo_pool", 0.0)
		_store.ammo[s] = roundi(pool)


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
