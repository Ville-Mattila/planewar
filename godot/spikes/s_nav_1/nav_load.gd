class_name NavLoad extends RefCounted
## S-NAV-1 load (03 s14.3): 120 ground units, every unit re-paths every 10 s (300 ticks, staggered) and on arrival.
## 4 bases x 15 Harvesters loop field <-> refinery (mask 25, 12 m/s); 60 Siege Crawlers drive to random goals
## 1-8 km away (mask 20, 8 m/s). Measures advance() time per tick, ticket latency, cache hit rates, correctness.

const R: float = Sphere.PLANET_RADIUS
const HARVESTERS: int = 60
const CRAWLERS: int = 60
const REPATH_TICKS: int = 300
const TICK_S: float = 1.0 / 30.0

var p: Pathing
var rng: Rng
var failures: int = 0
var pos: PackedVector3Array = PackedVector3Array()
var target: PackedVector3Array = PackedVector3Array()
var home: PackedVector3Array = PackedVector3Array()      # refinery per harvester
var field: PackedVector3Array = PackedVector3Array()     # field per harvester
var mask: PackedInt32Array = PackedInt32Array()
var speed: PackedFloat32Array = PackedFloat32Array()
var ticket: PackedInt32Array = PackedInt32Array()
var req_cell: PackedInt32Array = PackedInt32Array()     # start cell at request time (the unit keeps moving)
var idx: PackedInt32Array = PackedInt32Array()
var paths: Array[PackedVector3Array] = []
var tick_us: PackedInt32Array = PackedInt32Array()
var tick_exp: PackedInt32Array = PackedInt32Array()
var latency: PackedInt32Array = PackedInt32Array()
var h_req: int = 0
var h_hit: int = 0
var c_req: int = 0
var c_hit: int = 0
var no_path: int = 0
var rejected: int = 0
var arrivals: int = 0
var slow: PackedStringArray = PackedStringArray()


func _init(pathing: Pathing, r: Rng) -> void:
	p = pathing
	rng = r


func setup() -> void:
	for b: int in 4:
		var refinery: Vector3 = _passable(Sphere.from_lat_lon(0.0, deg_to_rad(22.5 + 90.0 * b), 1.0), 25)
		var fields: PackedVector3Array = PackedVector3Array()
		for f: int in 3:
			var _a: bool = fields.push_back(_around(refinery, rng.range_f(600.0, 1500.0), 25))
		for h: int in HARVESTERS >> 2:
			_add(_around(refinery, rng.range_f(0.0, 300.0), 25), fields[h % 3], 25, 12.0, refinery, fields[h % 3])
	for c: int in CRAWLERS:
		var a: Vector3 = _around(_rand_dir(), 0.0, 20)
		_add(a, _around(a, rng.range_f(1000.0, 8000.0), 20), 20, 8.0, a, a)


func _add(at: Vector3, to: Vector3, m: int, v: float, h: Vector3, f: Vector3) -> void:
	var _a: bool = pos.push_back(at)
	_a = target.push_back(to)
	_a = home.push_back(h)
	_a = field.push_back(f)
	_a = mask.push_back(m)
	_a = speed.push_back(v * TICK_S)
	_a = ticket.push_back(Pathing.NO_TICKET)
	_a = req_cell.push_back(-1)
	_a = idx.push_back(0)
	paths.append(PackedVector3Array())


func run(ticks: int) -> void:
	var n: int = pos.size()
	for t: int in ticks:
		for u: int in n:
			if t % REPATH_TICKS == MathX.floori_div(u * REPATH_TICKS, n):
				_request(u)
			_poll(u)
			_move(u)
		var a0: int = p.abstract_units
		var b0: int = p.clusters.builds
		var r0: int = p.requests
		var s0: int = Time.get_ticks_usec()
		var used: int = p.advance()
		var dt: int = Time.get_ticks_usec() - s0
		var _a: bool = tick_us.push_back(dt)
		_a = tick_exp.push_back(used)
		if dt > 1500:
			var _s: bool = slow.append("t%d:%dus/%du/abs%d/b%d/q%d/pend%d" % [t, dt, used, p.abstract_units - a0, p.clusters.builds - b0, p.requests - r0, p.pending()])


func _request(u: int) -> void:
	if ticket[u] != Pathing.NO_TICKET:
		p.release(ticket[u])
	var hits: int = p.cache_hits
	ticket[u] = p.request(pos[u] * R, target[u] * R, mask[u])
	req_cell[u] = PathGrid.cell_of(pos[u])
	if ticket[u] == Pathing.NO_TICKET:
		rejected += 1
		return
	if u < HARVESTERS:
		h_req += 1
		h_hit += p.cache_hits - hits
	else:
		c_req += 1
		c_hit += p.cache_hits - hits


func _poll(u: int) -> void:
	var tk: int = ticket[u]
	if tk == Pathing.NO_TICKET or p.status(tk) == Pathing.ST_PENDING:
		return
	var _a: bool = latency.push_back(p.done_tick(tk) - p.request_tick(tk))
	var s: int = req_cell[u]
	var g: int = PathGrid.cell_of(target[u])
	if p.status(tk) == Pathing.ST_DONE:
		var why: String = NavTestKit.validate(p, p.result_cells(tk), s, g, mask[u])
		if why != "":
			failures += 1
			print("FAIL load unit %d: %s" % [u, why])
		paths[u] = p.result(tk)
		idx[u] = 1
	else:
		no_path += 1
		if NavTestKit.reachable(p, s, g, mask[u]):
			failures += 1
			print("FAIL load NO_PATH but reachable %d -> %d" % [s, g])
		target[u] = _around(pos[u], rng.range_f(500.0, 3000.0), mask[u])
	p.release(tk)
	ticket[u] = Pathing.NO_TICKET


func _move(u: int) -> void:
	var path: PackedVector3Array = paths[u]
	var left: float = speed[u]
	while left > 0.0 and idx[u] < path.size():
		var w: Vector3 = path[idx[u]].normalized()
		var d: float = Sphere.great_circle(pos[u], w)
		if d <= left:
			pos[u] = w
			left -= d
			idx[u] += 1
		else:
			pos[u] = Sphere.slerp_dir(pos[u], w, left / d)
			left = 0.0
	if path.size() > 0 and idx[u] >= path.size():
		arrivals += 1
		paths[u] = PackedVector3Array()
		if u < HARVESTERS:
			target[u] = home[u] if target[u].is_equal_approx(field[u]) else field[u]
		else:
			target[u] = _around(pos[u], rng.range_f(1000.0, 8000.0), mask[u])
		_request(u)


func summary() -> String:
	var us: PackedInt32Array = tick_us.duplicate()
	us.sort()
	var ex: PackedInt32Array = tick_exp.duplicate()
	ex.sort()
	var lat: PackedInt32Array = latency.duplicate()
	lat.sort()
	var tot_us: int = 0
	var tot_ex: int = 0
	for k: int in us.size():
		tot_us += us[k]
		tot_ex += ex[k]
	var n: int = us.size()
	return ("mean_ms=%.4f p50_ms=%.3f p95_ms=%.3f p99_ms=%.3f max_ms=%.3f exp_mean=%.1f exp_p95=%d exp_max=%d " +
		"us_per_exp=%.2f requests=%d harvester_req=%d harvester_hit=%.3f crawler_req=%d crawler_hit=%.3f " +
		"splice_misses=%d fallbacks=%d latency_p50=%d latency_p95=%d latency_max=%d no_path=%d rejected=%d " +
		"arrivals=%d abstract_share=%.3f cache_entries=%d") % [
		float(tot_us) / float(n) / 1000.0, us[_q(n, 0.5)] / 1000.0, us[_q(n, 0.95)] / 1000.0, us[_q(n, 0.99)] / 1000.0,
		us[n - 1] / 1000.0, float(tot_ex) / float(n), ex[_q(n, 0.95)], ex[n - 1], float(tot_us) / maxf(1.0, float(tot_ex)),
		p.requests, h_req, float(h_hit) / maxf(1.0, float(h_req)), c_req, float(c_hit) / maxf(1.0, float(c_req)),
		p.splice_misses, p.fallbacks, lat[_q(lat.size(), 0.5)], lat[_q(lat.size(), 0.95)], lat[lat.size() - 1],
		no_path, rejected, arrivals, float(p.abstract_units) / maxf(1.0, float(p.expansions_total)), p.cache.size()]


static func _q(n: int, q: float) -> int:
	return clampi(floori(float(n) * q), 0, n - 1)


func _rand_dir() -> Vector3:
	while true:
		var v: Vector3 = Vector3(rng.range_f(-1.0, 1.0), rng.range_f(-1.0, 1.0), rng.range_f(-1.0, 1.0))
		if v.length_squared() > 0.01 and v.length_squared() <= 1.0:
			return v.normalized()
	return Vector3.UP


func _passable(d: Vector3, m: int) -> Vector3:
	return _around(d, 0.0, m)


## A passable point about `m_dist` metres from `a` (searching outward when the first pick is blocked).
func _around(a: Vector3, m_dist: float, m: int) -> Vector3:
	var reach: float = m_dist
	for t: int in 400:
		var f: Basis = Sphere.tangent_frame(a)
		var brg: float = rng.range_f(-PI, PI)
		var axis: Vector3 = (f.y * cos(brg) + f.x * sin(brg)).cross(a).normalized()
		var b: Vector3 = a.rotated(-axis, reach / R).normalized() if reach > 0.0 else a
		if p.grid.passable(PathGrid.cell_of(b), PathGrid.limit_q_of(m)):
			return b
		reach += 20.0
	return a
