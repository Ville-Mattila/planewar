extends GdUnitTestSuite
## GD-12 round 2 (sim/harvest/MODULE.md H1, H8): `SimWorld.load_map` loads the map's `ore_field` nodes from features.json,
## so a real match has its Ore Fields; a second load or a restore never doubles them.


func _nodes(map_id: String) -> Array:
	var f: FileAccess = FileAccess.open("res://content/maps/%s/features.json" % map_id, FileAccess.READ)
	var d: Dictionary = JSON.parse_string(f.get_as_text())
	var out: Array = []
	for n: Variant in d["nodes"]:
		var nd: Dictionary = n
		if nd["kind"] == "ore_field":
			out.append(nd)
	return out


func _load(map_id: StringName) -> SimWorld:
	var w: SimWorld = SimWorld.new(WorldTestKit.content())
	var map: MapDef = MapDef.new()
	map.id = map_id
	var res: Result = w.load_map(map, 7, WorldTestKit.rules())
	assert(res.ok, res.message)
	return w


func test_load_map_loads_every_ore_field_of_tiny_test_at_full_capacity() -> void:
	var expect: Array = _nodes("tiny_test")
	assert_int(expect.size()).is_greater(0)
	var w: SimWorld = _load(&"tiny_test")
	assert_int(w.economy().harvest.fields.count()).is_equal(expect.size())
	for i: int in expect.size():
		var nd: Dictionary = expect[i]
		assert_int(w.view().field_remaining(i)).is_equal(int(nd["capacity"]))
		assert_int(w.economy().harvest.fields.max_miners_of(i)).is_equal(int(nd["max_miners"]))


func test_cradle_and_the_flat_datum() -> void:
	var w: SimWorld = _load(&"cradle")
	assert_int(w.economy().harvest.fields.count()).is_equal(_nodes("cradle").size())
	var flat: SimWorld = EconomyTestKit.solo_world(false)
	assert_int(flat.economy().harvest.fields.count()).is_equal(0)


func test_loading_a_map_dir_again_into_the_same_table_does_not_double_it() -> void:
	var expect: Array = _nodes("tiny_test")
	var w: SimWorld = _load(&"tiny_test")
	var f: OreFields = w.economy().harvest.fields
	f.amount[0] = 10.0                                   # some Ore mined away
	f.miners[0] = 1
	assert_int(f.load_map_dir("res://content/maps/tiny_test")).is_equal(expect.size())
	assert_int(f.count()).is_equal(expect.size())
	for i: int in expect.size():
		var nd: Dictionary = expect[i]
		assert_int(f.remaining(i)).is_equal(int(nd["capacity"]))
	assert_int(f.miners_of(0)).is_equal(0)


func test_save_restore_keeps_the_fields_and_their_ore() -> void:
	var w: SimWorld = _load(&"tiny_test")
	var n: int = w.economy().harvest.fields.count()
	w.economy().harvest.fields.amount[0] = 1234.0
	var r: SimWorld = SimWorld.deserialize(w.serialize(), WorldTestKit.content(), null)
	assert_object(r).is_not_null()
	assert_int(r.economy().harvest.fields.count()).is_equal(n)
	assert_int(r.view().field_remaining(0)).is_equal(1234)
