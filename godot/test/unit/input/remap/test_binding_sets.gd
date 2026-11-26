extends GdUnitTestSuite
## UX-48 BindingStore mode-set queries (R0 B.31 A-154): set_ids, actions_in_set, sets_of, share_a_set.

const TMP: String = "user://test_remap/input_map_sets.cfg"


func after_test() -> void:
	if FileAccess.file_exists(TMP):
		var _e: Error = DirAccess.remove_absolute(TMP)


func test_sets_are_flight_then_ground() -> void:
	var s: BindingStore = BindingStore.new(TMP)
	assert_array(s.set_ids()).is_equal([&"flight", &"ground"])


func test_the_sets_match_the_ruling_table() -> void:
	var s: BindingStore = BindingStore.new(TMP)
	assert_array(s.actions_in_set(BindingStore.KBM, &"ground")).is_equal(
		[&"throttle_up", &"brake", &"steer_left", &"steer_right", &"barrel_up", &"barrel_down", &"release"])
	assert_array(s.actions_in_set(BindingStore.PAD, &"ground")).is_equal([&"barrel_up", &"barrel_down", &"release"])
	assert_array(s.actions_in_set(BindingStore.KBM, &"flight")).is_equal(
		[&"throttle_up", &"brake", &"yaw_left", &"yaw_right", &"boost", &"flip", &"dock", &"release"])
	assert_bool(s.actions_in_set(BindingStore.KBM, &"nope").is_empty()).is_true()


func test_sets_of_and_share_a_set() -> void:
	var s: BindingStore = BindingStore.new(TMP)
	assert_array(s.sets_of(BindingStore.KBM, &"throttle_up")).is_equal([&"flight", &"ground"])
	assert_array(s.sets_of(BindingStore.KBM, &"yaw_right")).is_equal([&"flight"])
	assert_array(s.sets_of(BindingStore.PAD, &"barrel_up")).is_equal([&"ground"])
	assert_bool(s.share_a_set(BindingStore.KBM, &"yaw_right", &"barrel_up")).is_false()
	assert_bool(s.share_a_set(BindingStore.KBM, &"yaw_right", &"throttle_up")).is_true()
	assert_bool(s.share_a_set(BindingStore.KBM, &"barrel_up", &"throttle_up")).is_true()


func test_every_action_has_a_set_through_the_api() -> void:
	var s: BindingStore = BindingStore.new(TMP)
	for device: StringName in [BindingStore.KBM, BindingStore.PAD]:
		for a: StringName in s.actions(device):
			assert_bool(s.sets_of(device, a).is_empty()).is_false()


func test_ground_remap_persists_and_a_flight_remap_does_not_move_it() -> void:
	var a: BindingStore = BindingStore.new(TMP)
	var _c: StringName = a.bind(BindingStore.KBM, &"barrel_up", 0, KEY_T)
	_c = a.bind(BindingStore.KBM, &"yaw_right", 1, KEY_Y)
	assert_int(a.save()).is_equal(OK)
	var b: BindingStore = BindingStore.new(TMP)
	assert_int(b.load_file()).is_equal(OK)
	assert_int(b.code(BindingStore.KBM, &"barrel_up", 0)).is_equal(KEY_T)
	assert_int(b.code(BindingStore.KBM, &"yaw_right", 1)).is_equal(KEY_Y)
	assert_int(b.code(BindingStore.KBM, &"barrel_down", 0)).is_equal(KEY_Q)
