extends GdUnitTestSuite
## TA-23: texel-index mesher, variant A (03 s7.3, R0 C1-06): shared index pattern and winding, per-depth
## direction table, heights bit-identical to the texel-space reference of height_at, skirts, cube-edge seams.

const MAP: String = "res://content/maps/s_world1_r6000"
## height_at re-derives (u, v) from a float32 Vector3 direction, so it agrees with the exact texel coordinate
## only to the direction quantisation (~1e-7 rad, i.e. ~1e-4 texel); well under the 0.5 mm float32 position
## step at 6.7 km (ADR-03).
const HEIGHT_AT_TOL_M: float = 2e-3

var _terrain: Terrain
var _mesher: ChunkMesher


func before() -> void:
	_terrain = Terrain.new()
	assert_int(_terrain.load_map(MAP)).is_equal(OK)
	_mesher = ChunkMesher.new(_terrain, 6)


func _nodes() -> Array[ChunkNode]:
	var out: Array[ChunkNode] = []
	for depth: int in 7:
		var side: int = 1 << depth
		for k: int in 3:
			out.append(ChunkNode.make((depth + k) % 6, depth, (k * 5 + 1) % side, (k * 3 + depth) % side, 0.0, 0.0))
	out.append(ChunkNode.make(4, 6, 63, 63, 0.0, 0.0))   # face corner
	out.append(ChunkNode.make(0, 5, 0, 17, 0.0, 0.0))    # face edge
	return out


## The texel-space reference written from 03 s6.2 independently of the mesher.
func _reference(face: int, depth: int, gx: int, gy: int) -> float:
	var n: int = _terrain.face_resolution
	var segs: float = float(32 << depth)
	var x: float = float((n - 1) * gx) / segs
	var y: float = float((n - 1) * gy) / segs
	var ix: int = mini(int(x), n - 2)
	var iy: int = mini(int(y), n - 2)
	var fx: float = x - float(ix)
	var fy: float = y - float(iy)
	var h0: float = lerpf(float(_terrain.height_texel(face, ix, iy)), float(_terrain.height_texel(face, ix + 1, iy)), fx)
	var h1: float = lerpf(float(_terrain.height_texel(face, ix, iy + 1)), float(_terrain.height_texel(face, ix + 1, iy + 1)), fx)
	return Sphere.RELIEF_MIN + lerpf(h0, h1, fy) * ((Sphere.RELIEF_MAX - Sphere.RELIEF_MIN) / float(Terrain.U16_MAX))


func test_shared_index_pattern_sizes() -> void:
	assert_int(_mesher.indices.size()).is_equal(ChunkMesher.INDEX_COUNT)
	assert_int(ChunkMesher.INDEX_COUNT).is_equal(6912)
	assert_int(ChunkMesher.VERTEX_COUNT).is_equal(1221)
	for i: int in _mesher.indices:
		assert_bool(i >= 0 and i < ChunkMesher.VERTEX_COUNT).is_true()
	var arrays: Array = _mesher.build_arrays(ChunkNode.make(2, 3, 1, 1, 0.0, 0.0))
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	assert_bool(idx == _mesher.indices).is_true()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var custom: PackedByteArray = arrays[Mesh.ARRAY_CUSTOM0]
	assert_int(verts.size()).is_equal(1221)
	assert_int(custom.size()).is_equal(1221 * 4)


func test_direction_table_is_bit_identical_to_face_uv_to_dir() -> void:
	for depth: int in 7:
		var segs: int = 32 << depth
		for k: int in 40:
			var face: int = k % 6
			var gx: int = (k * 977) % (segs + 1)
			var gy: int = (k * 613 + depth) % (segs + 1)
			var d: Vector3 = _mesher.vertex_dir(face, depth, gx, gy)
			var ref: Vector3 = Sphere.face_uv_to_dir(face, float(gx) / float(segs), float(gy) / float(segs))
			assert_bool(d == ref).override_failure_message("depth %d (%d,%d)" % [depth, gx, gy]).is_true()


func test_heights_bit_identical_to_texel_reference_and_match_height_at() -> void:
	var worst: float = 0.0
	for n: ChunkNode in _nodes():
		var _a: Array = _mesher.build_arrays(n)
		for b: int in 33:
			for a: int in 33:
				var h: float = _mesher.last_heights[b * 33 + a]
				var ref: float = _reference(n.face, n.depth, n.gx(a), n.gy(b))
				if h != ref:
					fail("face %d depth %d vertex (%d,%d): %.9f != %.9f" % [n.face, n.depth, a, b, h, ref])
					return
				assert_float(_mesher.vertex_height(n.face, n.depth, n.gx(a), n.gy(b))).is_equal(h)
				var dir: Vector3 = _mesher.vertex_dir(n.face, n.depth, n.gx(a), n.gy(b))
				worst = maxf(worst, absf(_terrain.height_at(dir) - h))
	assert_float(worst).is_less(HEIGHT_AT_TOL_M)


func test_vertices_sit_at_dir_times_radius_plus_height() -> void:
	var n: ChunkNode = ChunkNode.make(1, 4, 5, 9, 0.0, 0.0)
	var arrays: Array = _mesher.build_arrays(n)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for k: int in 1089:
		var a: int = k % 33
		var b: int = MathX.floori_div(k, 33)
		var expect: Vector3 = _mesher.vertex_dir(1, 4, n.gx(a), n.gy(b)) * (Sphere.PLANET_RADIUS + _mesher.last_heights[k])
		assert_float(verts[k].distance_to(expect)).is_less(1e-3)


func test_grid_triangles_clockwise_from_outside_and_normals_outward() -> void:
	var n: ChunkNode = ChunkNode.make(3, 2, 1, 2, 0.0, 0.0)
	var arrays: Array = _mesher.build_arrays(n)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = _mesher.indices
	for t: int in 2048:
		var p0: Vector3 = verts[idx[3 * t]]
		var c: Vector3 = (verts[idx[3 * t + 1]] - p0).cross(verts[idx[3 * t + 2]] - p0)
		assert_float(c.dot(p0.normalized())).is_less(0.0)       # Godot: clockwise = front
	for k: int in 1089:
		assert_float(normals[k].dot(verts[k].normalized())).is_greater(0.5)


func test_skirts_hang_skirt_depth_below_their_edge_and_face_outward() -> void:
	var n: ChunkNode = ChunkNode.make(0, 6, 20, 31, 0.0, 0.0)
	var arrays: Array = _mesher.build_arrays(n)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var custom: PackedByteArray = arrays[Mesh.ARRAY_CUSTOM0]
	var drop: float = ChunkMesher.skirt_depth(6)
	var mid: Vector3 = verts[16 * 33 + 16]
	for e: int in 4:
		for k: int in 33:
			var top: Vector3 = verts[ChunkMesher.edge_vertex(e, k)]
			var s: int = 1089 + e * 33 + k
			assert_float(top.length() - verts[s].length()).is_equal_approx(drop, 2e-3)
			assert_int(custom[s * 4 + 3]).is_equal(255)
	var idx: PackedInt32Array = _mesher.indices
	for t: int in range(2048, 2304):
		var p0: Vector3 = verts[idx[3 * t]]
		var c: Vector3 = (verts[idx[3 * t + 1]] - p0).cross(verts[idx[3 * t + 2]] - p0)
		var out: Vector3 = p0 - mid
		out -= p0.normalized() * out.dot(p0.normalized())
		assert_float(c.dot(out)).is_less(0.0)                  # front face looks away from the chunk


func test_skirt_depths_match_03_s7_3_table() -> void:
	var expected: Array[float] = [368.0, 184.0, 92.0, 46.0, 23.0, 12.0, 6.0]
	for depth: int in 7:
		assert_float(ChunkMesher.skirt_depth(depth)).is_equal_approx(expected[depth], expected[depth] * 0.05)


func test_cube_edge_vertices_coincide_across_faces() -> void:
	# F0 u=1 meets F2 v=1 with v -> u (03 s2.6): F0 vertex (segs, g) == F2 vertex (g, segs)
	for depth: int in [2, 5, 6]:
		var side: int = 1 << depth
		var segs: int = 32 << depth
		for j: int in [0, side >> 1, side - 1]:
			var a0: ChunkNode = ChunkNode.make(0, depth, side - 1, j, 0.0, 0.0)
			var _r: Array = _mesher.build_arrays(a0)
			var ha: PackedFloat64Array = _mesher.last_heights.duplicate()
			var b2: ChunkNode = ChunkNode.make(2, depth, j, side - 1, 0.0, 0.0)
			_r = _mesher.build_arrays(b2)
			for k: int in 33:
				var g: int = j * 32 + k
				var pa: Vector3 = _mesher.vertex_dir(0, depth, segs, g) * (Sphere.PLANET_RADIUS + ha[k * 33 + 32])
				var pb: Vector3 = _mesher.vertex_dir(2, depth, g, segs) * (Sphere.PLANET_RADIUS + _mesher.last_heights[32 * 33 + k])
				assert_float(pa.distance_to(pb)).is_less(1e-3)


func test_build_into_tightens_bounds_and_uploads_one_surface() -> void:
	var n: ChunkNode = ChunkNode.make(5, 4, 3, 3, Sphere.RELIEF_MIN, Sphere.RELIEF_MAX)
	var r0: float = n.radius
	var mesh: ArrayMesh = ArrayMesh.new()
	_mesher.build_into(n, mesh, null)
	assert_int(mesh.get_surface_count()).is_equal(1)
	assert_float(n.radius).is_less(r0)
	assert_float(n.h_min).is_equal(_mesher.last_h_min)
	assert_float(n.h_max).is_greater_equal(n.h_min)


## TA-24: custom.b carries the cube face (the shader reads the biome per pixel), custom.a stays the skirt flag.
func test_custom_b_is_the_face_and_a_marks_skirts() -> void:
	for node: ChunkNode in _nodes():
		var arrays: Array = _mesher.build_arrays(node)
		var custom: PackedByteArray = arrays[Mesh.ARRAY_CUSTOM0]
		for v: int in ChunkMesher.VERTEX_COUNT:
			assert_int(custom[v * 4 + 2]).is_equal(node.face)
			assert_int(custom[v * 4 + 3]).is_equal(255 if v >= ChunkMesher.GRID_VERTS else 0)
