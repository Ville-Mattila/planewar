class_name PerfVision
extends Node
## Vision component benchmark (TA-37; 03 s4.2 row "11 Vision" 1.1 ms p95). The perf_tick S-SIM-1 scene
## (PerfTickWorld: 400 ships, 200 ground, 480 structures, 120 wrecks on s_world1, 8 teams) is stepped untimed;
## then, per tick, Vision's parts are timed on the same state: the bucket index and every team's pass.
## godot --headless --path godot res://test/perf/perf_vision.tscn [-- --ticks=300 --flat]
## Prints PERF_VISION lines (p50 / p95 / max us): the index once per tick, one team's pass (sense + list), and
## `tick_10hz` = index + the passes the 10 Hz stagger schedules (3 or 2 teams; the default profile [1, 2] runs 5 Hz,
## 2 or 1 teams). The vision row of perf_tick --full is the in-tick figure perf notes cite. Report only; no gate.

const WARMUP: int = 60


func _ready() -> void:
	var ticks: int = 300
	var map_id: StringName = &"s_world1_r6000"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--ticks="):
			ticks = int(arg.substr(8))
		elif arg == "--flat":
			map_id = &""
	var pw: PerfTickWorld = PerfTickWorld.new(400, 200, 480, 120, 0, map_id)
	var w: SimWorld = pw.world
	for _i: int in WARMUP:
		w.step()
		var _e: Array[SimEvent] = w.drain_events()
	var v: Vision = w.vision
	var idx: PackedInt32Array = PackedInt32Array()
	var passes: PackedInt32Array = PackedInt32Array()
	var tick_us: PackedInt32Array = PackedInt32Array()
	var p: int = v.period(PackedInt32Array())   # 10 Hz: the rate the 1.1 ms row is budgeted at
	for _i: int in ticks:
		w.step()
		var _e: Array[SimEvent] = w.drain_events()
		var t0: int = Time.get_ticks_usec()
		v.grid.index(w.store())
		var scheduled: int = Time.get_ticks_usec() - t0
		var _a: bool = idx.push_back(scheduled)
		for t: int in Vision.TEAMS:
			var s0: int = Time.get_ticks_usec()
			v.pass_team(t, w.tick())
			var d: int = Time.get_ticks_usec() - s0
			var _b: bool = passes.push_back(d)
			if MathX.posmod_i(w.tick(), p) == t % p:
				scheduled += d
		var _d: bool = tick_us.push_back(scheduled)
	_print("index", idx)
	_print("pass_per_team", passes)
	_print("tick_10hz", tick_us)
	get_tree().quit(0)


func _print(name: String, a: PackedInt32Array) -> void:
	a.sort()
	var n: int = a.size()
	print("PERF_VISION part=%s n=%d p50_us=%d p95_us=%d max_us=%d" % [name, n, a[floori(float(n) * 0.5)],
		a[int(float(n) * 0.95)], a[n - 1]])
