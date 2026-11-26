extends GdUnitTestSuite
## AI-24 contract: `content/defs/build_orders.json` (05 s7.3, R0 C2-14): 3 doctrines x 2 books on the R0 B.6 start kit, no
## `storage_silo`, every `build outpost` preceded by an `order move` to the same site and carrying `when: presence`, every
## book compiles against the shipped defs (SC-41 runs every book in the sim).

const DOCTRINES: Array[StringName] = [&"vanguard", &"bulwark", &"foundry"]


func _raw() -> Array:
	var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(Ai23Kit.SHIPPED))
	assert_bool(v is Dictionary).is_true()
	var d: Dictionary = v
	return d["build_orders"]


func test_six_books_two_per_doctrine_with_a_standard_each() -> void:
	var raw: Array = _raw()
	assert_int(raw.size()).is_equal(6)
	for doctrine: StringName in DOCTRINES:
		var ids: Array[String] = []
		for e: Variant in raw:
			var d: Dictionary = e
			if StringName(str(d["doctrine"])) == doctrine:
				ids.append(str(d["id"]))
				assert_float(float(d["weight"])).is_greater(0.0)
		assert_int(ids.size()).override_failure_message("%s: %s" % [doctrine, str(ids)]).is_equal(2)
		assert_bool(ids.has("%s_standard" % doctrine)).is_true()


func test_every_book_compiles_against_the_shipped_defs() -> void:
	var c: ContentSet = Ai23Kit.content()
	assert_int(c.build_orders.size()).is_equal(6)
	for e: Variant in _raw():
		var errs: Array[String] = []
		var b: OpeningBook = OpeningBook.compile(e, c, errs)
		assert_object(b).override_failure_message("%s: %s" % [str((e as Dictionary)["id"]), str(errs)]).is_not_null()
		assert_int(b.n_steps).is_greater(6)


func test_no_storage_silo_anywhere() -> void:
	for e: Variant in _raw():
		for s: Variant in (e as Dictionary)["steps"]:
			assert_str(str((s as Dictionary).get("def", ""))).is_not_equal("storage_silo")


func test_every_outpost_follows_a_move_to_the_same_site_and_waits_for_presence() -> void:
	var n_outposts: int = 0
	for e: Variant in _raw():
		var steps: Array = (e as Dictionary)["steps"]
		for i: int in steps.size():
			var s: Dictionary = steps[i]
			if s["do"] != "build" or s["def"] != "outpost":
				continue
			n_outposts += 1
			assert_str(str(s["when"])).contains("presence")
			var prev: Dictionary = steps[i - 1]
			assert_str(str(prev["do"])).is_equal("order")
			assert_str(str(prev["kind"])).is_equal("move")
			assert_str(str(prev["to"])).is_equal(str(s["near"]))
	assert_int(n_outposts).is_greater_equal(6)


func test_the_commander_picks_one_of_the_doctrines_two_books() -> void:
	var cb: CommanderBrain = Ai23Kit.commander(&"cradle", Ai23Kit.shipped_books())
	for doctrine: StringName in DOCTRINES:
		var b: OpeningBook = cb.pick_book(doctrine)
		assert_object(b).is_not_null()
		assert_str(String(b.doctrine)).is_equal(String(doctrine))
