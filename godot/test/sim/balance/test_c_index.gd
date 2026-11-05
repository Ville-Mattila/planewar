extends GdUnitTestSuite
## GD-26 index of the thirteen 02 s18.3 scenario tests C-01..C-13: each id names the test files and functions that carry
## it; the suite fails when one is renamed or deleted, so "all thirteen run on every PR" cannot rot silently. The scenario
## JSON files in test/sim/scenarios/ are run by `test_scenarios.gd` (TA-33). Wall time of the heavy ones (local laptop):
## C-06 about 33 s (150 runs), C-08 about 40 s (200 runs), the rest a few seconds each.

# id -> [[file, function], ...]
const INDEX: Dictionary = {
	"C-01": [["res://test/sim/ai/test_c_tower_scenarios.gd", "test_c01_a_bomber_level_above_h_rel_max_draws_no_autocannon_fire"]],
	"C-02": [["res://test/sim/ai/test_c_tower_scenarios.gd", "test_c02_a_dart_below_the_flak_floor_for_twenty_seconds_draws_no_shell"]],
	"C-03": [["res://test/unit/sim/combat/test_tower_gates.gd", "test_c03_no_lock_under_the_agl_floor_in_ten_seconds_and_a_lock_above_it"]],
	"C-04": [["res://test/unit/sim/combat/test_tower_gates.gd", "test_c04_flip_breaks_the_lock_inside_the_window_only"]],
	"C-05": [["res://test/sim/balance/test_c05_lancer_vs_autocannon.gd", "test_c05_a_lancer_at_800_m_destroys_the_autocannon_in_under_25_s_and_takes_no_damage"]],
	"C-06": [["res://test/sim/balance/test_c06_bomber_vs_flak.gd", "test_c06_one_flak_the_bomber_survives_to_release_at_least_the_floor"],
		["res://test/sim/balance/test_c06_bomber_vs_flak.gd", "test_c06_two_flak_the_bomber_dies_before_release_at_least_the_floor"]],
	"C-07": [["res://test/unit/sim/combat/test_shield_domes.gd", "test_c07_four_bombs_within_five_seconds_three_absorbed_fourth_passes_and_the_dome_collapses"]],
	"C-08": [["res://test/sim/balance/test_c08_dart_duel.gd", "test_c08_the_band_or_its_tripwire"]],
	"C-09": [["res://test/unit/sim/combat/test_combat_world.gd", "test_c09_pad_dock_dies_hangar_dock_lives"]],
	"C-10": [["res://test/unit/content/test_doctrine_resolve.gd", "test_vanguard_examples"],
		["res://test/unit/content/test_doctrine_resolve.gd", "test_bulwark_examples"],
		["res://test/unit/content/test_doctrine_resolve.gd", "test_foundry_examples"]],
	"C-11": [["res://test/unit/sim/build/test_build.gd", "test_outpost_presence_and_spacing"],
		["res://test/sim/scenarios/outpost_presence_boundary.json", "C-11"]],
	"C-12": [["res://test/unit/sim/economy/test_power.gd", "test_c12_towers_fire_zero_at_ratio_045_and_scale_above_half"],
		["res://test/unit/sim/economy/test_power.gd", "test_c12_production_scales_and_construction_does_not"]],
	"C-13": [["res://test/unit/sim/combat/test_shield_domes.gd", "test_c13_eight_bombs_on_a_towerless_core_six_absorbed_the_core_keeps_600_hp"],
		["res://test/sim/scenarios/core_shield_dome.json", "C-13"]],
}


func test_all_thirteen_scenario_ids_are_indexed() -> void:
	assert_int(INDEX.size()).is_equal(13)
	for k: int in range(1, 14):
		assert_bool(INDEX.has("C-%02d" % k)).override_failure_message("C-%02d missing from the index" % k).is_true()


func test_every_indexed_test_still_exists() -> void:
	for id: String in INDEX:
		for pair: Array in INDEX[id]:
			var path: String = pair[0]
			var needle: String = pair[1]
			var text: String = FileAccess.get_file_as_string(path)
			assert_bool(not text.is_empty()).override_failure_message("%s: %s is missing" % [id, path]).is_true()
			var found: bool = text.contains("func %s(" % needle) if path.ends_with(".gd") else text.contains(needle)
			assert_bool(found).override_failure_message("%s: %s no longer holds %s" % [id, path, needle]).is_true()
