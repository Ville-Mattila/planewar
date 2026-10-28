class_name ScoreKeeper extends RefCounted
## Score events and the match result of one `SimWorld` (02 s17.1, GD-27; 03 s3.2 `scoring`, tick-order steps 9 and 10).
## Every point lands on a player's Pilot side (earned by the entity the player possesses) or Commander side
## (everything else); score never affects the match. Fed three ways, all inside `SimWorld.step()`:
## - `on_dying` (end of step 9, before the deferred frees): scans the events so far (HIT -> damage window and structure
##   damage, LANDING -> landing points, POSSESSED -> sorties), then scores the entities about to die (kills, deaths,
##   structures destroyed, assists) while victim and killer are still in the store;
## - `end_tick` (end of step 10): scans the rest (BUILD_DONE, SALVAGE_DELIVERED), counts pilot time and reads the Ore spent;
## - `finalize` at MATCH_END: `match_win`.
## The seams of systems that have not landed are public methods: `ore_mined` / `ice_delivered` (Harvest, Ice: GD-12 / GD-14),
## `relay_captured` / `relay_held` (GD-23). A content set without `scoring.json` scores nothing. No RNG, no Nodes.

const NO_CLASS: int = 255

var ledger: ScoreLedger = ScoreLedger.new()
var hits: ScoreHits = ScoreHits.new()

var _store: EntityStore
var _players: PlayerTable
var _defs: WorldDefs
var _events: SimEvents
var _def: ScoringDef
var _hz: int
var _window_ticks: int = 0
var _kill_pts: PackedInt32Array = PackedInt32Array()      ## by def_id: kill_points of the unit (0 = none)
var _class_of: PackedByteArray = PackedByteArray()        ## by def_id: pilot_time_s class or NO_CLASS
var _land_pts: PackedFloat32Array = PackedFloat32Array()  ## by LandingGrade.Grade: landing.points
var _hauler: int = -1
var _core: int = -1
var _mark: int = 0                                         ## first event of `_events.list` not scanned yet
var _drains_seen: int = 0
var _spend_paid: PackedFloat64Array = PackedFloat64Array()   ## per player: commander_ore_spent points paid so far (high-water)
var _won: int = 0                                          ## 1 once finalize paid match_win
var _total: PackedFloat32Array = PackedFloat32Array()     ## assist scratch per owner
var _by_pilot: PackedFloat32Array = PackedFloat32Array()


func _init(store: EntityStore, players: PlayerTable, defs: WorldDefs, events: SimEvents, hz: int) -> void:
	_store = store
	_players = players
	_defs = defs
	_events = events
	_hz = hz
	_def = defs.content.scoring
	var e: int = _spend_paid.resize(PlayerTable.SLOTS) | _total.resize(PlayerTable.SLOTS) | _by_pilot.resize(PlayerTable.SLOTS)
	e |= _kill_pts.resize(DefRanges.END) | _class_of.resize(DefRanges.END) | _land_pts.resize(LandingGrade.Grade.size())
	assert(e == OK)
	_spend_paid.fill(0.0)
	_kill_pts.fill(0)
	_class_of.fill(NO_CLASS)
	_land_pts.fill(0.0)
	var idx: Dictionary = defs.content.entity_index
	_hauler = idx.get(&"hauler", -1)
	_core = idx.get(&"core", -1)
	for c: int in ScoreLedger.CLASS_COUNT:
		var d: int = idx.get(StringName(ScoreLedger.CLASS_IDS[c]), -1)
		if d >= 0 and d < DefRanges.END:
			_class_of[d] = c
	if _def == null:
		return
	for unit: Variant in _def.kill_points:
		var d: int = idx.get(StringName(str(unit)), -1)
		if d >= 0 and d < DefRanges.END:
			_kill_pts[d] = roundi(Def.num(_def.kill_points[unit]))
	var pts: Dictionary = _def.landing["points"] if _def.landing.has("points") else {}
	_land_pts[LandingGrade.Grade.HARD] = Def.num(pts.get("hard", 0.0))
	_land_pts[LandingGrade.Grade.FAIR] = Def.num(pts.get("fair", 0.0))
	_land_pts[LandingGrade.Grade.CLEAN] = Def.num(pts.get("clean", 0.0))
	_land_pts[LandingGrade.Grade.ACE] = Def.num(pts.get("ace", 0.0))
	_window_ticks = ceili(Def.num(_def.assist.get("window_s", 0.0)) * float(hz))


## (Pilot, Commander) points of `slot`; zero for a slot that never scored.
func score_of(slot: int) -> Vector2i:
	if slot < 0 or slot >= PlayerTable.SLOTS:
		return Vector2i.ZERO
	return Vector2i(ledger.pilot[slot], ledger.commander[slot])


## Points a manual landing earns: the grade's points x `hot_mult` (LANDING flags bit1) + `dead_stick_bonus` (bit2); 0 for
## AUTO / BENT / CRASH (no points) and for a landing whose manual bit (bit0) is clear (R0 B.24 A-121).
func landing_points(grade: int, flags: int) -> float:
	if _def == null or (flags & 1) == 0 or grade < 0 or grade >= _land_pts.size() or _land_pts[grade] <= 0.0:
		return 0.0
	var p: float = _land_pts[grade]
	if (flags & 2) != 0:
		p *= Def.num(_def.landing.get("hot_mult", 1.0))
	if (flags & 4) != 0:
		p += Def.num(_def.landing.get("dead_stick_bonus", 0.0))
	return p


## Scans the events emitted since the last scan (a drain of the list restarts at its beginning).
func scan() -> void:
	var list: Array[SimEvent] = _events.list
	if _events.drains != _drains_seen:
		_drains_seen = _events.drains
		_mark = 0
	if _mark > list.size():
		_mark = 0
	var from: int = _mark
	_mark = list.size()
	if _def == null:
		return
	for i: int in range(from, _mark):
		var e: SimEvent = list[i]
		match e.kind:
			SimEvent.Kind.HIT:
				_on_hit(e)
			SimEvent.Kind.LANDING:
				_on_landing(e)
			SimEvent.Kind.POSSESSED:
				_on_possessed(e)
			SimEvent.Kind.BUILD_DONE:
				_on_built(e)
			SimEvent.Kind.SALVAGE_DELIVERED:
				_on_salvage(e)
			_:
				pass


## End of step 9: `dying` are the slots `CommandApplier.resolve_deaths` is about to free.
func on_dying(dying: PackedInt32Array, t: int) -> void:
	scan()
	if _def == null:
		return
	for i: int in dying.size():
		var s: int = dying[i]
		if (_store.flags[s] & EntityStore.F_ALIVE) == 0 or _listed_before(dying, i):
			continue
		_on_death(s, t)


## End of step 10: the remaining events, pilot time per class, the Ore spent ledger (`spent_ore` per player slot).
func end_tick(spent_ore: PackedInt32Array) -> void:
	scan()
	if _def == null:
		return
	var per_ore: float = _def.commander_points_per_ore_spent
	for p: int in PlayerTable.SLOTS:
		if _players.active[p] == 0:
			continue
		var id: int = _players.possessed[p]
		if id != 0 and _store.alive(id):
			var c: int = _class_of[_store.def_id[EntityId.slot(id)]]
			if c != NO_CLASS:
				ledger.pilot_ticks[p * ScoreLedger.CLASS_COUNT + c] += 1
		ledger.ore_spent[p] = spent_ore[p]
		var due: float = float(spent_ore[p]) * per_ore
		if due > _spend_paid[p]:
			ledger.credit(p, false, due - _spend_paid[p])
			_spend_paid[p] = due


## MATCH_END (02 s17.1 `match_win`): every member of `winner_team` earns it on the Commander side, once.
func finalize(winner_team: int) -> void:
	if _def == null or _won != 0 or winner_team < 0:
		return
	_won = 1
	for p: int in PlayerTable.SLOTS:
		if _players.active[p] != 0 and _players.team[p] == winner_team:
			ledger.credit(p, false, float(_def.match_win))


## Harvest seam (GD-12): `ore` mined by `player`'s Harvesters; the result counter only (no points).
func ore_mined(player: int, ore: int) -> void:
	if player >= 0 and player < PlayerTable.SLOTS and ore > 0:
		ledger.ore_mined[player] += ore


## Ice seam (GD-14): `ice` delivered for `player`; counts for the result, and scores `ice_delivered_possessed` when the
## delivering Hauler was possessed.
func ice_delivered(player: int, ice: int, possessed: bool) -> void:
	if _def == null or player < 0 or player >= PlayerTable.SLOTS or ice <= 0:
		return
	ledger.ice_delivered[player] += ice
	if possessed:
		ledger.credit(player, true, float(ice) * _def.ice_possessed_points_per_ice)


## Relay seam (GD-23): a capture by `player`; Pilot side when the capturing Hauler was possessed.
func relay_captured(player: int, possessed: bool) -> void:
	if _def != null:
		ledger.credit(player, possessed, Def.num(_def.relay.get("capture", 0.0)))


## Relay seam (GD-23): `minutes` of a held Relay Station (Commander side).
func relay_held(player: int, minutes: float) -> void:
	if _def != null:
		ledger.credit(player, false, minutes * Def.num(_def.relay.get("hold_per_min", 0.0)))


## cost_ore + cost_ice of the finished structures of `team`.
func structure_value(team: int) -> int:
	var v: int = 0
	for s: int in _store.structures:
		if _store.team[s] == team and (_store.flags[s] & EntityStore.F_BUILDING) == 0:
			v += _cost(s)
	return v


## The match result as of now (04 s2.3 / 02 s17.1): active players in slot order, structure value per team.
func result(winner_team: int, tick: int) -> MatchResult:
	var r: MatchResult = MatchResult.new()
	r.winner_team = winner_team
	r.tick = tick
	var e: int = r.structure_value.resize(PlayerTable.TEAMS)
	assert(e == OK)
	for t: int in PlayerTable.TEAMS:
		r.structure_value[t] = structure_value(t)
	for p: int in PlayerTable.SLOTS:
		if _players.active[p] != 0:
			r.players.append(_row(p))
	return r


func write_state(buf: StreamPeerBuffer) -> void:
	ledger.write_state(buf)
	hits.write_state(buf)
	buf.put_var(_spend_paid)
	buf.put_32(_won)


func read_state(buf: StreamPeerBuffer) -> bool:
	if not ledger.read_state(buf) or not hits.read_state(buf) or buf.get_available_bytes() < 8:
		return false
	var sp: Variant = buf.get_var()
	if typeof(sp) != TYPE_PACKED_FLOAT64_ARRAY or StateIO.size_of(sp) != PlayerTable.SLOTS:
		return false
	_spend_paid = sp
	_won = buf.get_32()
	_mark = _events.list.size()
	_drains_seen = _events.drains
	return _won == 0 or _won == 1


func _row(p: int) -> PlayerResult:
	var row: PlayerResult = PlayerResult.new()
	row.slot = p
	row.team = _players.team[p]
	row.score_pilot = ledger.pilot[p]
	row.score_commander = ledger.commander[p]
	row.kills = ledger.kills[p]
	row.deaths = ledger.deaths[p]
	row.structures_built = ledger.structures_built[p]
	row.structures_destroyed = ledger.structures_destroyed[p]
	row.manual_landings = ledger.manual_landings[p]
	row.sorties = ledger.sorties[p]
	row.ore_mined = ledger.ore_mined[p]
	row.ore_spent = ledger.ore_spent[p]
	row.ice_delivered = ledger.ice_delivered[p]
	var e: int = row.pilot_time_s.resize(ScoreLedger.CLASS_COUNT)
	assert(e == OK)
	for c: int in ScoreLedger.CLASS_COUNT:
		row.pilot_time_s[c] = floori(float(ledger.pilot_ticks[p * ScoreLedger.CLASS_COUNT + c]) / float(maxi(_hz, 1)))
	return row


# --- event handlers ----------------------------------------------------------------------------------------------------

# True when an attacker entity `id` is alive, owned by an active player: its owner slot, else -1.
func _owner_of(id: int) -> int:
	if id == 0 or not _store.alive(id):
		return -1
	var o: int = _store.owner[EntityId.slot(id)]
	return o if o < PlayerTable.SLOTS and _players.active[o] != 0 else -1


# True when `id` is the entity its owner currently possesses.
func _pilot_side(id: int) -> bool:
	var o: int = _store.owner[EntityId.slot(id)]
	return o < PlayerTable.SLOTS and _players.possessed[o] == id


# HIT: enemy hits feed the assist window; hits on a finished enemy structure pay structure_damage.
func _on_hit(e: SimEvent) -> void:
	var o: int = _owner_of(e.b)
	if o < 0 or not _store.alive(e.a):
		return
	var v: int = EntityId.slot(e.a)
	if _store.team[v] == _store.team[EntityId.slot(e.b)] or _store.kind[v] == EntityStore.K_WRECK:
		return
	var by_pilot: bool = _pilot_side(e.b)
	hits.record(e.a, o, by_pilot, e.value, e.tick, _window_ticks)
	if _store.kind[v] == EntityStore.K_STRUCTURE and (_store.flags[v] & EntityStore.F_BUILDING) == 0:
		ledger.credit(o, by_pilot, e.value * _def.structure_damage_points_per_hp)


func _on_landing(e: SimEvent) -> void:
	var o: int = _owner_of(e.a)
	if o < 0 or e.extra.size() < 3:
		return
	var pts: float = landing_points(e.extra[0], e.extra[2])
	if pts > 0.0:
		ledger.manual_landings[o] += 1
		ledger.credit(o, true, pts)


func _on_possessed(e: SimEvent) -> void:
	if e.b >= 0 and e.b < PlayerTable.SLOTS and _store.alive(e.a) and _store.kind[EntityId.slot(e.a)] == EntityStore.K_SHIP:
		ledger.sorties[e.b] += 1


func _on_built(e: SimEvent) -> void:
	var o: int = _owner_of(e.a)
	if o >= 0:
		ledger.structures_built[o] += 1


func _on_salvage(e: SimEvent) -> void:
	var o: int = _owner_of(e.a)
	if o >= 0:
		ledger.credit(o, _pilot_side(e.a), e.value * _def.salvage_points_per_ore)


# A death in step 9: the victim's own tally, then the kill, structure or assist points of its credited killer.
func _on_death(s: int, t: int) -> void:
	var kind: int = _store.kind[s]
	if kind == EntityStore.K_WRECK:
		return
	var owner_v: int = _store.owner[s]
	if kind != EntityStore.K_STRUCTURE and owner_v < PlayerTable.SLOTS:
		ledger.deaths[owner_v] += 1
	var att: int = _store.attacker[s]
	var o: int = _owner_of(att)
	if o < 0 or t - _store.last_damage_tick[s] > _window_ticks or _store.team[EntityId.slot(att)] == _store.team[s]:
		return
	var value: float = _kill_value(s)
	if kind == EntityStore.K_STRUCTURE:
		if (_store.flags[s] & EntityStore.F_BUILDING) != 0:
			return
		ledger.structures_destroyed[o] += 1
	else:
		ledger.kills[o] += 1
	if value <= 0.0:
		return
	if _pilot_side(att):
		ledger.credit(o, true, value)
	else:
		ledger.credit(o, false, value * _def.commander_auto_kill_share)
	_assists(_store.id_of(s), o, value, t)


# Kill value of victim slot `s`: kill_points (+ the loaded Hauler bonus), (cost / 5) for a structure, core_destroyed.
func _kill_value(s: int) -> float:
	var d: int = _store.def_id[s]
	if _store.kind[s] == EntityStore.K_STRUCTURE:
		if d == _core:
			return float(_def.core_destroyed)
		return float(_cost(s)) * _def.structure_destroyed_ratio
	var v: float = float(_kill_pts[d])
	if d == _hauler and (_store.cargo[s] > 0.0 or (_store.flags[s] & EntityStore.F_TETHERED) != 0):
		v += float(_def.kill_hauler_loaded_bonus)
	return v


func _cost(s: int) -> int:
	var sd: StructureDef = _defs.resolved(_store.owner[s]).structure(_store.def_id[s])
	return sd.cost_ore + sd.cost_ice if sd != null else 0


# Every owner other than the killer's with >= min_share of the damage within the window earns kill_share of the value.
func _assists(victim_id: int, killer_owner: int, value: float, t: int) -> void:
	var sum: float = hits.shares(victim_id, t, _window_ticks, _total, _by_pilot)
	if sum <= 0.0:
		return
	var min_share: float = Def.num(_def.assist.get("min_share", 1.0))
	var pay: float = value * Def.num(_def.assist.get("kill_share", 0.0))
	for p: int in PlayerTable.SLOTS:
		if p != killer_owner and _total[p] > 0.0 and _total[p] / sum >= min_share:
			ledger.credit(p, _by_pilot[p] * 2.0 >= _total[p], pay)


func _listed_before(dying: PackedInt32Array, i: int) -> bool:
	for k: int in i:
		if dying[k] == dying[i]:
			return true
	return false
