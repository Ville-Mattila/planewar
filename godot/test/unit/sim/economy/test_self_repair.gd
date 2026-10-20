extends GdUnitTestSuite
## SelfRepair (GD-16; 02 s6.3): a finished, supplied structure with no damage for 10 s repairs max(2, 0.005 hp) HP/s and
## pays 0.1 Ore per HP; it pauses without Ore, never touches sites or damaged-recently structures; stateless (S4) and
## deterministic.

const K: GDScript = preload("res://test/unit/sim/economy_test_kit.gd")


func _hurt(w: SimWorld, id: StringName, hp: float) -> int:
	var s: int = K.find(w, id)
	w.store().hp[s] = hp
	return s


func _top(w: SimWorld, s: int) -> float:
	return WorldDefs.new(WorldTestKit.content()).hp_max(0, w.store().def_id[s])


func _tick_hz(w: SimWorld) -> int:
	return WorldTestKit.rules().tick_hz


func test_rate_is_the_larger_of_two_and_half_a_percent() -> void:
	assert_float(SelfRepair.rate_hp_s(100.0)).is_equal(2.0)
	assert_float(SelfRepair.rate_hp_s(1200.0)).is_equal_approx(6.0, 0.0001)


func test_repairs_after_the_delay_and_pays_ore() -> void:
	var w: SimWorld = K.solo_world()
	var s: int = _hurt(w, &"refinery", 100.0)
	var hz: int = _tick_hz(w)
	var _gone: bool = w.store().free_slot(K.find(w, &"core"), 0)         # no Core, no trickle: Ore only falls
	var ore0: int = K.ore(w)
	var _a: Array[SimEvent] = K.run(w, 9 * hz)
	assert_float(w.store().hp[s]).is_equal(100.0)                       # 9 s: still inside the delay
	var _b: Array[SimEvent] = K.run(w, 2 * hz)
	var top: float = _top(w, s)
	var rate: float = SelfRepair.rate_hp_s(top)
	assert_float(w.store().hp[s]).is_greater(100.0)
	assert_float(w.store().hp[s]).is_less_equal(100.0 + 2.0 * rate)
	assert_int(K.ore(w)).is_less(ore0)                                  # paid
	assert_bool(w.economy().repair != null).is_true()


func test_a_hit_restarts_the_delay() -> void:
	var w: SimWorld = K.solo_world()
	var s: int = _hurt(w, &"refinery", 100.0)
	var hz: int = _tick_hz(w)
	var _a: Array[SimEvent] = K.run(w, 12 * hz)
	var healed: float = w.store().hp[s]
	assert_float(healed).is_greater(100.0)
	w.store().last_damage_tick[s] = w.tick()
	var _b: Array[SimEvent] = K.run(w, 8 * hz)
	assert_float(w.store().hp[s]).is_equal(healed)


func test_pauses_without_ore_and_resumes() -> void:
	var w: SimWorld = K.solo_world()
	var s: int = _hurt(w, &"refinery", 100.0)
	var _gone: bool = w.store().free_slot(K.find(w, &"core"), 0)         # no Core, no trickle: the pool stays empty
	var pool: int = K.ore(w)
	assert_bool(w.economy().economy.try_spend(0, pool, 0)).is_true()
	var hz: int = _tick_hz(w)
	var _a: Array[SimEvent] = K.run(w, 14 * hz)
	var stuck: float = w.store().hp[s]
	assert_float(stuck).is_equal(100.0)
	w.economy().economy.credit(0, 500, 0)
	var _b: Array[SimEvent] = K.run(w, 3 * hz)
	assert_float(w.store().hp[s]).is_greater(stuck)


func test_unsupplied_and_unfinished_do_not_repair() -> void:
	var w: SimWorld = K.solo_world()
	var s: int = _hurt(w, &"refinery", 100.0)
	w.economy().repair.unsupplied.resize(EntityId.WRECK_SLOT_MIN)
	w.economy().repair.unsupplied[s] = 1
	var hz: int = _tick_hz(w)
	var _a: Array[SimEvent] = K.run(w, 14 * hz)
	assert_float(w.store().hp[s]).is_equal(100.0)
	w.economy().repair.unsupplied[s] = 0
	w.store().flags[s] |= EntityStore.F_BUILDING
	var _b: Array[SimEvent] = K.run(w, 3 * hz)
	assert_float(w.store().hp[s]).is_equal(100.0)


func test_s4_and_determinism() -> void:
	var a: SimWorld = K.solo_world()
	var b: SimWorld = K.solo_world()
	var _ha: int = _hurt(a, &"refinery", 100.0)
	var _hb: int = _hurt(b, &"refinery", 100.0)
	var hz: int = _tick_hz(a)
	var _ea: Array[SimEvent] = K.run(a, 13 * hz)
	var _eb: Array[SimEvent] = K.run(b, 13 * hz)
	assert_bool(a.serialize() == b.serialize()).is_true()
	var r: SimWorld = SimWorld.deserialize(a.serialize(), WorldTestKit.content(), null)
	assert_object(r).is_not_null()
	var _ec: Array[SimEvent] = K.run(r, 3 * hz)
	var _ed: Array[SimEvent] = K.run(a, 3 * hz)
	assert_bool(r.serialize() == a.serialize()).is_true()
