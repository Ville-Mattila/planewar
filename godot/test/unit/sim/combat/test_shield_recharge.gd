extends GdUnitTestSuite
## GD-10 (02 s5.1, s5.2, s8.4, s12): recharge of the Shield Projector (delay, rate, Ice cost, supply, power, Exposure) and
## of the Core's integrated shield (no Ice, no power, removed at 480 s or Exposure), plus S4 and determinism with a dome
## mid-recharge and mid-collapse. Contract SH7-SH14 of sim/combat/MODULE.md.

const K: GDScript = preload("res://test/unit/sim/combat/shield_test_kit.gd")
const HZ: int = 30


func _run(w: SimWorld, n: int) -> Array[SimEvent]:
	return EconomyTestKit.run(w, n)


func _ice(w: SimWorld) -> int:
	return w.economy().economy.stockpile(0).y


func test_a_projector_recharges_20_per_s_and_pays_one_ice_per_20_points() -> void:
	var w: SimWorld = K.world()
	var p: int = K.projector(w, 300.0)
	var ice0: int = _ice(w)
	var c0: float = w.shields().charge_of(p)
	var _e: Array[SimEvent] = _run(w, 20 * HZ)
	var gained: float = w.shields().charge_of(p) - c0
	assert_float(gained).is_equal_approx(20.0 * 20.0, 1.0)                           # 20 s x 20 per s at ratio 1
	var spent: int = ice0 - _ice(w)
	assert_float(float(spent) * 20.0).is_equal_approx(gained, 20.0)                  # 0.05 Ice per point, less than one Ice prepaid
	assert_int(spent).is_between(20, 21)


func test_a_full_recharge_costs_60_ice_and_stops_at_charge_max() -> void:
	var w: SimWorld = K.world()
	var p: int = K.projector(w, 300.0)
	var ice0: int = _ice(w)
	var _e: Array[SimEvent] = _run(w, 70 * HZ)
	assert_float(w.shields().charge_of(p)).is_equal(1200.0)
	assert_int(ice0 - _ice(w)).is_between(60, 61)
	var ice1: int = _ice(w)
	var _f: Array[SimEvent] = _run(w, 10 * HZ)
	assert_int(_ice(w)).is_equal(ice1)                                               # full: no more Ice


func test_recharge_waits_five_seconds_after_an_absorb() -> void:
	var w: SimWorld = K.world()
	var p: int = K.projector(w, 300.0)
	var _filled: int = K.fill(w, p)
	var _id: int = K.shot(w, p)
	assert_int(K.absorb(w)).is_equal(1)
	var after_hit: float = w.shields().charge_of(p)
	var _a: Array[SimEvent] = _run(w, 149)
	assert_float(w.shields().charge_of(p)).is_equal(after_hit)                       # 149 ticks after the hit: still waiting
	var _b: Array[SimEvent] = _run(w, 1)
	assert_float(w.shields().charge_of(p)).is_greater(after_hit)                     # 150 ticks = recharge_delay_s
	var _c: Array[SimEvent] = _run(w, HZ)
	assert_float(w.shields().charge_of(p) - after_hit).is_equal_approx(20.0 * float(HZ + 1) / float(HZ), 0.05)


func test_an_unsupplied_projector_does_not_recharge_but_still_absorbs() -> void:
	var w: SimWorld = K.world()
	var p: int = K.projector(w, 900.0)                                               # outside the Core's 600 m build radius
	assert_bool(w.economy().supply.is_supplied(p)).is_false()
	var ice0: int = _ice(w)
	var _a: Array[SimEvent] = _run(w, 300)
	assert_float(w.shields().charge_of(p)).is_equal(0.0)                             # never charged: nothing paid
	assert_int(_ice(w)).is_equal(ice0)
	var root: int = K.put(w, &"outpost", WorldTestKit.at(0.0, 800.0))                 # a supply root within 400 m
	var _filled: int = K.fill(w, p)
	assert_int(K.hit(w, p)).is_equal(1)
	assert_int(EconomyTestKit.code(w, CommandPayload.debug_set(0, root, CommandPayload.SET_KILL, 0.0))).is_equal(CommandResult.Code.ACCEPTED)
	var _s: Array[SimEvent] = _run(w, 2)
	assert_bool(w.economy().supply.is_supplied(p)).is_false()                         # the link is cut
	var held: float = w.shields().charge_of(p)
	var ice1: int = _ice(w)
	var _b: Array[SimEvent] = _run(w, 400)
	assert_float(w.shields().charge_of(p)).is_equal(held)                            # no refill, no Ice
	assert_int(_ice(w)).is_equal(ice1)
	assert_int(K.hit(w, p)).is_equal(1)                                              # the dome is up, it just cannot refill
	var _o: int = K.put(w, &"outpost", WorldTestKit.at(0.0, 800.0))
	var _c: Array[SimEvent] = _run(w, 400)
	assert_bool(w.economy().supply.is_supplied(p)).is_true()
	assert_float(w.shields().charge_of(p)).is_greater(held - 400.0)


func test_without_ice_the_projector_waits_and_resumes_when_ice_arrives() -> void:
	var w: SimWorld = K.world()
	var p: int = K.projector(w, 300.0)
	var _paid: bool = w.economy().economy.try_spend(0, 0, _ice(w))                    # the pool is empty
	var held: float = w.shields().charge_of(p)
	var _a: Array[SimEvent] = _run(w, 200)
	assert_float(w.shields().charge_of(p)).is_equal_approx(held, 20.7)              # only the prepaid remainder (< 1 Ice), then nothing
	w.economy().economy.credit(0, 0, 5)
	var _b: Array[SimEvent] = _run(w, 200)
	assert_float(w.shields().charge_of(p)).is_greater(held + 100.0)


func test_power_ratio_scales_the_recharge_and_below_half_the_dome_is_down() -> void:
	var lit: SimWorld = K.world(true)
	var dim: SimWorld = K.world(false)                                                # Core 20 vs 35 demand = 0.571
	var pl: int = K.projector(lit, 300.0)
	var pd: int = K.projector(dim, 300.0)
	var l0: float = lit.shields().charge_of(pl)
	var d0: float = dim.shields().charge_of(pd)
	var _a: Array[SimEvent] = _run(lit, 300)
	var _b: Array[SimEvent] = _run(dim, 300)
	var ratio: float = dim.economy().economy.power_ratio(0)
	assert_float(ratio).is_equal_approx(20.0 / 35.0, 0.001)
	assert_float((dim.shields().charge_of(pd) - d0) / (lit.shields().charge_of(pl) - l0)).is_equal_approx(ratio, 0.02)
	var _filled: int = K.fill(dim, pd)
	var _p2: int = K.projector(dim, -300.0)                                           # demand 50: ratio 0.4 < 0.5
	assert_float(dim.economy().economy.power_ratio(0)).is_less(0.5)
	assert_bool(dim.shields().is_up(pd, dim.tick())).is_false()
	var _id: int = K.shot(dim, pd)
	assert_int(K.absorb(dim)).is_equal(0)                                             # offline: nothing absorbed
	var _c: Array[SimEvent] = _run(dim, 300)
	assert_float(dim.shields().charge_of(pd)).is_equal(1200.0)


func _exposure_world() -> Dictionary:
	var w: SimWorld = K.world(true, WorldTestKit.rules(75.0))                         # Exposure at tick 2250, after both Projectors are full
	var a: int = K.projector(w, 150.0)                                                # covers the Core (150 m < 250 m)
	var _o: int = K.put(w, &"outpost", WorldTestKit.at(0.0, 900.0))
	var b: int = K.projector(w, 1000.0)                                               # covers nothing, supplied by the Outpost
	var _filled: int = K.fill(w, a, b)
	return {"w": w, "a": a, "b": b}


func test_exposure_halves_charge_cap_and_recharge_of_a_projector_that_covers_a_core() -> void:
	var s: Dictionary = _exposure_world()
	var w: SimWorld = s["w"]
	var a: int = s["a"]
	var b: int = s["b"]
	assert_float(w.shields().charge_of(a)).is_equal(1200.0)
	var _x: Array[SimEvent] = _run(w, 2250 - w.tick())
	assert_float(w.shields().charge_of(a)).is_equal(600.0)                            # 1,200 x 0.5 cap
	assert_float(w.shields().charge_of(b)).is_equal(1200.0)                           # untouched
	var _r: Array[SimEvent] = _run(w, 600)
	assert_float(w.shields().charge_of(a)).is_equal(600.0)                            # never above the halved cap
	assert_float(w.shields().charge_of(b)).is_equal(1200.0)
	var _id: int = K.shot(w, a)
	var _id2: int = K.shot(w, b)
	assert_int(K.absorb(w)).is_equal(2)
	var a1: float = w.shields().charge_of(a)
	var b1: float = w.shields().charge_of(b)
	var _y: Array[SimEvent] = _run(w, 150 + 3 * HZ)                                   # 5 s delay, then 3 s of recharge
	assert_float(w.shields().charge_of(a) - a1).is_equal_approx(10.0 * 91.0 / 30.0, 0.01)   # 20 x 0.5 per s, 91 ticks from the 150th
	assert_float(w.shields().charge_of(b) - b1).is_equal_approx(20.0 * 91.0 / 30.0, 0.01)


func test_exposure_removes_the_core_shield_once_and_raises_core_shield_down() -> void:
	var w: SimWorld = K.world(true, WorldTestKit.rules(20.0))
	var core: int = K.core_slot(w)
	var _a: Array[SimEvent] = _run(w, 599 - w.tick())
	assert_bool(w.shields().is_up(core, w.tick())).is_true()
	var ev: Array[SimEvent] = _run(w, 1)                                              # tick 600: CORE_EXPOSURE
	assert_int(K.kinds(ev, SimEvent.Kind.CORE_EXPOSURE)).is_equal(1)
	assert_bool(w.shields().is_up(core, w.tick())).is_false()
	assert_bool(w.shields().core_up(0)).is_false()
	assert_float(w.shields().charge_of(core)).is_equal(0.0)
	assert_int(EconomyTestKit.count_alert(ev, AlertKind.Kind.CORE_SHIELD_DOWN)).is_equal(1)
	var _id: int = K.shot(w, core)
	assert_int(K.absorb(w)).is_equal(0)                                               # bombs now reach the Core
	var later: Array[SimEvent] = _run(w, 300)
	assert_int(EconomyTestKit.count_alert(later, AlertKind.Kind.CORE_SHIELD_DOWN)).is_equal(0)


func test_the_core_shield_expires_at_core_shield_until_s_480() -> void:
	var w: SimWorld = K.world()
	var core: int = K.core_slot(w)
	var until: int = roundi(WorldTestKit.content().match_rules.core_shield_until_s * float(HZ))
	assert_int(until).is_equal(480 * HZ)
	var _a: Array[SimEvent] = _run(w, until - 1 - w.tick())
	assert_bool(w.shields().is_up(core, w.tick())).is_true()
	assert_bool(w.shields().core_up(0)).is_true()
	var ev: Array[SimEvent] = _run(w, 1)
	assert_int(w.tick()).is_equal(until)
	assert_bool(w.shields().is_up(core, w.tick())).is_false()
	assert_bool(w.shields().core_up(0)).is_false()
	assert_int(EconomyTestKit.count_alert(ev, AlertKind.Kind.CORE_SHIELD_DOWN)).is_equal(1)


func test_the_core_shield_recharges_40_per_s_after_five_seconds_for_free() -> void:
	var w: SimWorld = K.world()
	var core: int = K.core_slot(w)
	var ice0: int = _ice(w)
	var _id: int = K.shot(w, core)
	assert_int(K.absorb(w)).is_equal(1)
	assert_float(w.shields().charge_of(core)).is_equal(2000.0)
	var _a: Array[SimEvent] = _run(w, 149)
	assert_float(w.shields().charge_of(core)).is_equal(2000.0)
	var _b: Array[SimEvent] = _run(w, HZ + 1)
	assert_float(w.shields().charge_of(core)).is_equal_approx(2000.0 + 40.0 * 31.0 / 30.0, 0.01)
	assert_int(_ice(w)).is_equal(ice0)                                                # no Ice
	var _c: Array[SimEvent] = _run(w, 2000)
	assert_float(w.shields().charge_of(core)).is_equal(2400.0)


func test_a_collapsed_core_shield_returns_empty_after_collapse_s_and_recharges() -> void:
	var w: SimWorld = K.world()
	var core: int = K.core_slot(w)
	K.collapse(w, core)                                                               # six bombs absorbed, the seventh collapses it
	assert_bool(w.shields().core_up(0)).is_false()
	var _a: Array[SimEvent] = _run(w, 10 * HZ + 5)
	assert_bool(w.shields().core_up(0)).is_true()
	assert_float(w.shields().charge_of(core)).is_between(0.1, 20.0)                   # back at 0 and already charging: the 5 s delay ran inside the collapse
	var _b: Array[SimEvent] = _run(w, HZ)
	assert_float(w.shields().charge_of(core)).is_greater(20.0)
