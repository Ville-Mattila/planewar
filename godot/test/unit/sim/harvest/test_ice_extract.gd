extends GdUnitTestSuite
## GD-14 contract tests (sim/harvest/MODULE.md I2-I8; 02 s8.3): the Extractor fills its 400-Ice buffer at the node rate,
## a Refinery within the pipe radius pipes it into the stockpile (0.8 Ice/s at the Home Cold Trap), a Hauler moves 40 Ice/s
## from a buffer into its hold and from its hold into the stockpile, and S4.

const K: GDScript = preload("res://test/unit/sim/harvest/ice_test_kit.gd")
const HZ: float = 30.0


# World with a 2,000-Ice node at arc 0 (rate `rate`) and a finished Extractor on it.
func _scene(rate: float = 0.8, capacity: int = 2000) -> Dictionary:
	var w: SimWorld = K.world()
	var n: int = K.node(w, 0.0, capacity, rate)
	var e: int = K.extractor(w, 0.0)
	return {"w": w, "node": n, "ext": e}


func _ice(w: SimWorld) -> IceExtract:
	return w.economy().ice


func test_the_defs_name_the_acceptance_numbers() -> void:
	var w: SimWorld = K.world()
	assert_float(w._defs.economy.hauler_transfer_per_s).is_equal(40.0)
	assert_float(w._defs.economy.pipe_radius_m).is_equal(500.0)
	var ext: StructureDef = w._defs.base.structure(WorldTestKit.def_id(&"ice_extractor"))
	assert_int(ext.buffer_ice).is_equal(400)


func test_a_piped_extractor_credits_08_ice_per_second() -> void:
	var sc: Dictionary = _scene(0.8)
	var w: SimWorld = sc["w"]
	var _ref: int = HarvestTestKit.refinery(w, 400.0)
	K.set_pool(w, 0)
	var before: int = K.ice(w)
	var _ev: Array[SimEvent] = EconomyTestKit.run(w, int(100.0 * HZ))
	assert_int(K.ice(w) - before).is_between(79, 80)                        # 100 s x 0.8 Ice/s
	assert_float(w.store().cargo[sc["ext"]]).is_less(1.0)                   # piped continuously: no buffer builds
	assert_float(_ice(w).nodes.amount[sc["node"]]).is_equal_approx(1920.0, 1.0)


func test_the_pipe_reaches_the_def_radius_and_not_beyond() -> void:
	var sc: Dictionary = _scene()
	var w: SimWorld = sc["w"]
	var near: int = HarvestTestKit.refinery(w, 490.0)
	assert_int(_ice(w).refinery_for(sc["ext"])).is_equal(near)
	var far: SimWorld = _scene()["w"]
	var _r: int = HarvestTestKit.refinery(far, 510.0)
	var fe: int = EconomyTestKit.find(far, &"ice_extractor")
	assert_int(_ice(far).refinery_for(fe)).is_equal(-1)


func test_an_unpiped_extractor_fills_to_the_buffer_and_stops() -> void:
	var sc: Dictionary = _scene(80.0, 2000)
	var w: SimWorld = sc["w"]
	K.pass_n(w, int(10.0 * HZ))
	assert_float(w.store().cargo[sc["ext"]]).is_equal_approx(400.0, 0.01)   # 400 Ice buffer
	assert_int(w.store().cargo_kind[sc["ext"]]).is_equal(2)                 # ICE
	assert_float(_ice(w).nodes.amount[sc["node"]]).is_equal_approx(1600.0, 0.1)
	K.pass_n(w, int(10.0 * HZ))
	assert_float(w.store().cargo[sc["ext"]]).is_equal_approx(400.0, 0.01)
	assert_float(_ice(w).nodes.amount[sc["node"]]).is_equal_approx(1600.0, 0.1)   # a full buffer takes nothing more


func test_an_extractor_beyond_the_pipe_radius_buffers_the_node_rate() -> void:
	var sc: Dictionary = _scene(0.8)
	var w: SimWorld = sc["w"]
	var _ref: int = HarvestTestKit.refinery(w, 600.0)
	K.set_pool(w, 0)
	K.pass_n(w, int(100.0 * HZ))
	assert_float(w.store().cargo[sc["ext"]]).is_equal_approx(80.0, 0.5)
	assert_int(K.ice(w)).is_equal(0)


func test_an_enemy_or_unfinished_refinery_does_not_pipe() -> void:
	var sc: Dictionary = _scene(0.8)
	var w: SimWorld = sc["w"]
	var _enemy: int = HarvestTestKit.refinery(w, 400.0, 1)
	var mine: int = HarvestTestKit.refinery(w, -400.0)
	w.store().flags[mine] |= EntityStore.F_BUILDING
	K.set_pool(w, 0)
	K.pass_n(w, int(10.0 * HZ))
	assert_int(_ice(w).refinery_for(sc["ext"])).is_equal(-1)
	assert_float(w.store().cargo[sc["ext"]]).is_equal_approx(8.0, 0.2)
	assert_int(K.ice(w)).is_equal(0)


func test_a_full_stockpile_keeps_the_ice_in_the_buffer() -> void:
	var sc: Dictionary = _scene(0.8)
	var w: SimWorld = sc["w"]
	var _ref: int = HarvestTestKit.refinery(w, 400.0)
	K.set_pool(w, 100000)                                                     # clamps to the cap
	var cap: int = w.economy().economy.caps(0).y
	assert_int(K.ice(w)).is_equal(cap)
	K.pass_n(w, int(100.0 * HZ))
	assert_int(K.ice(w)).is_equal(cap)
	assert_float(w.store().cargo[sc["ext"]]).is_equal_approx(80.0, 0.5)       # nothing is lost
	K.set_pool(w, 0)
	K.pass_n(w, 2)
	assert_float(w.store().cargo[sc["ext"]]).is_less(1.0)                     # piped as soon as there is room


func test_a_node_gives_only_what_is_left_and_an_off_node_extractor_nothing() -> void:
	var sc: Dictionary = _scene(80.0, 2000)
	var w: SimWorld = sc["w"]
	_ice(w).nodes.amount[sc["node"]] = 10.0
	K.pass_n(w, int(5.0 * HZ))
	assert_float(w.store().cargo[sc["ext"]]).is_equal_approx(10.0, 0.01)
	assert_float(_ice(w).nodes.amount[sc["node"]]).is_equal_approx(0.0, 0.001)
	var lone: SimWorld = K.world()
	var le: int = K.extractor(lone, 3000.0)
	K.pass_n(lone, int(5.0 * HZ))
	assert_float(lone.store().cargo[le]).is_equal(0.0)


func test_an_unfinished_extractor_does_not_extract() -> void:
	var sc: Dictionary = _scene(80.0)
	var w: SimWorld = sc["w"]
	w.store().flags[sc["ext"]] |= EntityStore.F_BUILDING
	K.pass_n(w, int(5.0 * HZ))
	assert_float(w.store().cargo[sc["ext"]]).is_equal(0.0)


func test_a_hauler_loads_40_ice_per_second_from_a_buffer() -> void:
	var sc: Dictionary = _scene(0.0)
	var w: SimWorld = sc["w"]
	var e: int = sc["ext"]
	w.store().cargo[e] = 400.0
	w.store().cargo_kind[e] = 2
	var h: int = K.hauler(w, 0.0)
	K.pass_n(w, int(5.0 * HZ))
	assert_float(w.store().cargo[h]).is_equal_approx(200.0, 0.5)              # 5 s x 40 Ice/s
	assert_float(w.store().cargo[e]).is_equal_approx(200.0, 0.5)
	assert_int(w.store().cargo_kind[h]).is_equal(2)
	K.pass_n(w, int(6.0 * HZ))
	assert_float(w.store().cargo[h]).is_equal_approx(400.0, 0.01)             # `cargo_ice`: the hold is full
	assert_float(w.store().cargo[e]).is_equal_approx(0.0, 0.01)
	assert_int(w.store().cargo_kind[e]).is_equal(0)


func test_a_hauler_out_of_reach_or_of_the_other_team_moves_nothing() -> void:
	var sc: Dictionary = _scene(0.0)
	var w: SimWorld = sc["w"]
	var e: int = sc["ext"]
	w.store().cargo[e] = 400.0
	var high: int = K.hauler(w, 0.0, 0, 300.0)
	var enemy: int = K.hauler(w, 0.0, 1)
	K.pass_n(w, int(5.0 * HZ))
	assert_float(w.store().cargo[high]).is_equal(0.0)
	assert_float(w.store().cargo[enemy]).is_equal(0.0)
	assert_float(w.store().cargo[e]).is_equal(400.0)


func test_a_hauler_unloads_40_ice_per_second_at_a_friendly_refinery() -> void:
	var w: SimWorld = K.world()
	var _ref: int = HarvestTestKit.refinery(w, 1000.0)
	var h: int = K.hauler(w, 1000.0)
	w.store().cargo[h] = 400.0
	w.store().cargo_kind[h] = 2
	K.set_pool(w, 0)
	K.pass_n(w, int(5.0 * HZ))
	assert_int(K.ice(w)).is_between(199, 201)                                 # 5 s x 40 Ice/s
	assert_float(w.store().cargo[h]).is_equal_approx(200.0, 1.0)
	K.pass_n(w, int(6.0 * HZ))
	assert_int(K.ice(w)).is_equal(400)
	assert_float(w.store().cargo[h]).is_equal(0.0)
	assert_int(w.store().cargo_kind[h]).is_equal(0)
	assert_int(w.economy().score.ledger.ice_delivered[0]).is_equal(400)       # the result counter (GD-27 seam)


func test_a_full_stockpile_keeps_the_hold_and_an_enemy_refinery_takes_nothing() -> void:
	var w: SimWorld = K.world()
	var _ref: int = HarvestTestKit.refinery(w, 1000.0)
	var _foe: int = HarvestTestKit.refinery(w, 3000.0, 1)
	var h: int = K.hauler(w, 1000.0)
	var g: int = K.hauler(w, 3000.0)
	w.store().cargo[h] = 400.0
	w.store().cargo[g] = 400.0
	K.set_pool(w, 100000)
	var cap: int = K.ice(w)
	K.pass_n(w, int(5.0 * HZ))
	assert_float(w.store().cargo[h]).is_equal(400.0)                          # no room: it waits
	assert_float(w.store().cargo[g]).is_equal(400.0)                          # not our Refinery
	assert_int(K.ice(w)).is_equal(cap)


func test_a_possessed_hauler_scores_its_delivery_on_the_pilot_side() -> void:
	var w: SimWorld = K.world()
	var _ref: int = HarvestTestKit.refinery(w, 1000.0)
	var h: int = K.hauler(w, 1000.0)
	w.store().cargo[h] = 100.0
	w.store().possessor[h] = 0
	K.set_pool(w, 0)
	var before: int = w.economy().score.ledger.pilot[0]
	K.pass_n(w, int(3.0 * HZ))
	assert_int(K.ice(w)).is_equal(100)
	assert_int(w.economy().score.ledger.pilot[0]).is_greater(before)


func test_a_dead_extractor_loses_its_buffer_and_a_dead_hauler_its_hold() -> void:
	var sc: Dictionary = _scene(80.0)
	var w: SimWorld = sc["w"]
	K.pass_n(w, 30)
	w._applier.kill(sc["ext"])
	w.step()
	var node_left: float = _ice(w).nodes.amount[sc["node"]]
	K.pass_n(w, 30)
	assert_float(_ice(w).nodes.amount[sc["node"]]).is_equal(node_left)       # no Extractor, no extraction


func test_save_restore_mid_pipe_replays_byte_for_byte() -> void:
	var sc: Dictionary = _scene(0.8)
	var w: SimWorld = sc["w"]
	var _ref: int = HarvestTestKit.refinery(w, 400.0)
	var _ev: Array[SimEvent] = EconomyTestKit.run(w, 100)
	var r: SimWorld = SimWorld.deserialize(w.serialize(), WorldTestKit.content(), null)
	assert_object(r).is_not_null()
	assert_array(r.serialize()).is_equal(w.serialize())
	assert_int(r.economy().ice.nodes.count()).is_equal(1)
	var _e1: Array[SimEvent] = EconomyTestKit.run(w, 200)
	var _e2: Array[SimEvent] = EconomyTestKit.run(r, 200)
	assert_array(r.serialize()).is_equal(w.serialize())
	assert_float(r.economy().ice.nodes.amount[0]).is_equal(w.economy().ice.nodes.amount[0])
