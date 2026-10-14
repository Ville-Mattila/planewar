extends GdUnitTestSuite
## TA-24: sky_moon hookup (07 s1.5, 03 s7.8, R0 C2-31): the Earth is a 6 degree disc exactly at -Z, the sun disc
## 2 degrees at sun_dir, vacuum (no scattering); SkyMoon.apply switches an Environment to the sky.

var _src: String = ""


func before() -> void:
	_src = FileAccess.get_file_as_string(SkyMoon.SHADER_PATH)


func test_earth_is_exactly_at_minus_z() -> void:
	assert_vector(SkyMoon.earth_dir()).is_equal(Vector3(0, 0, -1))
	assert_vector(SkyMoon.earth_dir()).is_equal(-Sphere.POLE_AXIS)
	assert_str(_src).contains("const vec3 EARTH_DIR = vec3(0.0, 0.0, -1.0);")


func test_disc_sizes_in_the_shader() -> void:
	var rx: RegEx = RegEx.create_from_string("const float EARTH_HALF_DEG = ([0-9.]+);")
	assert_float(float(rx.search(_src).get_string(1)) * 2.0).is_equal(SkyMoon.EARTH_DIAMETER_DEG)
	rx = RegEx.create_from_string("const float SUN_HALF_DEG = ([0-9.]+);")
	assert_float(float(rx.search(_src).get_string(1)) * 2.0).is_equal(SkyMoon.SUN_DIAMETER_DEG)
	assert_str(_src).contains("#include \"res://src/presentation/shaders/moon_light.gdshaderinc\"")   # sun_dir comes from the include
	assert_str(_src).not_contains("global uniform vec3 sun_dir;")
	assert_str(_src).contains("shader_type sky;")


func test_apply_switches_the_environment_to_the_sky() -> void:
	var env: Environment = MoonLight.make_environment()
	SkyMoon.apply(env)
	assert_int(env.background_mode).is_equal(Environment.BG_SKY)
	assert_object(env.sky).is_not_null()
	assert_object(env.sky.sky_material).is_not_null()
	assert_float(env.ambient_light_energy).is_equal(0.0)     # the include stays the single ambient source
	assert_int(env.ambient_light_source).is_equal(Environment.AMBIENT_SOURCE_COLOR)


func test_colour_handling_goes_through_ml_encode_without_a_glow_gradient() -> void:
	assert_str(_src).contains("#define ML_NO_LIGHT")
	assert_str(_src).contains("ml_encode(col)")
	assert_str(_src).not_contains("pow(max(cos_s")                # 07 s1.1 rule 5: a flat halo disc, not a pow() glow


func test_space_path_constant_is_the_encoded_space_colour() -> void:
	var rx: RegEx = RegEx.create_from_string("const vec3 SPACE_ENC = vec3\\(([0-9.]+), ([0-9.]+), ([0-9.]+)\\);")
	var m: RegExMatch = rx.search(_src)
	assert_object(m).is_not_null()
	var lin: Vector3 = Vector3(0.00152, 0.00212, 0.00368)    # #05070C, linear
	for i: int in 3:
		# measured: the framebuffer byte is (5, 7, 12) with this constant, within 1 LSB of ml_encode(SPACE)
		assert_float(float(m.get_string(i + 1))).is_equal_approx(_ml_encode(lin[i]), 1.5 / 255.0)


func test_stars_fit_inside_their_cell() -> void:
	var margin: RegEx = RegEx.create_from_string("cell \\+ ([0-9.]+) \\+ ([0-9.]+) \\* vec3")
	var radius: RegEx = RegEx.create_from_string("smoothstep\\(([0-9.]+), 0.0, distance\\(sp, centre\\)\\)")
	var lo: float = float(margin.search(_src).get_string(1))
	var span: float = float(margin.search(_src).get_string(2))
	var r: float = float(radius.search(_src).get_string(1))
	assert_float(r).is_less_equal(lo)                              # no cell-edge clipping
	assert_float(lo + span + r).is_less_equal(1.0 + 0.001)


## CPU port of ml_encode (moon_light.gdshaderinc): Newton on Compatibility's decode polynomial.
func _ml_encode(l: float) -> float:
	var x: float = 1.055 * pow(l, 1.0 / 2.4) - 0.055 if l >= 0.0031308 else l * 12.92
	for _i: int in 2:
		var f: float = x * (x * (x * 0.305306011 + 0.682171111) + 0.012522878) - l
		var df: float = x * (x * 3.0 * 0.305306011 + 2.0 * 0.682171111) + 0.012522878
		x -= f / df
	return clampf(x, 0.0, 1.0)
