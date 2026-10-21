extends GdUnitTestSuite
## GD-39 (sim/salvage/MODULE.md W11, sim/pathing/MODULE.md P10; R0 B.20 A-108; 03 s6.1): a resting wreck makes its path
## cell impassable (255); hooked, delivered or expired it gives the cell its baked weight back (re-read from the map
## bake, nothing stored); a towed wreck blocks nothing; two wrecks on one cell keep it blocked until the last leaves.

const K: GDScript = preload("res://test/unit/sim/salvage/salvage_test_kit.gd")
const N: int = Sphere.GRID_PATH
const MAP: StringName = &"tiny_test"


func _paths(w: SimWorld) -> WreckPaths:
	return w.economy().salvage.paths


func _p(w: SimWorld) -> Pathing:
	return w._pathing


# Spawns a Dart standing on the surface at `dir` and marks it dying (any number may die in one tick).
func _doom(w: SimWorld, dir: Vector3) -> void:
	var s: int = w._applier.spawn(WorldTestKit.def_id(&"dart"), 0, 0, dir.normalized() * Sphere.PLANET_RADIUS, Vector3.ZERO, Vector3(0, 1, 0), w.tick())
	assert(s > 0)
	w._applier.kill(s)


func _cell_of_slot(w: SimWorld, s: int) -> int:
	return PathGrid.cell_of(w.store().pos[s])


func _face(cell: int) -> int:
	return cell >> (PathGrid.SHIFT + PathGrid.SHIFT)


# One Dart dies at the surface point `east` metres along +Y; returns the newest wreck slot.
func _one_wreck(w: SimWorld, east: float) -> int:
	var _ev: Array[SimEvent] = K.kill(w, K.put(w, &"dart", 0, 0, 0.0, east))
	assert(w.store().wrecks.size() >= 1)
	return w.store().wrecks[w.store().wrecks.size() - 1]


func test_a_wreck_coming_to_rest_blocks_its_path_cell_once() -> void:
	var w: SimWorld = K.world()
	var p: Pathing = _p(w)
	var probe: int = PathGrid.cell_of(K.at(0.0, 1500.0))
	var v0: int = p.version(_face(probe))
	var sets0: int = _paths(w).sets
	var wr: int = _one_wreck(w, 1500.0)
	var cell: int = _cell_of_slot(w, wr)
	assert_int(p.weight(cell)).is_equal(PathGrid.W_BLOCKED)
	assert_int(w.view().path_grid_version(_face(cell))).is_equal(v0 + 1)       # one set_weight, one bump
	assert_int(_paths(w).sets - sets0).is_equal(1)


func test_hooking_gives_the_baked_weight_back_and_releasing_blocks_again() -> void:
	var w: SimWorld = K.world()
	var wr: int = _one_wreck(w, 1500.0)
	var cell: int = _cell_of_slot(w, wr)
	var h: int = K.put(w, &"hauler", K.FOUNDRY_SLOT, 0, 20.0, 1500.0)
	var v: int = w.view().path_grid_version(_face(cell))
	assert_int(w.economy().salvage.try_attach(h, wr)).is_equal(Salvage.Hook.OK)
	assert_int(_p(w).weight(cell)).is_equal(1)                                   # the flat datum bake is weight 1
	assert_int(w.view().path_grid_version(_face(cell))).is_equal(v + 1)
	assert_int(w.economy().salvage.drop(h)).is_equal(1)
	assert_int(_p(w).weight(cell)).is_equal(PathGrid.W_BLOCKED)
	assert_int(w.view().path_grid_version(_face(cell))).is_equal(v + 2)


func test_a_failed_hook_changes_no_weight() -> void:
	var w: SimWorld = K.world()
	var wr: int = _one_wreck(w, 1500.0)
	var cell: int = _cell_of_slot(w, wr)
	var h: int = K.put(w, &"hauler", 0, 0, 20.0, 3000.0)                         # out of reach
	var v: int = w.view().path_grid_version(_face(cell))
	assert_int(w.economy().salvage.try_attach(h, wr)).is_equal(Salvage.Hook.TOO_FAR)
	assert_int(_p(w).weight(cell)).is_equal(PathGrid.W_BLOCKED)
	assert_int(w.view().path_grid_version(_face(cell))).is_equal(v)


func test_a_dead_hauler_releases_its_wreck_onto_a_blocked_cell() -> void:
	var w: SimWorld = K.world()
	var wr: int = _one_wreck(w, 1500.0)
	var cell: int = _cell_of_slot(w, wr)
	var h: int = K.put(w, &"hauler", 0, 0, 20.0, 1500.0)
	assert_int(w.economy().salvage.try_attach(h, wr)).is_equal(Salvage.Hook.OK)
	assert_int(_p(w).weight(cell)).is_equal(1)
	var _ev: Array[SimEvent] = K.kill(w, h)
	assert_bool(K.tethered(w, wr)).is_false()
	assert_int(_p(w).weight(cell)).is_equal(PathGrid.W_BLOCKED)


func test_delivery_leaves_the_cell_at_its_baked_weight() -> void:
	var w: SimWorld = K.world()
	var wr: int = _one_wreck(w, 1500.0)
	var cell: int = _cell_of_slot(w, wr)
	var h: int = K.put(w, &"hauler", 0, 0, 20.0, 1500.0)
	var _ref: int = K.put(w, &"refinery", 0, 0, 0.0, 1520.0)
	assert_int(w.economy().salvage.try_attach(h, wr)).is_equal(Salvage.Hook.OK)
	var v: int = w.view().path_grid_version(_face(cell))
	var _ev: Array[SimEvent] = K.steps(w, 2)
	assert_int(w.store().wrecks.size()).is_equal(0)
	assert_int(_p(w).weight(cell)).is_equal(1)
	assert_int(w.view().path_grid_version(_face(cell))).is_equal(v)             # delivery of a towed wreck touches nothing


func test_a_resting_wreck_expiring_restores_the_cell_but_a_towed_one_touches_nothing() -> void:
	var w: SimWorld = K.world()
	var rest: int = _one_wreck(w, 1500.0)
	var tow: int = _one_wreck(w, 4500.0)
	var rcell: int = _cell_of_slot(w, rest)
	var tcell: int = _cell_of_slot(w, tow)
	var h: int = K.put(w, &"hauler", 0, 0, 20.0, 4500.0)
	assert_int(w.economy().salvage.try_attach(h, tow)).is_equal(Salvage.Hook.OK)
	var v: int = w.view().path_grid_version(_face(tcell))
	var _ev: Array[SimEvent] = K.steps(w, 2800)
	assert_int(w.store().wrecks.size()).is_equal(0)
	assert_int(_p(w).weight(rcell)).is_equal(1)
	assert_int(_p(w).weight(tcell)).is_equal(1)
	assert_int(w.view().path_grid_version(_face(tcell))).is_equal(v)


func test_two_wrecks_on_one_cell_stay_blocked_until_the_last_leaves() -> void:
	var w: SimWorld = K.world()
	var dir: Vector3 = K.at(0.0, 1500.0)
	_doom(w, dir)
	_doom(w, dir)
	w.step()
	var _d: Array[SimEvent] = w.drain_events()
	assert_int(w.store().wrecks.size()).is_equal(2)
	var wa: int = w.store().wrecks[0]
	var wb: int = w.store().wrecks[1]
	var cell: int = _cell_of_slot(w, wa)
	assert_int(_cell_of_slot(w, wb)).is_equal(cell)
	var hauler: int = K.put(w, &"hauler", K.FOUNDRY_SLOT, 0, 20.0, 1500.0)
	assert_int(w.economy().salvage.try_attach(hauler, wa)).is_equal(Salvage.Hook.OK)
	assert_int(_p(w).weight(cell)).is_equal(PathGrid.W_BLOCKED)                  # the other still rests there
	assert_int(w.economy().salvage.try_attach(hauler, wb)).is_equal(Salvage.Hook.OK)
	assert_int(_p(w).weight(cell)).is_equal(1)
	assert_int(w.economy().salvage.drop(hauler)).is_equal(2)
	assert_int(_p(w).weight(cell)).is_equal(PathGrid.W_BLOCKED)


func test_two_wrecks_expiring_in_one_tick_restore_the_cell() -> void:
	var w: SimWorld = K.world()
	var dir: Vector3 = K.at(0.0, 1500.0)
	_doom(w, dir)
	_doom(w, dir)
	w.step()
	var cell: int = _cell_of_slot(w, w.store().wrecks[0])
	var _ev: Array[SimEvent] = K.steps(w, 2800)
	assert_int(w.store().wrecks.size()).is_equal(0)
	assert_int(_p(w).weight(cell)).is_equal(1)


func test_staggered_expiry_keeps_the_cell_blocked_for_the_later_wreck() -> void:
	var w: SimWorld = K.world()
	var dir: Vector3 = K.at(0.0, 1500.0)
	_doom(w, dir)
	w.step()
	var _s: Array[SimEvent] = K.steps(w, 9)
	_doom(w, dir)
	w.step()
	var cell: int = _cell_of_slot(w, w.store().wrecks[0])
	var _ev: Array[SimEvent] = K.steps(w, 2700 - 10)                             # the first expired, the second has ~10 ticks left
	assert_int(w.store().wrecks.size()).is_equal(1)
	assert_int(_p(w).weight(cell)).is_equal(PathGrid.W_BLOCKED)
	_ev = K.steps(w, 20)
	assert_int(w.store().wrecks.size()).is_equal(0)
	assert_int(_p(w).weight(cell)).is_equal(1)


func test_the_restored_weight_is_re_read_from_the_map_bake() -> void:
	var w: SimWorld = WorldTestKit.world(7, WorldTestKit.rules(), MAP)
	var baked: PackedByteArray = PathGrid.read_faces("res://content/maps/%s" % String(MAP))
	assert_int(baked.size()).is_equal(PathGrid.CELLS)
	var spot: Vector3 = Vector3.ZERO
	for k: int in 40:                                                             # a cell whose bake is neither 1 nor impassable
		var d: Vector3 = Vector3(1.0, 0.02 * float(k) - 0.4, 0.15).normalized()
		var wt: int = baked[PathGrid.cell_of(d)]
		if wt > 1 and wt < 255:
			spot = d
			break
	assert_bool(spot != Vector3.ZERO).override_failure_message("no weighted cell near +X in the bake").is_true()
	var cell: int = PathGrid.cell_of(spot)
	assert_int(_p(w).weight(cell)).is_equal(baked[cell])
	_doom(w, spot)
	w.step()
	var wr: int = w.store().wrecks[0]
	assert_int(_cell_of_slot(w, wr)).is_equal(cell)
	assert_int(_p(w).weight(cell)).is_equal(PathGrid.W_BLOCKED)
	var h: int = K.put(w, &"hauler", K.FOUNDRY_SLOT, 0, 20.0, 0.0)
	w.store().pos[h] = w.store().pos[wr] * (1.0 + 20.0 / Sphere.PLANET_RADIUS)
	assert_int(w.economy().salvage.try_attach(h, wr)).is_equal(Salvage.Hook.OK)
	assert_int(_p(w).weight(cell)).is_equal(baked[cell])
	assert_int(_p(w).baked_weight(cell)).is_equal(baked[cell])


func test_baked_weight_of_the_flat_datum_is_one() -> void:
	var w: SimWorld = K.world()
	assert_int(_p(w).baked_weight(PathGrid.cell_of(K.at(0.0, 100.0)))).is_equal(1)


static func _harvester_mask() -> int:
	for g: GroundUnitDef in WorldTestKit.content().ground_units:
		if g.id == &"harvester":
			return Pathing.mask_for(g.max_slope_deg)
	return 0


# A Harvester request from cell `a` to cell `b`, stepped until it settles; the route's cells.
func _route(w: SimWorld, a: int, b: int) -> PackedInt32Array:
	var p: Pathing = _p(w)
	var t: int = p.request(Sphere.cell_center_dir(a, N), Sphere.cell_center_dir(b, N), _harvester_mask())
	assert_int(t).is_not_equal(Pathing.NO_TICKET)
	for _i: int in 400:
		w.step()
		if p.status(t) != Pathing.ST_PENDING:
			break
	assert_int(p.status(t)).is_equal(Pathing.ST_DONE)
	var cells: PackedInt32Array = p.result_cells(t)
	p.release(t)
	return cells


func test_a_harvester_route_goes_round_a_resting_wreck_and_through_the_cell_once_it_is_towed_away() -> void:
	var w: SimWorld = K.world()
	var row: int = 130
	var a: int = row * N + 60
	var b: int = row * N + 200
	var mid: int = row * N + 130
	var before: PackedInt32Array = _route(w, a, b)
	assert_bool(before.has(mid)).override_failure_message("the open route should cross the middle cell").is_true()
	_doom(w, Sphere.cell_center_dir(mid, N))
	w.step()
	assert_int(w.store().wrecks.size()).is_equal(1)
	var wr: int = w.store().wrecks[0]
	assert_int(_cell_of_slot(w, wr)).is_equal(mid)
	var around: PackedInt32Array = _route(w, a, b)
	assert_bool(around.has(mid)).is_false()
	assert_int(around[0]).is_equal(a)
	assert_int(around[around.size() - 1]).is_equal(b)
	var h: int = K.put(w, &"hauler", 0, 0, 20.0, 0.0)
	w.store().pos[h] = w.store().pos[wr] * (1.0 + 20.0 / Sphere.PLANET_RADIUS)
	assert_int(w.economy().salvage.try_attach(h, wr)).is_equal(Salvage.Hook.OK)
	var after: PackedInt32Array = _route(w, a, b)
	assert_bool(after.has(mid)).is_true()


func test_a_wreck_save_restore_continue_is_byte_exact_and_restores_the_weight_on_expiry() -> void:
	var w: SimWorld = K.world()
	var _ev: Array[SimEvent] = K.kill(w, K.put(w, &"shipyard", 0, 0, 0.0, 1500.0))
	var cells: PackedInt32Array = PackedInt32Array()
	for s: int in w.store().wrecks:
		assert_int(_p(w).weight(_cell_of_slot(w, s))).is_equal(PathGrid.W_BLOCKED)
		var _a: bool = cells.push_back(_cell_of_slot(w, s))
	var _s: Array[SimEvent] = K.steps(w, 50)
	var r: SimWorld = SimWorld.deserialize(w.serialize(), WorldTestKit.content(), null)
	assert_object(r).is_not_null()
	assert_array(r.serialize()).is_equal(w.serialize())
	for c: int in cells:
		assert_int(_p(r).weight(c)).is_equal(PathGrid.W_BLOCKED)
	for i: int in 2700:
		w.step()
		r.step()
		var _e1: Array[SimEvent] = w.drain_events()
		var _e2: Array[SimEvent] = r.drain_events()
		if i % 450 == 0:
			assert_array(r.serialize()).is_equal(w.serialize())
	assert_int(r.store().wrecks.size()).is_equal(0)
	for c: int in cells:
		assert_int(_p(r).weight(c)).is_equal(1)
		assert_int(_p(w).weight(c)).is_equal(1)
	assert_array(r.serialize()).is_equal(w.serialize())
	assert_int(SimSerialize.FORMAT).is_equal(12)                                  # no saved state of its own (GD-39)


func test_the_cost_is_per_wreck_event_only() -> void:
	var w: SimWorld = K.world()
	var _ev: Array[SimEvent] = K.kill(w, K.put(w, &"core", 0, 0, 0.0, 1500.0))
	assert_int(w.store().wrecks.size()).is_equal(7)
	var paths: WreckPaths = _paths(w)
	assert_int(paths.sets).is_less_equal(7)                                       # at most one set_weight per pod
	assert_int(paths.scans).is_equal(0)                                           # spawning scans nothing
	var sets: int = paths.sets
	var reads: int = paths.reads
	var _idle: Array[SimEvent] = K.steps(w, 300)
	assert_int(paths.sets).is_equal(sets)                                         # no per-tick work
	assert_int(paths.scans).is_equal(0)
	assert_int(paths.reads).is_equal(reads)
