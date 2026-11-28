class_name SlopedMapKit extends RefCounted
## BUG-6 (R0 B.33 A-158) fixture: a valid baked map whose ground is a plane tilted `slope_deg` about the +X axis
## direction, rising toward +Y (east of a pad at +X with fwd +Y). Height = tan(slope) x R x longitude, clamped to
## +-CLAMP_ARC_M of arc, so it stays inside the relief range. On face 0 the equal-angle u coordinate is linear in
## longitude, so the bilinear sample is the plane exactly (to the u16 step) around the pad. Written to user:// and
## loaded through Terrain.load_map like any bake (SHA-256 checked).

const N: int = 65                   ## texels per face edge: 147 m spacing, the clamp is 6+ texels from the pad
const CLAMP_ARC_M: float = 1000.0   ## the ramp is flat beyond this arc from the pad (|h| <= 268 m at 15 degrees)
const ROOT: String = "user://bug6_sloped_"


## Writes the map for `slope_deg` (0 = level, the datum) and returns its directory.
static func write(slope_deg: float) -> String:
	var dir: String = ROOT + str(roundi(slope_deg * 10.0))
	var _m: Error = DirAccess.make_dir_recursive_absolute(dir)
	var k: float = tan(deg_to_rad(slope_deg))
	var lim: float = CLAMP_ARC_M / Sphere.PLANET_RADIUS
	var scale: float = float(Terrain.U16_MAX) / (Sphere.RELIEF_MAX - Sphere.RELIEF_MIN)
	var outputs: Dictionary = {}
	var cells: int = N * N
	var b: PackedByteArray = PackedByteArray()
	var _r: int = b.resize(cells)
	b.fill(0)
	var sl: PackedByteArray = PackedByteArray()
	_r = sl.resize(cells)
	sl.fill(roundi(slope_deg / Terrain.SLOPE_STEP_DEG))
	for f: int in Terrain.FACE_COUNT:
		var h: PackedByteArray = PackedByteArray()
		_r = h.resize(cells * 2)
		for y: int in N:
			for x: int in N:
				var d: Vector3 = Sphere.face_uv_to_dir(f, float(x) / float(N - 1), float(y) / float(N - 1))
				var lon: float = clampf(atan2(d.y, d.x), -lim, lim)
				var m: float = k * Sphere.PLANET_RADIUS * lon
				h.encode_u16(2 * (y * N + x), clampi(roundi((m - Sphere.RELIEF_MIN) * scale), 0, Terrain.U16_MAX))
		_put(dir, "face%d.height.u16" % f, h, outputs)
		_put(dir, "face%d.biome.u8" % f, b, outputs)
		_put(dir, "face%d.slope.u8" % f, sl, outputs)
	var names: Array = outputs.keys()
	names.sort()
	var cat: String = ""
	for key: Variant in names:
		cat += str(outputs[key])
	var meta: Dictionary = {"schema_version": 1, "id": "bug6_sloped", "radius_m": Sphere.PLANET_RADIUS,
		"face_resolution": N, "relief": {"min_m": Sphere.RELIEF_MIN, "max_m": Sphere.RELIEF_MAX},
		"outputs": outputs, "map_hash": cat.sha256_text()}
	var fm: FileAccess = FileAccess.open(dir.path_join("meta.json"), FileAccess.WRITE)
	var _ok: bool = fm.store_string(JSON.stringify(meta))
	fm.close()
	return dir


## Loads the `slope_deg` map into `t` (asserts OK).
static func load_into(t: Terrain, slope_deg: float) -> void:
	var err: Error = t.load_map(write(slope_deg))
	assert(err == OK, "sloped map failed to load")


## Removes every map write() made.
static func remove_all() -> void:
	var user: DirAccess = DirAccess.open("user://")
	if user == null:
		return
	for sub: String in user.get_directories():
		if not ("user://" + sub).begins_with(ROOT):
			continue
		var d: DirAccess = DirAccess.open("user://" + sub)
		for file: String in d.get_files():
			var _e: Error = d.remove(file)
		var _e2: Error = DirAccess.remove_absolute("user://" + sub)


## The point `alt` metres radially above the terrain under the spot `off` metres along pad slot `p`'s fwd: where a
## ship of radius `alt` rests (Kinematics' radial push-out to R + height + radius, 03 s5.3 step 6).
static func resting(t: Terrain, store: EntityStore, p: int, off: float, alt: float) -> Vector3:
	var d: Vector3 = (store.pos[p] + store.fwd[p] * off).normalized()
	return d * (Sphere.PLANET_RADIUS + t.height_at(d) + alt)


static func _put(dir: String, file: String, bytes: PackedByteArray, outputs: Dictionary) -> void:
	var f: FileAccess = FileAccess.open(dir.path_join(file), FileAccess.WRITE)
	var _ok: bool = f.store_buffer(bytes)
	f.close()
	var ctx: HashingContext = HashingContext.new()
	var _s: Error = ctx.start(HashingContext.HASH_SHA256)
	_s = ctx.update(bytes)
	outputs[file] = ctx.finish().hex_encode()
