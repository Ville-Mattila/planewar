class_name CommandSink extends CommandSinkBase
## The AI's handle on the world (05 s1.3, R0 C2-04): brains and the Commander take a `CommandSink`, `AiDriver` binds it
## each tick to the `CommandSinkBase` that `SimWorld` passes to `SimAiHook.on_tick` (the sim's `SimSink`). Every call
## forwards unchanged, so validation, rate limits and the POSSESSED / dead refusal (S11) stay the sim's; this class only
## counts, for `AiDriver.stats()` and perf tests. Unbound it behaves like the base: refuses everything. No allocation.

var _inner: CommandSinkBase = null
var submits: int = 0         ## calls to `submit` since `reset_counters`
var drives: int = 0          ## calls to `drive`
var drives_refused: int = 0  ## `drive` calls that returned false (POSSESSED or dead target)
var tags: int = 0            ## calls to `set_ai_tag`


## Binds the sink to forward to; null unbinds.
func bind(inner: CommandSinkBase) -> void:
	_inner = inner


func is_bound() -> bool:
	return _inner != null


func reset_counters() -> void:
	submits = 0
	drives = 0
	drives_refused = 0
	tags = 0


func submit(cmd: Command) -> CommandResult:
	submits += 1
	if _inner == null:
		return super.submit(cmd)
	return _inner.submit(cmd)


func drive(id: int, input: PilotInput) -> bool:
	drives += 1
	var ok: bool = _inner != null and _inner.drive(id, input)
	if not ok:
		drives_refused += 1
	return ok


func set_ai_tag(id: int, tag: int) -> void:
	tags += 1
	if _inner != null:
		_inner.set_ai_tag(id, tag)


func end_overlay(id: int) -> void:
	if _inner != null:
		_inner.end_overlay(id)


func pathing() -> Pathing:
	return _inner.pathing() if _inner != null else null
