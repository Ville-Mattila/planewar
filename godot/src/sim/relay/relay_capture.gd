class_name RelayCapture extends RefCounted
## Relay Station capture and hold of tick-order step 10 (GD-23; 02 s5.3, R0 C2-20). A Hauler of team T DOCKED on a Relay
## Station's pad for `capture_s` with no ship or ground unit of another team within `contest_radius_m` hands the structure
## its own `team` and `owner`; the progress pauses while contested and returns to 0 when the Hauler leaves; recapture is the
## same rule. Everything the capture changes (pad service, sensors, Perception) reads the structure's team byte, so nothing
## else is written. State is the relay structure's own `timer_a` (progress, seconds), `timer_b` (contested flag) and
## `link` (candidate team + 1), all inside `EntityStore` (S4). No Nodes, signals or RNG; numbers from `scoring.json` `relay`.

const _SEC_PER_MIN: int = 60

var capture_s: float = 0.0
var contest_radius_m: float = 0.0

var _store: EntityStore
var _defs: WorldDefs
var _score: ScoreKeeper
var _events: SimEvents
var _def: int = -1                       ## def id of `relay_station`, -1 when the content has none


func _init(store: EntityStore, defs: WorldDefs, score: ScoreKeeper, events: SimEvents) -> void:
	_store = store
	_defs = defs
	_score = score
	_events = events
	_def = defs.content.entity_index.get(&"relay_station", -1)
	if defs.content.scoring != null:
		var rule: Dictionary = defs.content.scoring.relay
		capture_s = Def.num(rule.get("capture_s", 0.0))
		contest_radius_m = Def.num(rule.get("contest_radius_m", 0.0))


## Step 10 after Docking: every Relay Station in ascending slot order (the structures list is ascending).
func step(dt: float) -> void:
	if _def < 0 or capture_s <= 0.0:
		return
	for s: int in _store.structures:
		if _store.def_id[s] == _def:
			_relay(s, dt)


## Seconds of capture progress of the relay at slot `relay` (0 for none or not a relay).
func progress_s(relay: int) -> float:
	if relay < 0 or relay >= InputSlots.ENTITY_SLOTS or _store.def_id[relay] != _def:
		return 0.0
	return _store.timer_a[relay]


## True when an enemy pauses the capture of the relay at slot `relay` (this tick's pass).
func contested(relay: int) -> bool:
	if relay < 0 or relay >= InputSlots.ENTITY_SLOTS or _store.def_id[relay] != _def:
		return false
	return _store.timer_b[relay] > 0.0


# One relay: hold score, then the capture clock of the Hauler on its pad.
func _relay(s: int, dt: float) -> void:
	var holder: int = _store.team[s]
	if holder < PlayerTable.TEAMS and _score != null and _store.owner[s] < PlayerTable.SLOTS:
		_score.relay_held(_store.owner[s], dt / float(_SEC_PER_MIN))
	var h: int = _docked_hauler(s)
	if h < 0 or _store.team[h] == holder:
		_reset(s)
		return
	var cand: int = _store.team[h]
	if _store.link[s] != cand + 1:
		_reset(s)
		_store.link[s] = cand + 1
	if _foe_near(s, cand):
		if _store.timer_b[s] <= 0.0:
			_alert(AlertKind.Kind.RELAY_CONTESTED, s, cand, -1)
		_store.timer_b[s] = 1.0
		return
	_store.timer_b[s] = 0.0
	_store.timer_a[s] += dt
	if _store.timer_a[s] >= capture_s:
		_complete(s, h)


func _reset(s: int) -> void:
	_store.timer_a[s] = 0.0
	_store.timer_b[s] = 0.0
	_store.link[s] = 0


# The lowest-slot live Hauler DOCKED on relay `s`, -1 for none. A Hauler is a ship whose resolved def has `cargo_ice` > 0.
func _docked_hauler(s: int) -> int:
	var pad: int = _store.id_of(s)
	for u: int in _store.ships:
		if (_store.flags[u] & EntityStore.F_DOCKED) == 0 or _store.link[u] != pad:
			continue
		var sd: ShipDef = _defs.ship(_store.owner[u], _store.def_id[u])
		if sd != null and sd.cargo_ice > 0:
			return u
	return -1


# True when a ship or ground unit of a team other than `team` (neutral excluded) is within `contest_radius_m` of relay `s`.
func _foe_near(s: int, team: int) -> bool:
	var r2: float = contest_radius_m * contest_radius_m
	var p: Vector3 = _store.pos[s]
	return _any_near(_store.ships, p, team, r2) or _any_near(_store.ground, p, team, r2)


func _any_near(list: PackedInt32Array, p: Vector3, team: int, r2: float) -> bool:
	for u: int in list:
		var t: int = _store.team[u]
		if t != team and t < PlayerTable.TEAMS and p.distance_squared_to(_store.pos[u]) <= r2:
			return true
	return false


# The capture completes: the Hauler's team and owner take the structure; the loser is told, the capturer scored.
func _complete(s: int, h: int) -> void:
	var prev: int = _store.team[s]
	var owner: int = _store.owner[h]
	_store.team[s] = _store.team[h]
	_store.owner[s] = owner
	_reset(s)
	_alert(AlertKind.Kind.RELAY_CAPTURED, s, _store.team[h], owner)
	if prev < PlayerTable.TEAMS:
		_alert(AlertKind.Kind.RELAY_CONTESTED, s, prev, -1)
	if _score != null:
		_score.relay_captured(owner, _store.possessor[h] != EntityStore.NONE_U8)


func _alert(kind: AlertKind.Kind, s: int, team: int, player: int) -> void:
	var _e: SimEvent = _events.emit(SimEvent.Kind.ALERT, kind, _store.id_of(s), _store.pos[s], 0.0, team, player)
