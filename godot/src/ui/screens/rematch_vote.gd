class_name RematchVote extends RefCounted
## REMATCH_VOTE of the Results screen (06 s8): `rematch_vote_s` window, one yes/no per eligible human slot.
## Unanimous yes = PASSED; any no, or the window ending without unanimity = FAILED. DISABLED when the mode has no rematch.

enum Status { DISABLED, PENDING, PASSED, FAILED }
enum Vote { NONE, YES, NO }

var status: Status = Status.DISABLED
var left_s: float = 0.0
var _votes: Dictionary[int, Vote] = {}


func open(eligible: PackedInt32Array, allowed: bool) -> void:
	_votes.clear()
	if not allowed or eligible.is_empty():
		status = Status.DISABLED
		left_s = 0.0
		return
	for slot: int in eligible:
		_votes[slot] = Vote.NONE
	status = Status.PENDING
	left_s = ScreenParams.param("rematch_vote_s")


## False when the slot is not eligible or the vote is closed.
func cast(slot: int, yes: bool) -> bool:
	if status != Status.PENDING or not _votes.has(slot):
		return false
	_votes[slot] = Vote.YES if yes else Vote.NO
	_resolve()
	return true


func tick(dt: float) -> void:
	if status != Status.PENDING:
		return
	left_s = maxf(left_s - maxf(dt, 0.0), 0.0)
	if left_s <= 0.0:
		status = Status.FAILED


func vote_of(slot: int) -> Vote:
	return _votes.get(slot, Vote.NONE)


func yes_count() -> int:
	var n: int = 0
	for slot: int in _votes:
		if _votes[slot] == Vote.YES:
			n += 1
	return n


func eligible_count() -> int:
	return _votes.size()


func _resolve() -> void:
	var yes: int = 0
	for slot: int in _votes:
		if _votes[slot] == Vote.NO:
			status = Status.FAILED
			return
		if _votes[slot] == Vote.YES:
			yes += 1
	if yes == _votes.size():
		status = Status.PASSED
