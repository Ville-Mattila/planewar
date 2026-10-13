class_name PerfCore
extends SceneTree
## core/sphere.gd micro-benchmarks against the core/MODULE.md budget (03 s15.2, PC-mid).
## godot --headless --path godot -s res://test/perf/perf_core.gd [-- --iters=200000 --strict]
## Prints one PERF_CORE line per function: per-call us (loop and two-element read overhead subtracted).
## Exit 0 unless --strict and a budget is exceeded (absolute gates run on the pinned runner only).

const BUDGET_US: Dictionary[StringName, float] = {
	&"face_uv_to_dir": 0.6, &"dir_to_face_uv": 0.8, &"cell_of": 1.0, &"transport": 0.4, &"great_circle": 0.3,
}
const DIR_POOL: int = 1024


func _initialize() -> void:
	var iters: int = 200000
	var strict: bool = false
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--iters="):
			iters = int(arg.substr(8))
		elif arg == "--strict":
			strict = true
	var dirs: PackedVector3Array = PackedVector3Array()
	var _r: int = dirs.resize(DIR_POOL)
	for k: int in DIR_POOL:
		# Deterministic spread without Rng (Rng needs the Log autoload, absent under -s).
		var t: float = float(k + 1)
		dirs[k] = Vector3(sin(t * 12.9898), sin(t * 78.233), sin(t * 37.719)).normalized()
	var over: int = 0
	var base: float = _bench_empty(dirs, iters)
	over += _report(&"face_uv_to_dir", _bench_face_uv_to_dir(iters) - base, strict)
	over += _report(&"dir_to_face_uv", _bench_dir_to_face_uv(dirs, iters) - base, strict)
	over += _report(&"cell_of", _bench_cell_of(dirs, iters) - base, strict)
	over += _report(&"transport", _bench_transport(dirs, iters) - base, strict)
	over += _report(&"great_circle", _bench_great_circle(dirs, iters) - base, strict)
	quit(1 if over > 0 else 0)


func _report(fn: StringName, us: float, strict: bool) -> int:
	var budget: float = BUDGET_US[fn]
	print("PERF_CORE fn=%s us=%.3f budget_us=%.1f %s" % [fn, us, budget, "ok" if us <= budget else "OVER"])
	return 1 if strict and us > budget else 0


func _bench_empty(dirs: PackedVector3Array, iters: int) -> float:
	var acc: float = 0.0
	var t0: int = Time.get_ticks_usec()
	for k: int in iters:
		acc += dirs[k & (DIR_POOL - 1)].x + dirs[(k + 1) & (DIR_POOL - 1)].y
	return _per_call(t0, iters, acc)


func _bench_face_uv_to_dir(iters: int) -> float:
	var acc: float = 0.0
	var t0: int = Time.get_ticks_usec()
	for k: int in iters:
		acc += Sphere.face_uv_to_dir(k % 6, 0.37, 0.61).x
	return _per_call(t0, iters, acc)


func _bench_dir_to_face_uv(dirs: PackedVector3Array, iters: int) -> float:
	var acc: float = 0.0
	var t0: int = Time.get_ticks_usec()
	for k: int in iters:
		acc += Sphere.dir_to_face_uv(dirs[k & (DIR_POOL - 1)]).y
	return _per_call(t0, iters, acc)


func _bench_cell_of(dirs: PackedVector3Array, iters: int) -> float:
	var acc: int = 0
	var t0: int = Time.get_ticks_usec()
	for k: int in iters:
		acc += Sphere.cell_of(dirs[k & (DIR_POOL - 1)], Sphere.GRID_BUILD)
	return _per_call(t0, iters, float(acc))


func _bench_transport(dirs: PackedVector3Array, iters: int) -> float:
	var acc: float = 0.0
	var t0: int = Time.get_ticks_usec()
	for k: int in iters:
		acc += Sphere.transport(dirs[k & (DIR_POOL - 1)], dirs[(k + 1) & (DIR_POOL - 1)]).w
	return _per_call(t0, iters, acc)


func _bench_great_circle(dirs: PackedVector3Array, iters: int) -> float:
	var acc: float = 0.0
	var t0: int = Time.get_ticks_usec()
	for k: int in iters:
		acc += Sphere.great_circle(dirs[k & (DIR_POOL - 1)], dirs[(k + 3) & (DIR_POOL - 1)])
	return _per_call(t0, iters, acc)


func _per_call(t0: int, iters: int, sink: float) -> float:
	var us: float = float(Time.get_ticks_usec() - t0) / float(iters)
	if is_nan(sink):
		print("PERF_CORE sink nan")
	return us
