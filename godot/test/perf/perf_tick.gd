class_name PerfTick
extends Node
## SimWorld.step() benchmark with the 03 s4.4 per-row split (TA-18). Scenario: perf_tick_world.gd.
## godot --headless --path godot res://test/perf/perf_tick.tscn -- [--ticks=3600] [--full] [--flat]
##   default : A/B scale (flat datum, 24 ships, 8 ground, 16 structures, 4 wrecks, 60 projectiles) so the
##             same-job A/B of ab_perf.py (7 rounds x 2 sides, 10 noise repeats) stays inside its job timeout;
##   --full  : S-SIM-1 scale on s_world1 (400 ships, 200 ground, 480 structures, 120 wrecks = 1,200 entities,
##             2,000 projectiles), the scale every perf note cites (03 s4.2 rows); --flat drops the map.
## Prints PERF_ROW lines (p50/p95/p99/max ms per 03 s4.4 row, rows 1-13) and one PERF_TICK line (whole step,
## microseconds; the line ab_perf.py parses). A tree without perf_tick_world.gd (an A/B base older than TA-18)
## falls back to the S-CI-1 SoakWorldStub so the harness still prints PERF_TICK.

const WARMUP_TICKS: int = 300
const STEP_DT: float = 1.0 / 30.0
const WORLD_SCRIPT: String = "res://test/perf/perf_tick_world.gd"
const ROW_NAMES: PackedStringArray = ["transport", "commands_inputs", "ai_assist", "pathing", "kinematics",
	"projectiles", "spatial", "collision", "terrain_8b", "combat", "economy", "vision", "events", "total"]


func _ready() -> void:
	var ticks: int = 3600
	var full: bool = false
	var flat: bool = false
	var stub: bool = false
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--ticks="):
			ticks = int(arg.substr(8))
		elif arg == "--full":
			full = true
		elif arg == "--flat":
			flat = true
		elif arg == "--stub":
			stub = true
	if ResourceLoader.exists(WORLD_SCRIPT) and not stub:
		_run_sim(ticks, full, flat)
	else:
		_run_stub(ticks)
	get_tree().quit(0)


func _run_sim(ticks: int, full: bool, flat: bool) -> void:
	var script: GDScript = load(WORLD_SCRIPT)
	var map_id: StringName = &"" if flat or not full else &"s_world1_r6000"
	var pw: Variant
	if full:
		pw = script.new(400, 200, 480, 120, 2000, map_id)
	else:
		pw = script.new(24, 8, 16, 4, 60, map_id)
	var w: Variant = pw.world
	for _i: int in WARMUP_TICKS:
		w.step()
		w.drain_events()
		pw.top_up()
	var rows: PackedFloat32Array = PackedFloat32Array()   # row r, tick i at r * ticks + i (no packed array in an Array)
	rows.resize(ROW_NAMES.size() * ticks)
	var samples: PackedInt32Array = PackedInt32Array()
	samples.resize(ticks)
	var total: int = 0
	var live_p: int = 0
	for i: int in ticks:
		var t0: int = Time.get_ticks_usec()
		w.step()
		var dt: int = Time.get_ticks_usec() - t0
		samples[i] = dt
		total += dt
		var prof: PackedFloat32Array = w.profile()
		for r: int in ROW_NAMES.size():
			rows[r * ticks + i] = prof[r]
		live_p += w.projectiles().live_count()
		w.drain_events()
		pw.top_up()
	var st: Variant = w.store()
	print("PERF_SCENE scale=%s map=%s ticks=%d entities=%d ships=%d projectiles_mean=%d" % ["full" if full else "ab",
		map_id if map_id != &"" else "flat", ticks, st.live_count(), st.ships.size(), live_p / ticks])
	for r: int in range(1, ROW_NAMES.size()):
		var a: PackedFloat32Array = rows.slice(r * ticks, (r + 1) * ticks)
		a.sort()
		print("PERF_ROW row=%s p50_ms=%.3f p95_ms=%.3f p99_ms=%.3f max_ms=%.3f" % [ROW_NAMES[r], a[ticks / 2],
			a[int(float(ticks) * 0.95)], a[int(float(ticks) * 0.99)], a[ticks - 1]])
	_print_tick(samples, total, ticks)


func _run_stub(ticks: int) -> void:
	var stub: SoakWorldStub = SoakWorldStub.new(77)
	for _i: int in WARMUP_TICKS:
		stub.step(STEP_DT)
	var samples: PackedInt32Array = PackedInt32Array()
	samples.resize(ticks)
	var total: int = 0
	for i: int in ticks:
		var t0: int = Time.get_ticks_usec()
		stub.step(STEP_DT)
		var dt: int = Time.get_ticks_usec() - t0
		samples[i] = dt
		total += dt
	print("PERF_SCENE scale=stub")
	_print_tick(samples, total, ticks)


func _print_tick(samples: PackedInt32Array, total: int, ticks: int) -> void:
	samples.sort()
	print("PERF_TICK p50_us=%d p95_us=%d p99_us=%d max_us=%d mean_us=%d" % [
		samples[floori(float(ticks) * 0.5)], samples[int(float(ticks) * 0.95)],
		samples[int(float(ticks) * 0.99)], samples[ticks - 1], floori(float(total) / float(ticks))])
