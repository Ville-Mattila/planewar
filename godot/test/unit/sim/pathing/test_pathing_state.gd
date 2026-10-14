extends GdUnitTestSuite
## TA-50 (R0 B.11 A-55): Pathing's S4 bytes (tickets, queue, the cell / region search in flight, region graphs,
## cache, changed weights) round-trip mid-search and the restored copy continues byte for byte; the u8 parent
## encoding rests on neighbours8 being symmetric; the memory row after the REPORT s6 reductions (03 s11.3: ~6 MB).

const R: float = Sphere.PLANET_RADIUS
const N: int = PathGrid.N
const MAP_DIR: String = "res://content/maps/tiny_test"
const MB: float = 1048576.0


func _bytes(p: Pathing) -> PackedByteArray:
	var buf: StreamPeerBuffer = StreamPeerBuffer.new()
	p.write_state(buf)
	return buf.data_array


func _restore(bytes: PackedByteArray, budget: int) -> Pathing:
	var p: Pathing = Pathing.new(budget)
	var buf: StreamPeerBuffer = StreamPeerBuffer.new()
	buf.data_array = bytes
	return p if p.read_state(buf) else null


func _dir(lat: float, lon: float) -> Vector3:
	return Sphere.from_lat_lon(deg_to_rad(lat), deg_to_rad(lon), R)


# Every cell within two of a face edge (the cube-edge cases) plus a stride of interior cells: n = nb(c)[k] implies
# c = nb(n)[back], with back = PathSearch._INV[k] whenever c is interior (the in-face fast path of _expand).
func test_neighbours_are_symmetric_so_u8_parents_resolve() -> void:
	var g: PathGrid = PathGrid.new()
	var inv: PackedInt32Array = [1, 0, 3, 2, 7, 6, 5, 4]
	var checked: int = 0
	for c: int in PathGrid.CELLS:
		var i: int = c & PathGrid.LOW
		var j: int = (c >> PathGrid.SHIFT) & PathGrid.LOW
		var near_edge: bool = i < 2 or i > PathGrid.LOW - 2 or j < 2 or j > PathGrid.LOW - 2
		if not near_edge and c % 97 != 0:
			continue
		var interior: bool = i > 0 and i < PathGrid.LOW and j > 0 and j < PathGrid.LOW
		g.neighbours(c)
		var mine: PackedInt32Array = g.nb.duplicate()
		for k: int in 8:
			if mine[k] < 0:
				continue
			g.neighbours(mine[k])
			checked += 1
			if g.nb.find(c) < 0 or (interior and g.nb[inv[k]] != c):
				fail("cell %d dir %d -> %d has no way back" % [c, k, mine[k]])
				return
	assert_int(checked).is_greater(90000)


# Requests of mixed length on a walled flat grid; saved every tick (and restored every third) while searches are in
# flight: the restored Pathing writes the same bytes and, advanced in lockstep, the same results.
func test_state_round_trip_mid_search_continues_identically() -> void:
	var a: Pathing = Pathing.new(120)
	a.set_heuristic_pct(25)
	var wall: int = PathGrid.cell_of(_dir(0.0, 2.0))
	for k: int in 60:
		a.set_weight(wall - 30 * N + k * N, PathGrid.W_BLOCKED)
	var ends: PackedVector3Array = [_dir(0.0, 0.0), _dir(0.5, 4.0), _dir(-1.0, 3.0), _dir(0.2, 0.3), _dir(2.0, 5.0)]
	var b: Pathing = null
	var live: int = 0
	for t: int in 90:
		if t % 4 == 0:
			for p: Pathing in ([a] if b == null else [a, b]) as Array[Pathing]:
				var _tk: int = p.request(ends[t % 5], ends[(floori(float(t) / 4.0) + 2) % 5], 0 if t % 8 == 0 else 20)
		var sa: PackedByteArray = _bytes(a)
		if b != null and _bytes(b) != sa:
			fail("divergence before tick %d" % t)
			return
		if t % 3 == 0:
			if a.grid.state == PathSearch.RUNNING or a.clusters.state == PathSearch.RUNNING:
				live += 1
			b = _restore(sa, 120)
			assert_object(b).is_not_null()
			assert_bool(_bytes(b) == sa).is_true()
		assert_int(b.advance()).is_equal(a.advance())
	assert_int(live).is_greater(0)
	assert_int(a.requests).is_equal(b.requests)
	assert_bool(a.grid.weights_custom).is_true()


func test_truncated_or_foreign_state_is_rejected() -> void:
	var a: Pathing = Pathing.new(120)
	var _tk: int = a.request(_dir(0.0, 0.0), _dir(1.0, 1.0), 0)
	var _u: int = a.advance()
	var bytes: PackedByteArray = _bytes(a)
	assert_object(_restore(bytes.slice(0, floori(float(bytes.size()) / 3.0)), 120)).is_null()
	assert_object(_restore(PackedByteArray([1, 2, 3, 4]), 120)).is_null()
	assert_object(_restore(bytes, 120)).is_not_null()


# 03 s11.3 row (A-55: re-baselined to the measurement): static memory of one Pathing with the map's weights, the
# terrain slope source and both v1 ground-unit masks prepared. REPORT before the cuts: 8.8 MB.
func test_mem_mb_after_load_and_prepare_is_at_most_6() -> void:
	var terrain: Terrain = Terrain.new()
	assert_int(terrain.load_map(MAP_DIR)).is_equal(OK)
	var m0: float = Performance.get_monitor(Performance.MEMORY_STATIC)
	var p: Pathing = Pathing.new(120)
	assert_int(p.load_weights(MAP_DIR)).is_equal(OK)
	p.set_terrain(terrain)
	p.prepare(Pathing.mask_for(25.0))
	p.prepare(Pathing.mask_for(20.0))
	var mem_mb: float = (Performance.get_monitor(Performance.MEMORY_STATIC) - m0) / MB
	print("TA50_MEM mem_mb=%.2f" % mem_mb)
	assert_float(mem_mb).is_less_equal(6.0)
	assert_float(mem_mb).is_greater(2.0)                   # the measurement saw the arrays at all
