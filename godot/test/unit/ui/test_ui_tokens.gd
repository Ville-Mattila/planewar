extends GdUnitTestSuite
## UiTokens must match tools/blender/palette.json exactly (UX-12; docs/07 s2).


func _palette() -> Dictionary:
	var path: String = ProjectSettings.globalize_path("res://").path_join("../tools/blender/palette.json")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert_bool(parsed is Dictionary).is_true()
	return parsed as Dictionary


func _consts() -> Dictionary:
	return (UiTokens as Script).get_script_constant_map()


func _check_group(group: Dictionary, prefix: String) -> void:
	var consts: Dictionary = _consts()
	for key: String in group:
		var name: String = (prefix + key).to_upper()
		assert_bool(consts.has(name)).override_failure_message("missing token " + name).is_true()
		var want: Color = Color(str(group[key]))
		assert_bool((consts[name] as Color).is_equal_approx(want)).override_failure_message("drift " + name).is_true()


func test_ui_tokens_match_palette() -> void:
	_check_group(_palette()["ui"] as Dictionary, "")


func test_relation_tokens_match_palette() -> void:
	_check_group(_palette()["relation"] as Dictionary, "relation_")


func test_world_tokens_match_palette() -> void:
	_check_group(_palette()["world"] as Dictionary, "world_")


func test_team_tokens_match_palette() -> void:
	var team: Array = _palette()["team"] as Array
	assert_int(UiTokens.TEAM.size()).is_equal(team.size())
	for i: int in team.size():
		var want: Color = Color(str((team[i] as Dictionary)["hex"]))
		assert_bool(UiTokens.team_color(i).is_equal_approx(want)).is_true()
	assert_bool(UiTokens.team_color(99).is_equal_approx(UiTokens.TEAM[team.size() - 1])).is_true()
