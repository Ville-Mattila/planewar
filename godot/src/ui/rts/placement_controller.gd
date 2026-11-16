class_name PlacementController extends RefCounted
## Build placement glue (docs/06 s7.3): the PlacementMachine driven through an injected validator (`Build.can_place`,
## which `ui` cannot name), plus the BUILD command, toasts, the validity-flip haptic and the pending outline. The host
## (app) feeds the camera altitude, ghost moves and the `CommandResult`, submits `command_ready`, and draws the ghost.

signal command_ready(cmd: Command)
signal toast(key: StringName, args: Dictionary)
signal validity_flipped(valid: bool)
signal state_changed(state: PlacementMachine.State)

var machine: PlacementMachine = PlacementMachine.new()
var reject: int = PlacementRules.OK   ## the reason shown for the ghost now (highest priority); OK when valid

var _player: int = -1
var _validator: Callable = Callable()
var _client: PackedInt32Array = PackedInt32Array()
var _last_valid: int = -1             ## -1 unknown (the first evaluation is no flip), else 0 / 1
var _facts: Dictionary = {}


## `validator(def_index: int, cell: int, rotation: int) -> int` returns a `Build.Reject` ordinal.
func setup(player: int, validator: Callable) -> void:
	_player = player
	_validator = validator


func arm(id: StringName, ctx: DrawerContext) -> void:
	_client = PlacementRules.client_rejects(ctx, id)
	if ctx != null and (ctx.eliminated or not ctx.commander_rights):
		toast.emit(PlacementRules.key(PlacementRules.ELIMINATED), PlacementRules.args(PlacementRules.ELIMINATED, {}))
		return
	if machine.arm(id):
		_last_valid = -1
		state_changed.emit(machine.state)


func set_camera(alt_m: float, focus_cell: int) -> void:
	if machine.set_camera(alt_m, focus_cell):
		state_changed.emit(machine.state)
		_evaluate()


func move_to(cell: int) -> void:
	if machine.move_to(cell):
		_evaluate()


func rotate_by(dir: int) -> void:
	if machine.rotate_by(dir):
		_evaluate()


func set_repeat(on: bool) -> void:
	machine.repeat = on


## Facts the host measured for the reason text: "deg" (ghost slope), "need" (missing prerequisite def id).
func set_facts(facts: Dictionary) -> void:
	_facts = facts


## Funds, lock and rights changed (4 Hz drawer context): recompute the reason without moving the ghost.
func revalidate(ctx: DrawerContext) -> void:
	_client = PlacementRules.client_rejects(ctx, machine.def_id)
	if machine.state == PlacementMachine.State.POSITIONING:
		_evaluate()


func confirm() -> bool:
	if not machine.confirm(is_valid()):
		return false
	state_changed.emit(machine.state)
	command_ready.emit(Command.build(_player, ContentDB.def_index(machine.def_id), machine.cell, machine.rotation))
	return true


func cancel() -> void:
	if machine.cancel():
		state_changed.emit(machine.state)


## The BUILD `CommandResult`: accepted ends the placement (or keeps positioning with repeat), a rejection toasts its reason.
func on_result(r: CommandResult) -> void:
	var rj: int = PlacementRules.from_result(r.code, r.reject)
	if not machine.result(rj == PlacementRules.OK):
		return
	state_changed.emit(machine.state)
	if rj != PlacementRules.OK:
		toast.emit(PlacementRules.key(rj), PlacementRules.args(rj, _facts))
	else:
		_last_valid = -1
	if machine.state == PlacementMachine.State.POSITIONING:
		_evaluate()


func is_valid() -> bool:
	return machine.state == PlacementMachine.State.POSITIONING and reject == PlacementRules.OK


## The "pending" outline holds from CONFIRM until the CommandResult (hides one round trip).
func show_pending() -> bool:
	return machine.state == PlacementMachine.State.SENT


func reason_key() -> StringName:
	return PlacementRules.key(reject)


func reason_args(facts: Dictionary) -> Dictionary:
	return PlacementRules.args(reject, facts)


func _evaluate() -> void:
	var sim: int = PlacementRules.GENERIC
	if _validator.is_valid():
		var v: Variant = _validator.call(ContentDB.def_index(machine.def_id), machine.cell, machine.rotation)
		sim = v if v is int else PlacementRules.GENERIC
	var all: PackedInt32Array = _client.duplicate()
	var _a: bool = all.append(sim)
	reject = PlacementRules.top(all)
	if sim == PlacementRules.GENERIC and reject == PlacementRules.OK:
		reject = PlacementRules.GENERIC
	var valid: int = 1 if reject == PlacementRules.OK else 0
	if _last_valid >= 0 and valid != _last_valid:
		validity_flipped.emit(valid == 1)
	_last_valid = valid
