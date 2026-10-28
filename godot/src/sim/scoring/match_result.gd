class_name MatchResult extends RefCounted
## The match result of 02 s17.1 / R0 C2-17 as `SimWorld.match_result()` reports it (04 s2.3 `MATCH_END` head and tails,
## the FleetManager result POST): the winner, the tick, one `PlayerResult` per active player in slot order and the final
## structure value per team. Plain data; encoding and `result_hash` belong to the server (NET-22).

var winner_team: int = -1                                              ## -1 = none decided
var tick: int = 0                                                      ## tick MATCH_END fired, or the last completed tick while running
var structure_value: PackedInt32Array = PackedInt32Array()             ## per team: cost_ore + cost_ice of its finished structures
var players: Array[PlayerResult] = []
