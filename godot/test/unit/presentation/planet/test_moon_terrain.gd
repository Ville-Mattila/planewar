extends GdUnitTestSuite
## TA-24: moon_terrain.gdshader and its material (07 s3.1, 03 s7.8): constants mirrored by MoonDetail, the
## 1.2 m / 0.6 m displacement caps, mean-zero crater profile, biome array == Terrain.biome_at, ramp rows by
## biome id, shared light include and the ml_* colour discipline (ART-01).

const MAP: String = "res://content/maps/s_world1_r6000"

var _src: String = ""


func before() -> void:
	_src = FileAccess.get_file_as_string(MoonTerrain.SHADER_PATH)


## Value of `const float NAME = x;` in the shader source.
func _const(name: String) -> float:
	var rx: RegEx = RegEx.create_from_string("const float " + name + " = ([0-9.]+);")
	var m: RegExMatch = rx.search(_src)
	assert_object(m).is_not_null()
	return float(m.get_string(1))


func test_shader_loads_includes_light_and_encodes_colour() -> void:
	var sh: Shader = load(MoonTerrain.SHADER_PATH)
	assert_object(sh).is_not_null()
	assert_int(sh.get_mode()).is_equal(Shader.MODE_SPATIAL)
	assert_str(_src).contains("moon_light.gdshaderinc")
	assert_str(_src).contains("ml_encode(ml.albedo)")
	assert_str(_src).contains("ml_to_linear(ramp_rgb(")
	assert_str(_src).contains("render_mode cull_back, depth_draw_opaque")


func test_constants_mirror_the_shader() -> void:
	assert_float(_const("DETAIL_AMP_40")).is_equal_approx(MoonDetail.AMPLITUDES_M[0], 1e-6)
	assert_float(_const("DETAIL_AMP_15")).is_equal_approx(MoonDetail.AMPLITUDES_M[1], 1e-6)
	assert_float(_const("DETAIL_AMP_6")).is_equal_approx(MoonDetail.AMPLITUDES_M[2], 1e-6)
	assert_float(_const("FOOTPRINT_KEEP")).is_equal_approx(MoonDetail.FOOTPRINT_KEEP, 1e-6)
	assert_float(_const("FOOTPRINT_OUTER")).is_equal_approx(MoonDetail.FOOTPRINT_OUTER, 1e-6)
	assert_str(_src).contains("crater_layer(p, 40.0)")
	assert_str(_src).contains("crater_layer(p + 5.1, 15.0)")
	assert_str(_src).contains("crater_layer(p + 9.7, 6.0)")
	assert_int(int(_const("DETAIL_AMP_40") * 10.0)).is_equal(6)
	assert_float(FlattenSites.OUTER_FACTOR).is_equal(MoonDetail.FOOTPRINT_OUTER)
	assert_int(FlattenSites.MAX_SHADER_SITES).is_equal(MoonTerrain.MAX_SITES)
	assert_str(_src).contains("const int MAX_SITES = %d;" % MoonTerrain.MAX_SITES)


func test_displacement_caps() -> void:
	var total: float = 0.0
	for a: float in MoonDetail.AMPLITUDES_M:
		total += a
	assert_float(total).is_equal_approx(MoonDetail.TOTAL_M, 1e-6)
	assert_float(MoonDetail.TOTAL_M).is_equal(1.2)
	# worst case: every layer at its bowl centre at once; the shader scales by footprint_scale
	for r: float in [4.0, 8.68, 20.0]:
		assert_float(MoonDetail.max_displacement(0.0, r)).is_less_equal(0.6 + 1e-6)
		assert_float(MoonDetail.max_displacement(r, r)).is_less_equal(0.6 + 1e-6)
		assert_float(MoonDetail.max_displacement(r * 3.0, r)).is_equal_approx(1.2, 1e-6)
	assert_float(MoonDetail.FOOTPRINT_MAX_M).is_equal_approx(0.6, 1e-9)
	# the blend is monotone from the footprint edge to the outer radius
	var prev: float = 0.0
	for k: int in 11:
		var s: float = MoonDetail.footprint_scale(10.0 + 5.0 * float(k) / 10.0, 10.0)
		assert_float(s).is_greater_equal(prev)
		prev = s


func test_crater_profile_is_mean_zero_bowl_with_rim() -> void:
	assert_float(MoonDetail.profile(0.0)).is_equal_approx(-1.0, 1e-9)
	assert_float(MoonDetail.profile(1.0)).is_equal(0.0)
	var peak: float = -INF
	var acc: float = 0.0
	var n: int = 4000
	for k: int in n:
		var t: float = (float(k) + 0.5) / float(n)
		peak = maxf(peak, MoonDetail.profile(t))
		acc += MoonDetail.profile(t) * t / float(n)     # area-weighted: integral of h(t) t dt
	assert_float(acc).is_equal_approx(0.0, 1e-4)
	assert_float(peak).is_equal_approx(1.0 / 3.0, 1e-3)


func test_range_fade() -> void:
	assert_float(MoonDetail.range_fade(10.0, 300.0)).is_equal(1.0)
	assert_float(MoonDetail.range_fade(300.0, 300.0)).is_equal(0.0)
	assert_float(MoonDetail.range_fade(10.0, 0.0)).is_equal(0.0)
	assert_float(MoonDetail.range_fade(225.0, 300.0)).is_between(0.0, 1.0)


func test_measure_material_biome_selects_the_ramp_row_and_blends_edges() -> void:
	var m: ShaderMaterial = MoonTerrain.measure_material_biome(5)
	var arr: Texture2DArray = m.get_shader_parameter(&"biome_faces")
	assert_int(arr.get_layers()).is_equal(Terrain.FACE_COUNT)
	var layer: Image = arr.get_layer_data(0)     # null without a rendering device (CI headless dummy driver)
	if layer != null:
		assert_int(layer.get_pixel(0, 0).r8).is_equal(5)
	assert_float(m.get_shader_parameter(&"ramp_v_override")).is_equal(MoonTerrain.MEASURE_RAMP_V)
	assert_float(m.get_shader_parameter(&"detail_range_m")).is_equal(0.0)
	# ART-14: ids stay nearest, the colour is blended over the four texels (no stair-stepped patch edges)
	assert_str(_src).contains("sampler2DArray biome_faces : filter_nearest")
	assert_str(_src).contains("mix(mix(c00, c10, f.x), mix(c01, c11, f.x), f.y)")


func test_base_material_has_ramp_and_default_biome() -> void:
	var m: ShaderMaterial = MoonTerrain.base_material()
	assert_object(m.get_shader_parameter(&"ramp")).is_not_null()
	assert_object(m.get_shader_parameter(&"biome_faces")).is_not_null()
	assert_int(m.render_priority).is_equal(-1)
	var plate: ShaderMaterial = MoonTerrain.measure_material()
	assert_float(plate.get_shader_parameter(&"ramp_v_override")).is_equal(MoonTerrain.MEASURE_RAMP_V)
	assert_float(plate.get_shader_parameter(&"detail_range_m")).is_equal(0.0)


func test_biome_array_matches_biome_at_by_texel() -> void:
	var t: Terrain = Terrain.new()
	assert_int(t.load_map(MAP)).is_equal(OK)
	assert_object(MoonTerrain.biome_array(t)).is_not_null()
	var layers: Array[Image] = MoonTerrain.biome_images(t)
	assert_int(layers.size()).is_equal(6)
	var n: int = t.face_resolution
	var seen: Dictionary = {}
	for f: int in Terrain.FACE_COUNT:
		var img: Image = layers[f]
		for k: int in 400:
			var x: int = (k * 977 + f * 131) % n
			var y: int = (k * 389 + f * 71) % n
			var d: Vector3 = Sphere.face_uv_to_dir(f, float(x) / float(n - 1), float(y) / float(n - 1))
			var id: int = t.biome_at(d)
			seen[id] = true
			assert_int(img.get_pixel(x, y).r8).is_equal(id)
	assert_int(seen.size()).is_greater(1)       # the test map mixes biomes


func test_make_material_takes_the_tier_detail_range() -> void:
	var t: Terrain = Terrain.new()
	assert_int(t.load_map(MAP)).is_equal(OK)
	var cfg: PlanetTierConfig = PlanetTierConfig.new()
	cfg.detail_range_m = 321.0
	var m: ShaderMaterial = MoonTerrain.make_material(t, cfg)
	assert_float(m.get_shader_parameter(&"detail_range_m")).is_equal(321.0)


func test_set_sites_pads_and_counts() -> void:
	var m: ShaderMaterial = MoonTerrain.base_material()
	var sites: PackedVector4Array = PackedVector4Array([Vector4(1, 2, 3, 8), Vector4(4, 5, 6, 9)])
	MoonTerrain.set_sites(m, sites)
	assert_int(m.get_shader_parameter(&"site_count")).is_equal(2)
	var got: PackedVector4Array = m.get_shader_parameter(&"sites")
	assert_int(got.size()).is_equal(MoonTerrain.MAX_SITES)
	assert_float(got[1].w).is_equal(9.0)
	var many: PackedVector4Array = PackedVector4Array()
	for i: int in 50:
		var _a: bool = many.push_back(Vector4(float(i), 0, 0, 5))
	MoonTerrain.set_sites(m, many)
	assert_int(m.get_shader_parameter(&"site_count")).is_equal(MoonTerrain.MAX_SITES)
