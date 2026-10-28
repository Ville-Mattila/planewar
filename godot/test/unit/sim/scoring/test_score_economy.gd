extends GdUnitTestSuite
## GD-27 score events, part 3 (02 s17.1): salvage_delivered, ice_delivered_possessed, relay_capture / relay_hold_min,
## commander_ore_spent (high-water, so cancel-and-repay cannot farm), match_win, and the Pilot / Commander split. Each
## test reads the points through `SimView.player_score` (pilot, commander).

var _w: SimWorld
var _d: ScoringDef
var _k: ScoreKeeper


func before_test() -> void:
	_w = ScoringTestKit.world()
	_d = ScoringTestKit.def()
	_k = ScoringTestKit.keeper(_w)


func _salvage(hauler: int, ore: int) -> void:
	var e: SimEvent = _w._events.emit(SimEvent.Kind.SALVAGE_DELIVERED, hauler, 0, Vector3.ZERO, float(ore), 0)
	e.extra = PackedByteArray()
	_k.scan()


func test_salvage_delivered_is_a_quarter_point_per_ore_commander_side_when_unpossessed() -> void:
	var hauler: int = ScoringTestKit.spawn(_w, &"hauler", 0, 0)
	_salvage(hauler, 100)
	assert_object(ScoringTestKit.score(_w, 0)).is_equal(Vector2i(0, floori(100.0 * _d.salvage_points_per_ore)))


func test_salvage_delivered_by_a_possessed_hauler_scores_to_the_pilot() -> void:
	var hauler: int = ScoringTestKit.spawn(_w, &"hauler", 0, 0)
	assert_bool(DockingTestKit.possess(_w, hauler, 0)).is_true()
	_salvage(hauler, 100)
	assert_object(ScoringTestKit.score(_w, 0)).is_equal(Vector2i(floori(100.0 * _d.salvage_points_per_ore), 0))


func test_ice_delivered_possessed_is_a_tenth_point_per_ice_and_only_when_possessed() -> void:
	_k.ice_delivered(0, 100, true)
	assert_object(ScoringTestKit.score(_w, 0)).is_equal(Vector2i(floori(100.0 * _d.ice_possessed_points_per_ice), 0))
	_k.ice_delivered(0, 100, false)
	assert_object(ScoringTestKit.score(_w, 0)).is_equal(Vector2i(floori(100.0 * _d.ice_possessed_points_per_ice), 0))
	assert_int(_k.ledger.ice_delivered[0]).is_equal(200)                        # the contribution counts either way


func test_ore_mined_feeds_the_result_counter_only() -> void:
	_k.ore_mined(0, 70)
	assert_int(_k.ledger.ore_mined[0]).is_equal(70)
	assert_object(ScoringTestKit.score(_w, 0)).is_equal(Vector2i.ZERO)


func test_relay_capture() -> void:
	_k.relay_captured(0, true)
	assert_object(ScoringTestKit.score(_w, 0)).is_equal(Vector2i(int(_d.relay["capture"]), 0))
	_k.relay_captured(0, false)
	assert_object(ScoringTestKit.score(_w, 0)).is_equal(Vector2i(int(_d.relay["capture"]), int(_d.relay["capture"])))


func test_relay_hold_min_pays_per_minute_held() -> void:
	_k.relay_held(0, 2.5)
	assert_object(ScoringTestKit.score(_w, 0)).is_equal(Vector2i(0, floori(2.5 * Def.num(_d.relay["hold_per_min"]))))


func test_commander_ore_spent_pays_on_the_high_water_mark() -> void:
	var spent: PackedInt32Array = _w.economy().build.spent_ore
	spent[0] = 250
	_w.step()
	var per_ore: float = _d.commander_points_per_ore_spent
	assert_object(ScoringTestKit.score(_w, 0)).is_equal(Vector2i(0, floori(250.0 * per_ore)))
	assert_int(_k.ledger.ore_spent[0]).is_equal(250)
	spent[0] = 100                                                              # a refund lowers the counter, not the score
	_w.step()
	assert_int(_k.ledger.ore_spent[0]).is_equal(100)
	assert_object(ScoringTestKit.score(_w, 0)).is_equal(Vector2i(0, floori(250.0 * per_ore)))
	spent[0] = 300                                                              # paying back up to 250 earns nothing new
	_w.step()
	assert_object(ScoringTestKit.score(_w, 0)).is_equal(Vector2i(0, floori(300.0 * per_ore)))


func test_match_win_pays_each_member_of_the_winning_team_once() -> void:
	_k.finalize(1)
	_k.finalize(1)
	assert_object(ScoringTestKit.score(_w, 1)).is_equal(Vector2i(0, _d.match_win))
	assert_object(ScoringTestKit.score(_w, 0)).is_equal(Vector2i.ZERO)
	assert_object(ScoringTestKit.score(_w, 2)).is_equal(Vector2i.ZERO)


func test_no_winner_no_match_win() -> void:
	_k.finalize(-1)
	assert_object(ScoringTestKit.score(_w, 1)).is_equal(Vector2i.ZERO)


func test_pilot_and_commander_sides_are_separate_and_unknown_slots_read_zero() -> void:
	_k.ice_delivered(0, 100, true)
	_k.relay_held(0, 1.0)
	var s: Vector2i = ScoringTestKit.score(_w, 0)
	assert_bool(s.x > 0 and s.y > 0).is_true()
	assert_object(ScoringTestKit.score(_w, 7)).is_equal(Vector2i.ZERO)
	assert_object(ScoringTestKit.score(_w, -1)).is_equal(Vector2i.ZERO)
	assert_object(_k.score_of(0)).is_equal(s)


func test_a_world_without_scoring_defs_scores_nothing_and_does_not_crash() -> void:
	var k: ScoreKeeper = ScoreKeeper.new(_w.store(), _w._players, WorldDefs.new(ContentSet.new()), _w._events, ScoringTestKit.hz())
	k.ice_delivered(0, 100, true)
	k.scan()
	assert_object(k.score_of(0)).is_equal(Vector2i.ZERO)
