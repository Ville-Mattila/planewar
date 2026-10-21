extends GdUnitTestSuite
## GD-19 W4, W5 (sim/salvage/MODULE.md): a wreck lives wreck_lifetime_s, then goes with DEATH cause EXPIRED; the live cap
## stops new wrecks.

const K: GDScript = preload("res://test/unit/sim/salvage/salvage_test_kit.gd")


func _life_ticks() -> int:
	return roundi(WorldTestKit.content().economy.wreck_lifetime_s * float(WorldTestKit.rules().tick_hz))


func test_pods_expire_at_ninety_seconds_exactly() -> void:
	var w: SimWorld = K.world()
	var ev: Array[SimEvent] = K.kill(w, K.put(w, &"shipyard", 0, 0, 0.0))
	var ids: Array[int] = []
	for e: SimEvent in K.of_kind(ev, SimEvent.Kind.WRECK_SPAWNED):
		ids.append(e.a)
	var born: int = w.tick()
	assert_int(_life_ticks()).is_equal(90 * WorldTestKit.rules().tick_hz)
	var all: Array[SimEvent] = K.steps(w, _life_ticks() - 1)
	assert_int(w.tick()).is_equal(born + _life_ticks() - 1)
	assert_int(w.store().wrecks.size()).is_equal(2)
	assert_bool(w.store().alive(ids[0]) and w.store().alive(ids[1])).is_true()
	assert_int(K.of_kind(all, SimEvent.Kind.DEATH).size()).is_equal(0)
	var last: Array[SimEvent] = K.steps(w, 1)
	assert_int(w.store().wrecks.size()).is_equal(0)
	assert_bool(w.store().alive(ids[0]) or w.store().alive(ids[1])).is_false()
	var deaths: Array[SimEvent] = K.of_kind(last, SimEvent.Kind.DEATH)
	assert_int(deaths.size()).is_equal(2)
	assert_int(deaths[0].a).is_equal(ids[0])
	assert_int(deaths[1].a).is_equal(ids[1])
	assert_int(deaths[0].extra[0]).is_equal(Salvage.CAUSE_EXPIRED)
	assert_int(Salvage.CAUSE_EXPIRED).is_equal(1)
	assert_int(deaths[0].tick).is_equal(born + _life_ticks())


func test_the_lifetime_counts_from_the_death_tick_of_each_wreck() -> void:
	var w: SimWorld = K.world()
	var _a: Array[SimEvent] = K.kill(w, K.put(w, &"dart", 0, 0, 300.0))
	var first: int = w.store().wrecks[0]
	var _b: Array[SimEvent] = K.steps(w, 100)
	var _c: Array[SimEvent] = K.kill(w, K.put(w, &"dart", 0, 0, 300.0, 200.0))
	assert_int(w.store().wrecks.size()).is_equal(2)
	var _d: Array[SimEvent] = K.steps(w, _life_ticks() - 102)
	assert_bool((w.store().flags[first] & EntityStore.F_ALIVE) != 0).is_true()
	var _e: Array[SimEvent] = K.steps(w, 2)
	assert_int(w.store().wrecks.size()).is_equal(1)


func test_an_expired_wreck_ends_its_tow_and_the_haulers_flag() -> void:
	var w: SimWorld = K.world()
	var wr: int = K.wreck_at(w, &"dart", 60.0, K.at(0.0, 3000.0))
	var h: int = K.put(w, &"hauler", 0, 0, 20.0, 3000.0)
	assert_int(w.economy().salvage.try_attach(h, wr)).is_equal(Salvage.Hook.OK)
	assert_bool(K.tethered(w, h)).is_true()
	w.store().spawn_tick[wr] = w.tick() + 2 - _life_ticks()          # dies in step 10 of the second tick from now
	var _a: Array[SimEvent] = K.steps(w, 1)
	assert_bool(K.tethered(w, wr)).is_true()
	var ev: Array[SimEvent] = K.steps(w, 1)
	assert_int(K.of_kind(ev, SimEvent.Kind.DEATH).size()).is_equal(1)
	assert_int(w.store().wrecks.size()).is_equal(0)
	assert_int(w.economy().salvage.towed_count(h)).is_equal(0)
	assert_bool(K.tethered(w, h)).is_false()


func test_the_cap_stops_new_wrecks_and_loses_the_rest() -> void:
	var w: SimWorld = K.world(3)
	var ev: Array[SimEvent] = K.kill(w, K.put(w, &"core", 0, 0, 0.0))
	assert_int(K.of_kind(ev, SimEvent.Kind.WRECK_SPAWNED).size()).is_equal(3)
	assert_int(w.store().wrecks.size()).is_equal(3)
	var more: Array[SimEvent] = K.kill(w, K.put(w, &"dart", 0, 0, 300.0))
	assert_int(K.of_kind(more, SimEvent.Kind.WRECK_SPAWNED).size()).is_equal(0)
	assert_int(w.store().wrecks.size()).is_equal(3)


func test_a_slot_freed_by_expiry_lets_the_cap_admit_again() -> void:
	var w: SimWorld = K.world(1)
	var _a: Array[SimEvent] = K.kill(w, K.put(w, &"dart", 0, 0, 300.0))
	var _b: Array[SimEvent] = K.steps(w, _life_ticks())
	assert_int(w.store().wrecks.size()).is_equal(0)
	var ev: Array[SimEvent] = K.kill(w, K.put(w, &"dart", 0, 0, 300.0, 100.0))
	assert_int(K.of_kind(ev, SimEvent.Kind.WRECK_SPAWNED).size()).is_equal(1)
