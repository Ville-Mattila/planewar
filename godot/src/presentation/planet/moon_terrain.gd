class_name MoonTerrain extends RefCounted
## Builds the planet material (`shaders/moon_terrain.gdshader`, 07 s3.1): the 64 x 16 biome ramp, the six baked
## biome faces as one R8 Texture2DArray (nearest; uploaded once, ~6 MB at 1,024^2, 03 s11), the tier's detail
## range and the footprint sites. Why a texture and not a per-vertex biome: a vertex attribute blends ids across
## triangles (ramp rows are not ordered), and 1,089 vertices per chunk cannot resolve the 9 m texels; per pixel
## `texelFetch` reproduces `Terrain.biome_at` exactly. All static.

const SHADER_PATH: String = "res://src/presentation/planet/shaders/moon_terrain.gdshader"
const RAMP_PATH: String = "res://assets/textures/moon_ramp.png"
const MAX_SITES: int = 32                     ## sites[] capacity of the shader (FlattenSites.MAX_SHADER_SITES)
const DEFAULT_DETAIL_RANGE_M: float = 300.0
const MEASURE_RAMP_V: float = 0.5             ## ramp stop "mid" (07 s2.1) for measurement plates


## Material with the ramp and a 1 x 1 mare biome array (no map): lookdev scenes, tests.
static func base_material() -> ShaderMaterial:
	MoonLight.ensure_globals()
	var m: ShaderMaterial = ShaderMaterial.new()
	m.shader = load(SHADER_PATH)
	m.render_priority = -1                    # 03 s7.6: planet -1, structures 0
	m.set_shader_parameter(&"ramp", load(RAMP_PATH))
	m.set_shader_parameter(&"biome_faces", flat_biome_array(0))
	m.set_shader_parameter(&"detail_range_m", DEFAULT_DETAIL_RANGE_M)
	m.set_shader_parameter(&"site_count", 0)
	return m


## The planet material for `terrain` at tier `cfg`.
static func make_material(terrain: Terrain, cfg: PlanetTierConfig) -> ShaderMaterial:
	var m: ShaderMaterial = base_material()
	if terrain.face_resolution > 0:
		m.set_shader_parameter(&"biome_faces", biome_array(terrain))
	m.set_shader_parameter(&"detail_range_m", cfg.detail_range_m)
	return m


## Mare mid at ramp value 0.5, no detail: the Midnight Pole measurement plates (ART-01 goldens).
static func measure_material() -> ShaderMaterial:
	var m: ShaderMaterial = base_material()
	m.set_shader_parameter(&"ramp_v_override", MEASURE_RAMP_V)
	m.set_shader_parameter(&"detail_range_m", 0.0)
	return m


## The six baked biome faces as an R8 array layer per cube face (layer = face).
static func biome_array(terrain: Terrain) -> Texture2DArray:
	var n: int = terrain.face_resolution
	var layers: Array[Image] = []
	for f: int in Terrain.FACE_COUNT:
		layers.append(Image.create_from_data(n, n, false, Image.FORMAT_R8, terrain.biome_face(f)))
	var t: Texture2DArray = Texture2DArray.new()
	var _e: Error = t.create_from_images(layers)
	return t


## A 1 x 1 x 6 array filled with biome `id`.
static func flat_biome_array(id: int) -> Texture2DArray:
	var layers: Array[Image] = []
	for f: int in Terrain.FACE_COUNT:
		layers.append(Image.create_from_data(1, 1, false, Image.FORMAT_R8, PackedByteArray([id])))
	var t: Texture2DArray = Texture2DArray.new()
	var _e: Error = t.create_from_images(layers)
	return t


## Writes the footprint sites (x, y, z, radius) into `m`; at most MAX_SITES are used.
static func set_sites(m: ShaderMaterial, sites: PackedVector4Array) -> void:
	var padded: PackedVector4Array = sites.slice(0, MAX_SITES)
	var count: int = padded.size()
	var _r: int = padded.resize(MAX_SITES)
	m.set_shader_parameter(&"sites", padded)
	m.set_shader_parameter(&"site_count", count)
