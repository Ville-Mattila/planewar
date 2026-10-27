class_name Docking extends RefCounted
## Landing, pad queues and service (03 s6.4, 02 s2.3, s17.1; GD-15), composed by `EconomyHub` (step 10 owner of "docking
## service") and driven by `SimWorld`: `track` in step 4 (after the assist substitution: `PilotTrack`), `land` at the end
## of step 9 (`Touchdown`: PAD contacts -> grade, LANDING, damage / crash, DOCKED), `step` in step 10 after Production
## (one pass over the ships: service of every ship DOCKED on a live finished service pad (`PadService`), a ship whose pad
## is gone is released from it, the queue wishes, then `PadQueue.update`). State (S4, economy section, format 13): the
## queue, the per-ship service record, `LandingLog`, `PilotTrack`. No Nodes, signals or RNG; constants from defs only.

var queue: PadQueue
var service: PadService
var landings: LandingLog
var grade: LandingGrade                 ## scoring.json landing parameters; null when the content set has none (no landings graded)
var pilots: PilotTrack
var touchdown: Touchdown

var _store: EntityStore
var _defs: WorldDefs
var _radius: float = 0.0                ## flight_common.auto_dock_radius_m: the queue zone around a busy pad
var _wish_ship: PackedInt32Array = PackedInt32Array()   ## step scratch: ships that want a pad this tick (ascending slot)
var _wish_pad: PackedInt32Array = PackedInt32Array()    ## ... the pad each waits for (0 none)
var _cand: PackedInt32Array = PackedInt32Array()        ## step scratch: pad slots that are busy or queued this tick
var _cand_mark: PackedInt32Array = PackedInt32Array()   ## per entity slot: `_pass` when already in `_cand`
var _dock_mark: PackedInt32Array = PackedInt32Array()   ## per entity slot: `_pass` when its pilot holds DOCK this tick
var _cand_team: PackedInt32Array = PackedInt32Array()     ## per `_cand` entry: team, TEAMS when the pad is dead
var _cand_pos: PackedVector3Array = PackedVector3Array()  ## live candidates bucketed by team: pad position, EntityId
var _cand_id: PackedInt32Array = PackedInt32Array()
var _team_at: PackedInt32Array = PackedInt32Array()       ## TEAMS + 1 bucket starts
var _team_fill: PackedInt32Array = PackedInt32Array()     ## TEAMS fill cursors
var _docked_s: PackedInt32Array = PackedInt32Array()    ## step scratch: DOCKED ship slots, ascending
var _n_wish: int = 0
var _n_cand: int = 0
var _n_docked: int = 0
var _pass: int = 0


func _init(store: EntityStore, players: PlayerTable, defs: WorldDefs, economy: Economy, events: SimEvents,
		applier: CommandApplier, hz: int) -> void:
	_store = store
	_defs = defs
	_radius = defs.common.auto_dock_radius_m if defs.common != null else 0.0
	grade = LandingGrade.from_def(defs.content.scoring)
	if grade == null:
		grade = LandingGrade.new()
	queue = PadQueue.new()
	landings = LandingLog.new()
	pilots = PilotTrack.new(store, players)
	service = PadService.new(store, defs, economy, events, landings, grade)
	touchdown = Touchdown.new(store, defs, events, DamageSink.new(store, events, applier, defs), queue, service, landings, grade,
		pilots, hz)
	var e: int = _wish_ship.resize(InputSlots.ENTITY_SLOTS) | _wish_pad.resize(InputSlots.ENTITY_SLOTS)
	e |= _cand.resize(InputSlots.ENTITY_SLOTS) | _cand_mark.resize(InputSlots.ENTITY_SLOTS) | _docked_s.resize(InputSlots.ENTITY_SLOTS)
	e |= _cand_pos.resize(InputSlots.ENTITY_SLOTS) | _cand_team.resize(InputSlots.ENTITY_SLOTS) | _cand_id.resize(InputSlots.ENTITY_SLOTS)
	e |= _dock_mark.resize(InputSlots.ENTITY_SLOTS) | _team_at.resize(PlayerTable.TEAMS + 1) | _team_fill.resize(PlayerTable.TEAMS)
	assert(e == OK)
	_cand_mark.fill(0)
	_dock_mark.fill(0)


## Step 4: possessed ships' last non-human tick and DOCK button (`PilotTrack.track`).
func track(inputs: InputSlots) -> void:
	pilots.track(inputs)


## Step 9, after Combat and before the deferred deaths: the landings of this tick's PAD contacts.
func land(t: int, collision: Collision) -> void:
	if grade.n_vert > 0.0:
		touchdown.land(t, collision)


## Step 10, after Production: one pass over the ships (docked ones, queue wishes), then ships of dead pads released,
## the service pass (`PadService.open` .. `close`), the queue.
func step(_t: int, dt: float) -> void:
	service.serviced = 0
	_n_wish = 0
	_n_cand = 0
	_n_docked = 0
	_pass += 1
	for p: int in PlayerTable.SLOTS:                          # a pilot holding DOCK wants a pad too (PilotTrack, step 4)
		var id: int = pilots.h_id[p]
		if pilots.dock_held[p] != 0 and _store.alive(id):
			_dock_mark[EntityId.slot(id)] = _pass
	var flags: PackedByteArray = _store.flags                # local handles for the read-only pass: no copies
	var kinds: PackedByteArray = _store.order_kind
	var gen: PackedInt32Array = _store.generation
	for s: int in _store.ships:                               # wishes in ascending ship slot (D6)
		if (flags[s] & EntityStore.F_DOCKED) != 0:
			_docked_s[_n_docked] = s
			_n_docked += 1
		elif kinds[s] == OrderSpec.Kind.RETURN or _dock_mark[s] == _pass:
			_wish_ship[_n_wish] = EntityId.make(s, gen[s])
			_n_wish += 1
	flags = PackedByteArray()                                # released before anything writes the store
	gen = PackedInt32Array()
	if _n_docked > 0:
		_serve_docked(dt)
	if _n_wish > 0 or not queue.q_ship.is_empty():
		_queue_pass()


## (fuel01, rearm line, hp01) of a ship DOCKED on a service pad, ZERO otherwise (SimView.service_progress).
func service_progress(id: int) -> Vector3:
	if not _store.alive(id):
		return Vector3.ZERO
	var s: int = EntityId.slot(id)
	if _store.kind[s] != EntityStore.K_SHIP or (_store.flags[s] & EntityStore.F_DOCKED) == 0 or not _on_service_pad(s):
		return Vector3.ZERO
	return service.progress(s)


## Ships waiting for `pad` in arrival order (SimView.pad_queue; allocates).
func pad_queue(pad: int) -> PackedInt32Array:
	return queue.of(pad) if _store.alive(pad) else PackedInt32Array()


## Last LandingGrade.Grade of `id`, -1 none (SimView.landing_grade_last).
func landing_grade_last(id: int) -> int:
	return landings.grade_of(id) if _store.alive(id) else -1


func write_state(buf: StreamPeerBuffer) -> void:
	queue.write_state(buf)
	service.write_state(buf)
	landings.write_state(buf)
	pilots.write_state(buf)


func read_state(buf: StreamPeerBuffer) -> bool:
	return queue.read_state(buf) and service.read_state(buf) and landings.read_state(buf) and pilots.read_state(buf)


# The docked ships: one whose pad is gone is released from it (DOCKED / LANDED and `link` cleared, falls from the next
# step 5); the rest on a live finished service pad are served in one pass; a launch pad's ship is LaunchBay's.
func _serve_docked(dt: float) -> void:
	for k: int in _n_docked:
		var s: int = _docked_s[k]
		if _store.link[s] == 0:                               # docked on nothing (no pad to lose): left as it is
			_docked_s[k] = -1
		elif not _store.alive(_store.link[s]):
			_store.flags[s] &= ~(EntityStore.F_DOCKED | EntityStore.F_LANDED)
			_store.link[s] = 0
			_store.dirty[s] |= EntityStore.DIRTY_POSE | EntityStore.DIRTY_CONTROL
			_docked_s[k] = -1
	service.open()
	var links: PackedInt32Array = _store.link
	var did: PackedInt32Array = _store.def_id
	var flags: PackedByteArray = _store.flags
	var pad_r: PackedFloat32Array = _defs.pad_radius_by_def
	for k: int in _n_docked:
		var s: int = _docked_s[k]
		if s < 0:
			continue
		var p: int = links[s] & EntityId.SLOT_MASK
		var d: int = did[p]
		if d < pad_r.size() and pad_r[d] > 0.0 and (flags[p] & EntityStore.F_BUILDING) == 0:   # PadQueries.serves, finished
			service.serve(s, p, dt)
			if _cand_mark[p] != _pass:
				_cand_mark[p] = _pass
				_cand[_n_cand] = p
				_n_cand += 1
	service.close()


func _on_service_pad(s: int) -> bool:
	var link: int = _store.link[s]
	return _store.alive(link) and PadQueries.serves(_store, _defs, EntityId.slot(link))


# The queue wishes (D6): each wishing ship waits for the nearest busy or queued live pad of its team within the queue
# radius. Candidates are bucketed by team (stable, so ties keep the candidate order: busy pads in docked-ship order, the
# queued ones in arrival order; the last of equal distance wins); ships above the highest pad + radius skip the search.
func _queue_pass() -> void:
	var qp: PackedInt32Array = queue.q_pad
	for k: int in qp.size():
		var p: int = qp[k] & EntityId.SLOT_MASK
		if _cand_mark[p] != _pass:
			_cand_mark[p] = _pass
			_cand[_n_cand] = p
			_n_cand += 1
	var top: float = _bucket()
	var r2: float = _radius * _radius
	var pos: PackedVector3Array = _store.pos
	var teams: PackedByteArray = _store.team
	for i: int in _n_wish:
		var s: int = _wish_ship[i] & EntityId.SLOT_MASK
		var at: Vector3 = pos[s]
		var tm: int = teams[s]
		var best: int = 0
		if tm < PlayerTable.TEAMS and at.length_squared() <= top:
			var best_d2: float = r2
			var k: int = _team_at[tm]
			var end: int = _team_at[tm + 1]
			while k < end:
				var d2: float = at.distance_squared_to(_cand_pos[k])
				if d2 <= best_d2:
					best_d2 = d2
					best = _cand_id[k]
				k += 1
		_wish_pad[i] = best
	queue.update(_wish_ship, _wish_pad, _n_wish)


# Counting sort of the live candidates by team into `_cand_pos` / `_cand_id`, `_team_at[t] .. _team_at[t + 1]` per team;
# returns the squared altitude filter (highest live pad centre + the queue radius).
func _bucket() -> float:
	var pos: PackedVector3Array = _store.pos
	var teams: PackedByteArray = _store.team
	var flags: PackedByteArray = _store.flags
	var gen: PackedInt32Array = _store.generation
	_team_at.fill(0)
	for k: int in _n_cand:
		var p: int = _cand[k]
		var tm: int = teams[p] if (flags[p] & EntityStore.F_ALIVE) != 0 else PlayerTable.TEAMS
		_cand_team[k] = tm
		if tm < PlayerTable.TEAMS:
			_team_at[tm + 1] += 1
	for t: int in PlayerTable.TEAMS:
		_team_at[t + 1] += _team_at[t]
		_team_fill[t] = _team_at[t]
	var top: float = 0.0
	for k: int in _n_cand:
		var tm: int = _cand_team[k]
		if tm < PlayerTable.TEAMS:
			var p: int = _cand[k]
			var j: int = _team_fill[tm]
			_team_fill[tm] = j + 1
			_cand_pos[j] = pos[p]
			_cand_id[j] = EntityId.make(p, gen[p])
			top = maxf(top, pos[p].length())
	return (top + _radius) * (top + _radius)
