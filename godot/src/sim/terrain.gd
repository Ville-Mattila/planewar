class_name Terrain extends RefCounted
## Read-only terrain sampler shared by sim and presentation (03 s6.2, s8.4). Holds the baked height, biome and
## slope faces of one map as three packed arrays (6 faces concatenated, face stride n*n texels) and answers
## height_at / normal_at / biome_at / slope_deg_at. Texel (x, y) of a face sits at u = x/(n-1), v = y/(n-1), so
## edge texels lie on cube edges and height_at is continuous across them (8.5). Until a map is loaded the
## surface is the datum sphere (height 0, normal radial): the flat stub S-FLIGHT-1 runs on (03 s14.6).
## Invariant S9: identical bytes (SHA-256 verified at load) give identical results on every peer.

const FACE_COUNT: int = 6
const U16_MAX: int = 65535
const SLOPE_STEP_DEG: float = 0.5   ## slope.u8 is in 0.5 degree steps (03 s8.3)
const _META_FILE: String = "meta.json"

var map_hash: String = ""            ## meta.json map_hash, enters the handshake and replay header
var face_resolution: int = 0         ## n, texels per face edge; 0 = flat stub (no map loaded)
var _heights: PackedByteArray = PackedByteArray()   ## little-endian u16, face * n * n + y * n + x
var _biomes: PackedByteArray = PackedByteArray()
var _slopes: PackedByteArray = PackedByteArray()
var _nm1: float = 0.0
var _relief_scale: float = 0.0       ## (RELIEF_MAX - RELIEF_MIN) / U16_MAX
var _texel_rad: float = 0.0          ## angular size of one texel at the face centre


func is_loaded() -> bool:
	return face_resolution > 0


## Reads, hashes and installs the six faces of `map_dir` (e.g. "res://content/maps/tiny_test"). Any missing
## file, SHA-256 mismatch, radius or relief disagreement leaves the sampler unchanged and returns an error:
## a corrupt map on one peer would desync vision and collision (03 s8.4).
func load_map(map_dir: String) -> Error:
	var meta: Variant = JSON.parse_string(FileAccess.get_file_as_string(map_dir.path_join(_META_FILE)))
	if not (meta is Dictionary):
		return ERR_FILE_CANT_READ
	var m: Dictionary = meta
	var outputs: Dictionary = m.get("outputs", {})
	var relief: Dictionary = m.get("relief", {})
	var n: int = int(_num(m, "face_resolution"))
	if n < 2 or not _meta_matches_sphere(m, relief) or not _map_hash_ok(m, outputs):
		return ERR_INVALID_DATA
	var heights: PackedByteArray = PackedByteArray()
	var biomes: PackedByteArray = PackedByteArray()
	var slopes: PackedByteArray = PackedByteArray()
	for f: int in FACE_COUNT:
		var err: Error = _append_face(map_dir, "face%d.height.u16" % f, outputs, n * n * 2, heights)
		err = err if err != OK else _append_face(map_dir, "face%d.biome.u8" % f, outputs, n * n, biomes)
		err = err if err != OK else _append_face(map_dir, "face%d.slope.u8" % f, outputs, n * n, slopes)
		if err != OK:
			return err
	_install(n, heights, biomes, slopes, str(m["map_hash"]))
	return OK


static func _num(d: Dictionary, key: String) -> float:
	var v: Variant = d.get(key, 0.0)
	if v is float:
		var f: float = v
		return f
	if v is int:
		var i: int = v
		return float(i)
	return 0.0


func _meta_matches_sphere(m: Dictionary, relief: Dictionary) -> bool:
	return is_equal_approx(_num(m, "radius_m"), Sphere.PLANET_RADIUS) \
		and is_equal_approx(_num(relief, "min_m"), Sphere.RELIEF_MIN) \
		and is_equal_approx(_num(relief, "max_m"), Sphere.RELIEF_MAX)


## map_hash = SHA-256 over the output hashes in file-name order (03 s8.3).
func _map_hash_ok(m: Dictionary, outputs: Dictionary) -> bool:
	var names: Array = outputs.keys()
	names.sort()
	var cat: String = ""
	for k: Variant in names:
		cat += str(outputs[k])
	return cat.sha256_text() == str(m.get("map_hash", ""))


func _append_face(dir: String, file: String, outputs: Dictionary, size: int, dest: PackedByteArray) -> Error:
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(dir.path_join(file))
	if bytes.size() != size:
		return ERR_FILE_CORRUPT
	var ctx: HashingContext = HashingContext.new()
	var _s: Error = ctx.start(HashingContext.HASH_SHA256)
	_s = ctx.update(bytes)
	if ctx.finish().hex_encode() != str(outputs.get(file, "")):
		return ERR_FILE_CORRUPT
	dest.append_array(bytes)
	return OK


func _install(n: int, heights: PackedByteArray, biomes: PackedByteArray, slopes: PackedByteArray, hash_hex: String) -> void:
	face_resolution = n
	_heights = heights
	_biomes = biomes
	_slopes = slopes
	map_hash = hash_hex
	_nm1 = float(n - 1)
	_relief_scale = (Sphere.RELIEF_MAX - Sphere.RELIEF_MIN) / float(U16_MAX)
	_texel_rad = PI * 0.5 / _nm1


## Metres above the datum at direction `dir` (need not be normalised): bilinear over the u16 face.
func height_at(dir: Vector3) -> float:
	if face_resolution == 0:
		return 0.0
	var fuv: Vector3 = Sphere.dir_to_face_uv(dir)
	var n: int = face_resolution
	var x: float = fuv.y * _nm1
	var y: float = fuv.z * _nm1
	var ix: int = mini(int(x), n - 2)
	var iy: int = mini(int(y), n - 2)
	var fx: float = x - float(ix)
	var fy: float = y - float(iy)
	var o: int = 2 * ((int(fuv.x) * n + iy) * n + ix)
	var row: int = 2 * n
	var h0: float = lerpf(float(_heights.decode_u16(o)), float(_heights.decode_u16(o + 2)), fx)
	var h1: float = lerpf(float(_heights.decode_u16(o + row)), float(_heights.decode_u16(o + row + 2)), fx)
	return Sphere.RELIEF_MIN + lerpf(h0, h1, fy) * _relief_scale


## Unit surface normal from 3 samples (dir, dir + one texel east, dir + one texel north) in the tangent plane
## (03 s6.2): the height gradient per metre of arc, so a constant-height map gives exactly the radial normal.
func normal_at(dir: Vector3) -> Vector3:
	var up: Vector3 = dir.normalized()
	if face_resolution == 0:
		return up
	var frame: Basis = Sphere.tangent_frame(up)
	var h0: float = height_at(up)
	var d1: Vector3 = (up + frame.x * _texel_rad).normalized()
	var d2: Vector3 = (up + frame.y * _texel_rad).normalized()
	var ge: float = (height_at(d1) - h0) / (Sphere.PLANET_RADIUS * up.angle_to(d1))
	var gn: float = (height_at(d2) - h0) / (Sphere.PLANET_RADIUS * up.angle_to(d2))
	return (up - frame.x * ge - frame.y * gn).normalized()


## Raw baked u16 height word of texel (x, y) on `face` (seam and baker parity checks).
func height_texel(face: int, x: int, y: int) -> int:
	return _heights.decode_u16(2 * ((face * face_resolution + y) * face_resolution + x))


## dir * (R + height_at(dir)).
func surface_point(dir: Vector3) -> Vector3:
	var up: Vector3 = dir.normalized()
	return up * (Sphere.PLANET_RADIUS + height_at(up))


## Biome id (07 s2.1) of the nearest texel; 0 on the flat stub.
func biome_at(dir: Vector3) -> int:
	if face_resolution == 0:
		return 0
	return _biomes[_nearest_texel(dir)]


## Slope in degrees (0..90, 0.5 degree steps) of build-grid cell `cell` = face * n * n + j * n + i with
## n = face_resolution (GRID_BUILD = 1024 on production maps; the cache is the baked slope.u8).
func slope_deg_at(cell: int) -> float:
	if face_resolution == 0:
		return 0.0
	return float(_slopes[cell]) * SLOPE_STEP_DEG


## Slope of the texel nearest to `dir`.
func slope_deg_at_dir(dir: Vector3) -> float:
	return slope_deg_at(_nearest_texel(dir)) if face_resolution > 0 else 0.0


func _nearest_texel(dir: Vector3) -> int:
	var fuv: Vector3 = Sphere.dir_to_face_uv(dir)
	var n: int = face_resolution
	var x: int = int(fuv.y * _nm1 + 0.5)
	var y: int = int(fuv.z * _nm1 + 0.5)
	return (int(fuv.x) * n + y) * n + x
