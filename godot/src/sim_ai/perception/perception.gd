class_name Perception extends RefCounted
## One observer's knowledge of the world (05 s7.1 rule 2, s7.2 "Perception: visible enemies, ghosts, own assets",
## s7.8 Information / reaction delay; AI-22). Fed only by `SimView.visible_ids(team)` (the team's vision at its last
## pass), so every contact entered was `visible_to(team)` at the refresh that entered it (SC-43); difficulty only
## removes: `own` vision keeps the contacts its slot's sensors cover (`SensorCover`), a reaction delay postpones a
## new contact's use, the ghost memory forgets. Ghost = a contact not seen at the last refresh: kept at its last
## position until `memory_ticks` after its last sight, or until that position is covered by the observer's sensors and
## the team does not see it there (looked, gone). Never reads `alive`, events or anything else of an unseen entity.
## Arrays are by store slot (`EntityId.slot`); `known[0 .. n_known)` lists the contact slots in first-sight order,
## `own_*[0 .. n_own)` the observer team's own entities of the last refresh. Wrecks are not perceived. The digest of the
## last refresh (built in `known` order, so a restore rebuilds it bit for bit): `ghosts[0 .. n_ghosts)` the contacts not
## seen then; for the seen and usable ones the Ore value per cell (`fresh_val`, cells in `fresh_cells`) and the count
## per (cell, threat profile) bin (`fresh_bin[cell * profiles + p]`, keys in `fresh_keys`), which `ThreatMap` reads.
## Refresh: one `visible_ids` (allocates in the sim, `needs sim:` an O(visible) team list), one `pos` per seen ship /
## ground unit, one `team` (+ `owner` for `own` vision) per seen structure, every refresh (a capture, 05 C18, changes a
## structure's team and owner; ships and ground units never change team), and `def_id` + `team` (+ `owner`, + a
## structure's `pos`) once per new id. So the cache holds only facts fixed for the id's life: a restored run (empty
## cache) reads exactly what a continuous run uses.

const FORMAT: int = 1
const MAX_SLOT: int = EntityId.WRECK_SLOT_MIN      ## main-range slots only (wrecks are skipped)

var team: int = 0
var slot: int = -1                                 ## observer slot for `own` vision (-1: the team)
var prm: PerceptionParams = null
var tables: ThreatParams = null
var cover: SensorCover = null                      ## the observer team's sensors of the last refresh
var last_refresh: int = -1
var n_known: int = 0
var known: PackedInt32Array = PackedInt32Array()   ## contact slots, first n_known valid
var k_id: PackedInt32Array = PackedInt32Array()    ## [slot] EntityId of the contact, 0 = none
var k_first: PackedInt32Array = PackedInt32Array() ## [slot] tick of first sight (reaction delay)
var k_seen: PackedInt32Array = PackedInt32Array()  ## [slot] tick of last sight (== last_refresh: seen now)
var k_def: PackedInt32Array = PackedInt32Array()   ## [slot] def id
var k_cell: PackedInt32Array = PackedInt32Array()  ## [slot] interest cell at last sight
var k_pos: PackedVector3Array = PackedVector3Array()   ## [slot] position at last sight
var n_own: int = 0
var own_id: PackedInt32Array = PackedInt32Array()
var own_def: PackedInt32Array = PackedInt32Array()
var own_cell: PackedInt32Array = PackedInt32Array()
var own_pos: PackedVector3Array = PackedVector3Array()
var n_ghosts: int = 0
var ghosts: PackedInt32Array = PackedInt32Array()  ## slots of the contacts not seen at the last refresh
var n_fresh_cells: int = 0
var fresh_cells: PackedInt32Array = PackedInt32Array()
var fresh_val: PackedFloat32Array = PackedFloat32Array()   ## [cell] Ore value of the seen, usable contacts
var n_fresh_keys: int = 0
var fresh_keys: PackedInt32Array = PackedInt32Array()
var fresh_bin: PackedFloat32Array = PackedFloat32Array()   ## [cell * tables.profiles + profile] their count
var stats_view_calls: int = 0                      ## SimView calls (work counter)
var stats_refreshes: int = 0

var _c_id: PackedInt32Array = PackedInt32Array()   ## per-slot cache of an id's static facts (not S4 state)
var _c_def: PackedInt32Array = PackedInt32Array()
var _c_team: PackedInt32Array = PackedInt32Array()
var _c_owner: PackedInt32Array = PackedInt32Array()
var _c_cell: PackedInt32Array = PackedInt32Array()
var _c_pos: PackedVector3Array = PackedVector3Array()
var _e_slot: PackedInt32Array = PackedInt32Array() ## this refresh's other-team entities (scratch)
var _e_pos: PackedVector3Array = PackedVector3Array()


func _init(observer_team: int, observer_slot: int, p: PerceptionParams, t: ThreatParams) -> void:
	team = observer_team
	slot = observer_slot
	prm = p
	tables = t
	cover = SensorCover.new(t)
	var e: int = known.resize(MAX_SLOT) | k_id.resize(MAX_SLOT) | k_first.resize(MAX_SLOT) | k_seen.resize(MAX_SLOT)
	e |= k_def.resize(MAX_SLOT) | k_cell.resize(MAX_SLOT) | k_pos.resize(MAX_SLOT) | own_id.resize(MAX_SLOT)
	e |= own_def.resize(MAX_SLOT) | own_cell.resize(MAX_SLOT) | own_pos.resize(MAX_SLOT) | _c_id.resize(MAX_SLOT)
	e |= _c_def.resize(MAX_SLOT) | _c_team.resize(MAX_SLOT) | _c_owner.resize(MAX_SLOT) | _c_cell.resize(MAX_SLOT)
	e |= _c_pos.resize(MAX_SLOT) | _e_slot.resize(MAX_SLOT) | _e_pos.resize(MAX_SLOT) | ghosts.resize(MAX_SLOT)
	e |= fresh_cells.resize(ThreatParams.CELLS) | fresh_val.resize(ThreatParams.CELLS) | fresh_keys.resize(MAX_SLOT)
	e |= fresh_bin.resize(ThreatParams.CELLS * t.profiles)
	assert(e == OK)
	k_id.fill(0)
	_c_id.fill(0)
	fresh_val.fill(0.0)
	fresh_bin.fill(0.0)


## Reads the team's vision at `tick`: own assets, new and re-seen contacts, then forgets stale or disproved ghosts.
func refresh(v: SimView, tick: int) -> void:
	var vis: PackedInt32Array = v.visible_ids(team)
	stats_view_calls += 1 + vis.size()
	stats_refreshes += 1
	last_refresh = tick
	n_own = 0
	cover.clear()
	var ne: int = 0
	var t: ThreatParams = tables
	var cen: PackedVector3Array = t.centre
	var inc: PackedFloat32Array = t.in_cos
	for id: int in vis:
		var s: int = id & EntityId.SLOT_MASK
		if s >= MAX_SLOT:
			stats_view_calls -= 1
			continue
		if _c_id[s] != id:
			_learn(v, id, s)
		var p: Vector3
		if _c_def[s] >= DefRanges.STRUCTURE_BASE:
			p = _c_pos[s]
			_c_team[s] = v.team(id)        # re-read every refresh: a structure changes team on capture (05 C18)
			if prm.own_vision:
				_c_owner[s] = v.owner(id)
				stats_view_calls += 1
		else:
			p = v.pos(id)
			var c: int = _c_cell[s]
			if c < 0 or p.normalized().dot(cen[c]) < inc[c]:
				_c_cell[s] = Sphere.cell_of(p, ThreatParams.N)
		if _c_team[s] == team:
			_own(id, s, p)
		else:
			_e_slot[ne] = s
			_e_pos[ne] = p
			ne += 1
	cover.build()
	_contacts(ne, tick)
	_sweep(tick, true)


## Slot `s` holds a contact past the reaction delay at `tick`.
func usable(s: int, tick: int) -> bool:
	return k_id[s] != 0 and tick - k_first[s] >= prm.delay_ticks


## `id` is a usable contact at `tick` (seen or a ghost).
func knows(id: int, tick: int) -> bool:
	var s: int = id & EntityId.SLOT_MASK
	return s < MAX_SLOT and k_id[s] == id and usable(s, tick)


# Static facts of a newly listed id: def (kind from its def range), team, owner (own vision), a structure's pose.
func _learn(v: SimView, id: int, s: int) -> void:
	_c_id[s] = id
	_c_def[s] = v.def_id(id)
	_c_team[s] = v.team(id)
	_c_owner[s] = v.owner(id) if prm.own_vision else -1
	stats_view_calls += 3 if prm.own_vision else 2
	_c_cell[s] = -1
	if _c_def[s] >= DefRanges.STRUCTURE_BASE:
		_c_pos[s] = v.pos(id)
		_c_cell[s] = tables.cell_of(_c_pos[s], -1)
		stats_view_calls += 1


func _own(id: int, s: int, p: Vector3) -> void:
	var d: int = _c_def[s]
	var c: int = _c_cell[s]
	own_id[n_own] = id
	own_def[n_own] = d
	own_cell[n_own] = c
	own_pos[n_own] = p
	n_own += 1
	if k_id[s] == id:
		k_seen[s] = -1                 # a contact that joined the team (capture): forgotten below
	var r: float = tables.sensor_by_def[d]
	var rv: float = tables.reveal_by_def[d]
	if r > 0.0 or rv > 0.0:
		cover.add(p, c, r, rv, slot >= 0 and _c_owner[s] == slot)


# The other-team entities of this refresh (`_e_*[0 .. ne)`): new contacts enter, known ones are re-seen.
func _contacts(ne: int, tick: int) -> void:
	var own_only: bool = prm.own_vision
	for i: int in ne:
		var s: int = _e_slot[i]
		var p: Vector3 = _e_pos[i]
		var c: int = _c_cell[s]
		if own_only and not cover.covers(p, c, true):
			continue
		var id: int = _c_id[s]
		if k_id[s] != id:
			if k_id[s] == 0:
				known[n_known] = s
				n_known += 1
			k_id[s] = id
			k_first[s] = tick
		k_seen[s] = tick
		k_def[s] = _c_def[s]
		k_cell[s] = c
		k_pos[s] = p


# Stable pass over `known` (with `forget`: drops ghosts past memory, ghosts whose spot the observer's sensors cover
# now, i.e. the team would see them there, and contacts that joined the team) that rebuilds the digest.
func _sweep(tick: int, forget: bool) -> void:
	for k: int in n_fresh_cells:
		fresh_val[fresh_cells[k]] = 0.0
	for k: int in n_fresh_keys:
		fresh_bin[fresh_keys[k]] = 0.0
	n_fresh_cells = 0
	n_fresh_keys = 0
	n_ghosts = 0
	var val: PackedFloat32Array = tables.value_by_def
	var prof: PackedByteArray = tables.profile_by_def
	var np: int = tables.profiles
	var last_first: int = last_refresh - prm.delay_ticks
	var w: int = 0
	for i: int in n_known:
		var s: int = known[i]
		var seen: int = k_seen[s]
		var keep: bool = seen == last_refresh
		if keep:
			if k_first[s] <= last_first:
				_digest(k_cell[s], k_def[s], val, prof, np)
		else:
			keep = not forget or (seen >= 0 and tick - seen <= prm.memory_ticks
				and not cover.covers(k_pos[s], k_cell[s], prm.own_vision))
			if keep:
				ghosts[n_ghosts] = s
				n_ghosts += 1
		if keep:
			known[w] = s
			w += 1
		else:
			k_id[s] = 0
	n_known = w


func _digest(c: int, d: int, val: PackedFloat32Array, prof: PackedByteArray, np: int) -> void:
	var v: float = val[d]
	if v > 0.0:
		if fresh_val[c] == 0.0:
			fresh_cells[n_fresh_cells] = c
			n_fresh_cells += 1
		fresh_val[c] += v
	var p: int = prof[d]
	if p != 0:
		var key: int = c * np + p
		if fresh_bin[key] == 0.0:
			fresh_keys[n_fresh_keys] = key
			n_fresh_keys += 1
		fresh_bin[key] += 1.0


## S4 bytes: FORMAT, last_refresh, the contacts in list order, the own assets (caches and stats are not state).
func serialize() -> PackedByteArray:
	var b: StreamPeerBuffer = StreamPeerBuffer.new()
	b.put_u8(FORMAT)
	b.put_32(last_refresh)
	b.put_u32(n_known)
	for i: int in n_known:
		var s: int = known[i]
		b.put_32(k_id[s])
		b.put_32(k_first[s])
		b.put_32(k_seen[s])
		b.put_32(k_def[s])
		b.put_32(k_cell[s])
		_put_v3(b, k_pos[s])
	b.put_u32(n_own)
	for i: int in n_own:
		b.put_32(own_id[i])
		b.put_32(own_def[i])
		b.put_32(own_cell[i])
		_put_v3(b, own_pos[i])
	return b.data_array


## Restores `serialize` bytes; false (and empty knowledge) on a wrong FORMAT or short bytes.
func deserialize(bytes: PackedByteArray) -> bool:
	k_id.fill(0)
	_c_id.fill(0)
	n_known = 0
	n_own = 0
	last_refresh = -1
	_sweep(last_refresh, false)
	if bytes.size() < 9 or bytes[0] != FORMAT:
		return false
	var b: StreamPeerBuffer = StreamPeerBuffer.new()
	b.data_array = bytes
	b.seek(1)
	last_refresh = b.get_32()
	var nk: int = b.get_u32()
	if nk > MAX_SLOT or bytes.size() < 9 + nk * 32 + 4:
		return _fail()
	for i: int in nk:
		var id: int = b.get_32()
		var s: int = id & EntityId.SLOT_MASK
		if s <= 0 or s >= MAX_SLOT or k_id[s] != 0:
			return _fail()
		known[i] = s
		k_id[s] = id
		k_first[s] = b.get_32()
		k_seen[s] = b.get_32()
		k_def[s] = b.get_32()
		k_cell[s] = b.get_32()
		k_pos[s] = _get_v3(b)
	n_known = nk
	var no: int = b.get_u32()
	if no > MAX_SLOT or b.get_position() + no * 24 > bytes.size():
		return _fail()
	for i: int in no:
		own_id[i] = b.get_32()
		own_def[i] = b.get_32()
		own_cell[i] = b.get_32()
		own_pos[i] = _get_v3(b)
	n_own = no
	_sweep(last_refresh, false)
	return true


func _fail() -> bool:
	k_id.fill(0)
	n_known = 0
	n_own = 0
	last_refresh = -1
	_sweep(last_refresh, false)
	return false


static func _put_v3(b: StreamPeerBuffer, v: Vector3) -> void:
	b.put_float(v.x)
	b.put_float(v.y)
	b.put_float(v.z)


static func _get_v3(b: StreamPeerBuffer) -> Vector3:
	var x: float = b.get_float()
	var y: float = b.get_float()
	return Vector3(x, y, b.get_float())
