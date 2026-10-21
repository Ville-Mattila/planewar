extends GdUnitTestSuite
## GD-19 W1-W3 (sim/salvage/MODULE.md): the 02 s13 value table, the pod split, the wreck a death leaves.

const K: GDScript = preload("res://test/unit/sim/salvage/salvage_test_kit.gd")
const TABLE: Array = [[&"dart", 60], [&"lancer", 120], [&"bomber", 180], [&"scout", 24], [&"hauler", 80],
	[&"harvester", 100], [&"siege_crawler", 180], [&"pad", 60], [&"autocannon_turret", 80], [&"flak_battery", 120],
	[&"missile_tower", 140], [&"refinery", 120], [&"shipyard", 160], [&"outpost", 180], [&"core", 800]]


func _defs() -> WorldDefs:
	return WorldDefs.new(WorldTestKit.content())


func test_value_table_matches_02_s13() -> void:
	var d: WorldDefs = _defs()
	for row: Array in TABLE:
		var id: StringName = row[0]
		assert_int(Salvage.value_of(d, WorldTestKit.def_id(id))).override_failure_message(String(id)).is_equal(row[1])


func test_a_def_without_a_base_value_leaves_nothing() -> void:
	assert_int(Salvage.value_of(_defs(), WorldTestKit.def_id(&"relay_station"))).is_equal(0)
	assert_int(Salvage.value_of(_defs(), -1)).is_equal(0)


func test_pods_of_is_ceil_of_value_over_pod_size() -> void:
	assert_int(Salvage.pods_of(160, 120)).is_equal(2)
	assert_int(Salvage.pods_of(120, 120)).is_equal(1)
	assert_int(Salvage.pods_of(121, 120)).is_equal(2)
	assert_int(Salvage.pods_of(800, 120)).is_equal(7)
	assert_int(Salvage.pods_of(180, 120)).is_equal(2)
	assert_int(Salvage.pods_of(1, 120)).is_equal(1)
	assert_int(Salvage.pods_of(0, 120)).is_equal(1)


func test_pod_values_are_integers_that_sum_to_the_value_within_one() -> void:
	for value: int in range(1, 1000, 7):
		var n: int = Salvage.pods_of(value, 120)
		var sum: int = 0
		var lo: int = 1 << 30
		var hi: int = 0
		for i: int in n:
			var v: int = Salvage.pod_value(value, n, i)
			sum += v
			lo = mini(lo, v)
			hi = maxi(hi, v)
		assert_int(sum).override_failure_message("value %d" % value).is_equal(value)
		assert_bool(hi - lo <= 1).override_failure_message("value %d" % value).is_true()


func test_a_destroyed_shipyard_yields_two_pods_of_80() -> void:
	var w: SimWorld = K.world()
	var yard: int = K.put(w, &"shipyard", 0, 0, 0.0)
	var ev: Array[SimEvent] = K.kill(w, yard)
	var spawned: Array[SimEvent] = K.of_kind(ev, SimEvent.Kind.WRECK_SPAWNED)
	assert_int(spawned.size()).is_equal(2)
	assert_float(spawned[0].value).is_equal(80.0)
	assert_float(spawned[1].value).is_equal(80.0)
	assert_int(spawned[0].b).is_equal(WorldTestKit.def_id(&"shipyard"))
	var live: PackedInt32Array = K.wrecks(w)
	assert_int(live.size()).is_equal(2)
	for s: int in live:
		assert_float(w.store().hp[s]).is_equal(80.0)
		assert_int(w.store().kind[s]).is_equal(EntityStore.K_WRECK)
		assert_int(w.store().def_id[s]).is_equal(WorldTestKit.def_id(&"shipyard"))
		assert_int(w.store().team[s]).is_equal(EntityStore.NONE_U8)
		assert_int(w.store().owner[s]).is_equal(EntityStore.NONE_U8)
		assert_int(w.store().spawn_tick[s]).is_equal(w.tick())
	assert_int(spawned[0].a).is_equal(w.store().id_of(live[0]))
	assert_int(spawned[1].a).is_equal(w.store().id_of(live[1]))
	assert_int(spawned[0].tick).is_equal(w.tick())


func test_the_core_breaks_into_seven_pods_worth_800() -> void:
	var w: SimWorld = K.world()
	var core: int = K.put(w, &"core", 0, 0, 0.0)
	var ev: Array[SimEvent] = K.kill(w, core)
	assert_int(K.of_kind(ev, SimEvent.Kind.WRECK_SPAWNED).size()).is_equal(7)
	var sum: float = 0.0
	var lo: float = 1.0e9
	var hi: float = 0.0
	for s: int in K.wrecks(w):
		sum += w.store().hp[s]
		lo = minf(lo, w.store().hp[s])
		hi = maxf(hi, w.store().hp[s])
	assert_float(sum).is_equal(800.0)
	assert_bool(hi - lo <= 1.0).is_true()


func test_a_ship_leaves_one_wreck_even_above_the_pod_size() -> void:
	var w: SimWorld = K.world()
	var ev: Array[SimEvent] = K.kill(w, K.put(w, &"bomber", 0, 0, 300.0))
	assert_int(K.of_kind(ev, SimEvent.Kind.WRECK_SPAWNED).size()).is_equal(1)
	assert_float(w.store().hp[K.wrecks(w)[0]]).is_equal(180.0)


func test_a_ground_unit_leaves_one_wreck() -> void:
	var w: SimWorld = K.world()
	var _ev: Array[SimEvent] = K.kill(w, K.put(w, &"harvester", 0, 0, 0.0))
	assert_int(K.wrecks(w).size()).is_equal(1)
	assert_float(w.store().hp[K.wrecks(w)[0]]).is_equal(100.0)


func test_the_value_ignores_the_doctrine_of_the_owner() -> void:
	var w: SimWorld = K.world()
	var _ev: Array[SimEvent] = K.kill(w, K.put(w, &"dart", K.FOUNDRY_SLOT, 0, 300.0))
	assert_float(w.store().hp[K.wrecks(w)[0]]).is_equal(60.0)


func test_sites_and_the_relay_station_leave_nothing() -> void:
	var w: SimWorld = K.world()
	var site: int = K.put(w, &"shipyard", 0, 0, 0.0)
	w.store().flags[site] |= EntityStore.F_BUILDING
	assert_int(K.of_kind(K.kill(w, site), SimEvent.Kind.WRECK_SPAWNED).size()).is_equal(0)
	var relay: int = K.put(w, &"relay_station", EntityStore.NONE_U8, EntityStore.NONE_U8, 0.0, 400.0)
	assert_int(K.of_kind(K.kill(w, relay), SimEvent.Kind.WRECK_SPAWNED).size()).is_equal(0)
	assert_int(K.wrecks(w).size()).is_equal(0)


func test_a_wreck_never_leaves_a_wreck() -> void:
	var w: SimWorld = K.world()
	var wr: int = K.wreck_at(w, &"dart", 60.0, WorldTestKit.at(0.0))
	assert_int(K.of_kind(K.kill(w, wr), SimEvent.Kind.WRECK_SPAWNED).size()).is_equal(0)


func test_a_flying_ships_wreck_rests_on_the_ground() -> void:
	var w: SimWorld = K.world()
	var _ev: Array[SimEvent] = K.kill(w, K.put(w, &"dart", 0, 0, 300.0))
	var s: int = K.wrecks(w)[0]
	assert_float(w.store().pos[s].length()).is_equal_approx(Sphere.PLANET_RADIUS, 0.01)
	assert_vector(w.store().up[s]).is_equal_approx(w.store().pos[s].normalized(), Vector3(0.001, 0.001, 0.001))


func test_pods_sit_on_a_ring_around_the_structure() -> void:
	var w: SimWorld = K.world()
	var yard: int = K.put(w, &"shipyard", 0, 0, 0.0)
	var centre: Vector3 = w.store().pos[yard]
	var ring: float = w.store().radius[yard] * 0.5
	var _ev: Array[SimEvent] = K.kill(w, yard)
	var live: PackedInt32Array = K.wrecks(w)
	assert_float(w.store().pos[live[0]].distance_to(centre)).is_equal_approx(ring, ring * 0.02)
	assert_float(w.store().pos[live[1]].distance_to(centre)).is_equal_approx(ring, ring * 0.02)
	assert_float(w.store().pos[live[0]].distance_to(w.store().pos[live[1]])).is_equal_approx(2.0 * ring, ring * 0.05)
	assert_float(w.store().radius[live[0]]).is_equal_approx(w.store().radius[yard] / 2.0, 0.001)


func test_the_wreck_pass_is_deterministic() -> void:
	var a: SimWorld = K.world()
	var b: SimWorld = K.world()
	for w: SimWorld in [a, b]:
		var _e: Array[SimEvent] = K.kill(w, K.put(w, &"core", 0, 0, 0.0))
	assert_array(WorldTestKit.store_bytes(a)).is_equal(WorldTestKit.store_bytes(b))
