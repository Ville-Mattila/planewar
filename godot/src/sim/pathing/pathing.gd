class_name Pathing extends PathTickets
## Time-sliced A* on the 6 x 256^2 path grid (ADR-05, 03 s3.6, R0 C1-05; S-NAV-1 = TA-20; wired by TA-50: SimWorld
## step 3b, CommandSinkBase.pathing(), S4). `request` queues a query for a ticket; `advance()` spends at most
## `expansions_per_tick` units per tick on the tickets in FIFO order (one search in flight). Ends in different regions
## (PathRegions) search the region graph goal -> start first (exhaustion proves NO_PATH), then the cells inside the
## region corridor (a corridor miss falls back to the full grid). PathCache answers a repeated (start cluster, goal
## cell, mask) at once or by splicing. Deterministic (integer budget, no clock / RNG); no allocation per expansion.

const _PH_NONE: int = 0
const _PH_ABSTRACT: int = 1
const _PH_CORRIDOR: int = 2
const _PH_FULL: int = 3
const _PH_SPLICE: int = 4
const JOB_COST: int = 8                    ## units charged per job start (region lookups, corridor stamping, finish)
const _STATE: PackedStringArray = ["expansions_per_tick", "hier_min_cells", "ticks", "requests", "cache_hits", "splice_misses",
	"fallbacks", "expansions_total", "abstract_units", "_phase", "_join_e", "_join_k"]

var expansions_per_tick: int = 0           ## rules.path_expansions_per_tick
var hier_min_cells: int = 0                ## flat search (no region layer) up to this great-circle distance in cells
var grid: PathLabel = PathLabel.new()
var clusters: PathClusters = PathClusters.new(grid)
var cache: PathCache = PathCache.new()
var ticks: int = 0                         ## advance() calls so far
var requests: int = 0
var cache_hits: int = 0                    ## requests answered from the cache (direct or spliced)
var splice_misses: int = 0                 ## spliced hits that had to search afresh
var fallbacks: int = 0                     ## corridor searches that fell back to the full grid
var expansions_total: int = 0
var abstract_units: int = 0                ## share of expansions_total spent on the cluster layer
var _phase: int = _PH_NONE
var _join_e: int = -1
var _join_k: int = 0


func _init(expansions: int) -> void:
	expansions_per_tick = expansions
	assert(expansions > JOB_COST, "Pathing: budget must exceed one job start")


## Loads the six baked `face<f>.path.u8` faces of `map_dir`, each SHA-256 checked against meta.json (as Terrain).
func load_weights(map_dir: String) -> Error:
	var all: PackedByteArray = PathGrid.read_faces(map_dir)
	if all.is_empty():
		return ERR_FILE_CORRUPT
	if not set_weights(all):
		return ERR_INVALID_DATA
	grid.weights_custom = false
	return OK


## Installs all CELLS weights at once (tests, tools); drops the cache and the cluster graphs.
func set_weights(bytes: PackedByteArray) -> bool:
	if not grid.set_weights(bytes):
		return false
	clusters.invalidate()
	cache.clear()
	return true


## Slope source for request masks (per-cell max slope sampled lazily from Terrain.slope_deg_at).
func set_terrain(t: Terrain) -> void:
	grid.set_terrain(t)
	clusters.invalidate()
	cache.clear()


## Fixes the slope of one path cell in degrees (fixtures, flattening); region graphs and cache are rebuilt lazily.
func override_slope(cell: int, slope_deg: int) -> void:
	grid.override_slope(cell, slope_deg)
	clusters.on_flip(cell)
	cache.clear()


## Builds the region graph of `mask` for every cluster now (map load; v1: one call per ground unit mask).
func prepare(mask: int) -> void:
	clusters.prepare(mask)


## Heuristic inflation in percent for both layers (0 = exact A*; S-NAV-1 default in MODULE.md).
func set_heuristic_pct(pct: int) -> void:
	grid.heuristic_pct = pct
	clusters.heuristic_pct = pct


## A Pathing with the budget and heuristic inflation of `rules` (R0 B.11 A-51: `path_expansions_per_tick`, `path_heuristic_pct`).
static func from_rules(rules: RulesDef) -> Pathing:
	var p: Pathing = Pathing.new(rules.path_expansions_per_tick)
	p.set_heuristic_pct(rules.path_heuristic_pct)
	return p


## Request mask for a ground unit def (`max_slope_deg`; cells steeper than this are impassable, 02 s3).
static func mask_for(max_slope_deg: float) -> int:
	return clampi(int(max_slope_deg), 0, 0xFF)


## Queues a path query from the cell of `from` to the cell of `to`; NO_TICKET when all MAX_TICKETS are pending.
func request(from: Vector3, to: Vector3, mask: int) -> int:
	var sl: int = _alloc()
	if sl < 0:
		return NO_TICKET
	requests += 1
	var s: int = PathGrid.cell_of(from)
	var g: int = PathGrid.cell_of(to)
	_t_start[sl] = s
	_t_goal[sl] = g
	_t_mask[sl] = mask
	_t_req_tick[sl] = ticks
	_t_splice[sl] = 0
	var ticket: int = sl | (_t_gen[sl] << _GEN_SHIFT)
	var e: int = cache.lookup(PathCache.key_of(s, g, mask), grid)
	if e >= 0:
		cache_hits += 1
		if cache.start_cell[e] == s:
			_copy_cached(sl, 0, e, 0)
			_finish(sl, ST_DONE, cache.length[e])
			return ticket
		_t_splice[sl] = 1
	if s == g:
		_t_cells[sl * MAX_CELLS] = s
		_finish(sl, ST_DONE if grid.passable(g, PathGrid.limit_q_of(mask)) else ST_NO_PATH, 1)
		return ticket
	_q[(_qh + _qn) % MAX_TICKETS] = sl
	_qn += 1
	_t_queued[sl] = 1
	return ticket


## Cell centres on the datum sphere (Sphere.PLANET_RADIUS), start cell to goal cell; empty unless DONE.
func result(ticket: int) -> PackedVector3Array:
	var out: PackedVector3Array = PackedVector3Array()
	var sl: int = _slot(ticket)
	if sl < 0 or _t_state[sl] != ST_DONE:
		return out
	var _r: int = out.resize(_t_len[sl])
	for k: int in _t_len[sl]:
		out[k] = grid.center_dir(_t_cells[sl * MAX_CELLS + k]) * Sphere.PLANET_RADIUS
	return out


## Path-grid cell ids of the result (same order as result()); empty unless DONE.
func result_cells(ticket: int) -> PackedInt32Array:
	var sl: int = _slot(ticket)
	if sl < 0 or _t_state[sl] != ST_DONE:
		return PackedInt32Array()
	return _t_cells.slice(sl * MAX_CELLS, sl * MAX_CELLS + _t_len[sl])


## One tick of path work: at most expansions_per_tick units across the queue head-first (FIFO). Returns units used.
func advance() -> int:
	ticks += 1
	var used: int = 0
	while _qn > 0 and used < expansions_per_tick:
		var sl: int = _q[_qh]
		if _t_state[sl] != ST_PENDING:
			_phase = _PH_NONE
		elif _phase == _PH_NONE:
			if used + JOB_COST > expansions_per_tick:
				break
			used += JOB_COST + _start_job(sl)
		if _phase != _PH_NONE and used < expansions_per_tick:
			var u: int = _step_job(sl, expansions_per_tick - used)
			used += u
			if u == 0 and _phase != _PH_NONE:
				break                          # the next unit does not fit this tick
		if _phase == _PH_NONE:
			_t_queued[sl] = 0
			_qh = (_qh + 1) % MAX_TICKETS
			_qn -= 1
	expansions_total += used
	return used


## Sets one cell weight (0 or 255 = impassable) and bumps its face's change counter (cache and AI invalidation).
func set_weight(cell: int, w: int) -> void:
	if grid.set_weight(cell, w):
		clusters.on_flip(cell)


func weight(cell: int) -> int:
	return grid.weight_at(cell)


## Change counter of `face` (SimView.path_grid_version).
func version(face: int) -> int:
	return grid.version_of(face)


# Picks the job for the head ticket: a cache splice, a flat search (same region, or within hier_min_cells), or the
# region search (goal -> start) followed by the corridor search. Returns the units spent on lazy labels.
func _start_job(sl: int) -> int:
	var s: int = _t_start[sl]
	var g: int = _t_goal[sl]
	var lq: int = PathGrid.limit_q_of(_t_mask[sl])
	var rs: int = clusters.slot_for(_t_mask[sl])
	if _t_splice[sl] != 0:
		_join_e = cache.lookup(PathCache.key_of(s, g, _t_mask[sl]), grid)
		if _join_e >= 0:
			_join_k = cache.exit_index(_join_e)
			var cost: int = clusters.mark_around(s, rs)
			grid.begin(s, cache.cells[_join_e * PathCache.STRIDE + _join_k], lq, true)
			_phase = _PH_SPLICE
			return cost
		splice_misses += 1
		_t_splice[sl] = 0
	var units: int = clusters.ensure_labels(rs, PathGrid.cluster_of(s)) + clusters.ensure_labels(rs, PathGrid.cluster_of(g))
	var r_s: int = clusters.region_of(s, rs)
	var r_g: int = clusters.region_of(g, rs)
	if r_g < 0:
		_finish(sl, ST_NO_PATH, 0)
		return units
	var near: bool = grid.center_dir(s).angle_to(grid.center_dir(g)) <= float(hier_min_cells) * PI * 0.5 / float(PathGrid.N)
	if r_s == r_g:                                   # same region: a route exists inside it and its neighbours
		units += clusters.ensure_links(rs, r_s >> 3)
		clusters.mark_region(r_s, rs)
		grid.begin(s, g, lq, true)
		_phase = _PH_CORRIDOR
	elif r_s < 0 or near:
		grid.begin(s, g, lq, false)
		_phase = _PH_FULL
	else:
		clusters.begin(r_g, r_s, grid.center_dir(s), rs)
		_phase = _PH_ABSTRACT
	return units


func _step_job(sl: int, budget: int) -> int:
	if _phase == _PH_ABSTRACT:
		var ua: int = clusters.run(budget)
		abstract_units += ua
		if clusters.state == PathSearch.FOUND:
			clusters.mark_corridor()
			grid.begin(_t_start[sl], _t_goal[sl], PathGrid.limit_q_of(_t_mask[sl]), true)
			_phase = _PH_CORRIDOR
		elif clusters.state == PathSearch.EXHAUSTED:
			_abstract_exhausted(sl)
		return ua
	var u: int = grid.run(budget)
	if grid.state == PathSearch.FOUND:
		_found(sl)
	elif grid.state == PathSearch.EXHAUSTED:
		_exhausted(sl)
	return u


# No region route proves no cell route (regions are a superset) unless an orphan pair broke the region graph.
func _abstract_exhausted(sl: int) -> void:
	if clusters.orphans == 0:
		_finish(sl, ST_NO_PATH, 0)
		return
	fallbacks += 1
	grid.begin(_t_start[sl], _t_goal[sl], PathGrid.limit_q_of(_t_mask[sl]), false)
	_phase = _PH_FULL


func _exhausted(sl: int) -> void:
	if _phase == _PH_FULL:
		_finish(sl, ST_NO_PATH, 0)
		return
	if _phase == _PH_SPLICE:
		splice_misses += 1
		_t_splice[sl] = 0
		_phase = _PH_NONE
		var _u: int = _start_job(sl)
		return
	fallbacks += 1
	grid.begin(_t_start[sl], _t_goal[sl], PathGrid.limit_q_of(_t_mask[sl]), false)
	_phase = _PH_FULL


func _found(sl: int) -> void:
	var base: int = sl * MAX_CELLS
	if _phase == _PH_SPLICE:
		var key: int = PathCache.key_of(_t_start[sl], _t_goal[sl], _t_mask[sl])
		var n1: int = grid.write_path(_t_cells, base, MAX_CELLS)
		var tail: int = cache.length[_join_e] - _join_k - 1
		if cache.lookup(key, grid) != _join_e or n1 < 0 or n1 + tail > MAX_CELLS:
			_exhausted(sl)
			return
		_copy_cached(sl, n1, _join_e, _join_k + 1)
		_finish(sl, ST_DONE, n1 + tail)
		return
	var n: int = grid.write_path(_t_cells, base, MAX_CELLS)
	if n < 0:
		_finish(sl, ST_NO_PATH, 0)
		return
	var _c: bool = cache.insert(PathCache.key_of(_t_start[sl], _t_goal[sl], _t_mask[sl]), _t_cells, base, n, grid)
	_finish(sl, ST_DONE, n)


func _copy_cached(sl: int, at: int, e: int, from: int) -> void:
	var dst: int = sl * MAX_CELLS + at
	var seg: PackedInt32Array = cache.segment(e, from)
	for k: int in seg.size():
		_t_cells[dst + k] = seg[k]


func _finish(sl: int, st: int, n: int) -> void:
	_t_state[sl] = st
	_t_len[sl] = n
	_t_done_tick[sl] = ticks
	_phase = _PH_NONE


## S4 (TA-50): counters, tickets and queue, each ticket's result cells, then the grid (changed weights, labels, the
## cell search in flight), the region graphs (and the region search in flight) and the cache. Read it into a Pathing
## that loaded the same map (load_weights, set_terrain); prepare is not needed, the graphs are in the bytes.
func write_state(buf: StreamPeerBuffer) -> void:
	super.write_state(buf)
	StateIO.put_props(buf, self, _STATE)
	grid.write_state(buf)
	clusters.write_state(buf)
	cache.write_state(buf)


func read_state(buf: StreamPeerBuffer) -> bool:
	if not super.read_state(buf) or not StateIO.get_props(buf, self, _STATE):
		return false
	return grid.read_state(buf) and clusters.read_state(buf) and cache.read_state(buf)
