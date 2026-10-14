class_name SNav1Run extends Node
## S-NAV-1 harness (TA-20; 03 s14.3). godot --headless --path godot res://spikes/s_nav_1/run.tscn -- [options]
##   --map=rough|baked   rough = TA-16 s_world1_r6000 terrain + NavTestKit.rough_weights (default); baked = its path.u8
##   --pct=N             heuristic inflation percent (default 25)     --budget=N  expansions per tick (default 120)
##   --sections=strat,edge,corner,reweight,load,astar   (default all but astar)   --load-ticks=N (default 18000)
## Prints one RESULT line per measurement (key=value) for docs/spikes/TA-20/REPORT.md.

const R: float = Sphere.PLANET_RADIUS
const N: int = Sphere.GRID_PATH
const BUCKETS_M: PackedFloat32Array = [100.0, 1000.0, 5000.0, 15000.0]
const HARVESTER_MASK: int = 25
const CRAWLER_MASK: int = 20

var p: Pathing
var rng: Rng = Rng.new(20)
var failures: int = 0
var map_kind: String = "rough"
var pct: int = 25
var budget: int = 120
var load_ticks: int = 18000
var hier: int = 0
var sections: PackedStringArray = ["strat", "edge", "corner", "reweight", "load"]
var r_ticks: int = 0
var r_exp: int = 0
var r_us: int = 0
var r_st: int = 0
var r_cells: PackedInt32Array = PackedInt32Array()
var r_worst: int = 0


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		var kv: PackedStringArray = arg.trim_prefix("--").split("=")
		if kv.size() != 2:
			continue
		match kv[0]:
			"map": map_kind = kv[1]
			"pct": pct = int(kv[1])
			"budget": budget = int(kv[1])
			"load-ticks": load_ticks = int(kv[1])
			"sections": sections = kv[1].split(",")
			"hier": hier = int(kv[1])
	_setup()
	if sections.has("strat"):
		_stratified()
	if sections.has("edge"):
		_edge_corner("edge", 200, 1)
	if sections.has("corner"):
		_edge_corner("corner", 50, 0)
	if sections.has("reweight"):
		_reweight()
	if sections.has("load"):
		_load()
	if sections.has("astar"):
		_astar()
	print("RESULT correctness_failures=%d" % failures)
	get_tree().quit(0)


func _setup() -> void:
	var m0: float = Performance.get_monitor(Performance.MEMORY_STATIC)
	var t0: int = Time.get_ticks_usec()
	p = Pathing.new(budget)
	var t1: int = Time.get_ticks_usec()
	var terrain: Terrain = Terrain.new()
	var _e: Error = terrain.load_map("res://content/maps/s_world1_r6000")
	var err: Error = p.load_weights("res://content/maps/s_world1_r6000")
	if map_kind == "rough":
		var _ok: bool = p.set_weights(NavTestKit.rough_weights(7, 400, 150))
	p.set_terrain(terrain)
	p.set_heuristic_pct(pct)
	p.hier_min_cells = hier
	var t2: int = Time.get_ticks_usec()
	var blocked: int = 0
	var blocked20: int = 0
	var t3: int = Time.get_ticks_usec()
	for c: int in PathGrid.CELLS:
		if not p.grid.passable(c, PathGrid.SLOPE_NO_LIMIT):
			blocked += 1
		if not p.grid.passable(c, PathGrid.limit_q_of(CRAWLER_MASK)):
			blocked20 += 1
	var slope_us: float = float(Time.get_ticks_usec() - t3) / float(PathGrid.CELLS)
	t3 = Time.get_ticks_usec()
	var b0: int = p.clusters.builds
	p.prepare(CRAWLER_MASK)
	var prep_ms: float = (Time.get_ticks_usec() - t3) / 1000.0
	var build_us: float = (Time.get_ticks_usec() - t3) / float(maxi(1, p.clusters.builds - b0))
	t3 = Time.get_ticks_usec()
	p.prepare(HARVESTER_MASK)
	var prep2_ms: float = (Time.get_ticks_usec() - t3) / 1000.0
	print("RESULT section=setup_costs slope_sample_us_per_cell=%.2f prepare20_ms=%.0f prepare25_ms=%.0f build_us_per_cluster=%.1f blocked_mask20=%d orphans=%d overflows=%d" % [
		slope_us, prep_ms, prep2_ms, build_us, blocked20, p.clusters.orphans, p.clusters.overflows])
	print("RESULT section=setup map=%s pct=%d budget=%d load_err=%d init_ms=%.1f weights_ms=%.1f blocked_cells=%d mem_mb=%.2f" % [
		map_kind, pct, budget, err, (t1 - t0) / 1000.0, (t2 - t1) / 1000.0, blocked, (Performance.get_monitor(Performance.MEMORY_STATIC) - m0) / 1048576.0])


func _rand_dir() -> Vector3:
	while true:
		var v: Vector3 = Vector3(rng.range_f(-1.0, 1.0), rng.range_f(-1.0, 1.0), rng.range_f(-1.0, 1.0))
		if v.length_squared() > 0.01 and v.length_squared() <= 1.0:
			return v.normalized()
	return Vector3.UP


func _passable_dir(mask: int) -> Vector3:
	while true:
		var d: Vector3 = _rand_dir()
		if p.grid.passable(PathGrid.cell_of(d), PathGrid.limit_q_of(mask)):
			return d
	return Vector3.UP


## Point at great-circle distance `m` from `a` on a random bearing, passable for `mask`.
func _at_distance(a: Vector3, m: float, mask: int) -> Vector3:
	for _t: int in 200:
		var f: Basis = Sphere.tangent_frame(a)
		var brg: float = rng.range_f(-PI, PI)
		var axis: Vector3 = (f.y * cos(brg) + f.x * sin(brg)).cross(a).normalized()
		var b: Vector3 = a.rotated(-axis, m / R).normalized()
		if p.grid.passable(PathGrid.cell_of(b), PathGrid.limit_q_of(mask)):
			return b
	return a


## Runs one ticket to completion alone; results in the r_* members.
func _solve(a: Vector3, b: Vector3, mask: int) -> void:
	var tk: int = p.request(a * R, b * R, mask)
	var ticks: int = 0
	var exp: int = 0
	var t0: int = Time.get_ticks_usec()
	var worst: int = 0
	while p.status(tk) == Pathing.ST_PENDING:
		var s0: int = Time.get_ticks_usec()
		exp += p.advance()
		worst = maxi(worst, Time.get_ticks_usec() - s0)
		ticks += 1
	var us: int = Time.get_ticks_usec() - t0
	var cells: PackedInt32Array = p.result_cells(tk)
	var st: int = p.status(tk)
	_check(tk, a, b, mask, st, cells)
	p.release(tk)
	r_ticks = ticks
	r_exp = exp
	r_us = us
	r_st = st
	r_cells = cells
	r_worst = worst


func _check(_tk: int, a: Vector3, b: Vector3, mask: int, st: int, cells: PackedInt32Array) -> void:
	var s: int = PathGrid.cell_of(a)
	var g: int = PathGrid.cell_of(b)
	if st == Pathing.ST_DONE:
		var why: String = NavTestKit.validate(p, cells, s, g, mask)
		if why != "":
			failures += 1
			print("FAIL path %d -> %d: %s" % [s, g, why])
	elif NavTestKit.reachable(p, s, g, mask):
		failures += 1
		print("FAIL NO_PATH but reachable %d -> %d" % [s, g])


func _stratified() -> void:
	for m: float in BUCKETS_M:
		var ticks: PackedInt32Array = PackedInt32Array()
		var exps: PackedInt32Array = PackedInt32Array()
		var ratio: PackedFloat32Array = PackedFloat32Array()
		var us_total: int = 0
		var exp_total: int = 0
		var worst_tick: int = 0
		var nopath: int = 0
		for q: int in 250:
			p.cache.clear()
			var a: Vector3 = _passable_dir(CRAWLER_MASK)
			var b: Vector3 = _at_distance(a, m, CRAWLER_MASK)
			_solve(a, b, CRAWLER_MASK)
			var _x: bool = ticks.push_back(r_ticks)
			_x = exps.push_back(r_exp)
			us_total += r_us
			exp_total += r_exp
			worst_tick = maxi(worst_tick, r_worst)
			if r_st == Pathing.ST_DONE:
				var cells: PackedInt32Array = r_cells
				_x = ratio.push_back(NavTestKit.length_of(cells) / maxf(1.0, Sphere.great_circle(a, b)))
			else:
				nopath += 1
		_report("strat_%dm" % int(m), ticks, exps, ratio, us_total, exp_total, worst_tick, nopath)


func _edge_corner(label: String, count: int, mode: int) -> void:
	var ticks: PackedInt32Array = PackedInt32Array()
	var exps: PackedInt32Array = PackedInt32Array()
	var ratio: PackedFloat32Array = PackedFloat32Array()
	var us_total: int = 0
	var exp_total: int = 0
	var worst_tick: int = 0
	var nopath: int = 0
	var crossings: int = 0
	for q: int in count:
		p.cache.clear()
		var a: Vector3 = _near_edge(mode)
		var b: Vector3 = _at_distance(a, rng.range_f(200.0, 3000.0) if mode == 1 else rng.range_f(100.0, 1500.0), CRAWLER_MASK)
		if PathGrid.cell_of(a) >> 16 == PathGrid.cell_of(b) >> 16:
			b = _mirror_across(a, b)
		_solve(a, b, CRAWLER_MASK)
		var _x: bool = ticks.push_back(r_ticks)
		_x = exps.push_back(r_exp)
		us_total += r_us
		exp_total += r_exp
		worst_tick = maxi(worst_tick, r_worst)
		if r_st == Pathing.ST_DONE:
			var cells: PackedInt32Array = r_cells
			_x = ratio.push_back(NavTestKit.length_of(cells) / maxf(1.0, Sphere.great_circle(a, b)))
			crossings += 1 if cells[0] >> 16 != cells[cells.size() - 1] >> 16 else 0
		else:
			nopath += 1
	_report(label, ticks, exps, ratio, us_total, exp_total, worst_tick, nopath)
	print("RESULT section=%s cross_face_paths=%d" % [label, crossings])


func _near_edge(mode: int) -> Vector3:
	while true:
		var v: Vector3 = Vector3(1 if rng.next_float() < 0.5 else -1, 1 if rng.next_float() < 0.5 else -1,
			1 if rng.next_float() < 0.5 else -1)
		if mode == 1:
			v[rng.range_i(0, 2)] = rng.range_f(-0.9, 0.9)
		var j: Vector3 = Vector3(rng.range_f(-1.0, 1.0), rng.range_f(-1.0, 1.0), rng.range_f(-1.0, 1.0)) * 0.01
		var d: Vector3 = (v.normalized() + j).normalized()
		if p.grid.passable(PathGrid.cell_of(d), PathGrid.limit_q_of(CRAWLER_MASK)):
			return d
	return Vector3.UP


func _mirror_across(a: Vector3, b: Vector3) -> Vector3:
	var c: Vector3 = Sphere.slerp_dir(b, a, 2.0)
	return c if p.grid.passable(PathGrid.cell_of(c), PathGrid.limit_q_of(CRAWLER_MASK)) else b


func _reweight() -> void:
	var t0: int = Time.get_ticks_usec()
	var worst: int = 0
	for k: int in 500:
		var s0: int = Time.get_ticks_usec()
		p.set_weight(rng.range_i(0, PathGrid.CELLS - 1), PathGrid.W_BLOCKED if k % 2 == 0 else rng.range_i(1, 5))
		worst = maxi(worst, Time.get_ticks_usec() - s0)
	var t1: int = Time.get_ticks_usec()
	print("RESULT section=reweight cells=500 total_ms=%.3f per_cell_us=%.2f worst_us=%d" % [(t1 - t0) / 1000.0, (t1 - t0) / 500.0, worst])
	var ticks: PackedInt32Array = PackedInt32Array()
	var exps: PackedInt32Array = PackedInt32Array()
	var ratio: PackedFloat32Array = PackedFloat32Array()
	var us_total: int = 0
	var exp_total: int = 0
	var worst_tick: int = 0
	var nopath: int = 0
	for q: int in 100:
		var a: Vector3 = _passable_dir(CRAWLER_MASK)
		var b: Vector3 = _at_distance(a, rng.range_f(500.0, 8000.0), CRAWLER_MASK)
		_solve(a, b, CRAWLER_MASK)
		var _x: bool = ticks.push_back(r_ticks)
		_x = exps.push_back(r_exp)
		us_total += r_us
		exp_total += r_exp
		worst_tick = maxi(worst_tick, r_worst)
		if r_st != Pathing.ST_DONE:
			nopath += 1
	_report("after_reweight", ticks, exps, ratio, us_total, exp_total, worst_tick, nopath)


func _report(label: String, ticks: PackedInt32Array, exps: PackedInt32Array, ratio: PackedFloat32Array, us: int,
		exp: int, worst_tick_us: int, nopath: int) -> void:
	ticks.sort()
	exps.sort()
	ratio.sort()
	var n: int = ticks.size()
	print("RESULT section=%s n=%d ticks_p50=%d ticks_p95=%d ticks_max=%d exp_p50=%d exp_p95=%d exp_max=%d us_per_exp=%.2f worst_tick_ms=%.3f ratio_p50=%.3f ratio_p95=%.3f ratio_max=%.3f no_path=%d" % [
		label, n, ticks[NavLoad._q(n, 0.5)], ticks[NavLoad._q(n, 0.95)], ticks[n - 1], exps[NavLoad._q(n, 0.5)],
		exps[NavLoad._q(n, 0.95)], exps[n - 1], float(us) / maxf(1.0, float(exp)), worst_tick_us / 1000.0,
		ratio[NavLoad._q(ratio.size(), 0.5)] if ratio.size() > 0 else 0.0,
		ratio[NavLoad._q(ratio.size(), 0.95)] if ratio.size() > 0 else 0.0,
		ratio[ratio.size() - 1] if ratio.size() > 0 else 0.0, nopath])


# 120 ground units, each re-pathing every 10 s (300 ticks, staggered): 4 bases x 15 Harvesters looping field <->
# refinery (mask 25, 12 m/s) and 60 Siege Crawlers to random goals 1-8 km away (mask 20, 8 m/s).
func _load() -> void:
	var nl: NavLoad = NavLoad.new(p, rng)
	nl.setup()
	var t0: int = Time.get_ticks_usec()
	nl.run(load_ticks)
	var wall: float = (Time.get_ticks_usec() - t0) / 1000.0
	failures += nl.failures
	print("RESULT section=load ticks=%d wall_ms=%.1f %s" % [load_ticks, wall, nl.summary()])
	p.cache.clear()


func _astar() -> void:
	var cmp: NavAStar = NavAStar.new(p, rng)
	print("RESULT section=astar %s" % cmp.run(BUCKETS_M))
	failures += cmp.failures
