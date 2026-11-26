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


# AI-18b (R0 B.31 A-153): the brain reads SimView.barrel_elevation and slews dead-beat: every tick the barrel moves by at
# most the def rate x dt toward the solve, monotone, and lands exactly on it; FIRE1 is held only on ticks that end with
# the barrel on the solve, so no shell leaves during the slew; the heading ends on the bearing (dead-beat yaw).
func test_the_barrel_is_slewed_dead_beat_onto_the_solve_and_fire1_waits_for_it() -> void:
	var c: int = _world(1075.0)
	var s: int = EntityId.slot(c)
	_attack(c)
	var step: float = _b.prm.barrel_rate / float(HZ)
	var prev: float = _w.view().barrel_elevation(c)
	assert_float(prev).is_equal(0.0)                                              # at rest: level
	var laid: int = -1
	for k: int in 10 * HZ:
		Ai16Kit.step(_w)
		var e: float = _w.view().barrel_elevation(c)
		assert_float(e - prev).is_between(-1e-12, step + 1e-12)                     # rate-limited, never back down
		var fired: bool = Ai18Kit.shells(_w, 0).size() > 0
		if fired and laid < 0:
			laid = k
			assert_float(e).is_equal_approx(float(_d.state.tti[s]), 1e-12)          # the first shell leaves on the solve
		prev = e
	assert_int(laid).is_greater(0)
	assert_float(_w.view().barrel_elevation(c)).is_equal_approx(float(_d.state.tti[s]), 1e-12)
	var err: float = SiegeAim.heading_error(_w.view().pos(c), -_w.view().basis(c).z, _w.view().pos(_t))
	assert_float(absf(err)).is_less(1e-4)                                         # dead-beat traverse: on the bearing
	assert_int(_b.stats_solves).is_equal(1)


# Saves with a near-bomb relocation pending and checks that the restored world relocates and continues byte for byte:
# (a) the tick the bomb landed (BOMB_IMPACT queued in the sim for the hook, A-71), (b) the woken think's RELOCATE route
# being driven (B_BLAST taken, the spot moved, the Crawler under way).
func test_a_restored_world_with_a_pending_near_bomb_relocation_continues_byte_for_byte() -> void:
	for phase: int in 2:
		var c: int = _world(1075.0)
		var s: int = EntityId.slot(c)
		_attack(c)
		Ai16Kit.step(_w, 8 * HZ)                                                    # sieging, firing
		assert_int(_tag(c)).is_equal(AiTag.Tag.SIEGE)
		var _h: int = Ai18Kit.bomb(_w, Ai16Kit.dir_at(1075.0, 40.0), DartKit.FOE, 1, 0)
		var landed: bool = false
		for _k: int in 3 * HZ:
			_w.step()
			for ev: SimEvent in _w.drain_events():
				landed = landed or ev.kind == SimEvent.Kind.BOMB_IMPACT
			if landed:
				break
		assert_bool(landed).is_true()
		assert_int(_b.stats_relocations).is_equal(0)                                # not heard yet: queued for the hook
		if phase == 1:
			Ai16Kit.step(_w, HZ)
			assert_int(_tag(c)).is_equal(AiTag.Tag.RELOCATE)
			assert_int(_b.stats_relocations).is_equal(1)
			assert_int(_d.state.bflags[s] & CrawlerBrain.B_ARRIVED).is_equal(0)       # under way to the new spot
		var w2: SimWorld = _restore()
		var b2: CrawlerBrain = _b2
		for _k: int in 20 * HZ:
			Ai16Kit.step(_w)
			Ai16Kit.step(w2)
		assert_bool(w2.serialize() == _w.serialize()).override_failure_message("phase %d" % phase).is_true()
		assert_int(b2.stats_relocations).is_equal(1 - phase)                       # the restored brain did the pending one
		assert_int(_b.stats_relocations).is_equal(1)
		assert_int(w2.view().ai_tag(c)).is_equal(_tag(c))


var _b2: CrawlerBrain


# A restored copy of `_w` with a fresh driver configured before `deserialize` (`_b2` its brain); bytes equal at once.
func _restore() -> SimWorld:
	var bytes: PackedByteArray = _w.serialize()
	var d2: AiDriver = AiDriver.new(Rng.new(3))
	_b2 = Ai18Kit.brain(_w.terrain())
	Ai18Kit.configure(d2, _b2)
	var w2: SimWorld = SimWorld.deserialize(bytes, Ai18Kit.content(), d2)
	assert_object(w2).is_not_null()
	d2.set_terrain(w2.terrain())
	assert_bool(w2.serialize() == bytes).is_true()
	return w2
