extends GdUnitTestSuite
## ART-03: the (team, state) unit_lit material cache (07 s4.3 fallback; ART-01 REPORT s5).

const PALETTE_PATH: String = "res://../tools/blender/palette.json"


func _palette_teams() -> Array:
	var f: FileAccess = FileAccess.open(PALETTE_PATH, FileAccess.READ)
	assert_object(f).is_not_null()
	var d: Dictionary = JSON.parse_string(f.get_as_text())
	return d["team"]


func test_team_colours_equal_palette_json() -> void:
	var teams: Array = _palette_teams()
	assert_int(teams.size()).is_equal(UnitMaterialCache.TEAM_COUNT)
	for t: Dictionary in teams:
		var slot: int = int(t["slot"])
		assert_str(UnitMaterialCache.TEAM_HEX[slot]).is_equal(String(t["hex"]))
		var c: Color = UnitMaterialCache.team_color(slot)
		assert_bool(c.is_equal_approx(Color(String(t["hex"])))).is_true()


func test_material_uniforms_carry_team_and_state() -> void:
	var cache: UnitMaterialCache = UnitMaterialCache.new()
	var teams: Array = _palette_teams()
	for t: Dictionary in teams:
		var slot: int = int(t["slot"])
		var m: ShaderMaterial = cache.get_material(slot, UnitMaterialCache.State.HEALTHY)
		assert_int(int(m.get_shader_parameter(&"team_index"))).is_equal(slot)
		var col: Color = m.get_shader_parameter(&"team_color")
		assert_bool(col.is_equal_approx(Color(String(t["hex"])))).is_true()
		assert_float(float(m.get_shader_parameter(&"wreck"))).is_equal(0.0)


func test_cache_reuses_one_material_per_team_and_state() -> void:
	var cache: UnitMaterialCache = UnitMaterialCache.new()
	var a: ShaderMaterial = cache.get_material(3, UnitMaterialCache.State.DAMAGED_2)
	var b: ShaderMaterial = cache.get_material(3, UnitMaterialCache.State.DAMAGED_2)
	assert_bool(a == b).is_true()
	assert_bool(a == cache.get_material(4, UnitMaterialCache.State.DAMAGED_2)).is_false()
	assert_bool(a == cache.get_material(3, UnitMaterialCache.State.WRECK)).is_false()
	assert_int(cache.size()).is_equal(3)


func test_cache_is_bounded_by_teams_times_states() -> void:
	var cache: UnitMaterialCache = UnitMaterialCache.new()
	for _pass: int in 3:
		for t: int in 20:
			for s: int in 9:
				var _m: ShaderMaterial = cache.get_material(t, s)
	assert_int(cache.size()).is_equal(UnitMaterialCache.TEAM_COUNT * UnitMaterialCache.STATE_COUNT)
	cache.clear()
	assert_int(cache.size()).is_equal(0)


func test_state_buckets_follow_damage_steps_and_wreck() -> void:
	assert_int(UnitMaterialCache.state_for(0.0, false)).is_equal(UnitMaterialCache.State.HEALTHY)
	assert_int(UnitMaterialCache.state_for(0.24, false)).is_equal(UnitMaterialCache.State.HEALTHY)
	assert_int(UnitMaterialCache.state_for(0.25, false)).is_equal(UnitMaterialCache.State.DAMAGED_1)
	assert_int(UnitMaterialCache.state_for(0.6, false)).is_equal(UnitMaterialCache.State.DAMAGED_2)
	assert_int(UnitMaterialCache.state_for(0.99, false)).is_equal(UnitMaterialCache.State.DAMAGED_3)
	assert_int(UnitMaterialCache.state_for(0.1, true)).is_equal(UnitMaterialCache.State.WRECK)
	var m: ShaderMaterial = UnitMaterialCache.new().get_material(0, UnitMaterialCache.State.WRECK)
	assert_float(float(m.get_shader_parameter(&"wreck"))).is_equal(1.0)


func test_build_material_is_a_fresh_duplicate_with_progress() -> void:
	var cache: UnitMaterialCache = UnitMaterialCache.new()
	var shared: ShaderMaterial = cache.get_material(2, UnitMaterialCache.State.HEALTHY)
	var a: ShaderMaterial = cache.build_material(2, 0.4)
	var b: ShaderMaterial = cache.build_material(2, 0.4)
	assert_bool(a == b).is_false()
	assert_bool(a == shared).is_false()
	assert_float(float(a.get_shader_parameter(&"build_progress"))).is_equal_approx(0.4, 1e-6)
	assert_float(float(shared.get_shader_parameter(&"build_progress"))).is_equal(1.0)
	assert_int(cache.size()).is_equal(1)
