class_name NavAStar extends RefCounted
## S-NAV-1 comparison (03 s14.3): Godot's AStar3D over the same 393,216 cells and 8-connectivity (corner rule
## applied at build: a diagonal is connected only when both orthogonal cells are passable), weight_scale = the
## cell weight. Measures build time, memory, per-query time per distance bucket, path validity and cost ratio
## against the custom Pathing on the same queries. AStar3D cannot be time-sliced: one get_id_path call per query.

const R: float = Sphere.PLANET_RADIUS
const MASK: int = 20
const PER_BUCKET: int = 50

var p: Pathing
var rng: Rng
var failures: int = 0


func _init(pathing: Pathing, r: Rng) -> void:
	p = pathing
	rng = r


func run(buckets: PackedFloat32Array) -> String:
	var lq: int = PathGrid.limit_q_of(MASK)
	var m0: float = Performance.get_monitor(Performance.MEMORY_STATIC)
	var t0: int = Time.get_ticks_usec()
	var a: AStar3D = AStar3D.new()
	a.reserve_space(PathGrid.CELLS)
	for c: int in PathGrid.CELLS:
		if p.grid.passable(c, lq):
			a.add_point(c, p.grid.center_dir(c) * R, float(p.weight(c)))
	var links: int = 0
	for c: int in PathGrid.CELLS:
		if not a.has_point(c):
			continue
		var nb: PackedInt32Array = Sphere.neighbours8(c, PathGrid.N)
		for k: int in nb.size():
			var n: int = nb[k]
			if n < c or not a.has_point(n):
				continue
			if k >= 4 and not (a.has_point(nb[(k - 4) & 1]) and a.has_point(nb[2 + ((k - 4) >> 1)])):
				continue
			a.connect_points(c, n, true)
			links += 1
	var build_ms: float = (Time.get_ticks_usec() - t0) / 1000.0
	var mem_mb: float = (Performance.get_monitor(Performance.MEMORY_STATIC) - m0) / 1048576.0
	var out: String = "build_ms=%.0f mem_mb=%.1f points=%d links=%d" % [build_ms, mem_mb, a.get_point_count(), links]
	for m: float in buckets:
		out += " " + _bucket(a, m)
	return out


func _bucket(a: AStar3D, m: float) -> String:
	var us_a: int = 0
	var us_p: int = 0
	var exp_p: int = 0
	var ratio: float = 0.0
	var worst_a: int = 0
	var done: int = 0
	for q: int in PER_BUCKET:
		var s_dir: Vector3 = _passable_dir()
		var g_dir: Vector3 = _at(s_dir, m)
		var s: int = PathGrid.cell_of(s_dir)
		var g: int = PathGrid.cell_of(g_dir)
		var t0: int = Time.get_ticks_usec()
		var ids: PackedInt64Array = a.get_id_path(s, g)
		var dt: int = Time.get_ticks_usec() - t0
		us_a += dt
		worst_a = maxi(worst_a, dt)
		p.cache.clear()
		var tk: int = p.request(s_dir * R, g_dir * R, MASK)
		t0 = Time.get_ticks_usec()
		while p.status(tk) == Pathing.ST_PENDING:
			exp_p += p.advance()
		us_p += Time.get_ticks_usec() - t0
		var cells: PackedInt32Array = PackedInt32Array()
		for id: int in ids:
			var _x: bool = cells.push_back(id)
		if p.status(tk) == Pathing.ST_DONE and not cells.is_empty():
			var why: String = NavTestKit.validate(p, cells, s, g, MASK)
			if why != "":
				failures += 1
				print("FAIL astar3d %s" % why)
			ratio += NavTestKit.cost_of(p, cells) / maxf(1.0, NavTestKit.cost_of(p, p.result_cells(tk)))
			done += 1
		p.release(tk)
	return "b%dm_astar3d_ms=%.3f b%dm_astar3d_worst_ms=%.3f b%dm_custom_ms=%.3f b%dm_custom_exp=%d b%dm_cost_ratio=%.3f" % [
		int(m), us_a / 1000.0 / PER_BUCKET, int(m), worst_a / 1000.0, int(m), us_p / 1000.0 / PER_BUCKET, int(m),
		MathX.floori_div(exp_p, PER_BUCKET), int(m), ratio / maxf(1.0, float(done))]


func _passable_dir() -> Vector3:
	while true:
		var v: Vector3 = Vector3(rng.range_f(-1.0, 1.0), rng.range_f(-1.0, 1.0), rng.range_f(-1.0, 1.0))
		if v.length_squared() > 0.01 and v.length_squared() <= 1.0 \
				and p.grid.passable(PathGrid.cell_of(v), PathGrid.limit_q_of(MASK)):
			return v.normalized()
	return Vector3.UP


func _at(a: Vector3, m: float) -> Vector3:
	for _t: int in 200:
		var f: Basis = Sphere.tangent_frame(a)
		var brg: float = rng.range_f(-PI, PI)
		var axis: Vector3 = (f.y * cos(brg) + f.x * sin(brg)).cross(a).normalized()
		var b: Vector3 = a.rotated(-axis, m / R).normalized()
		if p.grid.passable(PathGrid.cell_of(b), PathGrid.limit_q_of(MASK)):
			return b
	return a
