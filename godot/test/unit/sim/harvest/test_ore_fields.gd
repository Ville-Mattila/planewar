extends GdUnitTestSuite
## GD-12 contract tests (sim/harvest/MODULE.md OreFields, H1-H3): field table, regen while below capacity, the state
## bytes, `SimView.field_remaining`, and the Core Exposure stop of the regen (02 s8.2; 02 s12.1).

const K: GDScript = preload("res://test/unit/sim/harvest/harvest_test_kit.gd")


func test_add_fills_the_field_and_exposes_its_numbers() -> void:
	var f: OreFields = OreFields.new()
	var i: int = f.add(Vector3(1, 0, 0), 6000, 2.0, 150.0, 4)
	assert_int(i).is_equal(0)
	assert_int(f.count()).is_equal(1)
	assert_int(f.remaining(0)).is_equal(6000)
	assert_int(f.capacity_of(0)).is_equal(6000)
	assert_float(f.radius_of(0)).is_equal(150.0)
	assert_int(f.max_miners_of(0)).is_equal(4)
	assert_int(f.miners_of(0)).is_equal(0)
	assert_int(f.remaining(7)).is_equal(0)           # out of range reads 0


func test_load_nodes_takes_only_ore_fields_in_file_order() -> void:
	var f: OreFields = OreFields.new()
	var nodes: Array = [
		{"kind": "ore_field", "dir": [1.0, 0.0, 0.0], "capacity": 4000, "regen_per_s": 1.0, "radius_m": 250.0, "max_miners": 2},
		{"kind": "cold_trap", "dir": [0.0, 1.0, 0.0], "capacity": 4000, "rate_per_s": 1.0, "radius_m": 250.0},
		{"kind": "ore_field", "dir": [0.0, 0.0, 2.0], "capacity": 10000, "regen_per_s": 3.0, "radius_m": 200.0, "max_miners": 6},
	]
	assert_int(f.load_nodes(nodes)).is_equal(2)
	assert_int(f.capacity_of(1)).is_equal(10000)
	assert_int(f.max_miners_of(1)).is_equal(6)
	assert_float(f.dir_of(1).z).is_equal_approx(1.0, 1e-6)       # normalised


func test_field_at_is_the_nearest_field_containing_the_direction() -> void:
	var f: OreFields = OreFields.new()
	var _a: int = f.add(K.dir_at(0.0), 100, 0.0, 150.0, 1)
	var _b: int = f.add(K.dir_at(200.0), 100, 0.0, 150.0, 1)
	assert_int(f.field_at(K.dir_at(60.0))).is_equal(0)
	assert_int(f.field_at(K.dir_at(120.0))).is_equal(1)
	assert_int(f.field_at(K.dir_at(500.0))).is_equal(-1)


func test_regen_runs_only_below_capacity_and_never_past_it() -> void:
	var f: OreFields = OreFields.new()
	var _i: int = f.add(Vector3(1, 0, 0), 100, 2.0, 150.0, 1)
	f.amount[0] = 90.0
	f.regen(1.0)
	assert_float(f.amount[0]).is_equal_approx(92.0, 1e-4)
	f.regen(10.0)
	assert_float(f.amount[0]).is_equal(100.0)


func test_state_is_self_describing_and_refuses_short_bytes() -> void:
	var f: OreFields = OreFields.new()
	var _a: int = f.add(Vector3(1, 0, 0), 100, 1.0, 150.0, 1)
	var _b: int = f.add(Vector3(0, 1, 0), 200, 2.0, 120.0, 3)
	f.amount[1] = 33.5
	var buf: StreamPeerBuffer = StreamPeerBuffer.new()
	f.write_state(buf)
	var g: OreFields = OreFields.new()                  # a restored world has no loader: the bytes carry the table
	buf.seek(0)
	assert_bool(g.read_state(buf)).is_true()
	assert_int(g.count()).is_equal(2)
	assert_float(g.amount[1]).is_equal(33.5)
	assert_int(g.max_miners_of(1)).is_equal(3)
	assert_float(g.radius_of(1)).is_equal(120.0)
	var again: StreamPeerBuffer = StreamPeerBuffer.new()
	g.write_state(again)
	assert_array(again.data_array).is_equal(buf.data_array)
	var cut: StreamPeerBuffer = StreamPeerBuffer.new()
	cut.data_array = buf.data_array.slice(0, 20)
	assert_bool(OreFields.new().read_state(cut)).is_false()


func test_world_regen_runs_and_stops_at_core_exposure() -> void:
	var w: SimWorld = K.world(2.0)                      # Exposure at 2 s of match time
	var i: int = K.field(w, 0.0, 1000, 3.0)
	var f: OreFields = w.economy().harvest.fields
	f.amount[i] = 500.0
	K.step(w, 30)                                       # 1 s, still playing
	assert_float(f.amount[i]).is_equal_approx(503.0, 0.2)
	K.step(w, 120)                                      # well past Exposure
	var at_exposure: float = f.amount[i]
	assert_float(at_exposure).is_less(510.0)            # about 2 s of regen, not 5 s
	K.step(w, 90)
	assert_float(f.amount[i]).is_equal(at_exposure)     # frozen (H3)


func test_sim_view_field_remaining_reads_the_field() -> void:
	var w: SimWorld = K.world()
	var _i: int = K.field(w, 0.0, 777, 0.0)
	assert_int(w.view().field_remaining(0)).is_equal(777)
	assert_int(w.view().field_remaining(5)).is_equal(0)
