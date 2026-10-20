class_name Production extends RefCounted
## Production queues of 02 s6.4 (TA-19; GD-17: `LaunchBay` rally + 3 s launch, `AutoReplenish`): one queue of at most
## `economy.queue_max` (5, S13) items per Shipyard / Vehicle Bay, shared by the team; every item remembers the player
## who queued it (the unit is that player's, with that player's doctrine; owner-only cancel, S12). The head item is paid
## when it STARTS (waiting for Ore / Ice / the early share lock otherwise, one alert per wait), then runs for
## `build_time_s / max(production_min_speed, power_ratio)`; a head that would exceed the unit cap blocks the queue with
## `CAP_REACHED` (+ ALERT PRODUCTION_BLOCKED_CAP) until a unit dies or is cancelled. Cancel refunds
## `cancel_refund_assembly` of what the head paid (queued items paid nothing: `cancel_refund_queued` of 0).
## Queue arrays are per entity slot of the factory, `queue_max` items each; progress lives in the factory's `timer_a`.

const NO_ITEM: int = -1
const CAP_UNITS: int = 0       ## CAP_REACHED `b` (04 s3.6 cap kind: 0 units, 1 structures, 2 projectiles)
const _FLAG_CAP: int = 1       ## CAP_REACHED already reported for this block
const _FLAG_WAIT: int = 2      ## "waiting" alert already raised for this wait
const _STATE: PackedStringArray = ["q_def", "q_player", "q_len", "started", "paid_ore", "paid_ice", "_flags", "_total"]

var q_def: PackedInt32Array = PackedInt32Array()       ## [slot * queue_max + i] unit def_id, NO_ITEM when empty
var q_player: PackedByteArray = PackedByteArray()      ## same index: the player who queued it
var q_len: PackedByteArray = PackedByteArray()         ## per factory slot
var started: PackedByteArray = PackedByteArray()       ## per factory slot: 1 once the head has been paid
var paid_ore: PackedInt32Array = PackedInt32Array()    ## per factory slot: what the head paid
var paid_ice: PackedInt32Array = PackedInt32Array()

var launch: LaunchBay                                  ## rally points, pad parking and the launch delay (GD-17)
var replenish: AutoReplenish                           ## per-player unit targets (GD-17)

var _store: EntityStore
var _players: PlayerTable
var _defs: WorldDefs
var _rules: MatchRules
var _events: SimEvents
var _econ: Economy
var _applier: CommandApplier
var _cfg: EconomyDef
var _qmax: int = 0
var _flags: PackedByteArray = PackedByteArray()
var _total: int = 0                                    ## items queued anywhere: step is a no-op at 0
var _units: PackedInt32Array = PackedInt32Array()      ## scratch per player: live units this tick
var _units_tick: int = -1


func _init(store: EntityStore, players: PlayerTable, defs: WorldDefs, rules: MatchRules, events: SimEvents,
		economy: Economy, applier: CommandApplier) -> void:
	_store = store
	_players = players
	_defs = defs
	_rules = rules
	_events = events
	_econ = economy
	_applier = applier
	_cfg = defs.economy if defs.economy != null else EconomyDef.new()
	_qmax = _cfg.queue_max
	var n: int = EntityId.WRECK_SLOT_MIN
	var e: int = q_def.resize(n * _qmax) | q_player.resize(n * _qmax) | q_len.resize(n) | started.resize(n)
	e |= paid_ore.resize(n) | paid_ice.resize(n) | _flags.resize(n) | _units.resize(PlayerTable.SLOTS)
	assert(e == OK)
	q_def.fill(NO_ITEM)
	q_player.fill(0)
	q_len.fill(0)
	started.fill(0)
	paid_ore.fill(0)
	paid_ice.fill(0)
	_flags.fill(0)
	_units.fill(0)
	launch = LaunchBay.new(store, defs, events, applier)
	replenish = AutoReplenish.new(store, players, defs, rules, self, economy)


func queue_max() -> int:
	return _qmax


func length(factory: int) -> int:
	return q_len[factory]


## Player who queued item `i` of `factory`, -1 when there is no such item.
func queuer(factory: int, i: int) -> int:
	return q_player[factory * _qmax + i] if i >= 0 and i < q_len[factory] else -1


## Unit def_ids of the queue, head first (a copy; for `SimView.production_queue`).
func queue_of(factory: int) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for i: int in q_len[factory]:
		var _a: bool = out.push_back(q_def[factory * _qmax + i])
	return out


## Head progress 0..1 (0 while unpaid or idle).
func progress01(factory: int) -> float:
	if q_len[factory] == 0 or started[factory] == 0:
		return 0.0
	var bt: float = _build_time(q_player[factory * _qmax], q_def[factory * _qmax])
	return clampf(_store.timer_a[factory] / bt, 0.0, 1.0) if bt > 0.0 else 1.0


## True when structure def `factory_def` produces anything (a Shipyard or Vehicle Bay).
func is_factory(factory_def: int) -> bool:
	var f: StructureDef = _defs.base.structure(factory_def)
	if f == null:
		return false
	for s: ShipDef in _defs.base.ships:
		if s.produced_at == f.id:
			return true
	for g: GroundUnitDef in _defs.base.ground_units:
		if g.produced_at == f.id:
			return true
	return false


## True when `unit_def` is made at structure def `factory_def` (its `produced_at`).
func can_make(factory_def: int, unit_def: int) -> bool:
	var f: StructureDef = _defs.base.structure(factory_def)
	if f == null:
		return false
	var s: ShipDef = _defs.base.ship(unit_def)
	if s != null:
		return s.produced_at == f.id
	var g: GroundUnitDef = _defs.base.ground_unit(unit_def)
	return g != null and g.produced_at == f.id


## Appends `count` items of `unit_def` queued by `player`; false (nothing added) when the queue would pass `queue_max` (S13).
func enqueue(factory: int, player: int, unit_def: int, count: int) -> bool:
	var n: int = q_len[factory]
	if count < 1 or n + count > _qmax:
		return false
	for k: int in count:
		q_def[factory * _qmax + n + k] = unit_def
		q_player[factory * _qmax + n + k] = player
	q_len[factory] = n + count
	_total += count
	return true


## Removes item `i` (S12 rights are the validator's). A paid head refunds `cancel_refund_assembly` of its payment.
func cancel(factory: int, i: int) -> void:
	var n: int = q_len[factory]
	if i < 0 or i >= n:
		return
	var base: int = factory * _qmax
	if i == 0:
		var f: float = _cfg.cancel_refund_assembly if started[factory] != 0 else _cfg.cancel_refund_queued
		_econ.refund(q_player[base], floori(float(paid_ore[factory]) * f), floori(float(paid_ice[factory]) * f))
		_reset_head(factory)
	for k: int in range(i, n - 1):
		q_def[base + k] = q_def[base + k + 1]
		q_player[base + k] = q_player[base + k + 1]
	q_def[base + n - 1] = NO_ITEM
	q_player[base + n - 1] = 0
	q_len[factory] = n - 1
	_total -= 1


## The factory died: its queue is lost without refund (nothing was promised after destruction).
func forget(factory: int) -> void:
	launch.forget(factory)
	_total -= q_len[factory]
	for i: int in q_len[factory]:
		q_def[factory * _qmax + i] = NO_ITEM
	q_len[factory] = 0
	_reset_head(factory)


## Step 10: every finished factory with a queue starts or advances its head.
func step(t: int, dt: float) -> void:
	launch.step(t)
	replenish.step(t)
	if _total <= 0:
		return
	for s: int in _store.structures:
		if q_len[s] != 0 and (_store.flags[s] & EntityStore.F_BUILDING) == 0:
			_run(s, t, dt)


func write_state(buf: StreamPeerBuffer) -> void:
	StateIO.put_props(buf, self, _STATE)
	launch.write_state(buf)
	replenish.write_state(buf)


func read_state(buf: StreamPeerBuffer) -> bool:
	if not StateIO.get_props(buf, self, _STATE) or not launch.read_state(buf) or not replenish.read_state(buf):
		return false
	var n: int = EntityId.WRECK_SLOT_MIN
	return q_def.size() == n * _qmax and q_player.size() == n * _qmax \
			and StateIO.sizes_ok(self, ["q_len", "started", "paid_ore", "paid_ice", "_flags"], n) and _total >= 0


func _run(s: int, t: int, dt: float) -> void:
	var player: int = q_player[s * _qmax]
	var unit: int = q_def[s * _qmax]
	if started[s] == 0 and not _start(s, player, unit, t):
		return
	var team: int = _store.team[s]
	_store.timer_a[s] += dt * _econ.production_speed(team)
	if _store.timer_a[s] >= _build_time(player, unit):
		_finish(s, player, unit, t)


func _start(s: int, player: int, unit: int, t: int) -> bool:
	if _at_cap(player, t):
		_block(s, player)
		return false
	var c: Vector2i = _defs.cost(player, unit)
	var r: Economy.Pay = _econ.try_pay(player, c.x, c.y)
	if r != Economy.Pay.OK:
		if (_flags[s] & _FLAG_WAIT) == 0:
			_flags[s] |= _FLAG_WAIT
			var kind: AlertKind.Kind = AlertKind.Kind.SPEND_LOCKED if r == Economy.Pay.LOCKED else AlertKind.Kind.WAITING_FOR_ORE
			if r == Economy.Pay.SHORT and c.y > _players.team_ice[_players.team[player]]:
				kind = AlertKind.Kind.WAITING_FOR_ICE
			var _e: SimEvent = _events.emit(SimEvent.Kind.ALERT, kind, _store.id_of(s), _store.pos[s], 0.0, _store.team[s], player)
		return false
	started[s] = 1
	paid_ore[s] = c.x
	paid_ice[s] = c.y
	_store.timer_a[s] = 0.0
	_flags[s] = 0
	return true


func _finish(s: int, player: int, unit: int, t: int) -> void:
	if _at_cap(player, t):
		_block(s, player)
		return
	var ship: bool = _defs.entity_kind(unit) == EntityStore.K_SHIP
	# A ship spawns DOCKED on the launch pad (the Shipyard's `pos`, normal `up`); a ground unit rolls out at the front.
	var at: Vector3 = _store.pos[s] + _store.fwd[s] * _store.radius[s]
	if ship:
		at = _store.pos[s] + _store.up[s] * _defs.radius_of(unit)
	var u: int = _applier.spawn(unit, player, _players.team[player], at, Vector3.ZERO, _store.fwd[s], t)
	if u < 0:
		_block(s, player)
		return
	if ship:
		launch.dock(u, s)
	else:
		launch.send_ground(u, s, player, t)
	_units[player] += 1
	_pop_head(s)


# The head left the queue by finishing: no refund.
func _pop_head(s: int) -> void:
	var base: int = s * _qmax
	var n: int = q_len[s]
	for k: int in range(0, n - 1):
		q_def[base + k] = q_def[base + k + 1]
		q_player[base + k] = q_player[base + k + 1]
	q_def[base + n - 1] = NO_ITEM
	q_player[base + n - 1] = 0
	q_len[s] = n - 1
	_total -= 1
	_reset_head(s)


func _block(s: int, player: int) -> void:
	if (_flags[s] & _FLAG_CAP) == 0:
		_flags[s] |= _FLAG_CAP
		var _c: SimEvent = _events.emit(SimEvent.Kind.CAP_REACHED, player, CAP_UNITS, _store.pos[s], 0.0, -1)
		var _a: SimEvent = _events.emit(SimEvent.Kind.ALERT, AlertKind.Kind.PRODUCTION_BLOCKED_CAP, _store.id_of(s),
			_store.pos[s], 0.0, _store.team[s], player)


func _reset_head(s: int) -> void:
	started[s] = 0
	paid_ore[s] = 0
	paid_ice[s] = 0
	_flags[s] = 0
	_store.timer_a[s] = 0.0


func _at_cap(player: int, t: int) -> bool:
	if t != _units_tick:
		_units_tick = t
		for p: int in PlayerTable.SLOTS:
			_units[p] = 0
		for s: int in _store.ships:
			_count(s)
		for s: int in _store.ground:
			_count(s)
	return _rules.caps != null and _rules.caps.units > 0 and _units[player] >= _rules.caps.units


func _count(s: int) -> void:
	if _store.owner[s] < PlayerTable.SLOTS:
		_units[_store.owner[s]] += 1


func _build_time(player: int, unit: int) -> float:
	var r: ResolvedDefs = _defs.resolved(player)
	var s: ShipDef = r.ship(unit)
	if s != null:
		return s.build_time_s
	var g: GroundUnitDef = r.ground_unit(unit)
	return g.build_time_s if g != null else 0.0
