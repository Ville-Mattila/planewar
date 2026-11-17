extends GdUnitTestSuite
## AI-18 behaviour tests of `CrawlerBrain` (sim_ai/brains/MODULE.md CR1-CR4; 05 s6.7, s5.7) on a real SimWorld (flat datum):
## AUTO = HOLD without BRAKE, MOVE, vision fairness (a never-seen target gets no spot and no shell), the spot search
## skipping blocked cells, the near-bomb rule through the driver, and S4 (a restored world continues byte for byte). The
## acceptance scenarios are `test/sim/ai/test_sc_crawler.gd` on `tiny_test`.

const HZ: int = 30

var _w: SimWorld
var _d: AiDriver
var _b: CrawlerBrain
var _t: int


# An enemy Refinery at 0 m, a Crawler at `east`; with `mast` a friendly Sensor Mast 950 m from the Refinery.
func _world(east: float, mast: bool = true) -> int:
	_w = Ai16Kit.world(9)
	_t = Ai16Kit.put(_w, &"refinery", DartKit.FOE, 0.0)
	if mast:
		var _m: int = Ai16Kit.put(_w, &"sensor_mast", 0, 900.0, 300.0)
	var c: int = Ai16Kit.put(_w, &"siege_crawler", 0, east)
	_b = Ai18Kit.brain(_w.terrain())
	_d = Ai18Kit.driver(_w, _b)
	return c


func _tag(id: int) -> int:
	return _w.view().ai_tag(id)


func _attack(c: int) -> void:
	DartKit.order(_w, c, OrderSpec.make(OrderSpec.Kind.ATTACK, _t))


func test_auto_is_hold_and_the_unit_stands_without_brake() -> void:
	var c: int = _world(2000.0)
	var p: Vector3 = _w.view().pos(c)
	for _k: int in 5 * HZ:
		Ai16Kit.step(_w)
		assert_int(Ai17Kit.buttons(_w, c) & PilotInput.BRAKE).is_equal(0)
	assert_int(_tag(c)).is_equal(AiTag.Tag.HOLD)
	assert_float(_w.view().pos(c).distance_to(p)).is_less(0.01)
	assert_int(_b.stats_spots).is_equal(0)


func test_move_drives_to_the_point_and_stands() -> void:
	var c: int = _world(2000.0)
	var dest: Vector3 = Ai16Kit.dir_at(2200.0, 100.0) * Ai16Kit.R
	DartKit.order(_w, c, OrderSpec.make(OrderSpec.Kind.MOVE, 0, dest))
	Ai16Kit.step(_w, 60 * HZ)
	assert_int(_tag(c)).is_equal(AiTag.Tag.MOVE)
	assert_float(GroundFollower.flat(_w.view().pos(c), dest)).is_less(_b.prm.ground.arrive_m + 1.0)
	assert_float(_w.view().vel(c).length()).is_less(0.01)


# Vision only (05 s6): with no friendly sensor on the Refinery (2,000 m away, the Crawler's own sensor is 1,000 m) the
# ATTACK has nothing to aim at: no spot, no route, no shell, HOLD.
func test_a_target_the_team_never_saw_gets_no_spot_and_no_shell() -> void:
	var c: int = _world(2000.0, false)
	_attack(c)
	Ai16Kit.step(_w, 20 * HZ)
	assert_bool(_w.view().visible_to(0, _t)).is_false()
	assert_int(_tag(c)).is_equal(AiTag.Tag.HOLD)
	assert_int(_b.stats_spots).is_equal(0)
	assert_int(_d.state.path_ticket[EntityId.slot(c)]).is_equal(-1)
	assert_int(Ai18Kit.shells(_w, 0).size()).is_equal(0)
	assert_int(_w.view().ammo(c)).is_equal(20)


# A spot inside the band is kept where the unit stands (no travel); the first ring point blocked on the path grid is
# skipped for the next candidate, still inside the band.
func test_in_band_it_sieges_in_place_and_a_blocked_ring_point_is_skipped() -> void:
	var c: int = _world(1100.0)
	_attack(c)
	Ai16Kit.step(_w, 2 * _d.think_period())
	var s: int = EntityId.slot(c)
	assert_int(_tag(c)).is_equal(AiTag.Tag.SIEGE)
	assert_int(_d.state.bflags[s] & CrawlerBrain.B_ARRIVED).is_equal(CrawlerBrain.B_ARRIVED)
	assert_float(GroundFollower.flat(_d.state.goal[s], _w.view().pos(c))).is_less(0.01)
	var c2: int = _world(2400.0)
	var pa: Pathing = _w._pathing
	for dx: int in range(-3, 4):
		for dy: int in range(-3, 4):
			pa.set_weight(PathGrid.cell_of(Ai16Kit.dir_at(1075.0 + float(dx) * 36.8, float(dy) * 36.8)), PathGrid.W_BLOCKED)
	_attack(c2)
	Ai16Kit.step(_w, 2 * _d.think_period())
	var g: Vector3 = _d.state.goal[EntityId.slot(c2)]
	assert_int(_d.state.aux_id[EntityId.slot(c2)]).is_greater(0)
	assert_float(g.distance_to(_w.view().pos(_t))).is_between(1000.0, 1150.0)
	assert_bool(PathGrid.blocks(pa.weight(PathGrid.cell_of(g.normalized())))).is_false()


# NO_AMMO is decided at once on an empty magazine and the unit holds where it is (no spot, no route).
func test_an_empty_crawler_holds_on_an_attack_order() -> void:
	var c: int = _world(2000.0)
	_w.store().ammo[EntityId.slot(c)] = 0
	_attack(c)
	Ai16Kit.step(_w, 2 * _d.think_period())
	assert_int(_tag(c)).is_equal(AiTag.Tag.HOLD)
	assert_int(_b.stats_no_ammo).is_equal(1)
	assert_int(_b.stats_spots).is_equal(0)


func test_a_restored_world_continues_byte_for_byte_mid_siege() -> void:
	var c: int = _world(1900.0)
	_attack(c)
	Ai16Kit.step(_w, 120 * HZ)                                                    # travelled and firing
	assert_int(_tag(c)).is_equal(AiTag.Tag.SIEGE)
	assert_int(_w.view().ammo(c)).is_less(20)
	var bytes: PackedByteArray = _w.serialize()
	var d2: AiDriver = AiDriver.new(Rng.new(3))
	Ai18Kit.configure(d2, Ai18Kit.brain(_w.terrain()))
	var w2: SimWorld = SimWorld.deserialize(bytes, Ai18Kit.content(), d2)
	assert_object(w2).is_not_null()
	d2.set_terrain(w2.terrain())
	assert_bool(w2.serialize() == bytes).is_true()
	for _k: int in 40 * HZ:
		_w.step()
		w2.step()
		var _a: Array[SimEvent] = _w.drain_events()
		var _b2: Array[SimEvent] = w2.drain_events()
	assert_bool(w2.serialize() == _w.serialize()).is_true()
	assert_int(w2.view().ammo(c)).is_equal(_w.view().ammo(c))
