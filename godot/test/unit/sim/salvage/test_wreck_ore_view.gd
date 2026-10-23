extends GdUnitTestSuite
## GD-41 (R0 B.20 A-108): `SimView.wreck_ore(id)` over real wrecks: the Ore a death left, 0.0 once the wreck is gone or for a
## non-wreck, -1.0 on a view without data.

const K: GDScript = preload("res://test/unit/sim/salvage/salvage_test_kit.gd")


func test_a_live_wreck_reports_the_ore_its_death_left() -> void:
	var w: SimWorld = K.world()
	var v: SimView = w.view()
	var wr: int = w.store().id_of(K.wreck_at(w, &"dart", 60.0, K.at(0.0, 3000.0)))
	assert_float(v.wreck_ore(wr)).is_equal(60.0)
	var _ev: Array[SimEvent] = K.kill(w, K.put(w, &"shipyard", 0, 0, 0.0))
	var pod: int = w.store().id_of(w.store().wrecks[1])
	assert_float(v.wreck_ore(pod)).is_equal(w.store().hp[EntityId.slot(pod)])
	assert_float(v.wreck_ore(pod)).is_greater(0.0)


func test_a_ship_a_zero_id_and_an_expired_wreck_report_zero() -> void:
	var w: SimWorld = K.world()
	var v: SimView = w.view()
	var ship: int = w.store().id_of(K.put(w, &"hauler", 0, 0, 20.0, 3000.0))
	var wr: int = w.store().id_of(K.wreck_at(w, &"dart", 60.0, K.at(0.0, 3200.0)))
	assert_float(v.wreck_ore(ship)).is_equal(0.0)
	assert_float(v.wreck_ore(0)).is_equal(0.0)
	w.store().spawn_tick[EntityId.slot(wr)] = w.tick() + 1 - roundi(WorldTestKit.content().economy.wreck_lifetime_s * float(WorldTestKit.rules().tick_hz))
	var _ev: Array[SimEvent] = K.steps(w, 1)
	assert_bool(w.store().alive(wr)).is_false()
	assert_float(v.wreck_ore(wr)).is_equal(0.0)


func test_a_view_without_data_answers_minus_one() -> void:
	assert_float(SimView.new().wreck_ore(123)).is_equal(-1.0)
