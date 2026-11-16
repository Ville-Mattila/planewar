extends GdUnitTestSuite
## GD-47 (02 s6.4, R0 C3-08, R0 B.8 A-8): an offline LocalSimView reports PlayerStateView.early_spend_left_ore and the
## TeamStateView.SPEND_LOCK_ACTIVE flag exactly as `Build.lock_blocks` applies the early share lock: a team of two or
## more, before `early_share_lock_s`; left = early_share_ore + delivered - spent (floor 0); otherwise -1 / flag clear.

const K := preload("res://test/unit/sim/economy_test_kit.gd")


func _team_world(team_size: int) -> SimWorld:
	var w: SimWorld = SimWorld.new(WorldTestKit.content())
	var map: MapDef = MapDef.new()
	map.id = &""
	var res: Result = w.load_map(map, 7, WorldTestKit.rules())
	assert(res.ok, res.message)
	for p: int in team_size:
		w.add_player(p, 0, &"", PlayerTable.KIND_HUMAN)
	w.add_player(team_size, 1, &"", PlayerTable.KIND_HUMAN)
	assert(w.spawn_start_kit(0, Vector3.RIGHT, Vector3.UP))
	return w


func _lock_ticks() -> int:
	return int(WorldTestKit.content().economy.early_share_lock_s) * WorldTestKit.content().rules.tick_hz


func test_team_of_two_reports_full_allowance_and_flag_at_start() -> void:
	var w: SimWorld = _team_world(2)
	var econ: EconomyDef = WorldTestKit.content().economy
	assert_int(w.view().player_state(0).early_spend_left_ore).is_equal(econ.early_share_ore)
	assert_int(w.view().player_state(1).early_spend_left_ore).is_equal(econ.early_share_ore)
	assert_int(w.view().team_state(0).flags & TeamStateView.SPEND_LOCK_ACTIVE).is_equal(TeamStateView.SPEND_LOCK_ACTIVE)


func test_a_lone_player_is_never_locked() -> void:
	var w: SimWorld = _team_world(1)
	assert_int(w.view().player_state(0).early_spend_left_ore).is_equal(-1)
	assert_int(w.view().player_state(1).early_spend_left_ore).is_equal(-1)
	assert_int(w.view().team_state(0).flags & TeamStateView.SPEND_LOCK_ACTIVE).is_equal(0)
	assert_int(w.view().team_state(1).flags & TeamStateView.SPEND_LOCK_ACTIVE).is_equal(0)


func test_left_tracks_the_ledger_and_floors_at_zero() -> void:
	var w: SimWorld = _team_world(2)
	var b: Build = w.economy().build
	var econ: EconomyDef = WorldTestKit.content().economy
	b.spent_ore[0] = 300
	b.delivered_ore[0] = 50
	assert_int(w.view().player_state(0).early_spend_left_ore).is_equal(econ.early_share_ore + 50 - 300)
	assert_int(w.view().player_state(1).early_spend_left_ore).is_equal(econ.early_share_ore)   # a teammate's own allowance
	b.spent_ore[0] = econ.early_share_ore + 400
	assert_int(w.view().player_state(0).early_spend_left_ore).is_equal(0)


func test_left_agrees_with_lock_blocks_at_the_boundary() -> void:
	var w: SimWorld = _team_world(2)
	var b: Build = w.economy().build
	b.spent_ore[0] = 500
	var left: int = w.view().player_state(0).early_spend_left_ore
	assert_bool(b.lock_blocks(0, left)).is_false()
	assert_bool(b.lock_blocks(0, left + 1)).is_true()


func test_lock_ends_at_early_share_lock_s() -> void:
	var w: SimWorld = _team_world(2)
	var _ev: Array[SimEvent] = K.run(w, _lock_ticks() - 1)
	assert_int(w.view().player_state(0).early_spend_left_ore).is_greater_equal(0)
	assert_int(w.view().team_state(0).flags & TeamStateView.SPEND_LOCK_ACTIVE).is_equal(TeamStateView.SPEND_LOCK_ACTIVE)
	_ev = K.run(w, 2)
	assert_int(w.view().player_state(0).early_spend_left_ore).is_equal(-1)
	assert_int(w.view().team_state(0).flags & TeamStateView.SPEND_LOCK_ACTIVE).is_equal(0)


## UX-22 acceptance: the drawer's own tile function, fed only by the real LocalSimView (default lock_left reads
## PlayerStateView.early_spend_left_ore), shows SPEND_LOCKED where CommandValidator answers REJECTED_LOCKED, and clears.
func test_drawer_tile_shows_the_lock_from_the_real_view_and_clears() -> void:
	assert_bool(ContentDB.load_all().ok).is_true()
	var w: SimWorld = _team_world(2)
	w.economy().build.spent_ore[0] = WorldTestKit.content().economy.early_share_ore - 10     # 10 Ore of allowance left
	var yard: int = w.store().id_of(K.find(w, &"shipyard"))
	var dart: int = K.def(&"dart")
	var ctx: DrawerContext = DrawerContextKit.from_view(w.view(), 0)
	assert_int(ctx.lock_left_ore).is_equal(10)
	assert_int(DrawerModel.tile(w.view(), ctx, &"dart").state).is_equal(DrawerMath.State.SPEND_LOCKED)
	assert_int(K.code(w, Command.produce(0, yard, dart, 1))).is_equal(CommandResult.Code.REJECTED_LOCKED)
	var _ev: Array[SimEvent] = K.run(w, _lock_ticks() + 1)
	ctx = DrawerContextKit.from_view(w.view(), 0)
	assert_int(ctx.lock_left_ore).is_equal(-1)
	assert_int(DrawerModel.tile(w.view(), ctx, &"dart").state).is_not_equal(DrawerMath.State.SPEND_LOCKED)
	assert_int(K.code(w, Command.produce(0, yard, dart, 1))).is_equal(CommandResult.Code.ACCEPTED)
