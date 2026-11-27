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


func test_dock_target_names_the_claimed_wreck_only_on_the_edge() -> void:
	var p: Vector2i = _setup()
	var sal: Salvage = _world.economy().salvage
	assert_int(sal.dock_target(0)).is_equal(0)
	var _r: CommandResult = _world.apply_command(Command.pilot(0, _world.tick() + 1, _pilot(DOCK)))
	_world._control.step_inputs(_world.tick() + 1)      # step 2: the edge is derived
	assert_int(sal.dock_target(0)).is_equal(p.y)
	assert_int(sal.dock_target(0)).is_equal(p.y)        # a query: nothing hooked yet
	assert_bool(K.tethered(_world, p.y)).is_false()


func test_save_restore_continue_with_the_press_is_byte_exact() -> void:
	var p: Vector2i = _setup()
	var _a: Array[SimEvent] = _press(_world, 0)
	var r: SimWorld = SimWorld.deserialize(_world.serialize(), WorldTestKit.content(), null)
	assert_object(r).is_not_null()
	var _b: Array[SimEvent] = _press(_world, DOCK)
	var _c: Array[SimEvent] = _press(r, DOCK)
	assert_bool(K.tethered(r, p.y)).is_true()
	assert_array(r.serialize()).is_equal(_world.serialize())
