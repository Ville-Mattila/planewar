class_name MatchResult extends RefCounted
## The match result of 02 s17.1 / R0 C2-17 as `SimWorld.match_result()` reports it (04 s2.3 `MATCH_END` head and tails,
## the FleetManager result POST): the winner, the tick, one `PlayerResult` per active player in slot order and the final
## structure value per team. Plain data; encoding and `result_hash` belong to the server (NET-22).

var winner_team: int = -1                                              ## -1 = none decided
var tick: int = 0                                                      ## tick MATCH_END fired, or the last completed tick while running
var structure_value: PackedInt32Array = PackedInt32Array()             ## per team: cost_ore + cost_ice of its finished structures
var players: Array[PlayerResult] = []


## The result of `ledger` for the active players of `table`; `hz` converts pilot ticks to seconds.
static func build(ledger: ScoreLedger, table: PlayerTable, hz: int, winner: int, at_tick: int, value_by_team: PackedInt32Array) -> MatchResult:
	var r: MatchResult = MatchResult.new()
	r.winner_team = winner
	r.tick = at_tick
	r.structure_value = value_by_team
	for p: int in PlayerTable.SLOTS:
		if table.active[p] != 0:
			r.players.append(_row(ledger, table, hz, p))
	return r


static func _row(l: ScoreLedger, table: PlayerTable, hz: int, p: int) -> PlayerResult:
	var row: PlayerResult = PlayerResult.new()
	row.slot = p
	row.team = table.team[p]
	row.score_pilot = l.pilot[p]
	row.score_commander = l.commander[p]
	row.kills = l.kills[p]
	row.deaths = l.deaths[p]
	row.structures_built = l.structures_built[p]
	row.structures_destroyed = l.structures_destroyed[p]
	row.manual_landings = l.manual_landings[p]
	row.sorties = l.sorties[p]
	row.ore_mined = l.ore_mined[p]
	row.ore_spent = l.ore_spent[p]
	row.ice_delivered = l.ice_delivered[p]
	var e: int = row.pilot_time_s.resize(ScoreLedger.CLASS_COUNT)
	assert(e == OK)
	for c: int in ScoreLedger.CLASS_COUNT:
		row.pilot_time_s[c] = floori(float(l.pilot_ticks[p * ScoreLedger.CLASS_COUNT + c]) / float(maxi(hz, 1)))
	return row
