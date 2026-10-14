extends GdUnitTestSuite
## ART-01: the shared light model (07 s1.5). The CPU mirror in MoonLight equals the shader include, the
## constants derive from the 07 hex values, the tuned night mare ratio sits inside the +-20 % band, and the
## shaders that include moon_light.gdshaderinc load with their uniforms.

const _CONST_RE: String = "const\\s+(float|vec3)\\s+(ML_[A-Z_]+)\\s*=\\s*(?:vec3\\()?([-0-9.,\\s]+)\\)?;"


static func _lin(hex: String, k: float) -> Vector3:
	var c: Color = Color(hex).srgb_to_linear()
	return Vector3(c.r, c.g, c.b) * k


static func _include_consts() -> Dictionary:
	var src: String = FileAccess.get_file_as_string(MoonLight.INCLUDE_PATH)
	var re: RegEx = RegEx.create_from_string(_CONST_RE)
	var out: Dictionary = {}
	for m: RegExMatch in re.search_all(src):
		var parts: PackedStringArray = m.get_string(3).split(",")
		if parts.size() == 3:
			out[m.get_string(2)] = Vector3(float(parts[0]), float(parts[1]), float(parts[2]))
		else:
			out[m.get_string(2)] = float(parts[0])
	return out


func test_cpu_mirror_equals_include_constants() -> void:
	var c: Dictionary = _include_consts()
	assert_float(c["ML_WRAP"]).is_equal_approx(MoonLight.WRAP, 1e-6)
	assert_vector(c["ML_AMB_LOW"]).is_equal_approx(MoonLight.AMB_LOW, Vector3.ONE * 1e-6)
	assert_vector(c["ML_AMB_HIGH"]).is_equal_approx(MoonLight.AMB_HIGH, Vector3.ONE * 1e-6)
	assert_vector(c["ML_EARTH"]).is_equal_approx(MoonLight.EARTH, Vector3.ONE * 1e-6)
	assert_float(c["ML_EARTH_GAIN"]).is_equal_approx(MoonLight.EARTH_GAIN, 1e-6)
	assert_float(c["ML_EARTH_BASE"]).is_equal_approx(MoonLight.EARTH_BASE, 1e-6)
	assert_float(c["ML_NIGHT_LO"]).is_equal_approx(MoonLight.NIGHT_LO, 1e-6)
	assert_float(c["ML_NIGHT_HI"]).is_equal_approx(MoonLight.NIGHT_HI, 1e-6)
	assert_vector(c["ML_RIM"]).is_equal_approx(MoonLight.RIM, Vector3.ONE * 1e-6)
	assert_float(c["ML_RIM_NEAR"]).is_equal_approx(MoonLight.RIM_NEAR, 1e-6)
	assert_float(c["ML_RIM_FAR"]).is_equal_approx(MoonLight.RIM_FAR, 1e-6)


func test_constants_derive_from_07_hex_values() -> void:
	var eps: Vector3 = Vector3.ONE * 2e-5
	assert_vector(MoonLight.AMB_LOW).is_equal_approx(_lin("#2B3142", 0.22), eps)
	assert_vector(MoonLight.AMB_HIGH).is_equal_approx(_lin("#8EA0C8", 0.38), eps)
	assert_vector(MoonLight.EARTH).is_equal_approx(_lin("#9DB6E8", 1.0), eps)
	assert_vector(MoonLight.RIM).is_equal_approx(_lin("#BFC9E0", 0.20), eps)
	assert_float(MoonLight.WRAP).is_equal(0.30)
	# Earthshine gain is an anchor tuned within +-20 % (07 s1.5): 0.55 -> 0.50.
	assert_float(absf(MoonLight.EARTH_GAIN / 0.55 - 1.0)).is_less_equal(0.20)


func test_night_mare_ratio_within_20_percent_of_07_target() -> void:
	var r: Vector3 = MoonLight.night_pole_ratio()
	var t: Vector3 = MoonLight.NIGHT_TARGET
	for i: int in 3:
		assert_float(absf(r[i] / t[i] - 1.0)).is_less_equal(MoonLight.NIGHT_TOLERANCE)
	var mare: Vector3 = _lin("#404552", 1.0)
	var w: Vector3 = Vector3(0.2126, 0.7152, 0.0722)
	var y_model: float = w.dot(mare * r)
	var y_target: float = w.dot(mare * t)
	assert_float(absf(y_model / y_target - 1.0)).is_less_equal(MoonLight.NIGHT_TOLERANCE)


func test_earthshine_is_full_at_midnight_pole_and_zero_by_day() -> void:
	var sun: Vector3 = MoonLight.DEFAULT_SUN_DIR
	assert_float(MoonLight.earth_k(Vector3(0, 0, -1), sun)).is_equal_approx(1.0, 1e-6)
	assert_float(MoonLight.earth_k(Vector3(0, 0, 1), sun)).is_equal(0.0)
	assert_float(MoonLight.earth_k(Vector3(1, 0, 0.3).normalized(), sun)).is_equal(0.0)
	var prev: float = -1.0
	for i: int in 10:
		var z: float = -0.1 - 0.09 * float(i)
		var k: float = MoonLight.earth_k(Vector3(sqrt(1.0 - z * z), 0, z), sun)
		assert_float(k).is_greater(prev)
		prev = k


func test_wrap_gives_terminator_bases_23_percent_sun() -> void:
	var up: Vector3 = Vector3(1, 0, 0)
	var day: Vector3 = MoonLight.shade_linear(Vector3.ONE, up, up, MoonLight.DEFAULT_SUN_DIR)
	var amb_earth: Vector3 = MoonLight.AMB_HIGH + MoonLight.EARTH * (MoonLight.EARTH_GAIN * MoonLight.earth_k(up, MoonLight.DEFAULT_SUN_DIR))
	var sun_r: float = MoonLight.SUN_COLOR.srgb_to_linear().r * MoonLight.SUN_ENERGY
	assert_float((day.x - amb_earth.x) / sun_r).is_equal_approx(0.3 / 1.3, 1e-4)


func test_sun_dir_global_and_light_stay_aligned() -> void:
	MoonLight.ensure_globals()
	MoonLight.ensure_globals()
	var sun: DirectionalLight3D = auto_free(MoonLight.make_sun())
	add_child(sun)
	var dir: Vector3 = Vector3(0.3, -0.2, 0.9).normalized()
	MoonLight.set_sun_dir(dir, sun)
	assert_vector(-sun.global_basis.z).is_equal_approx(-dir, Vector3.ONE * 1e-5)
	MoonLight.set_sun_dir(MoonLight.DEFAULT_SUN_DIR, sun)
	assert_vector(-sun.global_basis.z).is_equal_approx(-Sphere.POLE_AXIS, Vector3.ONE * 1e-5)


func test_environment_is_ldr_without_engine_ambient() -> void:
	var env: Environment = MoonLight.make_environment()
	assert_int(env.ambient_light_source).is_equal(Environment.AMBIENT_SOURCE_COLOR)
	assert_float(env.ambient_light_energy).is_equal(0.0)
	assert_int(env.tonemap_mode).is_equal(Environment.TONE_MAPPER_LINEAR)
	assert_bool(env.glow_enabled).is_false()
	assert_bool(env.fog_enabled).is_false()


func test_shaders_load_and_share_the_include() -> void:
	for path: String in [MoonLight.MOON_SHADER_PATH, MoonLight.UNIT_SHADER_PATH, MoonLight.UNIT_INSTANCED_SHADER_PATH]:
		var sh: Shader = load(path)
		assert_object(sh).is_not_null()
		assert_int(sh.get_mode()).is_equal(Shader.MODE_SPATIAL)
	var inc: String = FileAccess.get_file_as_string("res://src/presentation/shaders/unit_lit.gdshaderinc")
	assert_str(inc).contains("moon_light.gdshaderinc")
	assert_str(FileAccess.get_file_as_string(MoonLight.MOON_SHADER_PATH)).contains("moon_light.gdshaderinc")
	assert_str(FileAccess.get_file_as_string(MoonLight.UNIT_INSTANCED_SHADER_PATH)).contains("#define UNIT_PARAM instance uniform")
	assert_str(FileAccess.get_file_as_string(MoonLight.UNIT_SHADER_PATH)).contains("#define UNIT_PARAM uniform")


func test_unit_materials_take_team_and_state_per_material_or_instance() -> void:
	var m: ShaderMaterial = MoonLight.unit_material()
	assert_object(m.get_shader_parameter(&"atlas")).is_not_null()
	m.set_shader_parameter(&"team_color", Color("#4C64ED"))
	m.set_shader_parameter(&"team_index", 1)
	assert_int(m.get_shader_parameter(&"team_index")).is_equal(1)
	var mi: MeshInstance3D = auto_free(MeshInstance3D.new())
	mi.material_override = MoonLight.unit_material(true)
	mi.set_instance_shader_parameter(&"team_index", 3)
	assert_int(mi.get_instance_shader_parameter(&"team_index")).is_equal(3)


func test_moon_material_keeps_the_lod_debug_uniforms() -> void:
	var m: ShaderMaterial = MoonLight.moon_material()
	m.set_shader_parameter(&"debug_mix", 0.6)
	assert_float(m.get_shader_parameter(&"debug_mix")).is_equal_approx(0.6, 1e-6)


## The atlas carries the class code in alpha and plain swatches have alpha 0, so the import must keep RGB
## under alpha 0 (fix_alpha_border off, lossless). Cells: 0 hull_100, 18 team_paint_hi, 21 team_glow, 24 mare mid.
func test_imported_atlas_keeps_swatch_rgb_under_zero_alpha() -> void:
	var tex: Texture2D = load(MoonLight.ATLAS_PATH)
	assert_object(tex).is_not_null()
	var img: Image = tex.get_image()
	assert_int(img.get_width()).is_equal(256)
	assert_int(img.get_height()).is_equal(256)
	var expect: Dictionary = {0: Color8(228, 231, 236, 0), 18: Color8(240, 240, 240, 85), 21: Color8(255, 255, 255, 255), 24: Color8(64, 69, 82, 0)}
	for cell: int in expect:
		var c: Color = img.get_pixel((cell % 16) * 16 + 8, (cell >> 4) * 16 + 8)
		var e: Color = expect[cell]
		assert_int(c.r8).is_equal(e.r8)
		assert_int(c.g8).is_equal(e.g8)
		assert_int(c.b8).is_equal(e.b8)
		assert_int(c.a8).is_equal(e.a8)
