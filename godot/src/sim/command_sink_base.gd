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


## Ends an AI-executed overlay (SAFETY / RECOVER_CEILING) in the replicated overlay byte of a live entity (TA-59);
## LINK_BRIDGE is the sim's own and is left alone. The base does nothing.
func end_overlay(_id: int) -> void:
	pass


## The world's Pathing (R0 B.11 A-55): `sim_ai`'s only route to request / status / result / release. A request is a
## write (it queues work that step 3b advances under the tick budget), hence the sink and not the read-only SimView.
## The base has none (null).
func pathing() -> Pathing:
	return null
