class_name CommandSinkBase extends RefCounted
## Abstract command sink (05 s1.3): `SimWorld` passes its implementation (`SimSink`) to `SimAiHook.on_tick`;
## campaign's `MissionRuntime` receives one. The base refuses everything.


## Submits a command as if through `SimWorld.apply_command` (queued, validated, rate-limited).
func submit(_cmd: Command) -> CommandResult:
	var r: CommandResult = CommandResult.new()
	r.code = CommandResult.Code.REJECTED_NO_RIGHTS
	return r


## Writes `input` into the entity's input slot; false if the entity is POSSESSED or dead (S11).
func drive(_id: int, _input: PilotInput) -> bool:
	return false


## Writes the replicated `ai_tag` u8 of a live entity.
func set_ai_tag(_id: int, _tag: int) -> void:
	pass
