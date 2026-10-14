class_name BenchSerialize
extends Node
## TA-21 benchmark: SimWorld.serialize / deserialize time and bytes at the S-SIM-1 (--full) scale (400 ships, 200 ground,
## 480 structures, 120 wrecks = 1,200 entities, 2,000 projectiles) after a warm-up, with the section report.
## godot --headless --path godot res://test/perf/bench_serialize.tscn -- [--warm=300] [--rounds=10]
## Prints BENCH_SERIALIZE bytes=.. (file) raw_bytes=.. ser_ms=.. de_ms=.. and one BENCH_SECTION line per section (03 s4.4 row 1 is not
## affected: save/load runs between ticks, never inside step()).


func _ready() -> void:
	var warm: int = 300
	var rounds: int = 10
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--warm="):
			warm = int(arg.substr(7))
		elif arg.begins_with("--rounds="):
			rounds = int(arg.substr(9))
	var pw: PerfTickWorld = PerfTickWorld.new(400, 200, 480, 120, 2000, &"s_world1_r6000")
	var w: SimWorld = pw.world
	for _i: int in warm:
		w.step()
		var _e: Array[SimEvent] = w.drain_events()
		pw.top_up()
	var best_s: int = 1 << 40
	var best_d: int = 1 << 40
	var bytes: PackedByteArray = PackedByteArray()
	for _r: int in rounds:
		var t0: int = Time.get_ticks_usec()
		bytes = w.serialize()
		var t1: int = Time.get_ticks_usec()
		var b: SimWorld = SimWorld.deserialize(bytes, WorldTestKit.content(), null)
		var t2: int = Time.get_ticks_usec()
		assert(b != null)
		best_s = mini(best_s, t1 - t0)
		best_d = mini(best_d, t2 - t1)
	print("BENCH_SERIALIZE bytes=%d raw_bytes=%d ser_ms=%.2f de_ms=%.2f live_entities=%d live_projectiles=%d" % [bytes.size(), SimSerialize.unpack(bytes).size(),
		float(best_s) / 1000.0, float(best_d) / 1000.0, w.store().live_count(), w.projectiles().live_count()])
	var names: PackedStringArray = SimSerialize.SECTIONS
	var sizes: PackedInt32Array = SimSerialize.size_report(w)
	for k: int in names.size():
		print("BENCH_SECTION %s=%d" % [names[k], sizes[k]])
	get_tree().quit(0)
