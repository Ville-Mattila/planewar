class_name ResultsData extends RefCounted
## The decoded `MATCH_END` of 06 s8 / R0 C2-17 as the Results screen binds it: winner team, end reason
## (`Protocol.MatchEndReason`), tick, `structure_value` per team and one ResultsRow per player.
## The host (app) builds the dictionary from the MATCH_END message; keys: winner_team, end_reason, tick,
## structure_value[], players[] (ResultsRow.from_dict keys).

var winner_team: int = -1
var end_reason: int = 0
var tick: int = 0
var structure_value: PackedInt32Array = PackedInt32Array()
var rows: Array[ResultsRow] = []


static func from_dict(d: Dictionary) -> ResultsData:
	var r: ResultsData = ResultsData.new()
	r.winner_team = ResultsRow._int(d, "winner_team") if d.has("winner_team") else -1
	r.end_reason = ResultsRow._int(d, "end_reason")
	r.tick = ResultsRow._int(d, "tick")
	r.structure_value = PackedInt32Array(ResultsRow._arr(d, "structure_value"))
	for p: Variant in ResultsRow._arr(d, "players"):
		if p is Dictionary:
			var pd: Dictionary = p
			r.rows.append(ResultsRow.from_dict(pd))
	return r


func team_ids() -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for row: ResultsRow in rows:
		if not out.has(row.team):
			var _a: bool = out.append(row.team)
	out.sort()
	return out


func value_of(team: int) -> int:
	return structure_value[team] if team >= 0 and team < structure_value.size() else 0
