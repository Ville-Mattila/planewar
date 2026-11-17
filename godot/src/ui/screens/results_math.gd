class_name ResultsMath extends RefCounted
## Pure Results-screen logic (06 s8; UX-27): outcome state, row order, table cells, medal and pilot-time text.

enum Outcome { VICTORY, DEFEAT, TIME_LIMIT }

const COLUMNS: PackedStringArray = [
	"name", "score_pilot", "score_commander", "kills", "manual_landings", "structures_destroyed", "sorties",
	"ore_mined", "ore_spent", "ice_delivered",
]


## TIME_LIMIT is the mode's `hard_end_s` (HARD_END_VALUE); otherwise the winner team decides.
static func outcome(winner_team: int, end_reason: int, local_team: int) -> Outcome:
	if end_reason == Protocol.MatchEndReason.HARD_END_VALUE:
		return Outcome.TIME_LIMIT
	return Outcome.VICTORY if winner_team == local_team and local_team >= 0 else Outcome.DEFEAT


static func local_won(winner_team: int, local_team: int) -> bool:
	return local_team >= 0 and winner_team == local_team


## Locale key of the reason line (surrender, hard end, Cores destroyed, abandoned, admin).
static func reason_key(end_reason: int) -> StringName:
	match end_reason:
		Protocol.MatchEndReason.HARD_END_VALUE:
			return &"ui.results.reason.hard_end"
		Protocol.MatchEndReason.SURRENDER:
			return &"ui.results.reason.surrender"
		Protocol.MatchEndReason.ABANDONED:
			return &"ui.results.reason.abandoned"
		Protocol.MatchEndReason.ADMIN:
			return &"ui.results.reason.admin"
	return &"ui.results.reason.cores"


static func total_score(row: ResultsRow) -> int:
	return row.score_pilot + row.score_commander


## Team ascending, then total score descending, then slot.
static func sorted_rows(rows: Array[ResultsRow]) -> Array[ResultsRow]:
	var out: Array[ResultsRow] = rows.duplicate()
	out.sort_custom(func(a: ResultsRow, b: ResultsRow) -> bool:
		if a.team != b.team:
			return a.team < b.team
		var ta: int = total_score(a)
		var tb: int = total_score(b)
		return ta > tb if ta != tb else a.slot < b.slot)
	return out


## Table cells in COLUMNS order, numbers grouped per locale (Fmt).
static func cells(row: ResultsRow, locale: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray([row.player_name])
	for n: int in [row.score_pilot, row.score_commander, row.kills, row.manual_landings, row.structures_destroyed,
			row.sorties, row.ore_mined, row.ore_spent, row.ice_delivered]:
		out += PackedStringArray([Fmt.integer(n, locale)])
	return out


## Earned medals as ids; `order` is the `medals.json` id list (wire index = array index).
static func medal_ids(row: ResultsRow, order: PackedStringArray) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for i: int in mini(row.medals.size(), order.size()):
		if row.medals[i] != 0:
			out += PackedStringArray([order[i]])
	return out


## Pilot time per class as "dart 1:05" pairs (class id, clock); zero classes are skipped.
static func pilot_times(row: ResultsRow) -> Array[PackedStringArray]:
	var out: Array[PackedStringArray] = []
	for c: int in ResultsRow.CLASS_IDS.size():
		var s: int = row.pilot_time_s[c] if c < row.pilot_time_s.size() else 0
		if s > 0:
			out.append(PackedStringArray([ResultsRow.CLASS_IDS[c], Fmt.duration(s)]))
	return out
