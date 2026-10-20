class_name CommandIntake extends RefCounted
## The pending command queue of one world (sim/MODULE.md "Data owned", <= 256 per tick) and the single entry point
## of `SimWorld.apply_command` and `SimSink.submit` (S1, S10): validate, then queue for step 1 of the next `step()`;
## PILOT_INPUT alone is stored at once into the player's input slot. Serialized with the world (S4): commands
## accepted between two steps survive a save.

var pending: Array[Command] = []
var economy: EconomyHub = null   ## BUILD / CANCEL_BUILD / PRODUCE / CANCEL_PRODUCE go here (TA-19); set by SimWorld

var _validator: CommandValidator
var _applier: CommandApplier
var _state: MatchState


func _init(validator: CommandValidator, applier: CommandApplier, state: MatchState) -> void:
	_validator = validator
	_applier = applier
	_state = state


func submit(cmd: Command) -> CommandResult:
	var r: CommandResult = _validator.validate(cmd, _state.tick, _state.ended(), pending.size())
	if r.code == CommandResult.Code.ACCEPTED:
		if cmd.kind == Command.Kind.PILOT_INPUT:
			_applier.store_pilot(cmd)
		else:
			pending.append(cmd)
	return r


## The system path of `SimSink.submit` (TA-59): the ORDER is queued with `target` SYSTEM so step 1 stamps issuer -1;
## `player` stays the AI's slot (team check). The caller's command is not changed.
func submit_system(cmd: Command) -> CommandResult:
	var c: Command = Command.new()
	c.tick = cmd.tick
	c.player = cmd.player
	c.kind = cmd.kind
	c.target = CommandValidator.SYSTEM
	c.payload = cmd.payload
	var r: CommandResult = _validator.validate_system(c, _state.ended(), pending.size())
	if r.code == CommandResult.Code.ACCEPTED:
		pending.append(c)
	return r


## Step 1: applies every queued command in arrival order, then empties the queue.
func apply_all(tick: int) -> void:
	_validator.begin_tick()
	for cmd: Command in pending:
		if economy != null and EconomyHub.handles(cmd.kind):
			economy.apply(cmd)
		else:
			_applier.apply(cmd, tick)
	pending.clear()


func write_state(buf: StreamPeerBuffer) -> void:
	buf.put_32(pending.size())
	for c: Command in pending:
		buf.put_64(c.tick)
		buf.put_8(c.player)
		buf.put_8(c.kind)
		buf.put_64(c.target)
		buf.put_var(c.payload)


func read_state(buf: StreamPeerBuffer) -> bool:
	pending.clear()
	var n: int = buf.get_32()
	if n < 0 or n > CommandValidator.QUEUE_MAX:
		return false
	for _k: int in n:
		var c: Command = Command.new()
		c.tick = buf.get_64()
		c.player = buf.get_8()
		var kv: int = buf.get_8()
		if kv < 0 or kv > Command.Kind.DEBUG_SET:
			return false
		c.kind = kv as Command.Kind
		c.target = buf.get_64()
		var v: Variant = buf.get_var()
		if typeof(v) != TYPE_PACKED_BYTE_ARRAY:
			return false
		c.payload = v
		pending.append(c)
	return true
