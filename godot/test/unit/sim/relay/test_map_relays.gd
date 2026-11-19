extends GdUnitTestSuite
## GD-51 (R0 B.30 A-150; sim/relay/MODULE.md MapRelays): load_map spawns one finished neutral Relay Station per relay entry of
## the baked features.json (`nodes[]` kind relay_station, then `neutral_structures[]` def relay_station, each in file order);
## a map with none spawns none; a Hauler lands on a spawned one and captures it; S4 round trip is byte-exact.

const FIX: String = "res://test/unit/sim/relay/fixtures/"
const K: GDScript = preload("res://test/unit/sim/relay/relay_test_kit.gd")

var _w: SimWorld


func before_test() -> void:
	_w = K.world()


func _spawn(dir: String) -> int:
	return MapRelays.spawn(FIX + dir, _w._defs, _w._terrain, _w.store(), _w._applier, _w.tick())


func _relays() -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	var def: int = WorldTestKit.def_id(&"relay_station")
	for s: int in _w.store().structures:
		if _w.store().def_id[s] == def:
			var _a: bool = out.push_back(s)
	return out


func test_one_entry_yields_one_finished_neutral_relay_station() -> void:
	assert_int(_spawn("one_relay")).is_equal(1)
	var r: PackedInt32Array = _relays()
	assert_int(r.size()).is_equal(1)
	var st: EntityStore = _w.store()
	assert_int(st.team[r[0]]).is_equal(255)
	assert_int(st.owner[r[0]]).is_equal(255)
	assert_int(st.flags[r[0]] & EntityStore.F_BUILDING).is_equal(0)
	assert_float(st.up[r[0]].distance_to(_w._terrain.normal_at(Vector3(1.0, 0.0, 0.0)))).is_less(0.0001)
	assert_float(st.fwd[r[0]].dot(Vector3(0.0, 1.0, 0.0))).is_greater(0.99)


func test_spawn_order_is_file_order_nodes_then_neutral_structures() -> void:
	assert_int(_spawn("two_blocks")).is_equal(3)
	var r: PackedInt32Array = _relays()
	assert_int(r.size()).is_equal(3)
	var want: Array[Vector3] = [Vector3(0, 1, 0), Vector3(0, -1, 0), Vector3(-1, 0, 0)]
	for k: int in 3:
		assert_float(_w.store().pos[r[k]].normalized().distance_to(want[k])).is_less(0.0001)


func test_a_map_with_no_entry_or_a_missing_file_spawns_none() -> void:
	assert_int(MapRelays.spawn("res://content/maps/tiny_test", _w._defs, _w._terrain, _w.store(), _w._applier, 0)).is_equal(0)
	assert_int(_spawn("no_such_dir")).is_equal(0)
	assert_int(_relays().size()).is_equal(0)


func test_load_map_of_a_shipped_map_spawns_no_relay_yet() -> void:
	var w: SimWorld = WorldTestKit.world(7, null, &"tiny_test")
	for s: int in w.store().structures:
		assert_int(w.store().def_id[s]).is_not_equal(WorldTestKit.def_id(&"relay_station"))


func test_a_hauler_lands_on_a_spawned_relay_station_and_captures_it() -> void:
	var _n: int = _spawn("one_relay")
	var _spawned: Array[SimEvent] = _w.drain_events()   # the relay's SPAWN event is not the Hauler's
	var relay: int = _w.store().id_of(_relays()[0])
	var sd: ShipDef = DockingTestKit.ship_def(&"hauler")
	var up: Vector3 = _w.store().up[EntityId.slot(relay)]
	var h: int = DockingTestKit.ship_over(_w, &"hauler", 0, 0, relay, sd.bounding_radius, 0.0, -up * 2.0)
	var _d: Array[SimEvent] = _w.drain_events()
	_w.step()
	assert_int(_w.store().link[EntityId.slot(h)]).is_equal(relay)
	for _i: int in K.seconds(K.rule("capture_s")) + 5:
		_w.step()
	assert_int(K.team_of(_w, relay)).is_equal(0)


func test_the_spawned_relay_round_trips_byte_exact() -> void:
	var _n: int = _spawn("two_blocks")
	var bytes: PackedByteArray = _w.serialize()
	var back: SimWorld = SimWorld.deserialize(bytes, WorldTestKit.content(), null)
	assert_object(back).is_not_null()
	assert_array(back.serialize()).is_equal(bytes)


func test_the_relay_read_is_a_load_time_cost_only() -> void:
	var t0: int = Time.get_ticks_usec()
	for _i: int in 20:
		var _n: int = MapRelays.spawn("res://content/maps/cradle", _w._defs, _w._terrain, _w.store(), _w._applier, 0)
	var us: float = float(Time.get_ticks_usec() - t0) / 20.0
	assert_bool(PerfGate.check("map_relays_load_cradle", us, 20000.0, "GD-51 load time only (not on a tick path)")).is_true()
