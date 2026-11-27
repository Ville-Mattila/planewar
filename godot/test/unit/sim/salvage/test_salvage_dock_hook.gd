extends GdUnitTestSuite
## GD-40 W12 (sim/salvage/MODULE.md; R0 B.20 A-108): a possessed ship hooks the nearest free wreck in reach on the DOCK
## edge when a tow slot is free; otherwise DOCK keeps its meaning. WRECK_SALVAGED waits for delivery.

const K: GDScript = preload("res://test/unit/sim/salvage/salvage_test_kit.gd")
const DOCK: int = PilotInput.DOCK

var _world: SimWorld = null


func _press(w: SimWorld, buttons: int, player: int = 0) -> Array[SimEvent]:
	DockingTestKit.step_piloted(w, player, buttons)
	return w.drain_events()


# A possessed ship 20 m over the datum and one wreck on the ground beneath it; returns (ship slot, wreck slot).
func _setup(def: StringName = &"hauler") -> Vector2i:
	_world = K.world()
	var h: int = K.put(_world, def, 0, 0, 20.0, 3000.0)
	var wr: int = K.wreck_at(_world, &"dart", 60.0, K.at(0.0, 3000.0))
	assert_bool(DockingTestKit.possess(_world, _world.store().id_of(h), 0)).is_true()
	return Vector2i(h, wr)


func _pilot(buttons: int) -> PilotInput:
	var i: PilotInput = PilotInput.new()
	i.buttons = buttons
	return i


func test_dock_edge_hooks_the_free_wreck_without_salvaging_it() -> void:
	var p: Vector2i = _setup()
	var ev: Array[SimEvent] = _press(_world, DOCK)
	assert_bool(K.tethered(_world, p.x) and K.tethered(_world, p.y)).is_true()
	assert_int(_world.store().link[p.y]).is_equal(_world.store().id_of(p.x))
	assert_int(K.of_kind(ev, SimEvent.Kind.WRECK_SALVAGED).size()).is_equal(0)


func test_nothing_hooks_without_the_press() -> void:
	var p: Vector2i = _setup()
	var _e: Array[SimEvent] = _press(_world, 0)
	assert_bool(K.tethered(_world, p.y)).is_false()


func test_a_held_dock_is_one_edge_so_a_one_slot_ship_does_not_rehook() -> void:
	var p: Vector2i = _setup()
	var spare: int = K.wreck_at(_world, &"dart", 60.0, K.at(0.0, 3000.0))
	var _a: Array[SimEvent] = _press(_world, DOCK)
	var _b: Array[SimEvent] = _press(_world, DOCK)
	assert_int(_world.economy().salvage.towed_count(p.x)).is_equal(1)
	assert_bool(K.tethered(_world, spare) and K.tethered(_world, p.y)).is_false()


func test_a_new_press_hooks_the_second_slot_of_a_foundry_hauler() -> void:
	var w: SimWorld = K.world()
	var h: int = K.put(w, &"hauler", K.FOUNDRY_SLOT, 0, 20.0, 3000.0)
	var w1: int = K.wreck_at(w, &"dart", 60.0, K.at(0.0, 3000.0))
	var w2: int = K.wreck_at(w, &"dart", 60.0, K.at(0.0, 3000.0))
	assert_bool(DockingTestKit.possess(w, w.store().id_of(h), K.FOUNDRY_SLOT)).is_true()
	var _a: Array[SimEvent] = _press(w, DOCK, K.FOUNDRY_SLOT)
	assert_int(w.economy().salvage.towed_count(h)).is_equal(1)
	var _b: Array[SimEvent] = _press(w, DOCK, K.FOUNDRY_SLOT)          # still held: no new edge
	assert_int(w.economy().salvage.towed_count(h)).is_equal(1)
	var _c: Array[SimEvent] = _press(w, 0, K.FOUNDRY_SLOT)
	var _d: Array[SimEvent] = _press(w, DOCK, K.FOUNDRY_SLOT)
	assert_int(w.economy().salvage.towed_count(h)).is_equal(2)
	assert_bool(K.tethered(w, w1) and K.tethered(w, w2)).is_true()


func test_the_nearest_wreck_wins() -> void:
	var w: SimWorld = K.world()
	var h: int = K.put(w, &"hauler", 0, 0, 20.0, 3000.0)
	var far_w: int = K.wreck_at(w, &"dart", 60.0, K.at(0.0, 3015.0))
	var near_w: int = K.wreck_at(w, &"dart", 60.0, K.at(0.0, 3003.0))
	assert_bool(DockingTestKit.possess(w, w.store().id_of(h), 0)).is_true()
	var _e: Array[SimEvent] = _press(w, DOCK)
	assert_bool(K.tethered(w, near_w)).is_true()
	assert_bool(K.tethered(w, far_w)).is_false()


func test_a_wreck_out_of_reach_or_already_towed_is_not_hooked() -> void:
	var w: SimWorld = K.world()
	var h: int = K.put(w, &"hauler", 0, 0, 20.0, 3000.0)
	var far_w: int = K.wreck_at(w, &"dart", 60.0, K.at(0.0, 3100.0))
	var other: int = K.put(w, &"hauler", 2, 0, 20.0, 3020.0)
	var taken: int = K.wreck_at(w, &"dart", 60.0, K.at(0.0, 3010.0))
	assert_int(w.economy().salvage.try_attach(other, taken)).is_equal(Salvage.Hook.OK)
	assert_bool(DockingTestKit.possess(w, w.store().id_of(h), 0)).is_true()
	var _e: Array[SimEvent] = _press(w, DOCK)
	assert_bool(K.tethered(w, far_w)).is_false()
	assert_int(w.store().link[taken]).is_equal(w.store().id_of(other))
	assert_int(w.economy().salvage.towed_count(h)).is_equal(0)


func test_a_dart_never_hooks() -> void:
	var p: Vector2i = _setup(&"dart")
	var _e: Array[SimEvent] = _press(_world, DOCK)
	assert_bool(K.tethered(_world, p.y)).is_false()
	assert_bool(K.tethered(_world, p.x)).is_false()


# Probe A (review round 1): another Hauler's TOW order names the claimed wreck. The press is decided once, at step 4, and
# step 10 honours it before the W6 auto-hook, so the possessed ship tows it and the order's Hauler does not.
func test_the_claimed_wreck_is_hooked_before_the_auto_hook_of_a_tow_order() -> void:
	var w: SimWorld = K.world()
	var h: int = K.put(w, &"hauler", 0, 0, 20.0, 3000.0)
	var wr: int = K.wreck_at(w, &"dart", 60.0, K.at(0.0, 3015.0))
	var other: int = K.put(w, &"hauler", 2, 0, 20.0, 3030.0)
	K.haul(w, other, OrderSpec.HaulMode.TOW, w.store().id_of(wr))
	assert_bool(DockingTestKit.possess(w, w.store().id_of(h), 0)).is_true()
	assert_int(w.store().link[wr]).is_equal(0)
	var _e: Array[SimEvent] = _press(w, DOCK)
	assert_int(w.store().link[wr]).is_equal(w.store().id_of(h))
	assert_int(w.economy().salvage.towed_count(other)).is_equal(0)


# A velocity of `v` m/s from the ship toward the wreck's east position.
func _fly(w: SimWorld, h: int, from_east: float, to_east: float, v: float) -> void:
	w.store().vel[h] = (K.at(20.0, to_east) - K.at(20.0, from_east)).normalized() * v


# Probe B (review round 1): out of reach at the claim (33.1 m), in reach (30.1 m) after step 5 moved the ship: no claim,
# so no hook, and DOCK keeps its auto-dock meaning on that tick.
func test_a_ship_that_closes_into_reach_after_the_claim_hooks_nothing() -> void:
	var w: SimWorld = K.world()
	var h: int = K.put(w, &"hauler", 0, 0, 20.0, 3000.0)
	var wr: int = K.wreck_at(w, &"dart", 60.0, K.at(0.0, 3026.4))
	assert_bool(DockingTestKit.possess(w, w.store().id_of(h), 0)).is_true()
	assert_float(w.store().pos[h].distance_to(w.store().pos[wr])).is_greater(w.economy().salvage.reach_m())
	_fly(w, h, 3000.0, 3026.4, 90.0)
	var _e: Array[SimEvent] = _press(w, DOCK)
	assert_float(w.store().pos[h].distance_to(w.store().pos[wr])).is_less(w.economy().salvage.reach_m())
	assert_bool(K.tethered(w, wr)).is_false()


# The decision is the claim: a ship in reach at step 4 that has left it by step 10 still hooks the wreck it claimed.
func test_a_claim_taken_in_reach_is_hooked_even_if_the_ship_has_left_it() -> void:
	var w: SimWorld = K.world()
	var h: int = K.put(w, &"hauler", 0, 0, 20.0, 3000.0)
	var wr: int = K.wreck_at(w, &"dart", 60.0, K.at(0.0, 3024.0))
	assert_bool(DockingTestKit.possess(w, w.store().id_of(h), 0)).is_true()
	assert_float(w.store().pos[h].distance_to(w.store().pos[wr])).is_less(w.economy().salvage.reach_m())
	_fly(w, h, 3024.0, 3000.0, 90.0)
	var _e: Array[SimEvent] = _press(w, DOCK)
	assert_bool(K.tethered(w, wr)).is_true()
	assert_int(w.store().link[wr]).is_equal(w.store().id_of(h))


func test_a_claim_on_a_wreck_that_expires_this_tick_hooks_nothing_and_does_not_leak() -> void:
	var w: SimWorld = K.world()
	var h: int = K.put(w, &"hauler", 0, 0, 20.0, 3000.0)
	var wr: int = K.wreck_at(w, &"dart", 60.0, K.at(0.0, 3000.0))
	w.store().spawn_tick[wr] = w.tick() - roundi(WorldTestKit.content().economy.wreck_lifetime_s * float(WorldTestKit.rules().tick_hz))
	assert_bool(DockingTestKit.possess(w, w.store().id_of(h), 0)).is_true()
	var _e: Array[SimEvent] = _press(w, DOCK)
	assert_int(w.economy().salvage.towed_count(h)).is_equal(0)
	assert_bool(K.tethered(w, h)).is_false()


func test_a_tie_takes_the_lowest_slot_and_the_boundary_hooks() -> void:
	var w: SimWorld = K.world()
	var h: int = K.put(w, &"hauler", 0, 0, 20.0, 3000.0)
	var first: int = K.wreck_at(w, &"dart", 60.0, K.at(0.0, 3000.0))
	var second: int = K.wreck_at(w, &"dart", 60.0, K.at(0.0, 3000.0))
	assert_bool(DockingTestKit.possess(w, w.store().id_of(h), 0)).is_true()
	var _e: Array[SimEvent] = _press(w, DOCK)
	assert_bool(K.tethered(w, mini(first, second))).is_true()
	assert_bool(K.tethered(w, maxi(first, second))).is_false()


func test_save_restore_continue_with_the_press_is_byte_exact() -> void:
	var p: Vector2i = _setup()
	var _a: Array[SimEvent] = _press(_world, 0)
	var r: SimWorld = SimWorld.deserialize(_world.serialize(), WorldTestKit.content(), null)
	assert_object(r).is_not_null()
	var _b: Array[SimEvent] = _press(_world, DOCK)
	var _c: Array[SimEvent] = _press(r, DOCK)
	assert_bool(K.tethered(r, p.y)).is_true()
	assert_array(r.serialize()).is_equal(_world.serialize())
