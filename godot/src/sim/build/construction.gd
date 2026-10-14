class_name Construction extends RefCounted
## Construction sites of 02 s6.3 (TA-19): a site placed by `Build.place` is QUEUED until its owner has a free
## construction slot (`construction_slots_base` + finished Outposts, at most `construction_slots_max`); starting an
## assembly pays the full cost (waiting for Ore, Ice or the early share lock otherwise, one alert per wait); the site
## then gains `1 / build_time_s` progress per second (power never matters) and HP `hp * max(site_hp_fraction, progress)`;
## at progress 1 the structure is finished (BUILD_DONE). Cancel (S12 rights are the validator's) refunds
## `cancel_refund_queued` (queued) or `cancel_refund_assembly` (assembling) of what was paid and frees the footprint.
## Progress lives in the entity's `timer_a`; state, payment and the wait flag in the arrays below (per entity slot).

enum State { NONE, QUEUED, ASSEMBLING }

const _STATE: PackedStringArray = ["state", "paid_ore", "paid_ice", "waiting", "_sites"]

var state: PackedByteArray = PackedByteArray()           ## State per entity slot
var paid_ore: PackedInt32Array = PackedInt32Array()      ## what an assembling site paid
var paid_ice: PackedInt32Array = PackedInt32Array()
var waiting: PackedByteArray = PackedByteArray()         ## 1 once the "waiting for funds / lock" alert fired for this site

var _store: EntityStore
var _players: PlayerTable
var _defs: WorldDefs
var _events: SimEvents
var _econ: Economy
var _build: Build
var _cfg: EconomyDef
var applier: CommandApplier = null   ## the deferred free of a cancelled site (set by the wiring)

var _sites: int = 0              ## live sites (queued + assembling): step is a no-op at 0
var _busy: PackedInt32Array = PackedInt32Array()      ## scratch per player: assembling count
var _outposts: PackedInt32Array = PackedInt32Array()  ## scratch per player: finished Outposts
var _outpost_def: int = -1


func _init(store: EntityStore, players: PlayerTable, defs: WorldDefs, events: SimEvents, economy: Economy, build: Build) -> void:
	_store = store
	_players = players
	_defs = defs
	_events = events
	_econ = economy
	_build = build
	_cfg = defs.economy if defs.economy != null else EconomyDef.new()
	var e: int = state.resize(EntityId.WRECK_SLOT_MIN) | paid_ore.resize(EntityId.WRECK_SLOT_MIN) | paid_ice.resize(EntityId.WRECK_SLOT_MIN)
	e |= waiting.resize(EntityId.WRECK_SLOT_MIN) | _busy.resize(PlayerTable.SLOTS) | _outposts.resize(PlayerTable.SLOTS)
	assert(e == OK)
	state.fill(State.NONE)
	paid_ore.fill(0)
	paid_ice.fill(0)
	waiting.fill(0)
	_outpost_def = defs.content.entity_index.get(&"outpost", -1)


## Slots a player may assemble at once: base + finished Outposts, capped (02 s6.3).
func slot_limit(outposts_alive: int) -> int:
	return mini(_cfg.construction_slots_base + outposts_alive, _cfg.construction_slots_max)


## Enrols the freshly placed site `s` (from `Build.place`) as QUEUED.
func enrol(s: int) -> void:
	state[s] = State.QUEUED
	paid_ore[s] = 0
	paid_ice[s] = 0
	waiting[s] = 0
	_sites += 1


func is_site(s: int) -> bool:
	return state[s] != State.NONE


## Progress 0..1 of site `s` (0 while queued).
func progress01(s: int) -> float:
	var sd: StructureDef = _defs.resolved(_store.owner[s]).structure(_store.def_id[s])
	if state[s] != State.ASSEMBLING or sd == null or sd.build_time_s <= 0.0:
		return 0.0
	return clampf(_store.timer_a[s] / sd.build_time_s, 0.0, 1.0)


## Cancels site `s`: refunds (S12 rights already checked) and marks the entity for the deferred free (`kill`, no wreck;
## the footprint is released with it). Returns the Ore refunded.
func cancel(s: int) -> int:
	var f: float = _cfg.cancel_refund_assembly if state[s] == State.ASSEMBLING else _cfg.cancel_refund_queued
	var ore: int = floori(float(paid_ore[s]) * f)
	_econ.refund(_store.owner[s], ore, floori(float(paid_ice[s]) * f))
	forget(s)   # the footprint is freed with the deferred death (EconomyHub.on_death), not before
	if applier != null:
		applier.kill(s)
	return ore


## Drops the site bookkeeping of slot `s` (cancel, or the entity died).
func forget(s: int) -> void:
	if state[s] != State.NONE:
		_sites -= 1
	state[s] = State.NONE
	paid_ore[s] = 0
	paid_ice[s] = 0
	waiting[s] = 0
	_store.timer_a[s] = 0.0


## Step 10: progress, completion, then queued sites into free slots in placement order.
func step(_t: int, dt: float) -> void:
	if _sites == 0:
		return
	_busy.fill(0)
	_outposts.fill(0)
	var queued: bool = false
	for s: int in _store.structures:
		var o: int = _store.owner[s]
		if o >= PlayerTable.SLOTS:
			continue
		if state[s] == State.ASSEMBLING:
			if _advance(s, dt):
				_outposts[o] += 1 if _store.def_id[s] == _outpost_def else 0
			else:
				_busy[o] += 1
		elif state[s] == State.QUEUED:
			queued = true
		elif _store.def_id[s] == _outpost_def and (_store.flags[s] & EntityStore.F_BUILDING) == 0:
			_outposts[o] += 1
	if queued:
		_start_queued()


# True when the site finished this tick.
func _advance(s: int, dt: float) -> bool:
	var o: int = _store.owner[s]
	var sd: StructureDef = _defs.resolved(o).structure(_store.def_id[s])
	var before: float = maxf(_cfg.site_hp_fraction, progress01(s))
	_store.timer_a[s] += dt
	var p: float = progress01(s)
	var hpm: float = _defs.hp_max(o, _store.def_id[s])
	_store.hp[s] += hpm * (maxf(_cfg.site_hp_fraction, p) - before)
	if p < 1.0 and sd.build_time_s > 0.0:
		return false
	_store.flags[s] &= ~EntityStore.F_BUILDING
	_store.hp[s] = maxf(_store.hp[s], 0.0)
	_store.timer_a[s] = 0.0
	forget(s)
	_econ.mark_dirty()
	var id: int = _store.id_of(s)
	var _e: SimEvent = _events.emit(SimEvent.Kind.BUILD_DONE, id, _store.def_id[s], _store.pos[s], 0.0, _store.team[s])
	var _a: SimEvent = _events.emit(SimEvent.Kind.ALERT, AlertKind.Kind.BUILD_DONE, id, _store.pos[s], 0.0, _store.team[s], o)
	return true


func _start_queued() -> void:
	for p: int in PlayerTable.SLOTS:
		if _players.active[p] == 0:
			continue
		while _busy[p] < slot_limit(_outposts[p]):
			var s: int = _oldest_queued(p)
			if s < 0 or not _try_start(s, p):
				break
			_busy[p] += 1


# The player's QUEUED site that was placed first (spawn_tick, then slot).
func _oldest_queued(p: int) -> int:
	var best: int = -1
	for s: int in _store.structures:
		if state[s] == State.QUEUED and _store.owner[s] == p:
			if best < 0 or _store.spawn_tick[s] < _store.spawn_tick[best]:
				best = s
	return best


func _try_start(s: int, p: int) -> bool:
	var c: Vector2i = _defs.cost(p, _store.def_id[s])
	var r: Economy.Pay = _econ.try_pay(p, c.x, c.y)
	if r != Economy.Pay.OK:
		if waiting[s] == 0:
			waiting[s] = 1
			var kind: AlertKind.Kind = AlertKind.Kind.SPEND_LOCKED if r == Economy.Pay.LOCKED else AlertKind.Kind.WAITING_FOR_ORE
			if r == Economy.Pay.SHORT and c.y > _players.team_ice[_players.team[p]]:
				kind = AlertKind.Kind.WAITING_FOR_ICE
			var _e: SimEvent = _events.emit(SimEvent.Kind.ALERT, kind, _store.id_of(s), _store.pos[s], 0.0, _store.team[s], p)
		return false
	state[s] = State.ASSEMBLING
	paid_ore[s] = c.x
	paid_ice[s] = c.y
	_store.timer_a[s] = 0.0
	var _b: SimEvent = _events.emit(SimEvent.Kind.BUILD_STARTED, _store.id_of(s), _store.def_id[s], _store.pos[s], 0.0, _store.team[s], p)
	return true


func write_state(buf: StreamPeerBuffer) -> void:
	StateIO.put_props(buf, self, _STATE)


func read_state(buf: StreamPeerBuffer) -> bool:
	if not StateIO.get_props(buf, self, _STATE):
		return false
	return StateIO.sizes_ok(self, ["state", "paid_ore", "paid_ice", "waiting"], EntityId.WRECK_SLOT_MIN) and _sites >= 0
