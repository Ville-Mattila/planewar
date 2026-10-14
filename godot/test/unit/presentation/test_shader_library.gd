extends GdUnitTestSuite
## ART-03: the shader library. Every shader loads, includes the shared light model (so the Compatibility
## colour-space handling of ART-01 applies), and declares the uniforms its CPU users set.

const DIR: String = "res://src/presentation/shaders/"
const SHADERS: PackedStringArray = ["unit_lit", "unit_lit_instanced", "prop_lit", "vfx_additive", "shield_dome", "hologram_ghost"]


func _uniforms(shader_name: String) -> Array[String]:
	var sh: Shader = load(DIR + shader_name + ".gdshader")
	var out: Array[String] = []
	for u: Dictionary in sh.get_shader_uniform_list():
		out.append(String(u["name"]))
	return out


func test_every_shader_loads_and_includes_moon_light() -> void:
	for n: String in SHADERS:
		var sh: Shader = load(DIR + n + ".gdshader")
		assert_object(sh).is_not_null()
		# unit_lit and its instanced twin reach the light model through unit_lit.gdshaderinc
		var direct: bool = sh.code.contains("moon_light.gdshaderinc") or sh.code.contains("unit_lit.gdshaderinc")
		assert_bool(direct).is_true()
	var body: String = FileAccess.get_file_as_string(DIR + "unit_lit.gdshaderinc")
	assert_str(body).contains("moon_light.gdshaderinc")


func test_effect_shaders_are_additive_without_depth_write() -> void:
	for n: String in ["vfx_additive", "shield_dome", "hologram_ghost"]:
		var sh: Shader = load(DIR + n + ".gdshader")
		assert_str(sh.code).contains("blend_add")
		assert_str(sh.code).contains("depth_draw_never")


func test_prop_lit_has_no_team_zones() -> void:
	var u: Array[String] = _uniforms("prop_lit")
	assert_bool(u.has("atlas")).is_true()
	assert_bool(u.has("team_color")).is_false()


func test_shield_dome_uniforms() -> void:
	var u: Array[String] = _uniforms("shield_dome")
	for k: String in ["tint", "camera_inside", "max_alpha", "ripples", "strength"]:
		assert_bool(u.has(k)).is_true()


func test_hologram_and_vfx_uniforms() -> void:
	var holo: Array[String] = _uniforms("hologram_ghost")
	for k: String in ["tint", "alpha", "clip01", "height_m"]:
		assert_bool(holo.has(k)).is_true()
	var vfx: Array[String] = _uniforms("vfx_additive")
	for k: String in ["tint", "intensity", "mask", "scroll"]:
		assert_bool(vfx.has(k)).is_true()


func test_unit_lit_declares_team_and_state_uniforms() -> void:
	var u: Array[String] = _uniforms("unit_lit")
	for k: String in ["atlas", "team_index", "team_color", "build_progress", "damage01", "wreck"]:
		assert_bool(u.has(k)).is_true()
