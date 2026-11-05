extends GdUnitTestSuite
## GD-12 contract tests (sim/harvest/MODULE.md H4-H9; 02 s8.2): the measured trip time against the formula, `max_miners`,
## a partial load on depletion, the Refinery docks, mining only while stopped, Exposure leaving mining alone, and S4.

const K: GDScript = preload("res://test/unit/sim/harvest/harvest_test_kit.gd")
const HZ: float = 30.0
const DOCK_STANDOFF_M: float = 20.0      ## stop this far outside the Refinery radius, inside `salvage_deliver_m` (33 m)


# World with one Refinery at arc 0, the stop point `DOCK_STANDOFF_M` outside its radius and a field `d` metres further.
# Returns {w, ref, h, dock, field_dir, dock_dir}.
func _scene(d: float, capacity: int = 100000, max_miners: int = 4, regen: float = 0.0) -> Dictionary:
	var w: SimWorld = K.world()
	var ref: int = K.refinery(w)
	var dock_e: float = w.store().radius[ref] + DOCK_STANDOFF_M
	var h: int = K.harvester(w, dock_e)
	var _f: int = K.field(w, dock_e + d, capacity, regen, 150.0, max_miners)
	w.store().fwd[h] = Vector3(-sin(dock_e / K.R), cos(dock_e / K.R), 0.0)
	return {"w": w, "ref": ref, "h": h, "field_dir": K.dir_at(dock_e + d), "dock_dir": K.dir_at(dock_e)}


# Ticks between the 2nd and 3rd credited unload of a looping Harvester, in seconds.
func _measured_cycle_s(d: float) -> float:
	var sc: Dictionary = _scene(d)
	var w: SimWorld = sc["w"]
	var h: int = sc["h"]
	var cap: float = float(w._defs.base.ground_unit(w.store().def_id[h]).cargo_ore)
	var last: int = 0
	var marks: Array[int] = []
	for _i: int in int(400.0 * HZ):
		K.drive_cycle(w, h, sc["field_dir"], sc["dock_dir"], cap)
		var now: int = K.delivered(w)
		if now != last:
			marks.append(w.tick())
			last = now
		if marks.size() >= 3:
			break
	assert_int(marks.size()).is_equal(3)
	return float(marks[2] - marks[1]) / HZ


func test_trip_time_matches_the_02_s8_2_formula_at_450_m() -> void:
	var w: SimWorld = K.world()
	var def: GroundUnitDef = w._defs.base.ground_unit(WorldTestKit.def_id(&"harvester"))
	var formula: float = Economy.harvest_trip_time(450.0, def)
	assert_float(formula).is_equal_approx(108.5, 0.05)           # the 02 s8.2 table
	assert_float(_measured_cycle_s(450.0)).is_equal_approx(formula, formula * 0.05)


func test_trip_time_matches_the_02_s8_2_formula_at_600_m() -> void:
	var w: SimWorld = K.world()
	var def: GroundUnitDef = w._defs.base.ground_unit(WorldTestKit.def_id(&"harvester"))
	var formula: float = Economy.harvest_trip_time(600.0, def)
	assert_float(formula).is_equal_approx(136.0, 0.05)
	assert_float(_measured_cycle_s(600.0)).is_equal_approx(formula, formula * 0.05)


func test_a_delivery_credits_the_whole_load_to_the_owner_and_the_ledger() -> void:
	var sc: Dictionary = _scene(300.0)
	var w: SimWorld = sc["w"]
	var h: int = sc["h"]
	var before: int = EconomyTestKit.ore(w)
	var ledger: int = K.delivered(w)
	for _i: int in int(200.0 * HZ):
		K.drive_cycle(w, h, sc["field_dir"], sc["dock_dir"], 300.0)
		if K.delivered(w) > ledger:
			break
	assert_int(K.delivered(w) - ledger).is_equal(300)
	assert_bool(EconomyTestKit.ore(w) >= before + 300 - 2).is_true()
	assert_float(w.store().cargo[h]).is_equal(0.0)
	assert_int(K.state(w, h)).is_equal(Harvest.State.TRAVEL)


func test_max_miners_caps_the_harvesters_mining_at_once() -> void:
	var w: SimWorld = K.world()
	var _f: int = K.field(w, 5000.0, 6000, 0.0, 150.0, 2)
	var hs: Array[int] = []
	for k: int in 3:
		hs.append(K.harvester(w, 5000.0 + 6.0 * float(k)))
	K.step(w, 60)
	var mining: int = 0
	for h: int in hs:
		if K.state(w, h) == Harvest.State.MINING:
			mining += 1
	assert_int(mining).is_equal(2)
	assert_int(w.economy().harvest.fields.miners_of(0)).is_equal(2)
	assert_float(w.store().cargo[hs[2]]).is_equal(0.0)         # the third mined nothing: it must re-target
	assert_int(K.state(w, hs[0])).is_equal(Harvest.State.MINING)    # a claim is kept by the earlier arrival
	assert_float(w.store().cargo[hs[0]]).is_greater(0.0)


func test_a_miner_that_leaves_the_field_frees_its_slot() -> void:
	var w: SimWorld = K.world()
	var _f: int = K.field(w, 5000.0, 6000, 0.0, 150.0, 1)
	var a: int = K.harvester(w, 5000.0)
	var b: int = K.harvester(w, 5010.0)
	K.step(w, 30)
	assert_int(K.state(w, a)).is_equal(Harvest.State.MINING)
	assert_int(K.state(w, b)).is_equal(Harvest.State.TRAVEL)
	w._inputs.e_thrust[a] = 1.0                                 # a drives off: moving harvesters do not mine
	K.step(w, 3)
	assert_int(K.state(w, a)).is_equal(Harvest.State.TRAVEL)
	assert_int(K.state(w, b)).is_equal(Harvest.State.MINING)


func test_a_depleted_field_gives_a_partial_load_and_releases_the_miner() -> void:
	var w: SimWorld = K.world()
	var i: int = K.field(w, 5000.0, 6000, 0.0, 150.0, 4)
	w.economy().harvest.fields.amount[i] = 100.0
	var h: int = K.harvester(w, 5000.0)
	K.step(w, int(10.0 * HZ))                                   # 100 Ore at 15 / s is 6.7 s
	assert_float(w.store().cargo[h]).is_equal_approx(100.0, 0.5)
	assert_int(w.view().field_remaining(i)).is_equal(0)
	assert_int(K.state(w, h)).is_equal(Harvest.State.TRAVEL)
	assert_int(w.economy().harvest.fields.miners_of(i)).is_equal(0)


func test_a_moving_harvester_inside_a_field_mines_nothing() -> void:
	var w: SimWorld = K.world()
	var _f: int = K.field(w, 5000.0)
	var h: int = K.harvester(w, 4900.0)
	for _i: int in 60:
		w._inputs.e_thrust[h] = 1.0
		w.step()
	assert_float(w.store().cargo[h]).is_equal(0.0)


func _loaded_at_dock(w: SimWorld, ref: int, n: int) -> Array[int]:
	var hs: Array[int] = []
	var e: float = w.store().radius[ref] + DOCK_STANDOFF_M
	for k: int in n:
		var h: int = K.harvester(w, e + 3.0 * float(k))
		w.store().cargo[h] = 300.0
		hs.append(h)
	return hs


func test_a_refinery_unloads_two_at_a_time_and_the_third_waits_for_a_dock() -> void:
	var w: SimWorld = K.world()
	var ref: int = K.refinery(w)
	var hs: Array[int] = _loaded_at_dock(w, ref, 3)
	K.step(w, 15)
	var unloading: int = 0
	var waiting: int = 0
	for h: int in hs:
		unloading += 1 if K.state(w, h) == Harvest.State.UNLOADING else 0
		waiting += 1 if K.state(w, h) == Harvest.State.WAITING else 0
	assert_int(unloading).is_equal(2)                           # economy.json refinery_docks = 2
	assert_int(waiting).is_equal(1)
	assert_int(K.delivered(w)).is_equal(0)
	K.step(w, int(6.0 * HZ))                                    # unload_time_s = 6
	assert_int(K.delivered(w)).is_equal(600)
	K.step(w, int(7.0 * HZ))
	assert_int(K.delivered(w)).is_equal(900)
	for h: int in hs:
		assert_int(K.state(w, h)).is_equal(Harvest.State.TRAVEL)


func test_an_enemy_refinery_takes_no_delivery() -> void:
	var w: SimWorld = K.world()
	var ref: int = SalvageTestKit.put(w, &"refinery", 1, 1, 0.0, 0.0)
	var e: float = w.store().radius[ref] + DOCK_STANDOFF_M
	var h: int = K.harvester(w, e)
	w.store().cargo[h] = 300.0
	K.step(w, int(10.0 * HZ))
	assert_float(w.store().cargo[h]).is_equal(300.0)
	assert_int(K.delivered(w)).is_equal(0)


func test_exposure_leaves_mining_and_delivery_running() -> void:
	var w: SimWorld = K.world(1.0)
	var i: int = K.field(w, 5000.0, 6000, 2.0)
	var h: int = K.harvester(w, 5000.0)
	K.step(w, int(5.0 * HZ))                                    # past Exposure at 1 s
	assert_float(w.store().cargo[h]).is_equal_approx(75.0, 1.5)      # 5 s x 15 Ore/s, give or take the claim tick
	assert_bool(w.economy().harvest.fields.amount[i] < 6000.0).is_true()


func test_save_restore_continue_mid_cycle_is_byte_exact() -> void:
	var sc: Dictionary = _scene(300.0, 6000, 4, 1.0)
	var w: SimWorld = sc["w"]
	var h: int = sc["h"]
	for _i: int in int(30.0 * HZ):                              # mining under way
		K.drive_cycle(w, h, sc["field_dir"], sc["dock_dir"], 300.0)
	assert_int(K.state(w, h)).is_equal(Harvest.State.MINING)
	var _ev: Array[SimEvent] = w.drain_events()
	var r: SimWorld = SimWorld.deserialize(w.serialize(), WorldTestKit.content(), null)
	assert_object(r).is_not_null()
	assert_array(r.serialize()).is_equal(w.serialize())
	assert_int(r.economy().harvest.fields.count()).is_equal(1)
	for _i: int in int(60.0 * HZ):                              # through the drive, unload and back
		K.drive_cycle(w, h, sc["field_dir"], sc["dock_dir"], 300.0)
		K.drive_cycle(r, h, sc["field_dir"], sc["dock_dir"], 300.0)
	assert_array(r.serialize()).is_equal(w.serialize())
	assert_int(K.delivered(w)).is_greater(0)
