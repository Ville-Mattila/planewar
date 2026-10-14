extends GdUnitTestSuite
## Unit tests for sim/pathing (TA-20, S-NAV-1; 03 s3.6, R0 C1-05): optimality against brute-force Dijkstra on small
## grids (in-face, across a cube edge, at a cube corner), slope-blocked cells, ticket FIFO fairness, the per-tick
## expansion cap, hierarchy consistency (P1-P8 in sim/pathing/MODULE.md), route cache and determinism.

const R: float = Sphere.PLANET_RADIUS
const N: int = Sphere.GRID_PATH
const BIG: int = 1000000


# region helpers
## A Pathing whose only passable cells are `region` (weights from rng 1..5 when `noisy`).
func _window(region: PackedInt32Array, rng: Rng, noisy: bool, budget: int = BIG) -> Pathing:
	var p: Pathing = Pathing.new(budget)
	var w: PackedByteArray = PackedByteArray()
	var _r: int = w.resize(PathGrid.CELLS)
	w.fill(PathGrid.W_BLOCKED)
	for c: int in region:
		w[c] = rng.range_i(1, 5) if noisy else 1
	assert_bool(p.set_weights(w)).is_true()
	return p


func _dir(cell: int) -> Vector3:
	return Sphere.cell_center_dir(cell, N) * R


func _solve(p: Pathing, s: int, g: int, mask: int) -> int:
	var tk: int = p.request(_dir(s), _dir(g), mask)
	var guard: int = 0
	while p.status(tk) == Pathing.ST_PENDING and guard < 100000:
		var _u: int = p.advance()
		guard += 1
	return tk


func _corner_cell() -> int:
	return Sphere.cell_of(Vector3(1, 1, 1), N)


func _edge_cell() -> int:
	return Sphere.cell_of(Vector3(1, 1, 0.2), N)


## Exact flat A* (no inflation, no region layer) equals brute-force Dijkstra on random weights.
func _check_optimal(centre: int, seed_v: int) -> void:
	var rng: Rng = Rng.new(seed_v)
	var region: PackedInt32Array = NavTestKit.region_around(centre, 9)
	var p: Pathing = _window(region, rng, true)
	p.set_heuristic_pct(0)
	p.hier_min_cells = BIG
	for q: int in 6:
		var s: int = region[rng.range_i(0, region.size() - 1)]
		var g: int = region[rng.range_i(0, region.size() - 1)]
		var tk: int = _solve(p, s, g, 0)
		var best: float = NavTestKit.dijkstra(p, region, s, g, 0)
		assert_int(p.status(tk)).is_equal(Pathing.ST_DONE if best >= 0.0 else Pathing.ST_NO_PATH)
		if best >= 0.0:
			var cells: PackedInt32Array = p.result_cells(tk)
			assert_str(NavTestKit.validate(p, cells, s, g, 0)).is_equal("")
			assert_float(NavTestKit.cost_of(p, cells)).is_equal_approx(best, best * 1e-4 + 1e-3)
		p.release(tk)
# endregion


func test_optimal_vs_brute_force_inside_a_face() -> void:
	_check_optimal(Sphere.cell_of(Vector3(1, 0.1, 0.2), N), 1)


func test_optimal_vs_brute_force_across_a_cube_edge() -> void:
	_check_optimal(_edge_cell(), 2)


func test_optimal_vs_brute_force_at_a_cube_corner() -> void:
	_check_optimal(_corner_cell(), 3)


func test_inflated_and_hierarchical_paths_stay_within_bound() -> void:
	var rng: Rng = Rng.new(4)
	var region: PackedInt32Array = NavTestKit.region_around(_edge_cell(), 12)
	var p: Pathing = _window(region, rng, true)
	p.set_heuristic_pct(25)
	for q: int in 6:
		var s: int = region[rng.range_i(0, region.size() - 1)]
		var g: int = region[rng.range_i(0, region.size() - 1)]
		var tk: int = _solve(p, s, g, 0)
		var best: float = NavTestKit.dijkstra(p, region, s, g, 0)
		var cells: PackedInt32Array = p.result_cells(tk)
		assert_str(NavTestKit.validate(p, cells, s, g, 0)).is_equal("")
		# w-A* bound (1.25) times the corridor restriction; measured <= 1.10 on these fixtures
		assert_float(NavTestKit.cost_of(p, cells)).is_less_equal(best * 1.3 + 1e-3)
		p.release(tk)


func test_paths_cross_cube_edges_and_corners_continuously() -> void:
	var p: Pathing = Pathing.new(BIG)
	var pairs: Array[Vector3] = [Vector3(1, 0.5, 0.95), Vector3(0.95, 0.5, 1),     # face 0 -> 4 over an edge
		Vector3(1, 0.97, 0.9), Vector3(0.9, 1, 0.97),                                # around the (+,+,+) corner
		Vector3(1, 0.98, 0.98), Vector3(0.98, 0.98, 1)]
	for k: int in range(0, pairs.size(), 2):
		var s: int = Sphere.cell_of(pairs[k], N)
		var g: int = Sphere.cell_of(pairs[k + 1], N)
		var tk: int = _solve(p, s, g, 0)
		var cells: PackedInt32Array = p.result_cells(tk)
		assert_str(NavTestKit.validate(p, cells, s, g, 0)).is_equal("")
		assert_int(cells[0] >> 16).is_not_equal(cells[cells.size() - 1] >> 16)
		var pts: PackedVector3Array = p.result(tk)
		assert_int(pts.size()).is_equal(cells.size())
		for i: int in range(1, pts.size()):
			assert_float(pts[i].distance_to(pts[i - 1])).is_less(60.0)   # continuous: one cell step (<= 52 m)
			assert_float(pts[i].length()).is_equal_approx(R, 0.01)


func test_slope_blocked_cells_respect_the_mask() -> void:
	var p: Pathing = Pathing.new(BIG)
	var centre: int = Sphere.cell_of(Vector3(1, 0.1, 0.1), N)
	var wall: PackedInt32Array = PackedInt32Array()
	for k: int in range(-12, 13):
		var _a: bool = wall.push_back(centre + k * N)            # a 25-cell wall along v at fixed i
	for c: int in wall:
		p.override_slope(c, 22)
	var s: int = centre - 4
	var g: int = centre + 4
	var steep: int = _solve(p, s, g, Pathing.mask_for(20.0))      # crawler: 22 deg is impassable
	var cells: PackedInt32Array = p.result_cells(steep)
	assert_str(NavTestKit.validate(p, cells, s, g, Pathing.mask_for(20.0))).is_equal("")
	for c: int in cells:
		assert_bool(wall.has(c)).is_false()
	assert_int(cells.size()).is_greater(20)                      # detour round the wall end
	var ok: int = _solve(p, s, g, Pathing.mask_for(25.0))         # harvester: 22 deg is fine
	assert_int(p.result_cells(ok).size()).is_equal(9)


func test_unreachable_goal_answers_no_path_from_the_region_layer() -> void:
	var p: Pathing = Pathing.new(200)
	var g: int = Sphere.cell_of(Vector3(1, -0.3, 0.4), N)
	for c: int in NavTestKit.region_around(g, 2):
		if c != g and NavTestKit.region_around(g, 1).find(c) < 0:
			p.set_weight(c, PathGrid.W_BLOCKED)                   # a sealed ring two cells out
	var tk: int = p.request(_dir(Sphere.cell_of(Vector3(1, 0.4, -0.4), N)), _dir(g), 0)
	var ticks: int = 0
	while p.status(tk) == Pathing.ST_PENDING:
		var _u: int = p.advance()
		ticks += 1
	assert_int(p.status(tk)).is_equal(Pathing.ST_NO_PATH)
	assert_int(ticks).is_less_equal(30)                          # the pocket exhausts, not the whole sphere
	assert_bool(p.result(tk).is_empty()).is_true()


func test_tickets_complete_in_fifo_order() -> void:
	var p: Pathing = Pathing.new(60)
	var rng: Rng = Rng.new(9)
	var tickets: PackedInt32Array = PackedInt32Array()
	for k: int in 12:
		var a: Vector3 = Sphere.from_lat_lon(rng.range_f(-0.5, 0.5), rng.range_f(-PI, PI), R)
		var b: Vector3 = Sphere.from_lat_lon(rng.range_f(-0.5, 0.5), rng.range_f(-PI, PI), R)
		var _x: bool = tickets.push_back(p.request(a, b, 0))
	for tk: int in tickets:
		assert_int(p.status(tk)).is_equal(Pathing.ST_PENDING)
		assert_bool(p.result(tk).is_empty()).is_true()
	var guard: int = 0
	while p.pending() > 0 and guard < 100000:
		var _u: int = p.advance()
		guard += 1
	var last: int = -1
	for tk: int in tickets:
		assert_int(p.status(tk)).is_equal(Pathing.ST_DONE)
		assert_int(p.done_tick(tk)).is_greater_equal(last)      # no ticket overtakes an earlier one
		last = p.done_tick(tk)


func test_release_drops_a_pending_ticket_and_stales_the_handle() -> void:
	var p: Pathing = Pathing.new(50)
	var a: int = p.request(Sphere.from_lat_lon(0.0, 0.0, R), Sphere.from_lat_lon(0.4, 1.0, R), 0)
	var b: int = p.request(Sphere.from_lat_lon(0.1, 0.0, R), Sphere.from_lat_lon(0.1, 0.05, R), 0)
	p.release(a)
	assert_int(p.status(a)).is_equal(Pathing.ST_UNKNOWN)
	while p.status(b) == Pathing.ST_PENDING:
		var _u: int = p.advance()
	assert_int(p.status(b)).is_equal(Pathing.ST_DONE)
	assert_int(p.done_tick(b)).is_less_equal(10)                 # the released long query did not hold it up
	assert_int(p.status(Pathing.NO_TICKET)).is_equal(Pathing.ST_UNKNOWN)


func test_per_tick_expansion_cap_is_respected() -> void:
	var cap: int = 90
	var p: Pathing = Pathing.new(cap)
	var rng: Rng = Rng.new(11)
	p.prepare(0)
	for k: int in 30:
		var a: Vector3 = Sphere.from_lat_lon(rng.range_f(-1.2, 1.2), rng.range_f(-PI, PI), R)
		var b: Vector3 = Sphere.from_lat_lon(rng.range_f(-1.2, 1.2), rng.range_f(-PI, PI), R)
		var _t: int = p.request(a, b, 0)
	var total: int = 0
	while p.pending() > 0:
		var u: int = p.advance()
		assert_int(u).is_less_equal(cap)
		total += u
	assert_int(total).is_equal(p.expansions_total)


func test_region_graph_is_consistent_with_cell_adjacency() -> void:
	var p: Pathing = Pathing.new(BIG)
	assert_bool(p.set_weights(NavTestKit.rough_weights(5, 150, 60))).is_true()
	p.prepare(0)
	assert_int(p.clusters.orphans).is_equal(0)                  # every cross-border pair maps to a cluster neighbour
	var rng: Rng = Rng.new(5)
	var sl: int = p.clusters.slot_for(0)
	for q: int in 40:                                            # a region link implies a real cell step and back
		var c: int = rng.range_i(0, PathSearch.CLUSTERS - 1)
		for r: int in p.clusters.region_count(c, sl):
			for k: int in 8:
				var bits: int = p.clusters.adjacency(c * PathSearch.MAX_REG + r, k, sl)
				var b: int = p.clusters.neighbour(c, k)
				for rb: int in PathSearch.MAX_REG:
					if ((bits >> rb) & 1) != 0:
						var back: int = -1
						for kb: int in 8:
							if p.clusters.neighbour(b, kb) == c:
								back = kb
						assert_int((p.clusters.adjacency(b * PathSearch.MAX_REG + rb, back, sl) >> r) & 1).is_equal(1)
	for q: int in 30:                                            # NO_PATH exactly when unreachable
		var s: int = Sphere.cell_of(Sphere.from_lat_lon(rng.range_f(-1.4, 1.4), rng.range_f(-PI, PI), 1.0), N)
		var g: int = s + rng.range_i(-3, 3) * N + rng.range_i(-40, 40)
		if g < 0 or g >= PathGrid.CELLS or not p.grid.passable(g, PathGrid.SLOPE_NO_LIMIT):
			continue
		var tk: int = _solve(p, s, g, 0)
		var reach: bool = NavTestKit.reachable(p, s, g, 0)
		assert_int(p.status(tk)).is_equal(Pathing.ST_DONE if reach else Pathing.ST_NO_PATH)
		if reach:
			assert_str(NavTestKit.validate(p, p.result_cells(tk), s, g, 0)).is_equal("")
		p.release(tk)
	assert_int(p.fallbacks).is_equal(0)


func test_route_cache_hits_and_set_weight_invalidates() -> void:
	var p: Pathing = Pathing.new(BIG)
	var a: Vector3 = Sphere.from_lat_lon(0.05, 0.3, R)
	var b: Vector3 = Sphere.from_lat_lon(0.08, 0.36, R)
	var t1: int = _solve(p, PathGrid.cell_of(a), PathGrid.cell_of(b), 0)
	var cells: PackedInt32Array = p.result_cells(t1)
	var t2: int = p.request(a, b, 0)                             # same start cell: answered at once
	assert_int(p.status(t2)).is_equal(Pathing.ST_DONE)
	assert_array(p.result_cells(t2)).is_equal(cells)
	assert_int(p.cache_hits).is_equal(1)
	var other: int = cells[0] + 1 if PathGrid.cluster_of(cells[0] + 1) == PathGrid.cluster_of(cells[0]) else cells[0] - 1
	var t3: int = _solve(p, other, PathGrid.cell_of(b), 0)        # same cluster, other start cell: spliced
	assert_int(p.cache_hits).is_equal(2)
	assert_str(NavTestKit.validate(p, p.result_cells(t3), other, PathGrid.cell_of(b), 0)).is_equal("")
	var face: int = cells[cells.size() >> 1] >> 16
	var v0: int = p.version(face)
	p.set_weight(cells[cells.size() >> 1], PathGrid.W_BLOCKED)
	assert_int(p.version(face)).is_equal(v0 + 1)
	assert_int(p.weight(cells[cells.size() >> 1])).is_equal(PathGrid.W_BLOCKED)
	var t4: int = _solve(p, PathGrid.cell_of(a), PathGrid.cell_of(b), 0)
	assert_int(p.cache_hits).is_equal(2)                         # stale entry dropped
	assert_bool(p.result_cells(t4).has(cells[cells.size() >> 1])).is_false()


func test_identical_requests_give_identical_results_and_tick_split() -> void:
	var runs: Array[PackedInt32Array] = []
	for run: int in 2:
		var p: Pathing = Pathing.new(70)
		assert_bool(p.set_weights(NavTestKit.rough_weights(8, 60, 20))).is_true()
		p.set_heuristic_pct(25)
		var rng: Rng = Rng.new(13)
		var trace: PackedInt32Array = PackedInt32Array()
		var tickets: PackedInt32Array = PackedInt32Array()
		for k: int in 10:
			var a: Vector3 = Sphere.from_lat_lon(rng.range_f(-1.0, 1.0), rng.range_f(-PI, PI), R)
			var b: Vector3 = Sphere.from_lat_lon(rng.range_f(-1.0, 1.0), rng.range_f(-PI, PI), R)
			var _x: bool = tickets.push_back(p.request(a, b, Pathing.mask_for(25.0 if k % 2 == 0 else 20.0)))
		while p.pending() > 0:
			var _y: bool = trace.push_back(p.advance())
		for tk: int in tickets:
			trace.append_array(p.result_cells(tk))
		runs.append(trace)
	assert_array(runs[0]).is_equal(runs[1])


func test_mask_for_and_queue_limit() -> void:
	assert_int(Pathing.mask_for(25.0)).is_equal(25)
	assert_int(Pathing.mask_for(20.7)).is_equal(20)
	assert_int(PathGrid.limit_q_of(0)).is_equal(PathGrid.SLOPE_NO_LIMIT)
	var p: Pathing = Pathing.new(50)
	for k: int in Pathing.MAX_TICKETS:
		assert_int(p.request(Sphere.from_lat_lon(0.0, 0.0, R), Sphere.from_lat_lon(0.3, 0.3 + k * 0.001, R), 0)).is_not_equal(Pathing.NO_TICKET)
	assert_int(p.request(Sphere.from_lat_lon(0.0, 0.0, R), Sphere.from_lat_lon(0.3, 0.2, R), 0)).is_equal(Pathing.NO_TICKET)
