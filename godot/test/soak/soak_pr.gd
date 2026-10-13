class_name SoakPr
extends Node
## S-CI-1 soak (03 s14.5, R0 C1-11): steps SoakWorldStub at 30 Hz and prints, per sim-minute
## (1800 ticks), the p95 of step cost and the p95 of wall time between ticks, in microseconds.
## .github/scripts/soak_slope.py turns the SOAK_MINUTE lines into the slope of the per-minute p95.
##
## godot --headless --path godot --fixed-fps 30 res://test/soak/soak_pr.tscn -- --minutes=10 --pace=realtime
##   --pace=fast      no waiting; the engine loop runs as fast as it can (local smoke).
##   --pace=realtime  one tick per 33.3 ms of wall time, so 10 sim-minutes take 10 wall minutes
##                    (the mode that can reproduce the R2 s10.6 "slows after 25-55 s" report).

const TICKS_PER_MINUTE: int = 1800
const TICK_USEC: int = 33333
const STEP_DT: float = 1.0 / 30.0

var _world: SoakWorldStub
var _minutes_total: int = 10
var _realtime: bool = false
var _tick: int = 0
var _step_us: PackedInt32Array = PackedInt32Array()
var _gap_us: PackedInt32Array = PackedInt32Array()
var _last_tick_start: int = 0
var _next_due: int = 0


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--minutes="):
			_minutes_total = int(arg.substr(10))
		elif arg == "--pace=realtime":
			_realtime = true
	_world = SoakWorldStub.new(20260101)
	var _r1: int = _step_us.resize(TICKS_PER_MINUTE)
	var _r2: int = _gap_us.resize(TICKS_PER_MINUTE)
	_last_tick_start = Time.get_ticks_usec()
	_next_due = _last_tick_start
	print("SOAK_START minutes=%d pace=%s fixed_fps=%d entities=%d" % [
		_minutes_total, "realtime" if _realtime else "fast", Engine.physics_ticks_per_second,
		SoakWorldStub.ENTITY_COUNT])


func _process(_delta: float) -> void:
	if _realtime:
		var now: int = Time.get_ticks_usec()
		if now < _next_due:
			OS.delay_usec(_next_due - now)
		_next_due += TICK_USEC
	var t0: int = Time.get_ticks_usec()
	var slot: int = _tick % TICKS_PER_MINUTE
	_gap_us[slot] = t0 - _last_tick_start
	_last_tick_start = t0
	_world.step(STEP_DT)
	_step_us[slot] = Time.get_ticks_usec() - t0
	_tick += 1
	if _tick % TICKS_PER_MINUTE == 0:
		var minute: int = floori(float(_tick) / float(TICKS_PER_MINUTE))
		_report_minute(minute)
		if minute >= _minutes_total:
			print("SOAK_END ticks=%d checksum=%.6f" % [_tick, _world.checksum()])
			get_tree().quit(0)


func _report_minute(minute: int) -> void:
	print("SOAK_MINUTE %d step_p95_us=%d step_p50_us=%d gap_p95_us=%d" % [
		minute, _percentile(_step_us, 0.95), _percentile(_step_us, 0.5),
		_percentile(_gap_us, 0.95)])


func _percentile(values: PackedInt32Array, q: float) -> int:
	var sorted: PackedInt32Array = values.duplicate()
	sorted.sort()
	return sorted[mini(int(float(sorted.size()) * q), sorted.size() - 1)]
