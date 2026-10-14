extends GdUnitTestSuite
## Unit tests for sim/terrain.gd (03 s6.2, s8.4, TA-13): loader and SHA verification, height_at against the
## Python reference (tools/terrain_vectors.py), continuity across cube edges and corners, normal and slope,
## load time. Invariant S9: identical bytes give identical results.

const MAP_TINY: String = "res://content/maps/tiny_test"
const MAP_WORLD: String = "res://content/maps/s_world1_r6000"
const VECTORS: String = "res://test/unit/sim/terrain_vectors.json"
const LCG_MUL: int = 6364136223846793005
const LCG_ADD: int = 1442695040888963407
const SCRATCH: String = "user://terrain_test_map"
const SYN_N: int = 8

var _terrain: Terrain


func before_test() -> void:
	_terrain = Terrain.new()


func after_test() -> void:
	_remove_scratch()


# region helpers
## Same generator as tools/terrain_vectors.py lcg_dirs: top 24 bits of a 64-bit LCG, exact in doubles.
func _lcg_dirs(seed_value: int, count: int) -> PackedVector3Array:
	var out: PackedVector3Array = PackedVector3Array()
	var _r: int = out.resize(count)
	var x: int = seed_value
	for i: int in count:
		var c: Array[float] = [0.0, 0.0, 0.0]
		for k: int in 3:
			x = x * LCG_MUL + LCG_ADD
			c[k] = float((x >> 40) & 0xFFFFFF) / 16777216.0 - 0.5
		out[i] = Vector3(c[0], c[1], c[2])
	return out


func _load_tiny() -> Terrain:
	var t: Terrain = Terrain.new()
	assert_int(t.load_map(MAP_TINY)).is_equal(OK)
	return t


func _sha(bytes: PackedByteArray) -> String:
	var ctx: HashingContext = HashingContext.new()
	var _s: Error = ctx.start(HashingContext.HASH_SHA256)
	_s = ctx.update(bytes)
	return ctx.finish().hex_encode()


## Writes a valid SYN_N x SYN_N map with constant height word `hword`, biome 3, slope byte `slope_byte`.
func _write_synthetic(hword: int, slope_byte: int, radius: float = 6000.0) -> void:
	var _m: Error = DirAccess.make_dir_recursive_absolute(SCRATCH)
	var outputs: Dictionary = {}
	var cells: int = SYN_N * SYN_N
	var h: PackedByteArray = PackedByteArray()
	var _r: int = h.resize(cells * 2)
	for i: int in cells:
		h.encode_u16(i * 2, hword)
	var b: PackedByteArray = PackedByteArray()
	_r = b.resize(cells)
	b.fill(3)
	var s: PackedByteArray = PackedByteArray()
	_r = s.resize(cells)
	s.fill(slope_byte)
	for f: int in 6:
		_put("face%d.height.u16" % f, h, outputs)
		_put("face%d.biome.u8" % f, b, outputs)
		_put("face%d.slope.u8" % f, s, outputs)
	var names: Array = outputs.keys()
	names.sort()
	var cat: String = ""
	for k: Variant in names:
		cat += str(outputs[k])
	var meta: Dictionary = {"schema_version": 1, "id": "synthetic", "radius_m": radius, "face_resolution": SYN_N,
		"relief": {"min_m": Sphere.RELIEF_MIN, "max_m": Sphere.RELIEF_MAX}, "outputs": outputs,
		"map_hash": cat.sha256_text()}
	_write_text("meta.json", JSON.stringify(meta))


func _put(file: String, bytes: PackedByteArray, outputs: Dictionary) -> void:
	var f: FileAccess = FileAccess.open(SCRATCH.path_join(file), FileAccess.WRITE)
	var _ok: bool = f.store_buffer(bytes)
	f.close()
	outputs[file] = _sha(bytes)


func _write_text(file: String, text: String) -> void:
	var f: FileAccess = FileAccess.open(SCRATCH.path_join(file), FileAccess.WRITE)
	var _ok: bool = f.store_string(text)
	f.close()


func _remove_scratch() -> void:
	var d: DirAccess = DirAccess.open(SCRATCH)
	if d == null:
		return
	for file: String in d.get_files():
		var _e: Error = d.remove(file)
	var _e2: Error = DirAccess.remove_absolute(SCRATCH)


func _cube_edge_point(k_axis: int, si: float, sj: float, t: float) -> Array[Vector3]:
	## Returns [on-edge point, point just inside face i, point just inside face j].
	var i: int = (k_axis + 1) % 3
	var j: int = (k_axis + 2) % 3
	var p: Vector3 = Vector3.ZERO
	p[k_axis] = t
	p[i] = si
	p[j] = sj
	var a: Vector3 = p
	a[i] = si * (1.0 + 1e-6)
	var b: Vector3 = p
	b[j] = sj * (1.0 + 1e-6)
	return [p.normalized(), a.normalized(), b.normalized()]
# endregion


# region loader
func test_unloaded_terrain_is_flat_datum() -> void:
	assert_bool(_terrain.is_loaded()).is_false()
	assert_float(_terrain.height_at(Vector3(1, 2, 3))).is_equal(0.0)
	assert_int(_terrain.biome_at(Vector3(1, 2, 3))).is_equal(0)
	assert_vector(_terrain.normal_at(Vector3(0, 0, 5))).is_equal_approx(Vector3(0, 0, 1), Vector3(1e-9, 1e-9, 1e-9))


func test_loads_tiny_test_and_exposes_map_hash() -> void:
	assert_int(_terrain.load_map(MAP_TINY)).is_equal(OK)
	assert_bool(_terrain.is_loaded()).is_true()
	assert_int(_terrain.face_resolution).is_equal(128)
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MAP_TINY + "/meta.json"))
	assert_str(_terrain.map_hash).is_equal(str(meta["map_hash"]))


func test_loads_world_map() -> void:
	assert_int(_terrain.load_map(MAP_WORLD)).is_equal(OK)
	assert_bool(_terrain.is_loaded()).is_true()


func test_tiny_test_loads_in_under_50_ms() -> void:
	var t0: int = Time.get_ticks_usec()
	var err: Error = _terrain.load_map(MAP_TINY)
	var ms: float = float(Time.get_ticks_usec() - t0) / 1000.0
	assert_int(err).is_equal(OK)
	assert_float(ms).is_less(50.0)


func test_flipped_byte_fails_the_load_and_leaves_flat_stub() -> void:
	_write_synthetic(30000, 0)
	var f: FileAccess = FileAccess.open(SCRATCH.path_join("face2.height.u16"), FileAccess.READ_WRITE)
	f.seek(7)
	var b: int = f.get_8()
	f.seek(7)
	f.store_8(b ^ 1)
	f.close()
	assert_int(_terrain.load_map(SCRATCH)).is_equal(ERR_FILE_CORRUPT)
	assert_bool(_terrain.is_loaded()).is_false()
	assert_float(_terrain.height_at(Vector3(0, 0, 1))).is_equal(0.0)


func test_synthetic_valid_map_loads_then_each_tamper_fails() -> void:
	_write_synthetic(30000, 0)
	assert_int(_terrain.load_map(SCRATCH)).is_equal(OK)
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SCRATCH + "/meta.json"))
	meta["map_hash"] = "0".repeat(64)
	_write_text("meta.json", JSON.stringify(meta))
	assert_int(Terrain.new().load_map(SCRATCH)).is_equal(ERR_INVALID_DATA)
	_write_synthetic(30000, 0, 5000.0)
	assert_int(Terrain.new().load_map(SCRATCH)).is_equal(ERR_INVALID_DATA)


func test_missing_directory_and_truncated_face_fail() -> void:
	assert_int(Terrain.new().load_map("user://no_such_map_dir")).is_not_equal(OK)
	_write_synthetic(30000, 0)
	var f: FileAccess = FileAccess.open(SCRATCH.path_join("face4.biome.u8"), FileAccess.WRITE)
	var _ok: bool = f.store_8(3)
	f.close()
	assert_int(Terrain.new().load_map(SCRATCH)).is_equal(ERR_FILE_CORRUPT)
# endregion


# region height_at
func test_height_at_matches_python_reference_on_10000_samples() -> void:
	var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(VECTORS))
	var t: Terrain = _load_tiny()
	var count: int = int(doc["count"])
	assert_int(count).is_equal(10000)
	var dirs: PackedVector3Array = _lcg_dirs(int(doc["seed"]), count)
	var expect_h: Array = doc["height_um"]
	var expect_b: Array = doc["biome"]
	var worst: float = 0.0
	var biome_bad: int = 0
	for i: int in count:
		worst = maxf(worst, absf(t.height_at(dirs[i]) - float(expect_h[i]) * 1e-6))
		if t.biome_at(dirs[i]) != int(expect_b[i]):
			biome_bad += 1
	assert_float(worst).is_less(1e-3)
	assert_int(biome_bad).is_equal(0)


func test_height_is_scale_invariant_and_inside_relief() -> void:
	var t: Terrain = _load_tiny()
	for d: Vector3 in _lcg_dirs(5, 500):
		var h: float = t.height_at(d)
		assert_float(h).is_between(Sphere.RELIEF_MIN, Sphere.RELIEF_MAX)
		assert_float(t.height_at(d * 37.5)).is_equal(h)


func test_constant_map_height_and_texel_exactness() -> void:
	_write_synthetic(65535, 0)
	assert_int(_terrain.load_map(SCRATCH)).is_equal(OK)
	for d: Vector3 in _lcg_dirs(9, 50):
		assert_float(_terrain.height_at(d)).is_equal_approx(Sphere.RELIEF_MAX, 1e-9)
	assert_vector(_terrain.surface_point(Vector3(0, 0, 3))).is_equal_approx(
		Vector3(0, 0, Sphere.PLANET_RADIUS + Sphere.RELIEF_MAX), Vector3(1e-6, 1e-6, 1e-6))


func test_two_loads_give_identical_results() -> void:
	var a: Terrain = _load_tiny()
	var b: Terrain = _load_tiny()
	for d: Vector3 in _lcg_dirs(77, 300):
		assert_float(a.height_at(d)).is_equal(b.height_at(d))
		assert_vector(a.normal_at(d)).is_equal(b.normal_at(d))
# endregion


# region continuity (03 s8.5)
func test_continuous_across_all_12_cube_edges() -> void:
	var t: Terrain = _load_tiny()
	var worst: float = 0.0
	var checked: int = 0
	for k: int in 3:
		for si: float in [1.0, -1.0]:
			for sj: float in [1.0, -1.0]:
				for s: int in 64:
					var tt: float = -0.9 + 1.8 * float(s) / 63.0
					var pts: Array[Vector3] = _cube_edge_point(k, si, sj, tt)
					assert_int(Sphere.dir_to_face_uv(pts[1]).x as int).is_not_equal(Sphere.dir_to_face_uv(pts[2]).x as int)
					var h0: float = t.height_at(pts[0])
					worst = maxf(worst, maxf(absf(t.height_at(pts[1]) - h0), absf(t.height_at(pts[2]) - h0)))
					checked += 1
	assert_int(checked).is_equal(12 * 64)
	assert_float(worst).is_less(0.05)


func test_continuous_at_all_8_cube_corners() -> void:
	var t: Terrain = _load_tiny()
	var eps: float = 1e-6
	for sx: float in [1.0, -1.0]:
		for sy: float in [1.0, -1.0]:
			for sz: float in [1.0, -1.0]:
				var corner: Vector3 = Vector3(sx, sy, sz).normalized()
				var h0: float = t.height_at(corner)
				var faces: Dictionary[int, bool] = {}
				for axis: int in 3:
					var p: Vector3 = Vector3(sx, sy, sz)
					p[axis] *= 1.0 + eps
					faces[int(Sphere.dir_to_face_uv(p).x)] = true
					assert_float(absf(t.height_at(p.normalized()) - h0)).is_less(0.05)
				assert_int(faces.size()).is_equal(3)


func test_edge_texels_agree_on_both_faces_bit_exact() -> void:
	# The seam pass wrote identical u16 on both faces of every shared edge (03 s8.5), via EDGE_NEIGHBOUR.
	var t: Terrain = _load_tiny()
	var n: int = t.face_resolution
	for f: int in 6:
		for e: int in 4:
			var row: int = (f * 4 + e) * Sphere.EDGE_NEIGHBOUR_STRIDE
			var nf: int = Sphere.EDGE_NEIGHBOUR[row]
			var ne: int = Sphere.EDGE_NEIGHBOUR[row + 1]
			for s: int in n:
				var here: int = t.height_texel(f, _edge_x(e, s, n), _edge_y(e, s, n))
				var there: int = t.height_texel(nf, _edge_x(ne, s, n), _edge_y(ne, s, n))
				assert_int(here).is_equal(there)


func _edge_x(edge: int, s: int, n: int) -> int:
	if edge == Sphere.DIR_NEG_U:
		return 0
	return n - 1 if edge == Sphere.DIR_POS_U else s


func _edge_y(edge: int, s: int, n: int) -> int:
	if edge == Sphere.DIR_NEG_V:
		return 0
	return n - 1 if edge == Sphere.DIR_POS_V else s
# endregion


# region normal and slope
func test_biome_face_matches_biome_at_texels() -> void:
	assert_int(_terrain.biome_face(0).size()).is_equal(0)
	var t: Terrain = _load_tiny()
	var n: int = t.face_resolution
	assert_int(t.biome_face(6).size()).is_equal(0)
	for f: int in Terrain.FACE_COUNT:
		var b: PackedByteArray = t.biome_face(f)
		assert_int(b.size()).is_equal(n * n)
		for y: int in [0, (n - 1) >> 2, n - 1]:
			for x: int in [0, (n - 1) >> 1, n - 1]:
				var uv: Vector2 = Vector2(float(x), float(y)) / float(n - 1)
				var d: Vector3 = Sphere.face_uv_to_dir(f, uv.x, uv.y)
				assert_int(b[y * n + x]).is_equal(t.biome_at(d))


func test_flat_map_normal_is_radial_and_slope_zero() -> void:
	_write_synthetic(30000, 0)
	assert_int(_terrain.load_map(SCRATCH)).is_equal(OK)
	for d: Vector3 in _lcg_dirs(3, 100):
		assert_float(_terrain.normal_at(d).dot(d.normalized())).is_equal_approx(1.0, 1e-6)
		assert_float(_terrain.slope_deg_at_dir(d)).is_equal(0.0)
		assert_int(_terrain.biome_at(d)).is_equal(3)


func test_normals_are_unit_and_point_outward_on_real_map() -> void:
	var t: Terrain = _load_tiny()
	for d: Vector3 in _lcg_dirs(11, 400):
		var n: Vector3 = t.normal_at(d)
		assert_float(n.length()).is_equal_approx(1.0, 1e-6)
		assert_float(n.dot(d.normalized())).is_greater(0.5)


func test_normal_tilt_tracks_baked_slope() -> void:
	var t: Terrain = _load_tiny()
	var sum_err: float = 0.0
	var count: int = 400
	for d: Vector3 in _lcg_dirs(12, count):
		var tilt: float = rad_to_deg(acos(clampf(t.normal_at(d).dot(d.normalized()), -1.0, 1.0)))
		sum_err += absf(tilt - t.slope_deg_at_dir(d))
	assert_float(sum_err / float(count)).is_less(6.0)


func test_slope_cache_is_half_degree_steps_and_cell_indexed() -> void:
	_write_synthetic(30000, 37)
	assert_int(_terrain.load_map(SCRATCH)).is_equal(OK)
	assert_float(_terrain.slope_deg_at(0)).is_equal(18.5)
	assert_float(_terrain.slope_deg_at(6 * SYN_N * SYN_N - 1)).is_equal(18.5)
	var t: Terrain = _load_tiny()
	for d: Vector3 in _lcg_dirs(13, 200):
		var s: float = t.slope_deg_at_dir(d)
		assert_float(s).is_between(0.0, 90.0)
# endregion
