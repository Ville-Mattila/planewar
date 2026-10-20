class_name AutoReplenish extends RefCounted
## Auto-replenish of 02 s6.4 (GD-17, `TOGGLE_AUTO_REPLENISH`): per player and per unit def a target count (default 0).
## Every `economy.auto_replenish_period_s` one scan appends one item of `def` to the least-loaded eligible queue of the
## player's team whenever alive + queued < target. Nothing is appended into a full queue, at the unit cap or into the
## early share lock (so the replenisher never parks a head that cannot start). Targets are sim state (S4). No RNG.

const SPAN: int = DefRanges.STRUCTURE_BASE          ## ship + ground def ids: 0..511
const PAYLOAD_PAIR: int = 3                         ## u16 def + u8 count
const PAYLOAD_PAIRS_MAX: int = 8                    ## 04 s2.5 `target_roster` carries up to 8 pairs
const _STATE: PackedStringArray = ["target", "_any"]

var target: PackedByteArray = PackedByteArray()     ## [player * SPAN + def_id]: wanted alive + queued

var _store: EntityStore
var _players: PlayerTable
var _defs: WorldDefs
var _rules: MatchRules
var _prod: Production
var _econ: Economy
var _any: int = 0                                   ## non-zero targets anywhere: the scan is a no-op at 0
var _period: int = 1
var _have: PackedInt32Array = PackedInt32Array()    ## scratch [player * SPAN + def_id]: alive + queued this scan
var _units: PackedInt32Array = PackedInt32Array()   ## scratch per player: alive + queued units


func _init(store: EntityStore, players: PlayerTable, defs: WorldDefs, rules: MatchRules, production: Production,
		economy: Economy) -> void:
	_store = store
	_players = players
	_defs = defs
	_rules = rules
	_prod = production
	_econ = economy
	var eco: EconomyDef = defs.economy if defs.economy != null else EconomyDef.new()
	_period = maxi(ceili(eco.auto_replenish_period_s * float(rules.tick_hz)), 1)
	var e: int = target.resize(PlayerTable.SLOTS * SPAN) | _have.resize(PlayerTable.SLOTS * SPAN) | _units.resize(PlayerTable.SLOTS)
	assert(e == OK)
	target.fill(0)


## True when `payload` is `enabled u8` followed by 0..8 pairs of (def u16, count u8) naming ship / ground defs.
func payload_ok(payload: PackedByteArray) -> bool:
	var n: int = payload.size()
	if n < 1 or (n - 1) % PAYLOAD_PAIR != 0 or payload[0] > 1 or _pairs(payload) > PAYLOAD_PAIRS_MAX:
		return false
	for k: int in _pairs(payload):
		var d: int = payload.decode_u16(1 + k * PAYLOAD_PAIR)
		var kind: int = _defs.entity_kind(d)
		if kind != EntityStore.K_SHIP and kind != EntityStore.K_GROUND:
			return false
	return true


## Applies a validated TOGGLE_AUTO_REPLENISH payload: the player's roster is replaced (disabled = cleared).
func apply(player: int, payload: PackedByteArray) -> void:
	for d: int in SPAN:
		target[player * SPAN + d] = 0
	if payload[0] != 0:
		for k: int in _pairs(payload):
			target[player * SPAN + payload.decode_u16(1 + k * PAYLOAD_PAIR)] = payload.decode_u8(3 + k * PAYLOAD_PAIR)
	_any = 0
	for i: int in target.size():
		if target[i] != 0:
			_any += 1


func target_of(player: int, def_id: int) -> int:
	return target[player * SPAN + def_id] if def_id >= 0 and def_id < SPAN and player >= 0 and player < PlayerTable.SLOTS else 0


## Step 10 (before the queues run): every period, top up the players whose roster is short.
func step(t: int) -> void:
	if _any <= 0 or t % _period != 0:
		return
	_count()
	for p: int in PlayerTable.SLOTS:
		if _players.is_active(p) and _players.eliminated[p] == 0:
			_top_up(p)


func write_state(buf: StreamPeerBuffer) -> void:
	StateIO.put_props(buf, self, _STATE)


func read_state(buf: StreamPeerBuffer) -> bool:
	return StateIO.get_props(buf, self, _STATE) and target.size() == PlayerTable.SLOTS * SPAN and _any >= 0


func _pairs(payload: PackedByteArray) -> int:
	return MathX.floori_div(payload.size() - 1, PAYLOAD_PAIR)


func _top_up(p: int) -> void:
	var cap: int = _rules.caps.units if _rules.caps != null else 0
	for d: int in SPAN:
		var want: int = target[p * SPAN + d]
		if want == 0 or _have[p * SPAN + d] >= want or (cap > 0 and _units[p] >= cap):
			continue
		var f: int = _least_loaded(p, d)
		if f >= 0 and not _econ.spend_locked(p, _defs.cost(p, d).x) and _prod.enqueue(f, p, d, 1):
			_have[p * SPAN + d] += 1
			_units[p] += 1


# Alive units (by owner) and queued items (by queuer) into the scratch arrays.
func _count() -> void:
	_have.fill(0)
	_units.fill(0)
	for s: int in _store.ships:
		_add(_store.owner[s], _store.def_id[s])
	for s: int in _store.ground:
		_add(_store.owner[s], _store.def_id[s])
	for s: int in _store.structures:
		for i: int in _prod.length(s):
			_add(_prod.queuer(s, i), _prod.q_def[s * _prod.queue_max() + i])


func _add(owner: int, def_id: int) -> void:
	if owner >= 0 and owner < PlayerTable.SLOTS and def_id >= 0 and def_id < SPAN:
		_have[owner * SPAN + def_id] += 1
		_units[owner] += 1


# The finished factory of the player's team that makes `def_id` with the shortest queue (lowest slot on ties), -1 if
# none has room.
func _least_loaded(p: int, def_id: int) -> int:
	var best: int = -1
	var team: int = _players.team[p]
	for s: int in _store.structures:
		if _store.team[s] != team or (_store.flags[s] & EntityStore.F_BUILDING) != 0:
			continue
		var n: int = _prod.length(s)
		if n < _prod.queue_max() and _prod.can_make(_store.def_id[s], def_id) and (best < 0 or n < _prod.length(best)):
			best = s
	return best
