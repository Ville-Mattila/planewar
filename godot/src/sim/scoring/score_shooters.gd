class_name ScoreShooters extends RefCounted
## Who a dead shooter was (GD-27 round 2): a bomb, rocket or shell can hit after its shooter died, and the HIT or the kill
## then names an EntityId that is no longer in the store. `ScoreKeeper.on_dying` records every dying entity here
## (EntityId with its generation, owner, team, whether its owner possessed it), so the shot still scores for the owner and
## a stale id of a reused slot matches nothing. A fixed ring, oldest overwritten; part of S4.

const CAP: int = 1024
const _STATE: PackedStringArray = ["id", "owner", "team", "pilot", "head", "count"]

var id: PackedInt32Array = PackedInt32Array()
var owner: PackedByteArray = PackedByteArray()
var team: PackedByteArray = PackedByteArray()
var pilot: PackedByteArray = PackedByteArray()
var head: int = 0      ## next write position
var count: int = 0


func _init() -> void:
	var e: int = id.resize(CAP) | owner.resize(CAP) | team.resize(CAP) | pilot.resize(CAP)
	assert(e == OK)
	id.fill(0)
	owner.fill(0)
	team.fill(0)
	pilot.fill(0)


func record(entity_id: int, by_owner: int, by_team: int, was_pilot: bool) -> void:
	id[head] = entity_id
	owner[head] = by_owner
	team[head] = by_team
	pilot[head] = 1 if was_pilot else 0
	head = (head + 1) % CAP
	count = mini(count + 1, CAP)


## Ring index of `entity_id`, newest first; -1 when unknown.
func find(entity_id: int) -> int:
	for k: int in count:
		var i: int = (head - 1 - k + CAP) % CAP
		if id[i] == entity_id:
			return i
	return -1


func write_state(buf: StreamPeerBuffer) -> void:
	StateIO.put_props(buf, self, _STATE)


func read_state(buf: StreamPeerBuffer) -> bool:
	if not StateIO.get_props(buf, self, _STATE) or not StateIO.sizes_ok(self, _STATE.slice(0, 4), CAP):
		return false
	return head >= 0 and head < CAP and count >= 0 and count <= CAP
