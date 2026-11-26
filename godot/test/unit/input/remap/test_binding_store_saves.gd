extends GdUnitTestSuite
## TA-69: BindingStore persists through Saves.try_*; unavailable storage degrades to defaults without a crash.

const TMP: String = "user://test_remap_ta69/input_map.cfg"


func after_test() -> void:
	Saves.simulate_unavailable = false
	var _r: Result = Saves.try_remove(TMP)


func test_save_and_load_round_trip_through_saves() -> void:
	var a: BindingStore = BindingStore.new(TMP)
	var _o: StringName = a.bind(BindingStore.KBM, &"flip", 0, KEY_F9)
	assert_int(a.save()).is_equal(OK)
	assert_bool(Saves.try_exists(TMP)).is_true()
	var b: BindingStore = BindingStore.new(TMP)
	assert_int(b.load_file()).is_equal(OK)
	assert_int(b.code(BindingStore.KBM, &"flip", 0)).is_equal(KEY_F9)


func test_save_reports_unavailable_without_crash() -> void:
	var a: BindingStore = BindingStore.new(TMP)
	Saves.simulate_unavailable = true
	assert_int(a.save()).is_equal(ERR_UNAVAILABLE)


func test_load_unavailable_keeps_defaults() -> void:
	var a: BindingStore = BindingStore.new(TMP)
	var _o: StringName = a.bind(BindingStore.KBM, &"flip", 0, KEY_F9)
	assert_int(a.save()).is_equal(OK)
	Saves.simulate_unavailable = true
	var b: BindingStore = BindingStore.new(TMP)
	assert_int(b.load_file()).is_equal(ERR_UNAVAILABLE)
	assert_int(b.code(BindingStore.KBM, &"throttle_up", 0)).is_equal(KEY_W)
	assert_int(b.code(BindingStore.KBM, &"flip", 0)).is_not_equal(KEY_F9)


func test_load_absent_file_is_ok() -> void:
	var b: BindingStore = BindingStore.new("user://test_remap_ta69/none.cfg")
	assert_int(b.load_file()).is_equal(OK)
