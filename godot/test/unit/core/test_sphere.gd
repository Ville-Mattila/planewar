extends GdUnitTestSuite
## Unit tests for core/sphere.gd: 03 s2.8 vectors, C1-C5 property tests (10,000 random dirs), C8, C9.

const DIR_EPS: float = 1e-6
const M_EPS: float = 1e-3
const PROPERTY_SAMPLES: int = 10000
const GRIDS: Array[int] = [Sphere.GRID_BUILD, Sphere.GRID_PATH, Sphere.GRID_HASH, Sphere.GRID_INTEREST]


func _rand_dir(rng: Rng) -> Vector3:
	# Uniform on the sphere (Archimedes): z uniform in [-1, 1], longitude uniform.
	var z: float = rng.range_f(-1.0, 1.0)
	var lon: float = rng.range_f(-PI, PI)
	var r: float = sqrt(maxf(0.0, 1.0 - z * z))
	return Vector3(r * cos(lon), r * sin(lon), z)


func _cell(face: int, i: int, j: int, n: int) -> int:
	return face * n * n + j * n + i


func _assert_dir(actual: Vector3, expected: Vector3, eps: float = DIR_EPS) -> void:
	assert_float(actual.distance_to(expected)).is_less(eps)


# --- 2.8 vectors -------------------------------------------------------------

func test_face_uv_to_dir_vectors() -> void:
	_assert_dir(Sphere.face_uv_to_dir(0, 0.5, 0.5), Vector3(1, 0, 0))
	_assert_dir(Sphere.face_uv_to_dir(0, 0.0, 0.0), Vector3(0.577350, -0.577350, -0.577350), 2e-6)
	_assert_dir(Sphere.face_uv_to_dir(0, 1.0, 0.5), Vector3(0.707107, 0.707107, 0), 2e-6)
	_assert_dir(Sphere.face_uv_to_dir(4, 0.5, 0.5), Vector3(0, 0, 1))
	_assert_dir(Sphere.face_uv_to_dir(2, 0.75, 0.25), Vector3(-0.357407, 0.862856, 0.357407), 2e-6)
	_assert_dir(Sphere.face_uv_to_dir(5, 0.1, 0.9), Vector3(0.506732, -0.506732, -0.697457), 2e-6)


func test_dir_to_face_uv_round_trips_the_vectors() -> void:
	var triples: Array[Vector3] = [Vector3(0, 0.5, 0.5), Vector3(0, 0.0, 0.0), Vector3(0, 1.0, 0.5),
		Vector3(4, 0.5, 0.5), Vector3(2, 0.75, 0.25), Vector3(5, 0.1, 0.9)]
	for t: Vector3 in triples:
		var d: Vector3 = Sphere.face_uv_to_dir(int(t.x), t.y, t.z)
		var back: Vector3 = Sphere.dir_to_face_uv(d)
		# Edge and corner points belong to the lower face index (03 s2.5 tie rule); compare directions there.
		if int(back.x) == int(t.x):
			assert_float(absf(back.y - t.y)).is_less(DIR_EPS)
			assert_float(absf(back.z - t.z)).is_less(DIR_EPS)
		_assert_dir(Sphere.face_uv_to_dir(int(back.x), back.y, back.z), d)


func test_great_circle_vectors() -> void:
	var r: float = Sphere.PLANET_RADIUS
	assert_float(Sphere.great_circle(Vector3(r, 0, 0), Vector3(0, r, 0))).is_equal_approx(9424.778, M_EPS)
	assert_float(Sphere.great_circle(Vector3(r, 0, 0), Vector3(r, 0, 0))).is_equal(0.0)
	var p: Vector3 = Sphere.from_lat_lon(0.3, 1.1, r)
	var east: Vector3 = Sphere.tangent_frame(p).x
	assert_float(Sphere.great_circle(p, p + east * 3.7)).is_equal_approx(3.7, M_EPS)
	# Half circumference is stable (atan2 form).
	assert_float(Sphere.great_circle(Vector3(r, 0, 0), Vector3(-r, 0, 0))).is_equal_approx(PI * r, M_EPS)


func test_transport_vectors() -> void:
	var q: Quaternion = Sphere.transport(Vector3(1, 0, 0), Vector3(0, 1, 0))
	assert_float(absf(q.x) + absf(q.y)).is_less(DIR_EPS)
	assert_float(q.z).is_equal_approx(0.707107, DIR_EPS)
	assert_float(q.w).is_equal_approx(0.707107, DIR_EPS)
	_assert_dir(q * Vector3(0, 1, 0), Vector3(-1, 0, 0))
	var n2: Vector3 = Vector3(1, 0.001, 0).normalized()
	var q2: Quaternion = Sphere.transport(Vector3(1, 0, 0), n2)
	assert_float(q2.z).is_equal_approx(0.0005, DIR_EPS)
	assert_float(q2.w).is_equal_approx(1.0, DIR_EPS)
	_assert_dir(q2 * Vector3(1, 0, 0), n2)
	assert_bool(Sphere.transport(n2, n2).is_equal_approx(Quaternion.IDENTITY)).is_true()


func test_tangent_frame_vectors() -> void:
	var r: float = Sphere.PLANET_RADIUS
	var b: Basis = Sphere.tangent_frame(Vector3(r, 0, 0))
	_assert_dir(b.x, Vector3(0, 1, 0))
	_assert_dir(b.y, Vector3(0, 0, 1))
	_assert_dir(b.z, Vector3(1, 0, 0))
	var pole: Basis = Sphere.tangent_frame(Vector3(0, 0, r))
	_assert_dir(pole.z, Vector3(0, 0, 1))
	assert_bool(pole.x.is_finite() and pole.y.is_finite()).is_true()
	assert_float((pole.transposed() * pole).determinant()).is_equal_approx(1.0, DIR_EPS)
	assert_float(absf(pole.x.dot(pole.y)) + absf(pole.x.dot(pole.z)) + absf(pole.y.dot(pole.z))).is_less(DIR_EPS)


func test_lat_lon_and_altitude() -> void:
	var r: float = Sphere.PLANET_RADIUS
	var ll: Vector2 = Sphere.lat_lon(Vector3(0, r, 0))
	assert_float(ll.x).is_equal_approx(0.0, DIR_EPS)
	assert_float(ll.y).is_equal_approx(PI / 2.0, DIR_EPS)
	assert_float(Sphere.altitude(Vector3(0, 0, r + 120.0))).is_equal_approx(120.0, M_EPS)
	_assert_dir(Sphere.up_at(Vector3(0, -3, 0)), Vector3(0, -1, 0))
	var p: Vector3 = Sphere.from_lat_lon(-0.4, 2.5, r)
	var back: Vector2 = Sphere.lat_lon(p)
	assert_float(back.x).is_equal_approx(-0.4, DIR_EPS)
	assert_float(back.y).is_equal_approx(2.5, DIR_EPS)


func test_cell_of_vector() -> void:
	var d: Vector3 = Sphere.face_uv_to_dir(0, 0.5, 0.5)
	var c: int = Sphere.cell_of(d, Sphere.GRID_BUILD)
	assert_int(c).is_equal(524800)
	assert_int(Sphere.cell_face(c, Sphere.GRID_BUILD)).is_equal(0)
	assert_int(Sphere.cell_i(c, Sphere.GRID_BUILD)).is_equal(512)
	assert_int(Sphere.cell_j(c, Sphere.GRID_BUILD)).is_equal(512)


func test_slot_0_and_1_face_uv() -> void:
	var s0: Vector3 = Sphere.dir_to_face_uv(Sphere.from_lat_lon(0.0, deg_to_rad(22.5), 1.0))
	assert_int(int(s0.x)).is_equal(0)
	assert_float(s0.y).is_equal_approx(0.75, DIR_EPS)
	assert_float(s0.z).is_equal_approx(0.5, DIR_EPS)
	var s1: Vector3 = Sphere.dir_to_face_uv(Sphere.from_lat_lon(0.0, deg_to_rad(67.5), 1.0))
	assert_int(int(s1.x)).is_equal(2)
	assert_float(s1.y).is_equal_approx(0.5, DIR_EPS)
	assert_float(s1.z).is_equal_approx(0.75, DIR_EPS)


func test_neighbour_cell_vectors() -> void:
	var n: int = Sphere.GRID_BUILD
	assert_int(Sphere.neighbour_cell(_cell(0, 1023, 300, n), n, 1)).is_equal(_cell(2, 300, 1023, n))
	assert_int(Sphere.neighbour_cell(_cell(4, 500, 1023, n), n, 3)).is_equal(_cell(2, 1023, 500, n))
	assert_int(Sphere.neighbour_cell(_cell(0, 10, 20, n), n, 0)).is_equal(_cell(0, 9, 20, n))


func test_neighbours8_at_cube_corner_and_interior() -> void:
	for n: int in GRIDS:
		var corner: int = _cell(0, 0, 0, n)
		var nb: PackedInt32Array = Sphere.neighbours8(corner, n)
		assert_int(nb.size()).is_equal(7)
		var seen: Dictionary[int, bool] = {}
		for c: int in nb:
			assert_int(c).is_not_equal(corner)
			seen[c] = true
		assert_int(seen.size()).is_equal(7)
		assert_int(Sphere.neighbours8(_cell(3, 2, 5, n), n).size()).is_equal(8)
		assert_int(Sphere.neighbours8(_cell(1, n - 1, 3, n), n).size()).is_equal(8)


func test_horizon_distance_vectors() -> void:
	assert_float(Sphere.horizon_distance(50.0)).is_equal_approx(776.2, 0.05)
	assert_float(Sphere.horizon_distance(100.0)).is_equal_approx(1100.0, 0.05)
	assert_float(Sphere.horizon_distance(300.0)).is_equal_approx(1920.9, 0.05)
	assert_float(Sphere.horizon_distance(1500.0)).is_equal_approx(4500.0, 0.05)


func test_is_occluded_by_datum() -> void:
	var r: float = Sphere.PLANET_RADIUS
	assert_bool(Sphere.is_occluded_by_datum(Vector3(r + 10, 0, 0), Vector3(-r - 10, 0, 0))).is_true()
	assert_bool(Sphere.is_occluded_by_datum(Vector3(r + 10, 0, 0), Vector3(r + 10, 50, 0))).is_false()
	var a: Vector3 = Sphere.from_lat_lon(0.0, 0.0, r + 100.0)
	var near: Vector3 = Sphere.from_lat_lon(0.0, 1000.0 / r, r + 100.0)
	var far: Vector3 = Sphere.from_lat_lon(0.0, 3000.0 / r, r + 100.0)
	assert_bool(Sphere.is_occluded_by_datum(a, near)).is_false()
	assert_bool(Sphere.is_occluded_by_datum(a, far)).is_true()


# --- C1-C5 property tests ----------------------------------------------------

func test_c1_round_trip_dir_cell_center_10000() -> void:
	# Property loops aggregate and assert once: per-sample asserts would dominate the suite's runtime.
	var rng: Rng = Rng.new(4, 1)
	var worst: float = 0.0
	var bad: PackedStringArray = PackedStringArray()
	for k: int in PROPERTY_SAMPLES:
		var d: Vector3 = _rand_dir(rng)
		var fuv: Vector3 = Sphere.dir_to_face_uv(d)
		worst = maxf(worst, Sphere.face_uv_to_dir(int(fuv.x), fuv.y, fuv.z).distance_to(d))
		if fuv.y < 0.0 or fuv.y > 1.0 or fuv.z < 0.0 or fuv.z > 1.0:
			var _a: bool = bad.push_back("uv out of range %s" % fuv)
		for n: int in GRIDS:
			var c: int = Sphere.cell_of(d, n)
			var centre: Vector3 = Sphere.cell_center_dir(c, n)
			if c < 0 or c >= 6 * n * n or Sphere.cell_of(centre, n) != c or absf(centre.length() - 1.0) > DIR_EPS:
				var _b: bool = bad.push_back("cell round trip n=%d d=%s" % [n, d])
			# d lies within the cell's bounding cone (angle to the farthest corner).
			var cone: float = 0.0
			for corner: Vector3 in Sphere.cell_bounds_dirs(c, n):
				cone = maxf(cone, Sphere.great_circle(centre, corner))
			if Sphere.great_circle(centre, d) > cone + M_EPS:
				var _c: bool = bad.push_back("outside cell cone n=%d d=%s" % [n, d])
	assert_array(bad).is_empty()
	assert_float(worst).is_less(DIR_EPS)


func test_c2_transport_properties_10000() -> void:
	var rng: Rng = Rng.new(4, 2)
	var err_map: float = 0.0
	var err_unit: float = 0.0
	var err_tangent: float = 0.0
	var err_len: float = 0.0
	var err_compose: float = 0.0
	var identity_ok: bool = true
	for k: int in PROPERTY_SAMPLES:
		var n0: Vector3 = _rand_dir(rng)
		var step: Vector3 = _rand_dir(rng) * rng.range_f(0.0, 0.01)
		var n1: Vector3 = (n0 + step).normalized()
		var n2: Vector3 = (n1 + step).normalized()
		var q: Quaternion = Sphere.transport(n0, n1)
		err_unit = maxf(err_unit, absf(q.length() - 1.0))
		err_map = maxf(err_map, (q * n0).distance_to(n1))
		# A tangent vector stays tangent and keeps its length.
		var t: Vector3 = Sphere.tangent_frame(n0).x * 37.0
		var t1: Vector3 = q * t
		err_tangent = maxf(err_tangent, absf(t1.normalized().dot(n1)))
		err_len = maxf(err_len, absf(t1.length() - 37.0) / 37.0)
		# Two consecutive small transports compose to the direct one.
		var composed: Quaternion = Sphere.transport(n1, n2) * q
		err_compose = maxf(err_compose, (composed * t.normalized()).distance_to(Sphere.transport(n0, n2) * t.normalized()))
		identity_ok = identity_ok and Sphere.transport(n0, n0).is_equal_approx(Quaternion.IDENTITY)
	assert_float(err_map).is_less(DIR_EPS)
	assert_float(err_unit).is_less(DIR_EPS)
	assert_float(err_tangent).is_less(DIR_EPS)
	assert_float(err_len).is_less(DIR_EPS)
	assert_float(err_compose).is_less(1e-5)
	assert_bool(identity_ok).is_true()


func test_c3_neighbour_symmetry_all_edge_and_corner_cells() -> void:
	var bad: PackedStringArray = PackedStringArray()
	for n: int in GRIDS:
		var max_step: float = Sphere.PLANET_RADIUS * PI / float(n)
		for face: int in 6:
			for a: int in n:
				# Every border cell of every face (corners included) plus a diagonal of interior cells.
				var cells: PackedInt32Array = PackedInt32Array([_cell(face, a, 0, n), _cell(face, a, n - 1, n),
					_cell(face, 0, a, n), _cell(face, n - 1, a, n), _cell(face, a, a, n)])
				for c: int in cells:
					for dir: int in 4:
						var nb: int = Sphere.neighbour_cell(c, n, dir)
						if nb == c or Sphere.neighbour_cell(nb, n, _return_dir(c, nb, n, dir)) != c:
							var _a: bool = bad.push_back("n=%d cell=%d dir=%d nb=%d" % [n, c, dir, nb])
						elif Sphere.great_circle(Sphere.cell_center_dir(c, n), Sphere.cell_center_dir(nb, n)) > max_step:
							var _b: bool = bad.push_back("far n=%d cell=%d dir=%d nb=%d" % [n, c, dir, nb])
	assert_array(bad).is_empty()


func test_c3_neighbours8_symmetry_at_corners() -> void:
	var bad: PackedStringArray = PackedStringArray()
	for n: int in GRIDS:
		var max_step: float = Sphere.PLANET_RADIUS * 2.0 * PI / float(n)
		for face: int in 6:
			var cells: PackedInt32Array = PackedInt32Array([_cell(face, 0, 0, n), _cell(face, n - 1, 0, n),
				_cell(face, 0, n - 1, n), _cell(face, n - 1, n - 1, n), _cell(face, n - 1, 1, n), _cell(face, 1, n - 2, n)])
			for c: int in cells:
				for nb: int in Sphere.neighbours8(c, n):
					if not Sphere.neighbours8(nb, n).has(c):
						var _a: bool = bad.push_back("asym n=%d cell=%d nb=%d" % [n, c, nb])
					if Sphere.great_circle(Sphere.cell_center_dir(c, n), Sphere.cell_center_dir(nb, n)) > max_step:
						var _b: bool = bad.push_back("far n=%d cell=%d nb=%d" % [n, c, nb])
	assert_array(bad).is_empty()


func test_c4_great_circle_symmetric_and_zero_10000() -> void:
	var rng: Rng = Rng.new(4, 3)
	var r: float = Sphere.PLANET_RADIUS
	var bad: int = 0
	for k: int in PROPERTY_SAMPLES:
		var a: Vector3 = _rand_dir(rng) * rng.range_f(r - 500.0, r + 2000.0)
		var b: Vector3 = _rand_dir(rng) * r
		var ab: float = Sphere.great_circle(a, b)
		if ab != Sphere.great_circle(b, a) or Sphere.great_circle(a, a) != 0.0 or ab < 0.0 or ab > PI * r + M_EPS:
			bad += 1
	assert_int(bad).is_equal(0)


func test_c5_edge_table_matches_regeneration_from_frames() -> void:
	assert_int(Sphere.EDGE_NEIGHBOUR.size()).is_equal(24 * Sphere.EDGE_NEIGHBOUR_STRIDE)
	for face: int in 6:
		for edge: int in 4:
			var row: PackedInt32Array = Sphere.EDGE_NEIGHBOUR.slice((face * 4 + edge) * 3, (face * 4 + edge) * 3 + 3)
			var lo: Vector3 = _step_past_edge(face, edge, 0.3)
			var hi: Vector3 = _step_past_edge(face, edge, 0.7)
			assert_int(int(lo.x)).is_equal(row[0])
			assert_int(int(hi.x)).is_equal(row[0])
			assert_int(_entered_edge(lo)).is_equal(row[1])
			var along_is_u: bool = row[1] >= 2
			assert_int(row[2]).is_equal(1 if along_is_u else 0)
			# The along-edge coordinate is preserved in value (never reversed).
			assert_float(lo.y if along_is_u else lo.z).is_equal_approx(0.3, 1e-3)
			assert_float(hi.y if along_is_u else hi.z).is_equal_approx(0.7, 1e-3)


## Direction that leads from nb back to c: the opposite step within a face, the entered edge across one.
func _return_dir(c: int, nb: int, n: int, dir: int) -> int:
	var face: int = Sphere.cell_face(c, n)
	if Sphere.cell_face(nb, n) == face:
		return dir ^ 1
	return Sphere.EDGE_NEIGHBOUR[(face * 4 + dir) * Sphere.EDGE_NEIGHBOUR_STRIDE + 1]


func _step_past_edge(face: int, edge: int, along: float) -> Vector3:
	var past: float = -1e-4 if edge % 2 == 0 else 1.0 + 1e-4
	var d: Vector3 = Sphere.face_uv_to_dir(face, past, along) if edge < 2 else Sphere.face_uv_to_dir(face, along, past)
	return Sphere.dir_to_face_uv(d)


func _entered_edge(fuv: Vector3) -> int:
	var du: float = minf(fuv.y, 1.0 - fuv.y)
	var dv: float = minf(fuv.z, 1.0 - fuv.z)
	if du < dv:
		return 0 if fuv.y < 0.5 else 1
	return 2 if fuv.z < 0.5 else 3


# --- cells, hierarchy, radius --------------------------------------------------

func test_parent_cell_is_a_right_shift() -> void:
	var c: int = _cell(3, 1000, 517, Sphere.GRID_BUILD)
	assert_int(Sphere.parent_cell(c, Sphere.GRID_BUILD, Sphere.GRID_PATH)).is_equal(_cell(3, 250, 129, Sphere.GRID_PATH))
	assert_int(Sphere.parent_cell(c, Sphere.GRID_BUILD, Sphere.GRID_HASH)).is_equal(_cell(3, 62, 32, Sphere.GRID_HASH))
	assert_int(Sphere.parent_cell(c, Sphere.GRID_BUILD, Sphere.GRID_INTEREST)).is_equal(_cell(3, 7, 4, Sphere.GRID_INTEREST))
	var rng: Rng = Rng.new(4, 5)
	for k: int in 1000:
		var d: Vector3 = _rand_dir(rng)
		var fine: int = Sphere.cell_of(d, Sphere.GRID_BUILD)
		assert_int(Sphere.parent_cell(fine, Sphere.GRID_BUILD, Sphere.GRID_INTEREST)).is_equal(Sphere.cell_of(d, Sphere.GRID_INTEREST))


func test_cell_sizes_match_2_7() -> void:
	var n: int = Sphere.GRID_BUILD
	var h: float = float(n >> 1)
	var centre_edge: float = Sphere.great_circle(Sphere.face_uv_to_dir(0, h / float(n), 0.5),
		Sphere.face_uv_to_dir(0, (h + 1.0) / float(n), 0.5))
	assert_float(centre_edge).is_equal_approx(9.20, 0.01)
	var corner: PackedVector3Array = Sphere.cell_bounds_dirs(_cell(0, 0, 0, n), n)
	assert_float(Sphere.great_circle(corner[0], corner[1])).is_equal_approx(8.68, 0.01)
	assert_int(6 * n * n).is_equal(6291456)


func test_cells_in_radius_is_conservative() -> void:
	var rng: Rng = Rng.new(4, 6)
	for k: int in 50:
		var centre: Vector3 = _rand_dir(rng) * Sphere.PLANET_RADIUS
		var radius: float = rng.range_f(10.0, 400.0)
		var cells: PackedInt32Array = Sphere.cells_in_radius(centre, radius, Sphere.GRID_HASH)
		assert_bool(cells.has(Sphere.cell_of(centre, Sphere.GRID_HASH))).is_true()
		var f: Basis = Sphere.tangent_frame(centre)
		for s: int in 40:
			var ang: float = radius / Sphere.PLANET_RADIUS * sqrt(rng.next_float())
			var brg: float = rng.range_f(-PI, PI)
			var p: Vector3 = f.z * cos(ang) + (f.y * cos(brg) + f.x * sin(brg)) * sin(ang)
			assert_bool(cells.has(Sphere.cell_of(p, Sphere.GRID_HASH))).is_true()


func test_slerp_and_bearing() -> void:
	var a: Vector3 = Vector3(1, 0, 0)
	var b: Vector3 = Vector3(0, 1, 0)
	_assert_dir(Sphere.slerp_dir(a, b, 0.5), Vector3(1, 1, 0).normalized())
	_assert_dir(Sphere.slerp_dir(a, b, 0.0), a)
	_assert_dir(Sphere.slerp_dir(a, b, 1.0), b)
	var r: float = Sphere.PLANET_RADIUS
	assert_float(Sphere.bearing(Vector3(r, 0, 0), Vector3(r, 0, 100))).is_equal_approx(0.0, DIR_EPS)
	assert_float(Sphere.bearing(Vector3(r, 0, 0), Vector3(r, 100, 0))).is_equal_approx(PI / 2.0, DIR_EPS)


# --- C8, C9, slots, determinism -------------------------------------------------

func test_c8_max_sim_magnitude() -> void:
	assert_float(Sphere.MAX_SIM_MAGNITUDE).is_less(8192.0)
	assert_float(Sphere.MAX_SIM_MAGNITUDE).is_equal(Sphere.PLANET_RADIUS + Sphere.CEILING_HARD)


func test_slot_longitudes() -> void:
	for k: int in 8:
		var lon_deg: float = Sphere.SLOT_LON0_DEG + Sphere.SLOT_SPACING_DEG * k
		assert_float(lon_deg).is_equal(22.5 + 45.0 * k)
		var fuv: Vector3 = Sphere.dir_to_face_uv(Sphere.from_lat_lon(0.0, deg_to_rad(lon_deg), 1.0))
		assert_int(int(fuv.x)).is_less(4)          # equatorial faces only
		# One coordinate on the face centre line, the other at a quarter point (2.4 km off the edge).
		var on_u: bool = absf(fuv.y - 0.5) < DIR_EPS
		var other: float = fuv.z if on_u else fuv.y
		assert_float(minf(absf(other - 0.25), absf(other - 0.75))).is_less(DIR_EPS)
		assert_float(absf((fuv.z if not on_u else fuv.y) - 0.5)).is_less(DIR_EPS)
	# 03 s2.5 role column.
	assert_int(int(Sphere.dir_to_face_uv(Sphere.from_lat_lon(0.0, deg_to_rad(337.5), 1.0)).x)).is_equal(0)
	assert_int(int(Sphere.dir_to_face_uv(Sphere.from_lat_lon(0.0, deg_to_rad(157.5), 1.0)).x)).is_equal(1)
	assert_int(int(Sphere.dir_to_face_uv(Sphere.from_lat_lon(0.0, deg_to_rad(247.5), 1.0)).x)).is_equal(3)


func test_c9_no_slot_within_10_degrees_of_a_cube_edge() -> void:
	for k: int in 8:
		var lon: float = deg_to_rad(Sphere.SLOT_LON0_DEG + Sphere.SLOT_SPACING_DEG * k)
		var d: Vector3 = Sphere.from_lat_lon(0.0, lon, 1.0)
		var face: int = int(Sphere.dir_to_face_uv(d).x)
		var f: Basis = Sphere.face_frame(face)
		# Each face edge lies on the great circle with plane normal (+-S or +-T) - N; the angular
		# distance to that full circle lower-bounds the distance to the edge segment.
		var nearest: float = PI
		for axis: Vector3 in [f.x, -f.x, f.y, -f.y]:
			nearest = minf(nearest, asin(absf(d.dot((axis - f.z).normalized()))))
		assert_float(rad_to_deg(nearest)).is_greater_equal(10.0)
		assert_float(rad_to_deg(nearest)).is_equal_approx(22.5, 1e-4)


func test_face_frames_are_right_handed() -> void:
	for face: int in 6:
		var f: Basis = Sphere.face_frame(face)
		_assert_dir(f.x.cross(f.y), f.z)


func test_determinism_bit_identical() -> void:
	var rng_a: Rng = Rng.new(99, 7)
	var rng_b: Rng = Rng.new(99, 7)
	for k: int in 2000:
		var da: Vector3 = _rand_dir(rng_a)
		var db: Vector3 = _rand_dir(rng_b)
		assert_bool(da == db).is_true()
		assert_bool(Sphere.dir_to_face_uv(da) == Sphere.dir_to_face_uv(db)).is_true()
		assert_int(Sphere.cell_of(da, Sphere.GRID_BUILD)).is_equal(Sphere.cell_of(db, Sphere.GRID_BUILD))
		var c: int = Sphere.cell_of(da, Sphere.GRID_PATH)
		assert_bool(Sphere.cell_center_dir(c, Sphere.GRID_PATH) == Sphere.cell_center_dir(c, Sphere.GRID_PATH)).is_true()
		assert_bool(Sphere.transport(da, db) == Sphere.transport(da, db)).is_true()
