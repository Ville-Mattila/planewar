class_name EconomyHub extends RefCounted
## The economy-side systems of one `SimWorld` composed in one place (TA-19), so `SimWorld` and `CommandApplier` stay
## small: `Build` (placement, footprints), `Economy` (pools, power, payment), `Construction` (sites) and `Production`
## (queues). Step 1 routes BUILD, CANCEL_BUILD, PRODUCE and CANCEL_PRODUCE here (re-checked by the validator first,
## S10); step 9's deaths release footprints, sites and queues (`on_death`); step 10 runs Economy, Construction,
## Production. `spawn_start_kit` lays out the C2-14 opening for one player. No Nodes, no signals, no RNG.

var build: Build
var economy: Economy
var construction: Construction
var production: Production
var repair: SelfRepair
var supply: SupplyNet                    ## GD-18: the Pylon graph, supplied flags and tower refill (02 s5.4)
var salvage: Salvage                     ## GD-19: wrecks, pods, tows and delivery (02 s13)

var _store: EntityStore
var _players: PlayerTable
var _defs: WorldDefs
var _events: SimEvents
var _applier: CommandApplier
var _validator: CommandValidator
var _tick: int = 0


func _init(store: EntityStore, players: PlayerTable, defs: WorldDefs, rules: MatchRules, terrain: Terrain,
		events: SimEvents, applier: CommandApplier, validator: CommandValidator) -> void:
	_store = store
	_players = players
	_defs = defs
	_events = events
	_applier = applier
	_validator = validator
	build = Build.new(defs, store, players, terrain, rules)
	economy = Economy.new(store, players, defs, rules.tick_hz, events, build)
	economy.sun_period_s = rules.sun_period_s
	construction = Construction.new(store, players, defs, events, economy, build)
	construction.applier = applier
	production = Production.new(store, players, defs, rules, events, economy, applier)
	repair = SelfRepair.new(store, defs, economy, rules.tick_hz)
	supply = SupplyNet.new(store, defs, rules.tick_hz)
	salvage = Salvage.new(store, defs, economy, events, terrain, rules.tick_hz, rules.caps.wrecks if rules.caps != null else 0)
	validator.build = build
	validator.production = production


## True for the command kinds step 1 routes here instead of `CommandApplier`.
static func handles(kind: Command.Kind) -> bool:
	return kind == Command.Kind.BUILD or kind == Command.Kind.CANCEL_BUILD or kind == Command.Kind.PRODUCE \
			or kind == Command.Kind.CANCEL_PRODUCE \
			or kind == Command.Kind.SET_RALLY or kind == Command.Kind.TOGGLE_AUTO_REPLENISH


## Step 1: applies `cmd` after the validator's re-check (a command made invalid by an earlier one has no effect).
func apply(cmd: Command) -> void:
	if _validator.check(cmd) != CommandResult.Code.ACCEPTED:
		return
	match cmd.kind:
		Command.Kind.BUILD:
			var id: int = build.place(cmd.player, CommandPayload.u16_at(cmd, 0), CommandPayload.u32_at(cmd, 2), CommandPayload.u8_at(cmd, 6))
			if id != EntityId.NULL_ID:
				construction.enrol(EntityId.slot(id))
		Command.Kind.CANCEL_BUILD:
			var s: int = EntityId.slot(cmd.target)
			if construction.is_site(s):
				var _ore: int = construction.cancel(s)
		Command.Kind.PRODUCE:
			var _ok: bool = production.enqueue(EntityId.slot(cmd.target), cmd.player, CommandPayload.u16_at(cmd, 0), CommandPayload.u8_at(cmd, 2))
		Command.Kind.CANCEL_PRODUCE:
			production.cancel(EntityId.slot(cmd.target), CommandPayload.u8_at(cmd, 0))
		Command.Kind.SET_RALLY:
			production.launch.set_rally(EntityId.slot(cmd.target), CommandPayload.v3_at(cmd.payload, 0))
		Command.Kind.TOGGLE_AUTO_REPLENISH:
			production.replenish.apply(cmd.player, cmd.payload)


## Start of every tick: the clock `Build` stamps sites with and the early share lock reads.
func begin_tick(t: int) -> void:
	_tick = t
	build.set_clock(t)


## Step 10 (the economy row): pools and power, construction, production.
func step(t: int, dt: float) -> void:
	economy.set_clock(t)
	economy.step()
	construction.step(t, dt)
	production.step(t, dt)
	salvage.step(t)
	supply.step(t, economy.structure_epoch)
	repair.unsupplied = supply.unsupplied   # the repair pass reads the flags of this tick
	repair.step(t)


## Step 9, before the deferred free of slot `s`: it leaves its wrecks (GD-19); a dying structure frees its footprint, its site and its queue.
func on_death(s: int) -> void:
	if (_store.flags[s] & EntityStore.F_ALIVE) == 0:
		return
	var _wrecks: int = salvage.on_death(s, _tick)   # GD-19: ships, ground units and finished structures leave wrecks
	if _store.kind[s] != EntityStore.K_STRUCTURE:
		return
	var finished: bool = (_store.flags[s] & EntityStore.F_BUILDING) == 0
	build.release_site(s)
	construction.forget(s)
	production.forget(s)
	economy.mark_dirty()
	if finished:
		# 04 s3.6: structure, def u16 (extra[0..1] LE), killer
		var e: SimEvent = _events.emit(SimEvent.Kind.STRUCTURE_LOST, _store.id_of(s), _store.attacker[s], _store.pos[s], 0.0, _store.team[s])
		e.extra = PackedByteArray([_store.def_id[s] & 0xFF, (_store.def_id[s] >> 8) & 0xFF])


## C2-14 (02 s8.1): `economy.start_kit` for `slot` around `centre` (a direction from the planet centre): the Core there,
## the Refinery `start_refinery_dist_m` toward `toward` (Home Field A), the Shipyard `start_adjacent_dist_m` beside the
## Core, the Vehicle Bay beside the Refinery, the Harvester next to the Refinery. All finished, all pre-built (they count
## against `max_per_player`). False when a structure cannot be created (entity store full or a def without footprint); occupancy is not checked, the kit is laid out on a clear site.
func spawn_start_kit(slot: int, centre: Vector3, toward: Vector3, tick: int) -> bool:
	var eco: EconomyDef = _defs.economy
	if eco == null or not _players.is_active(slot):
		return false
	var n: Vector3 = centre.normalized()
	var along: Vector3 = (toward - n * toward.dot(n)).normalized()
	var side: Vector3 = n.cross(along)
	var ref_dir: Vector3 = _step(n, along, eco.start_refinery_dist_m)
	var ok: bool = true
	for id: String in eco.start_kit:
		var def: int = _defs.content.entity_index.get(StringName(id), -1)
		match id:
			"core":
				ok = _stamp(slot, def, n) and ok
			"refinery":
				ok = _stamp(slot, def, ref_dir) and ok
			"shipyard":
				ok = _stamp(slot, def, _step(n, side, eco.start_adjacent_dist_m)) and ok
			"vehicle_bay":
				ok = _stamp(slot, def, _step(ref_dir, side, eco.start_adjacent_dist_m)) and ok
			_:
				if _defs.entity_kind(def) != EntityStore.K_STRUCTURE:
					var at: Vector3 = _step(ref_dir, along, eco.start_adjacent_dist_m) * Sphere.PLANET_RADIUS
					ok = _applier.spawn(def, slot, _players.team[slot], at, Vector3.ZERO, along, tick) >= 0 and ok
	economy.mark_dirty()
	return ok


func write_state(buf: StreamPeerBuffer) -> void:
	build.write_state(buf)
	economy.write_state(buf)
	construction.write_state(buf)
	production.write_state(buf)


func read_state(buf: StreamPeerBuffer) -> bool:
	return build.read_state(buf) and economy.read_state(buf) and construction.read_state(buf) and production.read_state(buf)


func _stamp(slot: int, def: int, dir: Vector3) -> bool:
	return build.stamp(slot, def, Sphere.cell_of(dir, Sphere.GRID_BUILD), 0, true) != EntityId.NULL_ID


# `dir` moved `metres` along the great circle that leaves it toward the unit tangent `tangent`.
func _step(dir: Vector3, tangent: Vector3, metres: float) -> Vector3:
	var a: float = metres / Sphere.PLANET_RADIUS
	var t: Vector3 = (tangent - dir * tangent.dot(dir)).normalized()
	return dir * cos(a) + t * sin(a)
