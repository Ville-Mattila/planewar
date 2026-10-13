class_name PerfTerrain
extends SceneTree
## sim/terrain.gd micro-benchmarks against 03 s6.2 / TA-13: height_at <= 2 us per call (03 s4.2 collision and
## ship-vs-terrain rows). godot --headless --path godot -s res://test/perf/perf_terrain.gd [-- --iters=300000 --strict]
## Prints one PERF_TERRAIN line per function (loop overhead subtracted) and the load time of each map.

const BUDGET_US: Dictionary[StringName, float] = {&"height_at": 2.0, &"normal_at": 8.0, &"biome_at": 1.5}
const DIR_POOL: int = 1024
const MAPS: PackedStringArray = ["res://content/maps/tiny_test", "res://content/maps/s_world1_r6000"]


func _initialize() -> void:
	var iters: int = 300000
	var strict: bool = false
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--iters="):
			iters = int(arg.substr(8))
		elif arg == "--strict":
			strict = true
	var dirs: PackedVector3Array = PackedVector3Array()
	var _r: int = dirs.resize(DIR_POOL)
	for k: int in DIR_POOL:
		var t: float = float(k + 1)
		dirs[k] = Vector3(sin(t * 12.9898), sin(t * 78.233), sin(t * 37.719)).normalized()
	var over: int = 0
	for map_dir: String in MAPS:
		var terrain: Terrain = Terrain.new()
		var t0: int = Time.get_ticks_usec()
		var err: Error = terrain.load_map(map_dir)
		print("PERF_TERRAIN map=%s err=%d load_ms=%.2f" % [map_dir.get_file(), err, float(Time.get_ticks_usec() - t0) / 1000.0])
		var base: float = _bench_empty(dirs, iters)
		over += _report(&"height_at", _bench_height(terrain, dirs, iters) - base, strict)
		over += _report(&"normal_at", _bench_normal(terrain, dirs, iters / 8) - base, strict)
		over += _report(&"biome_at", _bench_biome(terrain, dirs, iters) - base, strict)
	quit(1 if over > 0 else 0)


func _report(fn: StringName, us: float, strict: bool) -> int:
	var budget: float = BUDGET_US[fn]
	print("PERF_TERRAIN fn=%s us=%.3f budget_us=%.1f %s" % [fn, us, budget, "ok" if us <= budget else "OVER"])
	return 1 if strict and us > budget else 0


func _bench_empty(dirs: PackedVector3Array, iters: int) -> float:
	var acc: float = 0.0
	var t0: int = Time.get_ticks_usec()
	for k: int in iters:
		acc += dirs[k & (DIR_POOL - 1)].x
	return _per_call(t0, iters, acc)


func _bench_height(terrain: Terrain, dirs: PackedVector3Array, iters: int) -> float:
	var acc: float = 0.0
	var t0: int = Time.get_ticks_usec()
	for k: int in iters:
		acc += terrain.height_at(dirs[k & (DIR_POOL - 1)])
	return _per_call(t0, iters, acc)


func _bench_normal(terrain: Terrain, dirs: PackedVector3Array, iters: int) -> float:
	var acc: float = 0.0
	var t0: int = Time.get_ticks_usec()
	for k: int in iters:
		acc += terrain.normal_at(dirs[k & (DIR_POOL - 1)]).x
	return _per_call(t0, iters, acc)


func _bench_biome(terrain: Terrain, dirs: PackedVector3Array, iters: int) -> float:
	var acc: float = 0.0
	var t0: int = Time.get_ticks_usec()
	for k: int in iters:
		acc += float(terrain.biome_at(dirs[k & (DIR_POOL - 1)]))
	return _per_call(t0, iters, acc)


func _per_call(t0: int, iters: int, sink: float) -> float:
	var us: float = float(Time.get_ticks_usec() - t0) / float(iters)
	if sink == 1.2345678:   # keeps the accumulator live
		print("")
	return us
