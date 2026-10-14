class_name SimSink extends CommandSinkBase
## The sim's `CommandSinkBase` (05 s1.3): what `SimWorld` passes to `SimAiHook.on_tick`. `submit` goes through the
## same intake as `SimWorld.apply_command` (validated, rate-limited, applied in step 1 of the next tick); `drive`
## writes a main-range entity's input slot and refuses POSSESSED or dead entities (S11, R0 B.5 rule 2); `pathing`
## hands brains the world's Pathing (R0 B.11 A-55: request / status / result / release, advanced in step 3b).

var _intake: CommandIntake
var _store: EntityStore
var _inputs: InputSlots
var _pathing: Pathing


func _init(intake: CommandIntake, store: EntityStore, inputs: InputSlots, path: Pathing = null) -> void:
	_intake = intake
	_store = store
	_inputs = inputs
	_pathing = path


func submit(cmd: Command) -> CommandResult:
	return _intake.submit(cmd)


func drive(id: int, input: PilotInput) -> bool:
	var s: int = EntityId.slot(id)
	if s >= InputSlots.ENTITY_SLOTS or not _store.alive(id):
		return false
	if _store.control_state[s] == ControlMachine.State.POSSESSED:
		return false
	_inputs.set_entity(s, input)
	return true


func set_ai_tag(id: int, tag: int) -> void:
	if _store.alive(id):
		var s: int = EntityId.slot(id)
		_store.ai_tag[s] = tag & 0xFF
		_store.dirty[s] |= EntityStore.DIRTY_CONTROL


func pathing() -> Pathing:
	return _pathing
