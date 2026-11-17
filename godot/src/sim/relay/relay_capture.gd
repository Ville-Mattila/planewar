class_name RelayCapture extends RefCounted
## Open-pad capture and hold of tick-order step 10 (GD-23; 02 s5.3, R0 C2-20, R0 B.30 A-146..A-149). A capturer (a ship whose def has
## `captures`, the Hauler) of team T DOCKED on an open pad (a structure whose def has `capture_s` > 0, the Relay Station) for that
## def's `capture_s` with no ship or ground unit of another team within its `contest_radius_m` hands the structure its own `team`
## and `owner`; the progress pauses while contested and returns to 0 when the capturer leaves; recapture is the same rule.
## Everything the capture changes (pad service, sensors, Perception) reads the structure's team byte. State is the structure's own
## `timer_b` (progress, seconds; 03 s3.2 row 33), `link` (EntityId of the capturer whose capture runs, 0 none) and `timer_a`
## (1.0 while contested, else 0.0), all inside `EntityStore` (S4). No Nodes, signals or RNG; numbers from `WorldDefs`.

const _SEC_PER_MIN: int = 60

var _store: EntityStore
var _defs: WorldDefs
var _score: ScoreKeeper
var _events: SimEvents
var _any: bool = false                   ## some def carries `capture_s` (the content has an open pad)


func _init(store: EntityStore, defs: WorldDefs, score: ScoreKeeper, events: SimEvents) -> void:
	_store = store
	_defs = defs
	_score = score
	_events = events
	for v: float in defs.capture_s_by_def:
		_any = _any or v > 0.0


## Step 10 after Docking: every open pad in ascending slot order (the structures list is ascending).
func step(dt: float) -> void:
	if not _any:
		return
	for s: int in _store.structures:
		if _defs.capture_s_by_def[_store.def_id[s]] > 0.0:
			_pad(s, dt)


# One open pad: hold score, then the capture clock of the capturer docked on it.
func _pad(s: int, dt: float) -> void:
	var holder: int = _store.team[s]
	if holder < PlayerTable.TEAMS and _score != null and _store.owner[s] < PlayerTable.SLOTS:
		_score.relay_held(_store.owner[s], dt / float(_SEC_PER_MIN))
	var h: int = _docked_capturer(s)
	if h < 0 or _store.team[h] == holder:
		_reset(s)
		return
	var cand: int = _store.team[h]
	if _store.link[s] != _store.id_of(h):
		_reset(s)
		_store.link[s] = _store.id_of(h)
	if _foe_near(s, cand):
		if _store.timer_a[s] <= 0.0:
			_alert(AlertKind.Kind.RELAY_CONTESTED, s, cand, -1)
		_store.timer_a[s] = 1.0
		return
	_store.timer_a[s] = 0.0
	_store.timer_b[s] += dt
	if _store.timer_b[s] >= _defs.capture_s_by_def[_store.def_id[s]]:
		_complete(s, h)


func _reset(s: int) -> void:
	_store.timer_a[s] = 0.0
	_store.timer_b[s] = 0.0
	_store.link[s] = 0


# The lowest-slot live capturer DOCKED on pad `s`, -1 for none.
func _docked_capturer(s: int) -> int:
	var pad: int = _store.id_of(s)
	for u: int in _store.ships:
		if (_store.flags[u] & EntityStore.F_DOCKED) != 0 and _store.link[u] == pad and _defs.capturer_by_def[_store.def_id[u]] != 0:
			return u
	return -1


# True when a ship or ground unit of a team other than `team` (neutral excluded) is within the def's contest radius of pad `s`.
func _foe_near(s: int, team: int) -> bool:
	var r: float = _defs.contest_radius_by_def[_store.def_id[s]]
	var p: Vector3 = _store.pos[s]
	return _any_near(_store.ships, p, team, r * r) or _any_near(_store.ground, p, team, r * r)


func _any_near(list: PackedInt32Array, p: Vector3, team: int, r2: float) -> bool:
	for u: int in list:
		var t: int = _store.team[u]
		if t != team and t < PlayerTable.TEAMS and p.distance_squared_to(_store.pos[u]) <= r2:
			return true
	return false


# The capture completes: the capturer's team and owner take the structure; the loser is told, the capturer scored.
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
