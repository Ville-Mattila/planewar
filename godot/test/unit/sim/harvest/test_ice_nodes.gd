extends GdUnitTestSuite
## GD-14 I1 (sim/harvest/MODULE.md; 02 s8.3, 02 s9): the Cold Trap table: file order, `node_at`, no regeneration,
## `SimWorld.load_map` loads the map's `cold_trap` nodes, S4 bytes.


func _cold_traps(map_id: String) -> Array:
	var f: FileAccess = FileAccess.open("res://content/maps/%s/features.json" % map_id, FileAccess.READ)
	var d: Dictionary = JSON.parse_string(f.get_as_text())
	var out: Array = []
	for n: Variant in d["nodes"]:
		var nd: Dictionary = n
		if nd["kind"] == "cold_trap":
			out.append(nd)
	return out


func _load(map_id: StringName) -> SimWorld:
	var w: SimWorld = SimWorld.new(WorldTestKit.content())
	var map: MapDef = MapDef.new()
	map.id = map_id
	var res: Result = w.load_map(map, 7, WorldTestKit.rules())
	assert(res.ok, res.message)
	return w


func test_add_starts_full_and_reads_back() -> void:
	var t: IceNodes = IceNodes.new()
	var i: int = t.add(Vector3.RIGHT, 2000, 0.8, 100.0)
	assert_int(i).is_equal(0)
	assert_int(t.count()).is_equal(1)
	assert_int(t.remaining(0)).is_equal(2000)
	assert_int(t.capacity_of(0)).is_equal(2000)
	assert_float(t.rate_of(0)).is_equal_approx(0.8, 0.0001)
	assert_float(t.radius_of(0)).is_equal(100.0)
	assert_vector(t.dir_of(0)).is_equal(Vector3.RIGHT)
	assert_int(t.remaining(5)).is_equal(0)           # out of range reads 0


func test_node_at_is_the_nearest_node_whose_radius_contains_the_direction() -> void:
	var t: IceNodes = IceNodes.new()
	var _a: int = t.add(IceTestKit.K.dir_at(0.0), 100, 1.0, 100.0)
	var _b: int = t.add(IceTestKit.K.dir_at(150.0), 100, 1.0, 100.0)
	assert_int(t.node_at(IceTestKit.K.dir_at(10.0))).is_equal(0)
	assert_int(t.node_at(IceTestKit.K.dir_at(140.0))).is_equal(1)
	assert_int(t.node_at(IceTestKit.K.dir_at(80.0))).is_equal(1)      # both contain it; node 1 is nearer
	assert_int(t.node_at(IceTestKit.K.dir_at(400.0))).is_equal(-1)


func test_load_nodes_takes_only_cold_traps_in_file_order() -> void:
	var t: IceNodes = IceNodes.new()
	var nodes: Array = [
		{"kind": "ore_field", "dir": [1.0, 0.0, 0.0], "capacity": 5, "regen_per_s": 1.0, "radius_m": 10.0, "max_miners": 2},
		{"kind": "cold_trap", "dir": [0.0, 1.0, 0.0], "capacity": 2000, "rate_per_s": 0.8, "radius_m": 100.0},
		{"kind": "cold_trap", "dir": [0.0, 0.0, 1.0], "capacity": 6000, "rate_per_s": 1.5, "radius_m": 150.0},
	]
	assert_int(t.load_nodes(nodes)).is_equal(2)
	assert_int(t.remaining(0)).is_equal(2000)
	assert_float(t.rate_of(1)).is_equal_approx(1.5, 0.0001)
	assert_vector(t.dir_of(1)).is_equal(Vector3(0.0, 0.0, 1.0))


func test_load_map_dir_replaces_the_table_and_never_doubles_it() -> void:
	var expect: Array = _cold_traps("cradle")
	var t: IceNodes = IceNodes.new()
	assert_int(t.load_map_dir("res://content/maps/cradle")).is_equal(expect.size())
	t.amount[0] = 1.0
	assert_int(t.load_map_dir("res://content/maps/cradle")).is_equal(expect.size())
	assert_int(t.count()).is_equal(expect.size())
	assert_int(t.remaining(0)).is_equal(int((expect[0] as Dictionary)["capacity"]))
	assert_int(t.load_map_dir("res://content/maps/no_such_map")).is_equal(-1)


func test_load_map_loads_every_cold_trap_of_cradle_full() -> void:
	var expect: Array = _cold_traps("cradle")
	assert_int(expect.size()).is_greater(0)
	var w: SimWorld = _load(&"cradle")
	var t: IceNodes = w.economy().ice.nodes
	assert_int(t.count()).is_equal(expect.size())
	for i: int in expect.size():
		var nd: Dictionary = expect[i]
		assert_int(t.remaining(i)).is_equal(int(nd["capacity"]))
		assert_float(t.rate_of(i)).is_equal_approx(float(nd["rate_per_s"]), 0.0001)
	assert_int(IceTestKit.world().economy().ice.nodes.count()).is_equal(0)     # the flat datum has none


func test_ice_does_not_regenerate() -> void:
	var w: SimWorld = IceTestKit.world()
	var n: int = IceTestKit.node(w, 0.0, 100, 0.8)
	w.economy().ice.nodes.amount[n] = 40.0
	for _i: int in 600:
		w.step()
	assert_float(w.economy().ice.nodes.amount[n]).is_equal(40.0)


func test_the_table_round_trips_through_the_state_bytes() -> void:
	var t: IceNodes = IceNodes.new()
	var _a: int = t.add(Vector3.RIGHT, 2000, 0.8, 100.0)
	var _b: int = t.add(Vector3.UP, 6000, 1.5, 150.0)
	t.amount[1] = 1234.0
	var buf: StreamPeerBuffer = StreamPeerBuffer.new()
	t.write_state(buf)
	var r: IceNodes = IceNodes.new()
	var rb: StreamPeerBuffer = StreamPeerBuffer.new()
	rb.data_array = buf.data_array
	assert_bool(r.read_state(rb)).is_true()
	assert_int(r.count()).is_equal(2)
	assert_int(r.remaining(1)).is_equal(1234)
	assert_float(r.rate_of(1)).is_equal_approx(1.5, 0.0001)
	assert_int(r.node_at(Vector3.UP)).is_equal(1)
	assert_bool(IceNodes.new().read_state(StreamPeerBuffer.new())).is_false()   # empty: refused


func test_save_restore_keeps_the_nodes_and_their_ice() -> void:
	var w: SimWorld = _load(&"cradle")
	var n: int = w.economy().ice.nodes.count()
	w.economy().ice.nodes.amount[0] = 777.0
	var r: SimWorld = SimWorld.deserialize(w.serialize(), WorldTestKit.content(), null)
	assert_object(r).is_not_null()
	assert_int(r.economy().ice.nodes.count()).is_equal(n)
	assert_int(r.economy().ice.nodes.remaining(0)).is_equal(777)
