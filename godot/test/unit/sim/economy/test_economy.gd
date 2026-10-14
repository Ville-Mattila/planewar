extends GdUnitTestSuite
## Economy core (TA-19; 02 s8, R0 C2-14, C3-08): pools and caps, payment / refund / early share lock, power ratio and
## LOW_POWER, the Core trickle, STORAGE_FULL, solar factor, harvest trip time, the start kit, S4, determinism.

const K := preload("res://test/unit/sim/economy_test_kit.gd")


func test_start_kit_c2_14() -> void:
	var w: SimWorld = K.solo_world()
	var eco: EconomyDef = WorldTestKit.content().economy
	assert_int(K.ore(w)).is_equal(eco.start_ore)                       # 800 for one player
	assert_int(w.economy().economy.stockpile(0).y).is_equal(eco.start_ice)
	var st: EntityStore = w.store()
	for id: StringName in [&"core", &"refinery", &"shipyard", &"vehicle_bay"]:
		var s: int = K.find(w, id)
		assert_int(s).is_greater_equal(0)
		assert_int(st.flags[s] & EntityStore.F_BUILDING).is_equal(0)   # pre-built, finished
		assert_float(w.view().hp01(st.id_of(s))).is_equal(1.0)
		assert_int(st.team[s]).is_equal(0)
	assert_int(st.ground.size()).is_equal(1)                           # 1 Harvester
	assert_int(st.def_id[st.ground[0]]).is_equal(K.def(&"harvester"))
	var core: int = K.find(w, &"core")
	var refinery: int = K.find(w, &"refinery")
	var yard: int = K.find(w, &"shipyard")
	assert_float(Sphere.great_circle(st.pos[core], st.pos[refinery])).is_equal_approx(eco.start_refinery_dist_m, 12.0)
	assert_float(Sphere.great_circle(st.pos[core], st.pos[yard])).is_equal_approx(eco.start_adjacent_dist_m, 12.0)
	var grid: BuildGrid = w.economy().build.grid
	assert_int(grid.flags_of(st.anchor_cell[core]) & BuildGrid.OCCUPIED).is_equal(BuildGrid.OCCUPIED)
	assert_float(w.economy().economy.power_ratio(0)).is_equal(1.0)     # 02 s8.4: supply 20 = demand 20 at 0:00


func test_start_ore_is_per_player_and_summed_into_the_team_pool() -> void:
	var w: SimWorld = WorldTestKit.world()                             # players 0 and 2 share team 0
	assert_int(K.ore(w, 0)).is_equal(WorldTestKit.content().economy.start_ore * 2)
	assert_int(K.ore(w, 1)).is_equal(WorldTestKit.content().economy.start_ore)


func test_start_kit_counts_against_max_per_player() -> void:
	var w: SimWorld = K.solo_world()
	var b: Build = w.economy().build
	var yard: StructureDef = WorldTestKit.content().structures[K.def(&"shipyard") - DefRanges.STRUCTURE_BASE]
	assert_int(yard.max_per_player).is_equal(3)
	assert_int(b.can_place(0, K.def(&"core"), K.cell_west(900.0), 0)).is_equal(Build.Reject.PREREQ)   # not buildable
	assert_int(b.place(0, K.def(&"shipyard"), K.cell_west(300.0), 0)).is_not_equal(0)     # 2 of 3
	assert_int(b.place(0, K.def(&"shipyard"), K.cell_west(450.0), 0)).is_not_equal(0)     # 3 of 3
	assert_int(b.can_place(0, K.def(&"shipyard"), K.cell_west(200.0), 0)).is_equal(Build.Reject.CAP)   # the pre-built one counted


func test_try_spend_credit_and_clamp_to_caps() -> void:
	var w: SimWorld = K.solo_world()
	var e: Economy = w.economy().economy
	var cap: Vector2i = e.caps(0)
	assert_int(cap.x).is_equal(3000 + 1500)                            # 02 s8.6: Core + Refinery
	assert_bool(e.try_spend(0, 100, 0)).is_true()
	assert_int(K.ore(w)).is_equal(700)
	assert_bool(e.try_spend(0, 100000, 0)).is_false()
	assert_int(K.ore(w)).is_equal(700)                                 # a failed spend takes nothing
	e.credit(0, 100000, 0)
	assert_int(K.ore(w)).is_equal(cap.x)
	var events: Array[SimEvent] = K.run(w, 1)
	assert_int(K.count_alert(events, AlertKind.Kind.STORAGE_FULL)).is_equal(1)
	e.credit(0, 5, 0)
	assert_int(K.count_alert(K.run(w, 2), AlertKind.Kind.STORAGE_FULL)).is_equal(0)   # reported once per overflow episode


func test_pay_refund_and_ledger() -> void:
	var w: SimWorld = K.solo_world()
	var e: Economy = w.economy().economy
	var b: Build = w.economy().build
	assert_int(e.try_pay(0, 300, 20)).is_equal(Economy.Pay.OK)
	assert_int(K.ore(w)).is_equal(500)
	assert_int(w.economy().economy.stockpile(0).y).is_equal(WorldTestKit.content().economy.start_ice - 20)
	assert_int(b.spent_ore[0]).is_equal(300)
	assert_int(e.try_pay(0, 100000, 0)).is_equal(Economy.Pay.SHORT)
	e.refund(0, 225, 15)                                               # 75 % of 300 / 20
	assert_int(K.ore(w)).is_equal(725)
	assert_int(b.spent_ore[0]).is_equal(75)


func test_early_share_lock_pay_outcome() -> void:
	var w: SimWorld = WorldTestKit.world()                             # team 0 has two players: lock active until 2:00
	var e: Economy = w.economy().economy
	var lock: int = WorldTestKit.content().economy.early_share_ore
	assert_int(e.try_pay(0, lock + 1, 0)).is_equal(Economy.Pay.LOCKED)
	assert_int(e.try_pay(0, lock, 0)).is_equal(Economy.Pay.OK)
	assert_int(e.try_pay(0, 1, 0)).is_equal(Economy.Pay.LOCKED)        # 800 spent: nothing more until delivered Ore
	w.economy().build.delivered_ore[0] = 50
	assert_int(e.try_pay(0, 50, 0)).is_equal(Economy.Pay.OK)


func test_power_ratio_low_power_event_once() -> void:
	var w: SimWorld = K.solo_world()
	var e: Economy = w.economy().economy
	assert_float(e.power_ratio(0)).is_equal(1.0)
	assert_int(WorldTestKit.queue_spawn(w, &"shipyard", 0, 0, WorldTestKit.at(0.0, 3000.0))).is_equal(CommandResult.Code.ACCEPTED)   # demand 10 more
	var events: Array[SimEvent] = K.run(w, 3)
	assert_float(e.power_ratio(0)).is_equal_approx(20.0 / 30.0, 0.001)
	assert_int(K.count_kind(events, SimEvent.Kind.LOW_POWER)).is_equal(1)
	assert_int(K.count_alert(events, AlertKind.Kind.LOW_POWER)).is_equal(1)
	assert_int(K.count_kind(K.run(w, 40), SimEvent.Kind.LOW_POWER)).is_equal(0)   # not repeated while it lasts
	assert_float(w.view().stockpile(0).z).is_equal_approx(e.power_ratio(0), 0.001)


func test_solar_array_output_scales_with_latitude() -> void:
	var w: SimWorld = K.solo_world()
	var e: Economy = w.economy().economy
	var band: float = WorldTestKit.content().economy.solar_band_deg
	var north: float = deg_to_rad(band)
	var south: float = -north
	var s_def: StructureDef = WorldTestKit.content().structures[K.def(&"solar_array") - DefRanges.STRUCTURE_BASE]
	# A Solar Array on the equator yields half, on the north band edge all, on the south band edge nothing (02 s8.4).
	assert_float(Economy.solar_factor(Vector3(cos(0.0), 0.0, sin(0.0)), Vector3.BACK, false, band, 1.5)).is_equal_approx(0.5, 0.001)
	assert_float(Economy.solar_factor(Vector3(cos(north), 0.0, sin(north)), Vector3.BACK, false, band, 1.5)).is_equal_approx(1.0, 0.001)
	assert_float(Economy.solar_factor(Vector3(cos(south), 0.0, sin(south)), Vector3.BACK, false, band, 1.5)).is_equal_approx(0.0, 0.001)
	assert_float(Economy.solar_factor(Vector3(cos(north), 0.0, sin(north)), Vector3.BACK, true, band, 1.5)).is_equal_approx(1.5, 0.001)
	var id: int = WorldTestKit.spawn(w, &"solar_array", 0, 0, WorldTestKit.at(0.0, 3000.0))
	assert_int(id).is_not_equal(0)
	var pb: Vector2 = w.view().power_balance(0)
	assert_float(pb.x).is_equal_approx(20.0 + 0.5 * s_def.power, 0.5)   # Core 20 + 12 x ~0.5 (3 km east of the equator point)
	assert_float(e.power_ratio(0)).is_equal(1.0)


func test_harvest_trip_time_matches_the_02_table() -> void:
	var h: GroundUnitDef = WorldTestKit.content().ground_units[K.def(&"harvester") - DefRanges.GROUND_BASE]
	assert_float(Economy.harvest_trip_time(450.0, h)).is_equal_approx(108.5, 0.05)     # 02 s8.2
	assert_float(Economy.harvest_trip_time(200.0, h)).is_equal_approx(62.7, 0.1)


func test_core_trickle_credits_the_owner_and_the_ledger() -> void:
	var w: SimWorld = K.solo_world()
	var before: int = K.ore(w)
	var _ev: Array[SimEvent] = K.run(w, 300)                           # 10 s at 1.0 Ore/s per Core
	assert_int(K.ore(w) - before).is_equal(10)
	assert_int(w.economy().build.delivered_ore[0]).is_equal(10)
	assert_int(w.economy().build.delivered_ore[1]).is_equal(0)


func test_storage_caps_do_not_count_unfinished_sites() -> void:
	var w: SimWorld = K.solo_world()
	var e: Economy = w.economy().economy
	assert_int(K.code(w, Command.build(0, K.def(&"refinery"), K.cell_west(300.0), 0))).is_equal(CommandResult.Code.ACCEPTED)
	var _ev: Array[SimEvent] = K.run(w, 5)
	assert_int(e.caps(0).x).is_equal(4500)                             # the second Refinery is still a site
	var _ev2: Array[SimEvent] = K.run(w, 31 * WorldTestKit.content().rules.tick_hz)
	assert_int(e.caps(0).x).is_equal(6000)                             # finished after build_time_s 30


func test_determinism_two_worlds_identical_bytes() -> void:
	var a: SimWorld = K.solo_world()
	var b: SimWorld = K.solo_world()
	for w: SimWorld in [a, b]:
		assert_int(K.code(w, Command.build(0, K.def(&"solar_array"), K.cell_west(250.0), 0))).is_equal(CommandResult.Code.ACCEPTED)
		assert_int(K.code(w, Command.produce(0, w.store().id_of(K.find(w, &"shipyard")), K.def(&"dart"), 2))).is_equal(CommandResult.Code.ACCEPTED)
	var _x: Array[SimEvent] = K.run(a, 700)
	var _y: Array[SimEvent] = K.run(b, 700)
	assert_bool(a.serialize() == b.serialize()).is_true()
	assert_bool(SimSerialize.write_raw(a) == SimSerialize.write_raw(b)).is_true()
