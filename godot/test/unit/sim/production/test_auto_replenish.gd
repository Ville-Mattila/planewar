extends GdUnitTestSuite
## GD-17 (02 s6.4): TOGGLE_AUTO_REPLENISH targets, the scan that appends one item per period to the least-loaded eligible
## queue while alive + queued < target, the unit cap and early share lock guards, validation, and the S4 round trip.

const K := preload("res://test/unit/sim/economy_test_kit.gd")
const C := CommandResult.Code


func _yard_id(w: SimWorld) -> int:
	return w.store().id_of(K.find(w, &"shipyard"))


func _roster(def: StringName, n: int) -> PackedInt32Array:
	return PackedInt32Array([K.def(def), n])


func _len(w: SimWorld, factory_id: int) -> int:
	return w.economy().production.length(EntityId.slot(factory_id))


func test_toggle_sets_targets_and_the_view_reads_them() -> void:
	var w: SimWorld = K.solo_world()
	var yard: int = _yard_id(w)
	var dart: int = K.def(&"dart")
	assert_int(w.view().auto_replenish_target(0, dart)).is_equal(0)
	assert_int(K.code(w, Command.toggle_auto_replenish(0, yard, true, _roster(&"dart", 3)))).is_equal(C.ACCEPTED)
	var _e: Array[SimEvent] = K.run(w, 1)
	assert_int(w.view().auto_replenish_target(0, dart)).is_equal(3)
	assert_int(w.view().auto_replenish_target(1, dart)).is_equal(0)          # per player
	assert_int(K.code(w, Command.toggle_auto_replenish(0, yard, true, _roster(&"lancer", 1)))).is_equal(C.ACCEPTED)
	var _e2: Array[SimEvent] = K.run(w, 1)
	assert_int(w.view().auto_replenish_target(0, dart)).is_equal(0)          # the roster replaces the old one
	assert_int(w.view().auto_replenish_target(0, K.def(&"lancer"))).is_equal(1)
	assert_int(K.code(w, Command.toggle_auto_replenish(0, yard, false, PackedInt32Array()))).is_equal(C.ACCEPTED)
	var _e3: Array[SimEvent] = K.run(w, 1)
	assert_int(w.view().auto_replenish_target(0, K.def(&"lancer"))).is_equal(0)


func test_queue_fills_to_target_one_item_per_scan_and_stops() -> void:
	var w: SimWorld = K.solo_world()
	var yard: int = _yard_id(w)
	var hz: int = WorldTestKit.content().rules.tick_hz
	assert_int(K.code(w, Command.toggle_auto_replenish(0, yard, true, _roster(&"dart", 3)))).is_equal(C.ACCEPTED)
	var _a: Array[SimEvent] = K.run(w, hz + 1)
	assert_int(_len(w, yard)).is_equal(1)                                     # one per scan (auto_replenish_period_s)
	var _b: Array[SimEvent] = K.run(w, 3 * hz)
	assert_int(_len(w, yard)).is_equal(3)                                     # alive + queued reached the target ...
	var _c: Array[SimEvent] = K.run(w, 3 * hz)
	assert_int(_len(w, yard)).is_equal(3)                                     # ... and it stops there
	assert_int(w.view().production_queue(yard).size()).is_equal(3)
	for i: int in 3:
		assert_int(w.economy().production.queuer(EntityId.slot(yard), i)).is_equal(0)


func test_a_finished_unit_counts_as_alive_and_a_loss_is_replaced() -> void:
	var w: SimWorld = K.solo_world()                                          # the kit holds one Harvester
	var yard: int = _yard_id(w)
	var bay: int = w.store().id_of(K.find(w, &"vehicle_bay"))
	var hz: int = WorldTestKit.content().rules.tick_hz
	var _kit: Array[SimEvent] = K.run(w, 1)                                   # the start kit's SPAWN events
	assert_int(K.code(w, Command.toggle_auto_replenish(0, yard, true, _roster(&"harvester", 2)))).is_equal(C.ACCEPTED)
	var ev: Array[SimEvent] = K.run(w, 40 * hz)
	assert_int(K.count_kind(ev, SimEvent.Kind.SPAWN)).is_equal(1)             # one more built, nothing queued behind it
	assert_int(_len(w, bay)).is_equal(0)
	assert_int(w.store().ground.size()).is_equal(2)
	var id: int = w.store().id_of(w.store().ground[1])
	assert_int(K.code(w, CommandPayload.debug_set(0, id, CommandPayload.SET_KILL, 0.0))).is_equal(C.ACCEPTED)
	var _more: Array[SimEvent] = K.run(w, 2 * hz)
	assert_int(_len(w, bay)).is_equal(1)                                      # the lost Harvester is queued again


func test_the_least_loaded_eligible_queue_gets_the_item() -> void:
	var w: SimWorld = K.solo_world()
	var yard: int = _yard_id(w)
	var hz: int = WorldTestKit.content().rules.tick_hz
	var _kit: Array[SimEvent] = K.run(w, 1)                                   # the start kit's SPAWN events
	var yard2: int = WorldTestKit.spawn(w, &"shipyard", 0, 0, WorldTestKit.at(0.0, 3000.0))
	assert_int(K.code(w, Command.produce(0, yard, K.def(&"dart"), 2))).is_equal(C.ACCEPTED)
	assert_int(K.code(w, Command.toggle_auto_replenish(0, yard, true, _roster(&"scout", 2)))).is_equal(C.ACCEPTED)
	var _a: Array[SimEvent] = K.run(w, 2 * hz + 1)
	assert_int(_len(w, yard2)).is_equal(2)                                    # the empty yard takes both (yard holds 2 darts)
	assert_int(_len(w, yard)).is_equal(2)


func test_ground_units_go_to_a_vehicle_bay_not_a_shipyard() -> void:
	var w: SimWorld = K.solo_world()
	var yard: int = _yard_id(w)
	var bay: int = w.store().id_of(K.find(w, &"vehicle_bay"))
	var hz: int = WorldTestKit.content().rules.tick_hz
	assert_int(K.code(w, Command.toggle_auto_replenish(0, yard, true, _roster(&"harvester", 3)))).is_equal(C.ACCEPTED)
	var _a: Array[SimEvent] = K.run(w, 3 * hz + 1)
	assert_int(_len(w, yard)).is_equal(0)
	assert_int(_len(w, bay)).is_equal(2)                                      # the kit's Harvester is alive: 1 + 2 queued = 3
	var _b: Array[SimEvent] = K.run(w, 2 * hz)
	assert_int(_len(w, bay)).is_equal(2)


func test_the_unit_cap_stops_the_replenisher() -> void:
	var r: MatchRules = WorldTestKit.rules()
	r.caps.units = 3                                                          # the start kit's Harvester holds one
	var w: SimWorld = K.solo_world(true, 7, r)
	var yard: int = _yard_id(w)
	var hz: int = WorldTestKit.content().rules.tick_hz
	assert_int(K.code(w, Command.toggle_auto_replenish(0, yard, true, _roster(&"scout", 5)))).is_equal(C.ACCEPTED)
	var _a: Array[SimEvent] = K.run(w, 8 * hz)
	assert_int(_len(w, yard)).is_equal(2)                                     # 1 alive + 2 queued = cap 3


func test_the_early_share_lock_stops_the_replenisher() -> void:
	var w: SimWorld = WorldTestKit.world()                                    # team 0: players 0 and 2, so the lock applies
	var yard: int = WorldTestKit.spawn(w, &"shipyard", 0, 0, WorldTestKit.at(0.0, 400.0))
	var hz: int = WorldTestKit.content().rules.tick_hz
	var econ: EconomyDef = WorldTestKit.content().economy
	w.economy().build.spent_ore[0] = econ.early_share_ore - 100               # 100 Ore of quota left, a Lancer costs 300
	assert_bool(w.economy().economy.spend_locked(0, 300)).is_true()
	assert_bool(w.economy().economy.spend_locked(0, 100)).is_false()
	assert_int(K.code(w, Command.toggle_auto_replenish(0, yard, true, _roster(&"lancer", 2)))).is_equal(C.ACCEPTED)
	var _a: Array[SimEvent] = K.run(w, 3 * hz)
	assert_int(_len(w, yard)).is_equal(0)
	var _b: Array[SimEvent] = K.run(w, int(econ.early_share_lock_s) * hz)
	assert_int(_len(w, yard)).is_greater(0)                                   # after 2:00 the lock is gone


func test_toggle_validation() -> void:
	var w: SimWorld = WorldTestKit.world()                                    # players 0 and 2 share team 0
	var yard: int = WorldTestKit.spawn(w, &"shipyard", 0, 0, WorldTestKit.at(0.0, 400.0))
	var core: int = WorldTestKit.spawn(w, &"core", 0, 0, WorldTestKit.at(0.0, 900.0))
	var ok: PackedInt32Array = _roster(&"dart", 2)
	assert_int(K.code(w, Command.toggle_auto_replenish(1, yard, true, ok))).is_equal(C.REJECTED_NOT_OWNER)   # foreign team
	assert_int(K.code(w, Command.toggle_auto_replenish(0, core, true, ok))).is_equal(C.REJECTED_MALFORMED)
	assert_int(K.code(w, Command.toggle_auto_replenish(0, yard, true, PackedInt32Array([WorldTestKit.def_id(&"shipyard"), 1])))).is_equal(C.REJECTED_MALFORMED)
	var nine: PackedInt32Array = PackedInt32Array()
	for _i: int in 9:
		nine.append_array(ok)
	assert_int(K.code(w, Command.toggle_auto_replenish(0, yard, true, nine))).is_equal(C.REJECTED_MALFORMED)   # at most 8 pairs
	var bad: Command = Command.toggle_auto_replenish(0, yard, true, ok)
	bad.payload.append(7)                                                     # a stray byte
	assert_int(K.code(w, bad)).is_equal(C.REJECTED_MALFORMED)
	var flag: Command = Command.toggle_auto_replenish(0, yard, true, ok)
	flag.payload[0] = 2
	assert_int(K.code(w, flag)).is_equal(C.REJECTED_MALFORMED)
	assert_int(K.code(w, Command.toggle_auto_replenish(0, yard, true, ok))).is_equal(C.ACCEPTED)


func test_a_teammate_may_toggle_and_the_roster_is_their_own() -> void:
	var w: SimWorld = WorldTestKit.world()                                    # players 0 and 2 share team 0 (A-81: team-shared)
	var yard: int = WorldTestKit.spawn(w, &"shipyard", 0, 0, WorldTestKit.at(0.0, 400.0))
	var dart: int = K.def(&"dart")
	assert_int(K.code(w, Command.toggle_auto_replenish(0, yard, true, _roster(&"dart", 1)))).is_equal(C.ACCEPTED)
	assert_int(K.code(w, Command.toggle_auto_replenish(2, yard, true, _roster(&"dart", 4)))).is_equal(C.ACCEPTED)
	var _e: Array[SimEvent] = K.run(w, 1)
	assert_int(w.view().auto_replenish_target(2, dart)).is_equal(4)
	assert_int(w.view().auto_replenish_target(0, dart)).is_equal(1)           # the teammate's roster did not touch the owner's


func test_targets_survive_serialization() -> void:
	var w: SimWorld = K.solo_world()
	var yard: int = _yard_id(w)
	assert_int(K.code(w, Command.toggle_auto_replenish(0, yard, true, _roster(&"dart", 2)))).is_equal(C.ACCEPTED)
	var _a: Array[SimEvent] = K.run(w, 40)
	var copy: SimWorld = SimWorld.deserialize(w.serialize(), WorldTestKit.content(), null)
	assert_int(copy.view().auto_replenish_target(0, K.def(&"dart"))).is_equal(2)
	for _i: int in 200:
		w.step()
		copy.step()
	assert_bool(w.serialize() == copy.serialize()).is_true()
