extends GdUnitTestSuite
## Unit tests for core/saves.gd (TA-36; 03 s11.4: user:// access never crashes when IndexedDB is unavailable).

const DIR: String = "user://ta36_saves_test"


func before_test() -> void:
	Saves.simulate_unavailable = false
	var _r: Result = Saves.try_make_dir(DIR)


func after_test() -> void:
	Saves.simulate_unavailable = false
	var _a: Result = Saves.try_remove(DIR.path_join("a.bin"))
	var _b: Result = Saves.try_remove(DIR.path_join("t.txt"))
	var _c: Result = Saves.try_remove(DIR)


func test_is_user_path_accepts_only_user_scheme() -> void:
	assert_bool(Saves.is_user_path("user://x.sav")).is_true()
	assert_bool(Saves.is_user_path("res://x.sav")).is_false()
	assert_bool(Saves.is_user_path("/etc/passwd")).is_false()
	assert_bool(Saves.is_user_path("user://../x")).is_false()
	assert_bool(Saves.is_user_path("")).is_false()


func test_bytes_round_trip() -> void:
	var p: String = DIR.path_join("a.bin")
	var data: PackedByteArray = PackedByteArray([1, 2, 3, 250])
	assert_bool(Saves.try_write_bytes(p, data).ok).is_true()
	assert_bool(Saves.try_exists(p)).is_true()
	var r: Result = Saves.try_read_bytes(p)
	assert_bool(r.ok).is_true()
	assert_array(r.value).is_equal(data)


func test_text_round_trip() -> void:
	var p: String = DIR.path_join("t.txt")
	assert_bool(Saves.try_write_text(p, "hello").ok).is_true()
	var r: Result = Saves.try_read_text(p)
	assert_bool(r.ok).is_true()
	assert_str(r.value).is_equal("hello")


func test_remove_deletes_file() -> void:
	var p: String = DIR.path_join("t.txt")
	var _w: Result = Saves.try_write_text(p, "x")
	assert_bool(Saves.try_remove(p).ok).is_true()
	assert_bool(Saves.try_exists(p)).is_false()


func test_missing_file_fails_without_crash() -> void:
	var r: Result = Saves.try_read_bytes(DIR.path_join("nope.bin"))
	assert_bool(r.ok).is_false()
	assert_int(r.error).is_not_equal(OK)


func test_write_into_missing_directory_fails() -> void:
	var r: Result = Saves.try_write_bytes("user://ta36_no_such_dir/x.bin", PackedByteArray([1]))
	assert_bool(r.ok).is_false()


func test_non_user_paths_rejected() -> void:
	var r: Result = Saves.try_write_text("res://ta36_forbidden.txt", "x")
	assert_bool(r.ok).is_false()
	assert_int(r.error).is_equal(Saves.ERR_BAD_PATH)
	assert_bool(Saves.try_read_text("/etc/passwd").ok).is_false()
	assert_bool(Saves.try_exists("/etc/passwd")).is_false()


func test_unavailable_storage_fails_every_wrapper_without_crash() -> void:
	var p: String = DIR.path_join("a.bin")
	var _w: Result = Saves.try_write_bytes(p, PackedByteArray([9]))
	Saves.simulate_unavailable = true
	assert_bool(Saves.storage_available()).is_false()
	assert_int(Saves.try_write_bytes(p, PackedByteArray([1])).error).is_equal(Saves.ERR_UNAVAILABLE)
	assert_int(Saves.try_read_bytes(p).error).is_equal(Saves.ERR_UNAVAILABLE)
	assert_int(Saves.try_write_text(p, "x").error).is_equal(Saves.ERR_UNAVAILABLE)
	assert_int(Saves.try_read_text(p).error).is_equal(Saves.ERR_UNAVAILABLE)
	assert_int(Saves.try_remove(p).error).is_equal(Saves.ERR_UNAVAILABLE)
	assert_int(Saves.try_make_dir(DIR).error).is_equal(Saves.ERR_UNAVAILABLE)
	assert_bool(Saves.try_exists(p)).is_false()


func test_storage_available_on_desktop() -> void:
	assert_bool(Saves.storage_available()).is_true()
