extends GdUnitTestSuite
## SupplyNet (GD-18; 02 s5.4): roots (Core, Outpost), Relay Pylon links inside build radii, the supplied flag of every
## finished structure, the tower ammo refill, the unsupplied fire rate and the next-tick cut. Derived state: S4 +
## determinism. Geometry on the datum: the start kit's Core at +X, structures `east` metres along +Y (Core radius 600,
## Pylon radius 250, Outpost radius 400).

const K: GDScript = preload("res://test/unit/sim/economy_test_kit.gd")


# WorldTestKit.spawn returns the first SPAWN event pending, so the start kit's events are drained first.
func _put(w: SimWorld, def: StringName, east: float, owner: int = 0) -> int:
	var _old: Array[SimEvent] = w.drain_events()
	return WorldTestKit.spawn(w, def, owner, 1 if owner == 1 else 0, WorldTestKit.at(0.0, east))


func _net(w: SimWorld) -> SupplyNet:
	return w.economy().supply


func _ok(w: SimWorld, id: int) -> bool:
	return _net(w).is_supplied(EntityId.slot(id))


func _kill(w: SimWorld, id: int) -> void:
	assert_int(K.code(w, CommandPayload.debug_set(0, id, CommandPayload.SET_KILL, 0.0))).is_equal(CommandResult.Code.ACCEPTED)
	w.step()


# Core at east 0 (radius 600); pylons at 500 / 700 / 900 chain outward (each inside the previous radius); tower at 1050.
func _chain() -> Dictionary:
	var w: SimWorld = K.solo_world()
	var p1: int = _put(w, &"relay_pylon", 500.0)
	var p2: int = _put(w, &"relay_pylon", 700.0)
	var p3: int = _put(w, &"relay_pylon", 900.0)
	var tw: int = _put(w, &"autocannon_turret", 1050.0)
	w.step()
	return {"w": w, "p1": p1, "p2": p2, "p3": p3, "tw": tw}


func test_a_tower_inside_a_root_radius_is_supplied() -> void:
	var w: SimWorld = K.solo_world()
	var near: int = _put(w, &"autocannon_turret", 400.0)
	var far: int = _put(w, &"autocannon_turret", 800.0)
	w.step()
	assert_bool(_ok(w, near)).is_true()
	assert_bool(_ok(w, far)).is_false()                        # 800 m from the Core, no Pylon


func test_a_pylon_chain_carries_supply_out_to_a_far_tower() -> void:
	var c: Dictionary = _chain()
	var w: SimWorld = c["w"]
	for k: String in ["p1", "p2", "p3", "tw"]:
		assert_bool(_ok(w, c[k])).override_failure_message(k).is_true()


func test_destroying_a_mid_chain_pylon_unsupplies_downstream_on_the_next_tick() -> void:
	var c: Dictionary = _chain()
	var w: SimWorld = c["w"]
	_kill(w, c["p2"])                                          # the command tick: step 9 frees it, step 10 rebuilds
	assert_bool(_ok(w, c["p1"])).is_true()                     # upstream stays fed
	assert_bool(_ok(w, c["p3"])).is_false()
	assert_bool(_ok(w, c["tw"])).is_false()
	var s: int = EntityId.slot(c["tw"])
	assert_int(w._combat.fire.unsupplied[s]).is_equal(1)       # what step 9 of the following tick reads
	w.step()
	assert_int(w._combat.fire.unsupplied[s]).is_equal(1)


func test_losing_the_root_unsupplies_the_whole_chain_and_a_new_pylon_restores_the_link() -> void:
	var c: Dictionary = _chain()
	var w: SimWorld = c["w"]
	_kill(w, c["p2"])
	var p2b: int = _put(w, &"relay_pylon", 700.0)
	w.step()
	assert_bool(_ok(w, p2b)).is_true()
	assert_bool(_ok(w, c["tw"])).is_true()                     # the replaced link feeds the tower again
	_kill(w, w.store().id_of(K.find(w, &"core")))
	for k: String in ["p1", "p3", "tw"]:
		assert_bool(_ok(w, c[k])).override_failure_message(k).is_false()


func test_an_unfinished_pylon_does_not_link_and_finishing_it_does() -> void:
	var c: Dictionary = _chain()
	var w: SimWorld = c["w"]
	_kill(w, c["p2"])
	var site: int = _put(w, &"relay_pylon", 700.0)
	w.store().flags[EntityId.slot(site)] |= EntityStore.F_BUILDING
	w.economy().economy.mark_dirty()
	w.step()
	assert_bool(_ok(w, c["tw"])).is_false()
	w.store().flags[EntityId.slot(site)] &= ~EntityStore.F_BUILDING
	w.economy().economy.mark_dirty()                           # Construction does this at BUILD_DONE
	w.step()
	assert_bool(_ok(w, c["tw"])).is_true()


func test_a_pylon_out_of_every_radius_supplies_nothing_around_it() -> void:
	var w: SimWorld = K.solo_world()
	var lone: int = _put(w, &"relay_pylon", 1500.0)
	var tw: int = _put(w, &"autocannon_turret", 1600.0)       # inside the lone Pylon's 250 m, outside any connected node
	w.step()
	assert_bool(_ok(w, lone)).is_false()
	assert_bool(_ok(w, tw)).is_false()


func test_an_outpost_is_a_root() -> void:
	var w: SimWorld = K.solo_world()
	var out: int = _put(w, &"outpost", 3000.0)
	var tw: int = _put(w, &"autocannon_turret", 3300.0)       # Outpost radius 400
	var p: int = _put(w, &"relay_pylon", 3350.0)
	var tw2: int = _put(w, &"autocannon_turret", 3550.0)      # via the Pylon (250), 550 m from the Outpost
	w.step()
	for id: int in [out, tw, p, tw2]:
		assert_bool(_ok(w, id)).is_true()


func test_a_teammates_network_counts_and_an_enemys_does_not() -> void:
	var w: SimWorld = WorldTestKit.world()
	var _core: int = WorldTestKit.spawn(w, &"core", 0, 0, WorldTestKit.at(0.0, 0.0))
	var mate: int = WorldTestKit.spawn(w, &"autocannon_turret", 2, 0, WorldTestKit.at(0.0, 300.0))    # player 2, team 0
	var foe: int = WorldTestKit.spawn(w, &"autocannon_turret", 1, 1, WorldTestKit.at(0.0, 320.0))     # team 1, same spot
	w.step()
	assert_bool(_ok(w, mate)).is_true()
	assert_bool(_ok(w, foe)).is_false()


func test_a_pylon_only_links_its_own_team() -> void:
	var w: SimWorld = WorldTestKit.world()
	var _core: int = WorldTestKit.spawn(w, &"core", 0, 0, WorldTestKit.at(0.0, 0.0))
	var enemy_pylon: int = WorldTestKit.spawn(w, &"relay_pylon", 1, 1, WorldTestKit.at(0.0, 500.0))
	w.step()
	assert_bool(_ok(w, enemy_pylon)).is_false()                # inside our Core's radius, but not our team's node


func test_supplied_towers_refill_to_the_pool_and_no_further() -> void:
	var w: SimWorld = K.solo_world()
	var tw: int = _put(w, &"autocannon_turret", 300.0)
	w.step()
	var s: int = EntityId.slot(tw)
	w.store().ammo[s] = 100
	var hz: int = WorldTestKit.rules().tick_hz
	var _a: Array[SimEvent] = K.run(w, 2 * hz)
	assert_int(w.store().ammo[s]).is_equal(120)                # ammo_refill_per_s 10
	w.store().ammo[s] = 295
	var _b: Array[SimEvent] = K.run(w, 2 * hz)
	assert_int(w.store().ammo[s]).is_equal(300)                # pool 300


func test_fractional_refill_rates_land_on_the_exact_tick() -> void:
	var w: SimWorld = K.solo_world()
	var tw: int = _put(w, &"missile_tower", 300.0)             # ammo_refill_per_s 0.25, pool 12
	w.step()
	var s: int = EntityId.slot(tw)
	w.store().ammo[s] = 0
	var t0: int = w.tick()
	var hz: int = WorldTestKit.rules().tick_hz
	var got: PackedInt32Array = PackedInt32Array()
	for _k: int in 8 * hz:
		w.step()
		var _e: Array[SimEvent] = w.drain_events()
		if w.store().ammo[s] > got.size():
			got.push_back(w.tick() - t0)
	assert_int(got.size()).is_equal(2)                         # 8 s x 0.25 per s
	assert_int(got[1] - got[0]).is_equal(4 * hz)               # one round every 4 s, on the tick grid


func test_unsupplied_towers_never_refill() -> void:
	var w: SimWorld = K.solo_world()
	var tw: int = _put(w, &"autocannon_turret", 1500.0)
	w.step()
	var s: int = EntityId.slot(tw)
	w.store().ammo[s] = 100
	var _a: Array[SimEvent] = K.run(w, 60)
	assert_int(w.store().ammo[s]).is_equal(100)


func test_an_unsupplied_tower_fires_at_the_reduced_rate_from_its_remaining_pool() -> void:
	var w: SimWorld = K.solo_world()
	CombatTestKit.power(w, 0, 0)
	var fed: int = _put(w, &"autocannon_turret", 300.0)
	var cut: int = _put(w, &"autocannon_turret", 1500.0)
	_foe_near(w, fed)
	_foe_near(w, cut)
	w.step()
	var h: FireTestKit.TriggerHook = FireTestKit.hook(w)
	h.hold(fed, PilotInput.FIRE1)
	h.hold(cut, PilotInput.FIRE1)
	var sf: int = EntityId.slot(fed)
	var sc: int = EntityId.slot(cut)
	var _a: Array[SimEvent] = K.run(w, 216)                    # 7.2 s: 6 bursts of 5 fed, 3 unsupplied (A-66 x 0.5)
	assert_int(300 - w.store().ammo[sc]).is_equal(15)
	assert_int(w.store().ammo[sf]).is_greater(300 - 30)        # the fed tower's refill claws back what it spends


# CB13a (A-129): a tower fires only with an envelope target: a hostile Dart that cannot die, 300 m up and 300 m beside `tw`.
func _foe_near(w: SimWorld, tw: int) -> void:
	var p: Vector3 = w.store().pos[EntityId.slot(tw)]
	var f: Basis = Sphere.tangent_frame(p.normalized())
	var q: Vector3 = (p + f.x * 300.0).normalized() * (p.length() + 300.0)
	var other: int = 1 - w.store().team[EntityId.slot(tw)]
	var id: int = WorldTestKit.spawn(w, &"dart", other, other, q)
	w.store().hp[EntityId.slot(id)] = 1000000.0


func test_a_pylon_built_by_command_links_when_construction_finishes() -> void:
	var w: SimWorld = K.solo_world()
	var tw: int = _put(w, &"autocannon_turret", -800.0)        # west of the Core, out of its 600 m
	w.step()
	assert_bool(_ok(w, tw)).is_false()
	var pylon: int = WorldTestKit.def_id(&"relay_pylon")
	assert_int(K.code(w, Command.build(0, pylon, K.cell_west(450.0), 0))).is_equal(CommandResult.Code.ACCEPTED)
	var hz: int = WorldTestKit.rules().tick_hz
	var _a: Array[SimEvent] = K.run(w, 12 * hz)                 # 10 s build: the first Pylon is finished and linked
	assert_int(K.code(w, Command.build(0, pylon, K.cell_west(650.0), 0))).is_equal(CommandResult.Code.ACCEPTED)   # inside its 250 m
	var _b: Array[SimEvent] = K.run(w, 5 * hz)
	assert_bool(_ok(w, tw)).is_false()                          # the second is still a site: no link
	var _c: Array[SimEvent] = K.run(w, 8 * hz)
	assert_bool(_ok(w, tw)).is_true()                           # Core -> 450 -> 650 (200 m apart) -> tower 150 m on


func test_rebuilds_only_when_the_structure_set_changes() -> void:
	var c: Dictionary = _chain()
	var w: SimWorld = c["w"]
	var n: int = _net(w).rebuilds
	var _a: Array[SimEvent] = K.run(w, 30)
	assert_int(_net(w).rebuilds).is_equal(n)
	_kill(w, c["p2"])
	assert_int(_net(w).rebuilds).is_equal(n + 1)


func test_a_tower_dying_or_finishing_does_not_rebuild_the_graph_and_flags_itself() -> void:
	var c: Dictionary = _chain()
	var w: SimWorld = c["w"]
	var n: int = _net(w).rebuilds
	_kill(w, c["tw"])
	var tw2: int = _put(w, &"autocannon_turret", 1100.0)
	var far: int = _put(w, &"autocannon_turret", 2500.0)
	w.step()
	assert_int(_net(w).rebuilds).is_equal(n)                   # consumers never rebuild the graph
	assert_bool(_ok(w, tw2)).is_true()
	assert_bool(_ok(w, far)).is_false()


func test_s4_and_determinism_with_a_cut_chain() -> void:
	var ca: Dictionary = _chain()
	var cb: Dictionary = _chain()
	var a: SimWorld = ca["w"]
	var b: SimWorld = cb["w"]
	_kill(a, ca["p2"])
	_kill(b, cb["p2"])
	var _ea: Array[SimEvent] = K.run(a, 40)
	var _eb: Array[SimEvent] = K.run(b, 40)
	assert_bool(a.serialize() == b.serialize()).is_true()
	var r: SimWorld = SimWorld.deserialize(a.serialize(), WorldTestKit.content(), null)
	assert_object(r).is_not_null()
	var _ec: Array[SimEvent] = K.run(r, 40)
	var _ed: Array[SimEvent] = K.run(a, 40)
	assert_bool(r.serialize() == a.serialize()).is_true()
	assert_bool(r.economy().supply.unsupplied == a.economy().supply.unsupplied).is_true()
	assert_bool(r.economy().supply.is_supplied(EntityId.slot(ca["tw"]))).is_false()


func _refill_world() -> Dictionary:
	var w: SimWorld = K.solo_world()
	var gun: int = _put(w, &"autocannon_turret", 300.0)
	var mis: int = _put(w, &"missile_tower", 350.0)
	w.step()
	w.store().ammo[EntityId.slot(gun)] = 100
	w.store().ammo[EntityId.slot(mis)] = 1
	return {"w": w, "gun": gun, "mis": mis}


# Saved mid-refill: the autocannon is below its pool and the missile tower is partway (tick 17 of 120) through its 4 s
# round interval. The refill is a function of the tick, so the restored world continues byte for byte.
func test_s4_save_mid_refill_continues_byte_for_byte() -> void:
	var c: Dictionary = _refill_world()
	var a: SimWorld = c["w"]
	var _pre: Array[SimEvent] = K.run(a, 17)
	var ammo_gun: int = a.store().ammo[EntityId.slot(c["gun"])]
	var ammo_mis: int = a.store().ammo[EntityId.slot(c["mis"])]
	assert_int(ammo_gun).is_between(101, 120)                         # refilling, not at the pool
	var r: SimWorld = SimWorld.deserialize(a.serialize(), WorldTestKit.content(), null)
	assert_object(r).is_not_null()
	assert_int(r.store().ammo[EntityId.slot(c["gun"])]).is_equal(ammo_gun)
	assert_int(r.store().ammo[EntityId.slot(c["mis"])]).is_equal(ammo_mis)
	for _k: int in 10:
		var _ea: Array[SimEvent] = K.run(a, 37)                      # off the 30 Hz second and the 120-tick interval
		var _er: Array[SimEvent] = K.run(r, 37)
		assert_bool(r.serialize() == a.serialize()).is_true()
	assert_int(a.store().ammo[EntityId.slot(c["mis"])]).is_greater(ammo_mis)    # the missile tower did gain rounds
	assert_int(a.store().ammo[EntityId.slot(c["gun"])]).is_greater(ammo_gun + 100)   # 370 ticks x 10 per s


# A cut chain saved and restored: the flags come back on the first tick, and the replacement Pylon built after the
# restore re-supplies the tower exactly as in the uninterrupted world (refill resumes on the same tick).
func test_s4_supply_regained_after_restore() -> void:
	var c: Dictionary = _chain()
	var a: SimWorld = c["w"]
	_kill(a, c["p2"])
	a.store().ammo[EntityId.slot(c["tw"])] = 50
	var _pre: Array[SimEvent] = K.run(a, 11)
	var r: SimWorld = SimWorld.deserialize(a.serialize(), WorldTestKit.content(), null)
	assert_object(r).is_not_null()
	var _r1: Array[SimEvent] = K.run(r, 1)
	var _a1: Array[SimEvent] = K.run(a, 1)
	assert_bool(_ok(r, c["tw"])).is_false()                          # still cut after the restore
	assert_int(r.store().ammo[EntityId.slot(c["tw"])]).is_equal(50)  # and not refilling
	var _na: int = _put(a, &"relay_pylon", 700.0)
	var _nr: int = _put(r, &"relay_pylon", 700.0)
	var _e: Array[SimEvent] = K.run(a, 23)
	var _f: Array[SimEvent] = K.run(r, 23)
	assert_bool(_ok(r, c["tw"])).is_true()
	assert_int(r.store().ammo[EntityId.slot(c["tw"])]).is_greater(50)
	assert_bool(r.serialize() == a.serialize()).is_true()
