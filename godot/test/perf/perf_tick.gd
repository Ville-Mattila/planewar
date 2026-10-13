class_name PerfTick
extends Node
## Same-job A/B benchmark (03 s12.1, R0 C1-11). Stub until TA-22 promotes the real S-SIM-1 scenario.
## godot --headless --path godot res://test/perf/perf_tick.tscn -- --ticks=3600
## Prints one line: PERF_TICK p50_us=.. p95_us=.. p99_us=.. max_us=.. mean_us=..

const WARMUP_TICKS: int = 300
const STEP_DT: float = 1.0 / 30.0


func _ready() -> void:
	var ticks: int = 3600
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--ticks="):
			ticks = int(arg.substr(8))
	var world: SoakWorldStub = SoakWorldStub.new(77)
	var samples: PackedInt32Array = PackedInt32Array()
	var _r1: int = samples.resize(ticks)
	for i: int in WARMUP_TICKS:
		world.step(STEP_DT)
	var total: int = 0
	for i: int in ticks:
		var t0: int = Time.get_ticks_usec()
		world.step(STEP_DT)
		var dt: int = Time.get_ticks_usec() - t0
		samples[i] = dt
		total += dt
	samples.sort()
	print("PERF_TICK p50_us=%d p95_us=%d p99_us=%d max_us=%d mean_us=%d" % [
		samples[floori(float(ticks) * 0.5)], samples[int(float(ticks) * 0.95)],
		samples[int(float(ticks) * 0.99)], samples[ticks - 1], floori(float(total) / float(ticks))])
	get_tree().quit(0)
