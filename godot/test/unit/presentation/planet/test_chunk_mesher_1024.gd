extends GdUnitTestSuite
## TA-23 regression (cradle spikes): on a full-resolution 1,024 map the mesher reproduces Terrain.height_at at
## every vertex of every depth, and skirts never rise above the surface. The synthetic map carries what the
## first 1,024 bake (cradle, PR #19) had: single-texel cliffs of ~370 m (60-100 m mesas) next to smooth bowls,
## so a texel-index / uv / decode-scale mismatch or a skirt pointing up would show as metres, not millimetres.
## Root cause of the cradle pillars was in the baked data, not here; this pins the renderer side.

const SCRATCH: String = "user://ta23_map1024"
const N: int = 1024
const BASE_WORD: int = 24000                 ## ~-60 m
const MESA_WORD: int = 20000                 ## +366 m single-texel cliff
const MESA_PITCH: int = 48                   ## texels between mesa centres
const MESA_R2: int = 9                       ## mesa radius^2 in texels (r = 3 texels, ~28 m)
const BOWL_WORD: float = 9000.0              ## smooth bowl depth (~165 m) at the face centre
## height_at re-derives (u, v) from a float32 direction (~1e-4 texel); across a 366 m cliff texel that is
## a few cm. Any mismatch the cradle symptoms need is tens to hundreds of metres.
const HEIGHT_AT_TOL_M: float = 0.1
const SURFACE_EPS_M: float = 1e-3

var _terrain: Terrain
var _mesher: ChunkMesher


func before() -> void:
	_write_map()
	_terrain = Terrain.new()
	assert_int(_terrain.load_map(SCRATCH)).is_equal(OK)
	assert_int(_terrain.face_resolution).is_equal(N)
	_mesher = ChunkMesher.new(_terrain, 6)


func after() -> void:
	var d: DirAccess = DirAccess.open(SCRATCH)
	if d == null:
		return
	for file: String in d.get_files():
		var _e: Error = d.remove(file)
	var _e2: Error = DirAccess.remove_absolute(SCRATCH)


static func _word(x: int, y: int) -> int:
	if x < 2 or y < 2 or x > N - 3 or y > N - 3:
		return BASE_WORD                     # constant rim: every face agrees on the shared cube edges
	var cx: float = (float(x) - 511.5) / 511.5
	var cy: float = (float(y) - 511.5) / 511.5
	var w: int = BASE_WORD - int(BOWL_WORD * maxf(0.0, 1.0 - 4.0 * (cx * cx + cy * cy)))
	var dx: int = posmod(x, MESA_PITCH) - (MESA_PITCH >> 1)
	var dy: int = posmod(y, MESA_PITCH) - (MESA_PITCH >> 1)
	if dx * dx + dy * dy <= MESA_R2:
		w += MESA_WORD
	return w


func _write_map() -> void:
	var _m: Error = DirAccess.make_dir_recursive_absolute(SCRATCH)
	var h: PackedByteArray = PackedByteArray()
	var _r: int = h.resize(N * N * 2)
	for y: int in N:
		for x: int in N:
			h.encode_u16((y * N + x) * 2, _word(x, y))
	var zeros: PackedByteArray = PackedByteArray()
	_r = zeros.resize(N * N)
	var outputs: Dictionary = {}
	for f: int in Terrain.FACE_COUNT:
		_put("face%d.height.u16" % f, h, outputs)
		_put("face%d.biome.u8" % f, zeros, outputs)
		_put("face%d.slope.u8" % f, zeros, outputs)
	var names: Array = outputs.keys()
	names.sort()
	var cat: String = ""
	for k: Variant in names:
		cat += str(outputs[k])
	var meta: Dictionary = {"schema_version": 1, "id": "ta23_1024", "radius_m": Sphere.PLANET_RADIUS, "face_resolution": N,
		"relief": {"min_m": Sphere.RELIEF_MIN, "max_m": Sphere.RELIEF_MAX}, "outputs": outputs, "map_hash": cat.sha256_text()}
	var f: FileAccess = FileAccess.open(SCRATCH.path_join("meta.json"), FileAccess.WRITE)
	var _ok: bool = f.store_string(JSON.stringify(meta))
	f.close()


func _put(file: String, bytes: PackedByteArray, outputs: Dictionary) -> void:
	var f: FileAccess = FileAccess.open(SCRATCH.path_join(file), FileAccess.WRITE)
	var _ok: bool = f.store_buffer(bytes)
	f.close()
	var ctx: HashingContext = HashingContext.new()
	var _s: Error = ctx.start(HashingContext.HASH_SHA256)
	_s = ctx.update(bytes)
	outputs[file] = ctx.finish().hex_encode()


## Chunks of every depth over mesas, the bowl, a face edge and a face corner.
func _nodes() -> Array[ChunkNode]:
	var out: Array[ChunkNode] = []
	for depth: int in 7:
		var side: int = 1 << depth
		for k: int in 3:
			out.append(ChunkNode.make((depth + k) % 6, depth, (k * 5 + (side >> 1)) % side, (k * 3 + depth) % side, 0.0, 0.0))
	out.append(ChunkNode.make(4, 6, 63, 63, 0.0, 0.0))
	out.append(ChunkNode.make(1, 5, 0, 17, 0.0, 0.0))
	out.append(ChunkNode.make(2, 6, 32, 32, 0.0, 0.0))     # face centre: bowl + mesa at 1:1 vertex/texel
	return out


func test_map_has_single_texel_cliffs() -> void:
	var d: Vector3 = Sphere.face_uv_to_dir(0, 24.0 / float(N - 1), 24.0 / float(N - 1))
	var e: Vector3 = Sphere.face_uv_to_dir(0, 30.0 / float(N - 1), 24.0 / float(N - 1))
	assert_float(_terrain.height_at(d) - _terrain.height_at(e)).is_greater(300.0)


func test_vertex_heights_match_height_at_at_every_depth() -> void:
	var worst: float = 0.0
	var where: String = ""
	for n: ChunkNode in _nodes():
		var arrays: Array = _mesher.build_arrays(n)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for b: int in ChunkMesher.VERTS:
			for a: int in ChunkMesher.VERTS:
				var vi: int = b * ChunkMesher.VERTS + a
				var dir: Vector3 = _mesher.vertex_dir(n.face, n.depth, n.gx(a), n.gy(b))
				var ref: float = _terrain.height_at(dir)
				var err: float = absf(_mesher.last_heights[vi] - ref)
				var r_err: float = absf(verts[vi].length() - (Sphere.PLANET_RADIUS + ref))
				if maxf(err, r_err) > worst:
					worst = maxf(err, r_err)
					where = "face %d depth %d vertex (%d,%d)" % [n.face, n.depth, a, b]
	assert_float(worst).override_failure_message("%s off by %.3f m" % [where, worst]).is_less(HEIGHT_AT_TOL_M)


func test_mesh_never_exceeds_the_data_range() -> void:
	var lo: float = Sphere.RELIEF_MIN + float(BASE_WORD - int(BOWL_WORD)) * (Sphere.RELIEF_MAX - Sphere.RELIEF_MIN) / float(Terrain.U16_MAX)
	var hi: float = Sphere.RELIEF_MIN + float(BASE_WORD + MESA_WORD) * (Sphere.RELIEF_MAX - Sphere.RELIEF_MIN) / float(Terrain.U16_MAX)
	for n: ChunkNode in _nodes():
		var _a: Array = _mesher.build_arrays(n)
		assert_float(_mesher.last_h_min).is_greater_equal(lo - SURFACE_EPS_M)
		assert_float(_mesher.last_h_max).is_less_equal(hi + SURFACE_EPS_M)


## Skirt vertices hang straight down (same direction as their edge vertex, skirt_depth below it) and no skirt
## triangle has a vertex above the surface: a skirt can never stand up as a wall or pillar.
func test_no_skirt_quad_rises_above_the_surface() -> void:
	for n: ChunkNode in _nodes():
		var arrays: Array = _mesher.build_arrays(n)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var drop: float = ChunkMesher.skirt_depth(n.depth)
		for e: int in 4:
			for k: int in ChunkMesher.VERTS:
				var top: Vector3 = verts[ChunkMesher.edge_vertex(e, k)]
				var s: Vector3 = verts[ChunkMesher.GRID_VERTS + e * ChunkMesher.VERTS + k]
				assert_float(top.normalized().distance_to(s.normalized())).is_less(1e-6)
				assert_float(top.length() - s.length()).is_equal_approx(drop, 2e-3)
		var idx: PackedInt32Array = _mesher.indices
		for t: int in range(2048, 2304):
			for c: int in 3:
				var p: Vector3 = verts[idx[3 * t + c]]
				var surface: float = Sphere.PLANET_RADIUS + _terrain.height_at(p)
				if p.length() > surface + HEIGHT_AT_TOL_M:
					fail("face %d depth %d skirt tri %d vertex %.2f m above the surface" % [n.face, n.depth, t, p.length() - surface])
					return
