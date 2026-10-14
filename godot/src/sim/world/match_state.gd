class_name MatchState extends RefCounted
## The world clock and match-level state shared by `SimWorld` (writer), `CommandIntake` and `LocalSimView`
## (readers), so no reader holds the world itself (no reference cycles). Serialized with the world (S4).

const _STATE: PackedStringArray = ["tick", "exposure_tick", "ended_tick", "winner_team"]

var tick: int = 0             ## tick of the last completed step (0 after load_map)
var exposure_tick: int = -1   ## tick the CORE_EXPOSURE event fired, -1 before
var ended_tick: int = -1      ## tick the MATCH_END event fired, -1 while running
var winner_team: int = -1     ## -1 = none decided (hard end before Economy scores structure value)


func ended() -> bool:
	return ended_tick >= 0


func write_state(buf: StreamPeerBuffer) -> void:
	StateIO.put_props(buf, self, _STATE)


func read_state(buf: StreamPeerBuffer) -> bool:
	return StateIO.get_props(buf, self, _STATE) and tick >= 0 and exposure_tick >= -1 and ended_tick >= -1 and winner_team >= -1 and winner_team < PlayerTable.TEAMS
