extends GdUnitTestSuite
## TA-50 (R0 B.11 A-55) scenario: Pathing wired into SimWorld. load_map loads the baked weights, sets the terrain
## and prepares one region graph per ground-unit mask; step 3b advances it under rules.path_expansions_per_tick with
## the rules heuristic; a brain stub reaches it only through CommandSinkBase.pathing(); the view's
## path_grid_version follows set_weight.

const MAP: StringName = &"tiny_test"

var _world: SimWorld = null


static func _mask_of(id: StringName) -> int:
	for g: GroundUnitDef in WorldTestKit.content().ground_units:
		if g.id == id:
			return Pathing.mask_for(g.max_slope_deg)
	return 0


# A world with a fresh stub attached and stepped once, so the stub has seen sink.pathing().
func _world_with_stub(map_id: StringName, profile: bool) -> PathBrainStub:
	var w: SimWorld = WorldTestKit.world(13, WorldTestKit.rules(-1.0, -1.0, profile), map_id)
	var hook: PathBrainStub = PathBrainStub.new()
	w.set_ai_hook(hook)
	w.step()
	_world = w
	return hook


func test_brain_stub_paths_through_the_sink_at_step_3b() -> void:
	var hook: PathBrainStub = _world_with_stub(MAP, true)
	var w: SimWorld = _world
	var p: Pathing = hook.seen
	assert_object(p).is_not_null()
	hook.check = true
	hook.populate(p, Vector3(-0.3, 1.0, 0.2).normalized(), 10, 4, _mask_of(&"harvester"), _mask_of(&"siege_crawler"))
	var row_max: float = 0.0
	var units_max: int = 0
	for _t: int in 150:
		var e0: int = p.expansions_total
		w.step()
		units_max = maxi(units_max, p.expansions_total - e0)
		row_max = maxf(row_max, w.profile()[TickProfiler.ROW_PATHING])
		var _ev: Array[SimEvent] = w.drain_events()
	assert_array(hook.failures).is_empty()
	assert_int(hook.done_count()).is_greater(20)
	assert_int(p.ticks).is_equal(w.tick())                    # one advance() per step
	assert_int(units_max).is_greater(0)
	assert_int(units_max).is_less_equal(p.expansions_per_tick)  # P4: graphs prepared at load, no lazy overrun
	assert_float(row_max).is_greater(0.0)
	assert_int(p.cache_hits).is_greater(0)


func test_load_map_prepares_each_ground_unit_mask_and_reads_rules() -> void:
	var p: Pathing = _world_with_stub(MAP, false).seen
	var rules: RulesDef = WorldTestKit.content().rules
	assert_int(p.expansions_per_tick).is_equal(rules.path_expansions_per_tick)
	assert_int(p.grid.heuristic_pct).is_equal(rules.path_heuristic_pct)
	assert_int(p.clusters.builds).is_equal(2 * PathSearch.CLUSTERS)   # harvester 25 and siege_crawler 20
	assert_bool(p.grid.weights_custom).is_false()
	assert_int(p.weight(PathGrid.cell_of(Vector3(1, 0, 0)))).is_not_equal(0)


func test_flat_datum_builds_graphs_lazily() -> void:
	assert_int(_world_with_stub(&"", false).seen.clusters.builds).is_equal(0)


func test_set_weight_bumps_the_view_path_grid_version() -> void:
	var p: Pathing = _world_with_stub(MAP, false).seen
	var w: SimWorld = _world
	var cell: int = PathGrid.cell_of(Vector3(0, 0, 1))
	var face: int = cell >> (PathGrid.SHIFT + PathGrid.SHIFT)
	var v0: int = w.view().path_grid_version(face)
	p.set_weight(cell, PathGrid.W_BLOCKED)
	assert_int(w.view().path_grid_version(face)).is_equal(v0 + 1)
	assert_int(w.view().path_grid_version(-1)).is_equal(0)


func test_cut_rung_8_lowers_the_path_budget_at_step_3b() -> void:
	var hook: PathBrainStub = _world_with_stub(&"", false)
	var w: SimWorld = _world
	var rules: RulesDef = WorldTestKit.content().rules
	w.set_budget_profile(8)
	w.step()
	assert_int(hook.seen.expansions_per_tick).is_equal(rules.rung_8_path_expansions_per_tick)
	w.set_budget_profile(2)
	w.step()
	assert_int(hook.seen.expansions_per_tick).is_equal(rules.path_expansions_per_tick)


func test_the_base_sink_has_no_pathing() -> void:
	assert_object(CommandSinkBase.new().pathing()).is_null()
