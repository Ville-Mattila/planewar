class_name PlacementMachine extends RefCounted
## The build placement state machine of docs/06 s7.3 (IDLE, ARMED, POSITIONING, SENT). Pure: the caller feeds the
## camera altitude, ghost moves, validity and the command verdict; every method returns whether the state changed.

enum State { IDLE, ARMED, POSITIONING, SENT }

var state: State = State.IDLE
var def_id: StringName = &""
var cell: int = -1
var rotation: int = 0
var repeat: bool = false   ## the "repeat" toggle: stay in POSITIONING after an accepted placement


func is_active() -> bool:
	return state != State.IDLE


## BUILD_ARM from a drawer tile; re-arming replaces the def. Not while a command is in flight.
func arm(id: StringName) -> bool:
	if state == State.SENT or id == &"":
		return false
	def_id = id
	cell = -1
	rotation = 0
	state = State.ARMED
	return true


## ARMED becomes POSITIONING once the camera is at `placement.json arm_alt_m` or lower; the ghost starts at `focus_cell`.
func set_camera(alt_m: float, focus_cell: int) -> bool:
	if state != State.ARMED or alt_m > PlacementRules.arm_alt_m():
		return false
	cell = focus_cell
	state = State.POSITIONING
	return true


## BUILD_MOVE.
func move_to(new_cell: int) -> bool:
	if state != State.POSITIONING or new_cell == cell:
		return false
	cell = new_cell
	return true


## BUILD_ROTATE by quarter turns (+1 clockwise); wraps over `rotations`.
func rotate_by(dir: int) -> bool:
	if state != State.POSITIONING or dir == 0:
		return false
	rotation = posmod(rotation + dir, PlacementRules.rotations())
	return true


## BUILD_CONFIRM: only a valid ghost is sent.
func confirm(valid: bool) -> bool:
	if state != State.POSITIONING or not valid:
		return false
	state = State.SENT
	return true


## The CommandResult: accepted -> IDLE (POSITIONING with `repeat`), rejected -> POSITIONING.
func result(accepted: bool) -> bool:
	if state != State.SENT:
		return false
	state = State.POSITIONING if (repeat or not accepted) else State.IDLE
	return true


## BUILD_CANCEL; ignored while a command is in flight.
func cancel() -> bool:
	if state != State.ARMED and state != State.POSITIONING:
		return false
	state = State.IDLE
	return true
