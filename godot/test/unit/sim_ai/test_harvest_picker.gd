extends GdUnitTestSuite
## GD-12 contract tests (sim_ai/MODULE.md `HarvestPicker`; 02 s8.2 "re-targets the nearest field with free capacity",
## 05 s6.6 PICK_FIELD utility): a pure function, no world.

const R: float = Sphere.PLANET_RADIUS
const WEIGHT: float = 0.5                 ## 05 s6.6 `0.5 * harvesters_assigned`


func _dir(east: float) -> Vector3:
	return Vector3(cos(east / R), sin(east / R), 0.0)


func test_utility_is_the_05_s6_6_formula() -> void:
	# remaining01 / (1 + path_km) / (1 + w * assigned) * (1 - risk)
	assert_float(HarvestPicker.utility(1.0, 0.0, 0, 0.0, WEIGHT)).is_equal_approx(1.0, 1e-6)
	assert_float(HarvestPicker.utility(0.5, 1000.0, 2, 0.25, WEIGHT)).is_equal_approx(0.5 / 2.0 / 2.0 * 0.75, 1e-6)


func test_picks_the_nearest_field_with_remaining_ore_and_a_free_miner_slot() -> void:
	var dirs: PackedVector3Array = PackedVector3Array([_dir(0.0), _dir(700.0), _dir(1500.0)])
	var rem: PackedFloat32Array = PackedFloat32Array([1.0, 1.0, 1.0])
	var free: PackedInt32Array = PackedInt32Array([4, 4, 4])
	var assigned: PackedInt32Array = PackedInt32Array([0, 0, 0])
	assert_int(HarvestPicker.pick(_dir(650.0), dirs, rem, free, assigned, WEIGHT, -1)).is_equal(1)
	free[1] = 0                                                   # max_miners reached: re-target
	assert_int(HarvestPicker.pick(_dir(650.0), dirs, rem, free, assigned, WEIGHT, -1)).is_equal(0)
	rem[0] = 0.0                                                  # depleted: re-target
	assert_int(HarvestPicker.pick(_dir(650.0), dirs, rem, free, assigned, WEIGHT, -1)).is_equal(2)
	rem[2] = 0.0
	assert_int(HarvestPicker.pick(_dir(650.0), dirs, rem, free, assigned, WEIGHT, -1)).is_equal(-1)


func test_crowding_and_remaining_ore_trade_against_distance() -> void:
	var dirs: PackedVector3Array = PackedVector3Array([_dir(0.0), _dir(1000.0)])
	var rem: PackedFloat32Array = PackedFloat32Array([0.9, 0.9])
	var free: PackedInt32Array = PackedInt32Array([4, 4])
	var assigned: PackedInt32Array = PackedInt32Array([3, 0])
	# From 100 m: field 0 is 100 m away but has 3 assigned (U = 0.9 / 1.1 / 2.5), field 1 is 900 m (0.9 / 1.9)
	assert_int(HarvestPicker.pick(_dir(100.0), dirs, rem, free, assigned, WEIGHT, -1)).is_equal(1)
	assigned[0] = 0
	assert_int(HarvestPicker.pick(_dir(100.0), dirs, rem, free, assigned, WEIGHT, -1)).is_equal(0)


func test_avoid_skips_the_field_just_left_and_ties_take_the_lowest_index() -> void:
	var dirs: PackedVector3Array = PackedVector3Array([_dir(500.0), _dir(-500.0)])
	var rem: PackedFloat32Array = PackedFloat32Array([1.0, 1.0])
	var free: PackedInt32Array = PackedInt32Array([4, 4])
	var assigned: PackedInt32Array = PackedInt32Array([0, 0])
	assert_int(HarvestPicker.pick(_dir(0.0), dirs, rem, free, assigned, WEIGHT, -1)).is_equal(0)
	assert_int(HarvestPicker.pick(_dir(0.0), dirs, rem, free, assigned, WEIGHT, 0)).is_equal(1)
