class_name TeamPicture extends RefCounted
## Per-team list of the enemy ships the team sees (05 s6: `visible_to` only), built once per Vision epoch on first use
## and shared by every choice point of the epoch (AI-13). Team t's visibility bits change only in its own Vision pass
## (tick step 11 on ticks with tick % period == t % period, `Vision.runs`), so within an epoch (the ticks after one pass
## up to the next) the membership is a function of the epoch alone: a restored session rebuilds it identically (not in
## the S4 bytes). A fresh enemy ship starts with no visibility bits (EntityStore.alloc) and stays out until the next
## pass, as the list does; `near` skips the dead and reads live positions. A choice point filters the list by distance
## instead of an `ids_near` over its 1.2-2 km radius (beyond `Spatial.ring2_m` that walks every touched hash cell).
## Built from `SimView.visible_enemy_ships` (TA-63, V10: live ships of other teams, ascending EntityId, the team's last
## Vision pass) instead of a `ships()` walk; same set and order as the old walk, so every tie-break is unchanged.

var _tick: PackedInt32Array = PackedInt32Array()     ## by team: Vision epoch of the cached list (-1: none)
var _ids: Array[PackedInt32Array] = []                ## by team: visible enemy ships of that epoch
var _near: PackedInt32Array = PackedInt32Array()      ## scratch of `near` (grown on demand, reused)
var _buf: PackedInt32Array = PackedInt32Array()      ## scratch of the Vision list (grown by the view, reused)
var builds: int = 0                                   ## lists built (tests, perf)
var period: int = 1                                   ## Vision pass period in ticks (DartParams.vision_period; the session's rungs)


func _init() -> void:
	var _r: int = _tick.resize(PlayerTable.TEAMS)
	_tick.fill(-1)
	for t: int in PlayerTable.TEAMS:
		_ids.append(PackedInt32Array())


## The enemy ships team `team` sees at `tick` (the shared list: do not modify).
func enemies(view: SimView, team: int, tick: int) -> PackedInt32Array:
	if team < 0 or team >= PlayerTable.TEAMS:
		return PackedInt32Array()
	var e: int = epoch(team, tick)
	if _tick[team] != e:
		_tick[team] = e
		builds += 1
		var n: int = view.visible_enemy_ships(team, _buf)   # Vision's list, ascending EntityId (V10), the old ships() order
		_ids[team] = _buf.slice(0, n)
	return _ids[team]


## The visible enemy ships of `team` within `radius` (3D) of `origin`, into a reused scratch; returns the count `n`
## (the ids are `near_ids()[0..n)`).
func near(view: SimView, team: int, tick: int, origin: Vector3, radius: float) -> int:
	var list: PackedInt32Array = enemies(view, team, tick)
	if _near.size() < list.size():
		var _r: int = _near.resize(list.size())
	var r2: float = radius * radius
	var n: int = 0
	for id: int in list:
		if view.alive(id) and origin.distance_squared_to(view.pos(id)) <= r2:
			_near[n] = id
			n += 1
	return n


## Vision epoch of `team` at `tick`: the number of its last pass before this tick's step 3.
func epoch(team: int, tick: int) -> int:
	return MathX.floori_div(tick - 1 - team % period, period)


## Forgets every list (after a restore or a rebind; the next use rebuilds).
func reset() -> void:
	_tick.fill(-1)


## The scratch `near` filled.
func near_ids() -> PackedInt32Array:
	return _near
