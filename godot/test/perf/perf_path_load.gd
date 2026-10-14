class_name PerfPathLoad extends RefCounted
## perf_tick's row-3b load (TA-50; the S-NAV-1 load of 03 s14.3 / TA-20 REPORT, driven through the sim): up to 120
## ground units re-path every 10 s (300 ticks, staggered) and on arrival, using only `CommandSinkBase.pathing()`
## from the stub hook. Half are Harvesters looping refinery <-> field around the 8 bases (warm cache), half Siege
## Crawlers driving to fresh goals 1-8 km away. Unit positions are virtual (ground motion is TA-38): they move along
## the returned route at the def speed. Setup on the first tick reads the grid for passable endpoints.

const REPATH_TICKS: int = 300
const MAX_UNITS: int = 120

var units: int = 0
var requests: int = 0
var cache_hits: int = 0
var no_path: int = 0

var _bases: PackedVector3Array
var _rng: Rng = Rng.new(50)
var _pos: PackedVector3Array = PackedVector3Array()
var _target: PackedVector3Array = PackedVector3Array()
var _home: PackedVector3Array = PackedVector3Array()
var _field: PackedVector3Array = PackedVector3Array()
var _mask: PackedInt32Array = PackedInt32Array()
var _step: PackedFloat32Array = PackedFloat32Array()
var _ticket: PackedInt32Array = PackedInt32Array()
var _idx: PackedInt32Array = PackedInt32Array()
var _paths: Array[PackedVector3Array] = []


func _init(n_ground: int, bases: PackedVector3Array) -> void:
	units = mini(MAX_UNITS, n_ground)
	_bases = bases


func tick(t: int, sink: CommandSinkBase) -> void:
	var p: Pathing = sink.pathing()
	if p == null or units == 0:
		return
	if _pos.is_empty():
		_setup(p)
	for u: int in units:
		if t % REPATH_TICKS == floori(float(u * REPATH_TICKS) / float(units)):
			_request(p, u)
		var tk: int = _ticket[u]
		if tk != Pathing.NO_TICKET and p.status(tk) != Pathing.ST_PENDING:
			if p.status(tk) == Pathing.ST_DONE:
				_paths[u] = p.result(tk)
				_idx[u] = 1
			else:
				no_path += 1
				_target[u] = _around(p, _pos[u], _rng.range_f(500.0, 3000.0), _mask[u])
			p.release(tk)
			_ticket[u] = Pathing.NO_TICKET
		_move(p, u)


func _setup(p: Pathing) -> void:
	var c: ContentSet = WorldTestKit.content()
	var h: GroundUnitDef = c.ground_units[0]
	var cr: GroundUnitDef = c.ground_units[1]
	for g: GroundUnitDef in c.ground_units:
		if g.id == &"harvester":
			h = g
		elif g.id == &"siege_crawler":
			cr = g
	for u: int in units:
		var harvester: bool = u % 2 == 0
		var g: GroundUnitDef = h if harvester else cr
		var m: int = Pathing.mask_for(g.max_slope_deg)
		var base: Vector3 = _around(p, _bases[u % _bases.size()], 0.0, m)
		var at: Vector3 = _around(p, base, _rng.range_f(0.0, 300.0), m)
		var field: Vector3 = _around(p, base, _rng.range_f(600.0, 1500.0), m) if harvester else at
		var _a: bool = _pos.push_back(at)
		_a = _target.push_back(field if harvester else _around(p, at, _rng.range_f(1000.0, 8000.0), m))
		_a = _home.push_back(base)
		_a = _field.push_back(field)
		_a = _mask.push_back(m)
		_a = _step.push_back(g.ground_speed / 30.0)
		_a = _ticket.push_back(Pathing.NO_TICKET)
		_a = _idx.push_back(0)
		_paths.append(PackedVector3Array())


func _request(p: Pathing, u: int) -> void:
	if _ticket[u] != Pathing.NO_TICKET:
		p.release(_ticket[u])
	var hits: int = p.cache_hits
	_ticket[u] = p.request(_pos[u] * Sphere.PLANET_RADIUS, _target[u] * Sphere.PLANET_RADIUS, _mask[u])
	requests += 1
	cache_hits += p.cache_hits - hits


func _move(p: Pathing, u: int) -> void:
	var path: PackedVector3Array = _paths[u]
	var left: float = _step[u]
	while left > 0.0 and _idx[u] < path.size():
		var w: Vector3 = path[_idx[u]].normalized()
		var d: float = Sphere.great_circle(_pos[u], w)
		if d <= left:
			_pos[u] = w
			left -= d
			_idx[u] += 1
		else:
			_pos[u] = Sphere.slerp_dir(_pos[u], w, left / d)
			left = 0.0
	if path.size() > 0 and _idx[u] >= path.size():
		_paths[u] = PackedVector3Array()
		if u % 2 == 0:
			_target[u] = _home[u] if _target[u].is_equal_approx(_field[u]) else _field[u]
		else:
			_target[u] = _around(p, _pos[u], _rng.range_f(1000.0, 8000.0), _mask[u])
		_request(p, u)


## A passable unit direction about `m_dist` metres from `a` (searching outward when the first pick is blocked).
func _around(p: Pathing, a: Vector3, m_dist: float, m: int) -> Vector3:
	var reach: float = m_dist
	for _t: int in 400:
		var f: Basis = Sphere.tangent_frame(a)
		var brg: float = _rng.range_f(-PI, PI)
		var axis: Vector3 = (f.y * cos(brg) + f.x * sin(brg)).cross(a).normalized()
		var b: Vector3 = a.rotated(-axis, reach / Sphere.PLANET_RADIUS).normalized() if reach > 0.0 else a
		if p.grid.passable(PathGrid.cell_of(b), PathGrid.limit_q_of(m)):
			return b
		reach += 20.0
	return a
