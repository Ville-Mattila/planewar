extends Node
## Autoload `Log`. No class_name: it would hide the autoload singleton (CLAUDE.md, ADR-14).
## Public shape per 03 s2. With no sink set, lines go to print(); tests and the server
## install a sink with set_sink() to capture (level, tag, msg).

enum Level { DEBUG, INFO, WARN, ERROR }

## Debug lines are compiled out of release builds by setting this to false.
const DEBUG: bool = true

var _level: int = Level.INFO
var _sink: Callable = Callable()


func debug(tag: StringName, msg: String) -> void:
	if DEBUG:
		_emit(Level.DEBUG, tag, msg)


func info(tag: StringName, msg: String) -> void:
	_emit(Level.INFO, tag, msg)


func warn(tag: StringName, msg: String) -> void:
	_emit(Level.WARN, tag, msg)


func error(tag: StringName, msg: String) -> void:
	_emit(Level.ERROR, tag, msg)


func set_level(level: int) -> void:
	_level = level


## Pass an invalid Callable (Callable()) to restore printing.
func set_sink(cb: Callable) -> void:
	_sink = cb


func _emit(level: int, tag: StringName, msg: String) -> void:
	if level < _level:
		return
	if _sink.is_valid():
		var _r: Variant = _sink.call(level, tag, msg)
		return
	print("[%s] %s: %s" % [Level.keys()[level], tag, msg])
