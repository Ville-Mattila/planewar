extends GdUnitTestSuite
## GD-38 (SH11; R0 A-73): `SimView.shield01(id)` and the `TeamStateView.CORE_SHIELD_UP` flag over `ShieldDomes`.

const K: GDScript = preload("res://test/unit/sim/combat/shield_test_kit.gd")
const HZ: int = 30
const CORE_CAP: float = 2400.0
const PROJECTOR_CAP: float = 1200.0


func _id(w: SimWorld, slot: int) -> int:
	return w.store().id_of(slot)


func test_a_full_core_dome_reads_one_and_a_hit_lowers_it_by_the_bomb_damage() -> void:
	var w: SimWorld = K.world()
	var v: SimView = w.view()
	var core: int = K.core_slot(w)
	assert_float(v.shield01(_id(w, core))).is_equal(1.0)
	var _s: int = K.shot(w, core)
	assert_int(K.absorb(w)).is_equal(1)
	assert_float(v.shield01(_id(w, core))).is_equal_approx(w.shields().charge_of(core) / CORE_CAP, 1e-9)
	assert_float(v.shield01(_id(w, core))).is_between(0.5, 0.95)


func test_entities_without_a_dome_and_dead_ids_read_zero() -> void:
	var w: SimWorld = K.world()
	var v: SimView = w.view()
	var ship: int = K.put(w, &"dart", WorldTestKit.at(500.0))
	var foe_core: int = K.put(w, &"core", WorldTestKit.at(0.0, 3000.0), 1)
	assert_float(v.shield01(ship)).is_equal(0.0)
	assert_float(v.shield01(0)).is_equal(0.0)
	assert_float(v.shield01(EntityId.make(EntityId.slot(ship), 99))).is_equal(0.0)
	assert_float(v.shield01(foe_core)).is_between(0.0, 1.0)   # a Core whose dome is not bound yet or is: never -1.0 on a local view


func test_a_collapsed_dome_reads_zero_and_the_core_flag_clears_until_it_returns() -> void:
	var w: SimWorld = K.world()
	var v: SimView = w.view()
	var core: int = K.core_slot(w)
	assert_int(v.team_state(0).flags & TeamStateView.CORE_SHIELD_UP).is_equal(TeamStateView.CORE_SHIELD_UP)
	K.collapse(w, core)
	assert_float(v.shield01(_id(w, core))).is_equal(0.0)
	assert_int(v.team_state(0).flags & TeamStateView.CORE_SHIELD_UP).is_equal(0)
	var _a: Array[SimEvent] = EconomyTestKit.run(w, 10 * HZ + 5)
	assert_int(v.team_state(0).flags & TeamStateView.CORE_SHIELD_UP).is_equal(TeamStateView.CORE_SHIELD_UP)
	assert_float(v.shield01(_id(w, core))).is_greater(0.0)


func test_the_core_shield_flag_flips_at_tick_14400_with_core_shield_until_s_480() -> void:
	var w: SimWorld = K.world()
	var v: SimView = w.view()
	var core: int = K.core_slot(w)
	var until: int = roundi(WorldTestKit.content().match_rules.core_shield_until_s * float(HZ))
	assert_int(until).is_equal(14400)
	var _a: Array[SimEvent] = EconomyTestKit.run(w, until - 1 - w.tick())
	assert_int(v.team_state(0).flags & TeamStateView.CORE_SHIELD_UP).is_equal(TeamStateView.CORE_SHIELD_UP)
	assert_float(v.shield01(_id(w, core))).is_equal(1.0)
	var _b: Array[SimEvent] = EconomyTestKit.run(w, 1)
	assert_int(w.tick()).is_equal(until)
	assert_int(v.team_state(0).flags & TeamStateView.CORE_SHIELD_UP).is_equal(0)
	assert_float(v.shield01(_id(w, core))).is_equal(0.0)
	assert_int(v.team_state(1).flags & TeamStateView.CORE_SHIELD_UP).is_equal(0)


func test_exposure_clears_the_flag_and_scales_a_covering_projector_to_its_halved_cap() -> void:
	var w: SimWorld = K.world(true, WorldTestKit.rules(75.0))
	var v: SimView = w.view()
	var a: int = K.projector(w, 150.0)                                               # covers the Core
	var _o: int = K.put(w, &"outpost", WorldTestKit.at(0.0, 900.0))
	var b: int = K.projector(w, 1000.0)                                              # covers nothing
	var _f: int = K.fill(w, a, b)
	assert_float(v.shield01(_id(w, a))).is_equal(1.0)
	assert_int(v.team_state(0).flags & TeamStateView.CORE_SHIELD_UP).is_equal(TeamStateView.CORE_SHIELD_UP)
	var _x: Array[SimEvent] = EconomyTestKit.run(w, 2250 - w.tick())
	assert_int(v.team_state(0).flags & TeamStateView.CORE_SHIELD_UP).is_equal(0)
	assert_float(v.shield01(_id(w, a))).is_equal(1.0)                                # 600 of the halved 600
	var _s1: int = K.shot(w, a)
	var _s2: int = K.shot(w, b)
	assert_int(K.absorb(w)).is_equal(2)
	assert_float(v.shield01(_id(w, a))).is_equal_approx(w.shields().charge_of(a) / (PROJECTOR_CAP * 0.5), 1e-9)
	assert_float(v.shield01(_id(w, b))).is_equal_approx(w.shields().charge_of(b) / PROJECTOR_CAP, 1e-9)
	assert_float(v.shield01(_id(w, a))).is_less(1.0)
	assert_float(v.shield01(core_of(w))).is_equal(0.0)                       # the removed Core dome


func core_of(w: SimWorld) -> int:
	return w.store().id_of(K.core_slot(w))


func test_a_new_projector_starts_near_zero_and_reads_one_when_full() -> void:
	var w: SimWorld = K.world()
	var v: SimView = w.view()
	var p: int = K.projector(w, 300.0)
	assert_float(v.shield01(_id(w, p))).is_less(0.01)                               # starts at charge 0, one tick of recharge
	var _f: int = K.fill(w, p)
	assert_float(v.shield01(_id(w, p))).is_equal(1.0)


func test_the_base_simview_answers_minus_one_for_no_data() -> void:
	assert_float(SimView.new().shield01(123)).is_equal(-1.0)
