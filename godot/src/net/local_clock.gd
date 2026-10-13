class_name LocalClock extends RefCounted
## Virtual clock shared by a LocalTransport hub and its clients (04 s15.1): tests never sleep, they advance it.
## Time is milliseconds; the tick is derived at 30 Hz.

var _ms: float = 0.0
var _tick: int = 0


func now_ms() -> float:
	return _ms


func tick() -> int:
	return _tick


func advance_tick() -> void:
	_tick += 1
	_ms = FaultModel.tick_to_ms(_tick)


func advance_ms(ms: float) -> void:
	_ms += ms
	_tick = floori(_ms * float(FaultModel.TICK_HZ) / 1000.0)
