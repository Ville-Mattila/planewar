class_name Pathing extends RefCounted
## Time-sliced A* on the 6 x 256^2 path grid (ADR-05, 03 s3.6, R0 C1-05; S-NAV-1 = TA-20). `request` queues a
## query and returns a ticket; `advance()` runs once per tick (step 3b) and spends at most `expansions_per_tick`
## expansion units on the open tickets in FIFO order (one search in flight); `result` is empty until the ticket is
## DONE. A query whose ends lie in different regions (PathRegions: connected parts of 16 x 16-cell clusters) first
## searches the region graph goal -> start (PathClusters; exhaustion proves NO_PATH) and then the cell grid inside the
## region corridor; a corridor miss (only after a region OVERFLOW) falls back to the unrestricted grid search, so the
## hierarchy never changes reachability. The route cache (PathCache) answers a repeated (start cluster, goal cell, mask) at once
## for the same start cell, or by splicing a short local search onto the cached route for another start cell.
## Deterministic: integer budget, no clock, no RNG; Dictionary used for lookups only. No Nodes, no allocation per
## expansion. Request masks: bits 0-7 = the unit's max slope in whole degrees (0 = weights only), see mask_for.

const NO_TICKET: int = -1
const ST_UNKNOWN: int = 0                  ## stale or never issued ticket
const ST_PENDING: int = 1
const ST_DONE: int = 2
const ST_NO_PATH: int = 3
const MAX_TICKETS: int = 160               ## 03 s3.2 path_tickets row
const MAX_CELLS: int = PathGrid.N * 4      ## longest result in cells
const _PH_NONE: int = 0
const _PH_ABSTRACT: int = 1
const _PH_CORRIDOR: int = 2
const _PH_FULL: int = 3
const _PH_SPLICE: int = 4
const _GEN_SHIFT: int = 8
const JOB_COST: int = 8                    ## units charged per job start (region lookups, corridor stamping, finish)

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
var _t_gen: PackedInt32Array = PackedInt32Array()
var _t_state: PackedInt32Array = PackedInt32Array()
var _t_start: PackedInt32Array = PackedInt32Array()
var _t_goal: PackedInt32Array = PackedInt32Array()
var _t_mask: PackedInt32Array = PackedInt32Array()
var _t_len: PackedInt32Array = PackedInt32Array()
var _t_seq: PackedInt32Array = PackedInt32Array()
var _t_req_tick: PackedInt32Array = PackedInt32Array()
var _t_done_tick: PackedInt32Array = PackedInt32Array()
var _t_splice: PackedByteArray = PackedByteArray()
var _t_queued: PackedByteArray = PackedByteArray()   ## 1 while the slot sits in the FIFO (never re-allocated then)
var _t_cells: PackedInt32Array = PackedInt32Array()  ## MAX_TICKETS * MAX_CELLS
var _q: PackedInt32Array = PackedInt32Array()
var _qh: int = 0
var _qn: int = 0
var _seq: int = 0
var _phase: int = _PH_NONE
var _join_e: int = -1
var _join_k: int = 0


func _init(expansions: int) -> void:
	expansions_per_tick = expansions
	assert(expansions > JOB_COST, "Pathing: budget must exceed one job start")
	var _r: int = _t_gen.resize(MAX_TICKETS)
	_r = _t_state.resize(MAX_TICKETS)
	_r = _t_start.resize(MAX_TICKETS)
	_r = _t_goal.resize(MAX_TICKETS)
	_r = _t_mask.resize(MAX_TICKETS)
	_r = _t_len.resize(MAX_TICKETS)
	_r = _t_seq.resize(MAX_TICKETS)
	_r = _t_req_tick.resize(MAX_TICKETS)
	_r = _t_done_tick.resize(MAX_TICKETS)
	_r = _t_splice.resize(MAX_TICKETS)
	_r = _t_queued.resize(MAX_TICKETS)
	_r = _t_cells.resize(MAX_TICKETS * MAX_CELLS)
	_r = _q.resize(MAX_TICKETS)


## Loads the six baked `face<f>.path.u8` faces of `map_dir`, each SHA-256 checked against meta.json (as Terrain).
func load_weights(map_dir: String) -> Error:
	var all: PackedByteArray = PathGrid.read_faces(map_dir)
	if all.is_empty():
		return ERR_FILE_CORRUPT
	return OK if set_weights(all) else ERR_INVALID_DATA


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


func status(ticket: int) -> int:
	var sl: int = _slot(ticket)
	return _t_state[sl] if sl >= 0 else ST_UNKNOWN


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


## advance() count at which the ticket completed (-1 while pending or unknown); request tick via request_tick.
func done_tick(ticket: int) -> int:
	var sl: int = _slot(ticket)
	return _t_done_tick[sl] if sl >= 0 and _t_state[sl] >= ST_DONE else -1


func request_tick(ticket: int) -> int:
	var sl: int = _slot(ticket)
	return _t_req_tick[sl] if sl >= 0 else -1


## Frees the ticket (a pending query is dropped); the handle turns ST_UNKNOWN.
func release(ticket: int) -> void:
	var sl: int = _slot(ticket)
	if sl >= 0:
		_t_state[sl] = ST_UNKNOWN
		_t_gen[sl] = (_t_gen[sl] + 1) & 0xFFFFF


func pending() -> int:  # queued tickets
	return _qn


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


func _slot(ticket: int) -> int:
	if ticket < 0:
		return -1
	var sl: int = ticket & ((1 << _GEN_SHIFT) - 1)
	if sl >= MAX_TICKETS or (ticket >> _GEN_SHIFT) != _t_gen[sl] or _t_state[sl] == ST_UNKNOWN:
		return -1
	return sl


# A free slot, else the oldest finished one (its handle turns stale), else -1.
func _alloc() -> int:
	var best: int = -1
	for sl: int in MAX_TICKETS:
		var st: int = _t_state[sl]
		if _t_queued[sl] != 0:
			continue
		if st == ST_UNKNOWN:
			best = sl
			break
		if st != ST_PENDING and (best < 0 or _t_seq[sl] < _t_seq[best]):
			best = sl
	if best < 0:
		return -1
	if _t_state[best] != ST_UNKNOWN:
		_t_gen[best] = (_t_gen[best] + 1) & 0xFFFFF
	_seq += 1
	_t_seq[best] = _seq
	_t_state[best] = ST_PENDING
	_t_done_tick[best] = -1
	return best


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
