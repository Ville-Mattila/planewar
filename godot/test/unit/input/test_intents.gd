extends GdUnitTestSuite
## Unit tests for input/intents.gd: the 06 s2.5 catalogue is complete and unique.


func test_catalogue_size_and_uniqueness() -> void:
	var kinds: Array[StringName] = Intents.all_kinds()
	assert_int(kinds.size()).is_equal(44)
	var seen: Dictionary = {}
	for k: StringName in kinds:
		assert_bool(seen.has(k)).is_false()
		seen[k] = true


func test_representative_kinds_and_keys() -> void:
	assert_str(String(Intents.SELECT_BOX)).is_equal("select_box")
	assert_str(String(Intents.PING_WHEEL)).is_equal("ping_wheel")
	assert_str(String(Intents.K_POS)).is_equal("pos")
	assert_str(String(Intents.K_DEF_ID)).is_equal("def_id")
	assert_bool(Intents.all_kinds().has(Intents.ROSTER)).is_true()
