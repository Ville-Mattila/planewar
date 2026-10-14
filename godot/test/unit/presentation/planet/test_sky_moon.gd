extends GdUnitTestSuite
## TA-24: sky_moon hookup (07 s1.5, 03 s7.8, R0 C2-31): the Earth is a 6 degree disc exactly at -Z, the sun disc
## 2 degrees at sun_dir, vacuum (no scattering); SkyMoon.apply switches an Environment to the sky.

var _src: String = ""


func before() -> void:
	_src = FileAccess.get_file_as_string(SkyMoon.SHADER_PATH)


func test_earth_is_exactly_at_minus_z() -> void:
	assert_vector(SkyMoon.earth_dir()).is_equal(Vector3(0, 0, -1))
	assert_vector(SkyMoon.earth_dir()).is_equal(-Sphere.POLE_AXIS)
	assert_str(_src).contains("vec3 earth_dir = vec3(0.0, 0.0, -1.0);")


func test_disc_sizes_in_the_shader() -> void:
	var rx: RegEx = RegEx.create_from_string("const float EARTH_HALF_DEG = ([0-9.]+);")
	assert_float(float(rx.search(_src).get_string(1)) * 2.0).is_equal(SkyMoon.EARTH_DIAMETER_DEG)
	rx = RegEx.create_from_string("const float SUN_HALF_DEG = ([0-9.]+);")
	assert_float(float(rx.search(_src).get_string(1)) * 2.0).is_equal(SkyMoon.SUN_DIAMETER_DEG)
	assert_str(_src).contains("global uniform vec3 sun_dir;")
	assert_str(_src).contains("shader_type sky;")


func test_apply_switches_the_environment_to_the_sky() -> void:
	var env: Environment = MoonLight.make_environment()
	SkyMoon.apply(env)
	assert_int(env.background_mode).is_equal(Environment.BG_SKY)
	assert_object(env.sky).is_not_null()
	assert_object(env.sky.sky_material).is_not_null()
	assert_float(env.ambient_light_energy).is_equal(0.0)     # the include stays the single ambient source
	assert_int(env.ambient_light_source).is_equal(Environment.AMBIENT_SOURCE_COLOR)
