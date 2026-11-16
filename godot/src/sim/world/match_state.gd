class_name MatchState extends RefCounted
## The world clock and match-level state shared by `SimWorld` (writer), `CommandIntake` and `LocalSimView`
## (readers), so no reader holds the world itself (no reference cycles). Serialized with the world (S4). GD-20: the
## `MatchJudge`'s state lives here too (packed members, so the judge and the S4 bytes share one owner).

const _STATE: PackedStringArray = ["tick", "exposure_tick", "ended_tick", "winner_team", "had_core", "selfdestruct", "votes",
	"defeated", "structure_damage", "end_reason"]

var tick: int = 0             ## tick of the last completed step (0 after load_map)
var exposure_tick: int = -1   ## tick the CORE_EXPOSURE event fired, -1 before
var ended_tick: int = -1      ## tick the MATCH_END event fired, -1 while running
var winner_team: int = -1     ## -1 = none decided (a draw, or still running)
var had_core: PackedByteArray = PackedByteArray()          ## per player slot: 1 once a Core of the player was seen
var selfdestruct: PackedInt32Array = PackedInt32Array()    ## per player slot: tick its structures are due, -1 none
var votes: PackedByteArray = PackedByteArray()             ## per player slot: 1 after a counted SURRENDER vote
var defeated: PackedByteArray = PackedByteArray()          ## per team: 1 once it lost its last Core or surrendered
var structure_damage: PackedFloat32Array = PackedFloat32Array()   ## per team: damage dealt to finished enemy structures
var end_reason: int = -1      ## MatchJudge.EndReason once ended, else -1


func _init() -> void:
	var e: int = had_core.resize(PlayerTable.SLOTS) | selfdestruct.resize(PlayerTable.SLOTS) | votes.resize(PlayerTable.SLOTS)
	e |= defeated.resize(PlayerTable.TEAMS) | structure_damage.resize(PlayerTable.TEAMS)
	assert(e == OK)
	had_core.fill(0)
	selfdestruct.fill(-1)
	votes.fill(0)
	defeated.fill(0)
	structure_damage.fill(0.0)


func ended() -> bool:
	return ended_tick >= 0


func write_state(buf: StreamPeerBuffer) -> void:
	StateIO.put_props(buf, self, _STATE)


func read_state(buf: StreamPeerBuffer) -> bool:
	return StateIO.get_props(buf, self, _STATE) and tick >= 0 and exposure_tick >= -1 and ended_tick >= -1 \
			and winner_team >= -1 and winner_team < PlayerTable.TEAMS and end_reason >= -1 \
			and StateIO.size_of(had_core) == PlayerTable.SLOTS and StateIO.size_of(selfdestruct) == PlayerTable.SLOTS \
			and StateIO.size_of(votes) == PlayerTable.SLOTS and StateIO.size_of(defeated) == PlayerTable.TEAMS \
			and StateIO.size_of(structure_damage) == PlayerTable.TEAMS
