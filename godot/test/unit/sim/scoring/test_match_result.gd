extends GdUnitTestSuite
## GD-27 / 02 s17.1 "Match result fields" (04 s2.3 `MATCH_END`, binds in NET-22): `SimWorld.match_result()` carries per
## player score_pilot, score_commander, medals[], structures_destroyed, sorties, ore_mined, ore_spent, ice_delivered and
## pilot_time_s[5] (dart, lancer, bomber, scout, hauler) and per team structure_value, plus the 04 row's kills, deaths,
## structures_built and manual_landings. The ledger survives `serialize` / `deserialize` (S4, format 14).

const FIELDS: PackedStringArray = ["score_pilot", "score_commander", "medals", "structures_destroyed", "sorties", "ore_mined",
	"ore_spent", "ice_delivered", "pilot_time_s", "kills", "deaths", "structures_built", "manual_landings"]

var _w: SimWorld
var _k: ScoreKeeper


func before_test() -> void:
	_w = ScoringTestKit.world()
	_k = ScoringTestKit.keeper(_w)


func _row(r: MatchResult, slot: int) -> PlayerResult:
	for p: PlayerResult in r.players:
		if p.slot == slot:
			return p
	return null


func test_every_17_1_field_exists_on_the_result_row() -> void:
	var names: PackedStringArray = PackedStringArray()
	for prop: Dictionary in PlayerResult.new().get_property_list():
		var _a: bool = names.push_back(String(prop["name"]))
	for f: String in FIELDS:
		assert_bool(names.has(f)).override_failure_message("PlayerResult lacks %s" % f).is_true()
	var head: PackedStringArray = PackedStringArray()
	for prop: Dictionary in MatchResult.new().get_property_list():
		var _b: bool = head.push_back(String(prop["name"]))
	for f: String in ["winner_team", "tick", "structure_value", "players"]:
		assert_bool(head.has(f)).is_true()


func test_rows_are_the_active_players_in_slot_order_with_their_team() -> void:
	var r: MatchResult = _w.match_result()
	assert_int(r.players.size()).is_equal(3)
	assert_int(r.players[0].slot).is_equal(0)
	assert_int(r.players[1].slot).is_equal(1)
	assert_int(r.players[2].team).is_equal(0)
	assert_int(r.structure_value.size()).is_equal(PlayerTable.TEAMS)
	assert_int(r.winner_team).is_equal(-1)
	assert_int(r.tick).is_equal(_w.tick())
	assert_int(r.players[0].medals.size()).is_equal(0)                       # medals.json lands with GD-28
	assert_int(r.players[0].pilot_time_s.size()).is_equal(5)


func test_the_counters_follow_the_events_that_feed_them() -> void:
	var dart: int = ScoringTestKit.spawn(_w, &"dart", 0, 0)
	assert_bool(WorldTestKit.possess(_w, dart, 0)).is_true()                  # one sortie
	var victim: int = ScoringTestKit.spawn(_w, &"scout", 1, 1)
	ScoringTestKit.kill(_w, victim, dart)                                     # a kill, a death
	var pad: int = ScoringTestKit.spawn(_w, &"pad", 1, 1)
	ScoringTestKit.kill(_w, pad, dart)                                        # a structure destroyed
	var built: int = ScoringTestKit.spawn(_w, &"pad", 0, 0)
	var _e: SimEvent = _w._events.emit(SimEvent.Kind.BUILD_DONE, built, 0, Vector3.ZERO, 0.0, 0)
	_k.scan()                                                                 # a structure built
	ScoringTestKit.landing(_w, dart, LandingGrade.Grade.CLEAN, ScoringTestKit.MANUAL)
	_k.ore_mined(0, 40)
	_k.ice_delivered(0, 30, true)
	var r: MatchResult = _w.match_result()
	var a: PlayerResult = _row(r, 0)
	var b: PlayerResult = _row(r, 1)
	assert_int(a.sorties).is_equal(1)
	assert_int(a.kills).is_equal(1)
	assert_int(b.deaths).is_equal(1)
	assert_int(a.structures_destroyed).is_equal(1)
	assert_int(a.structures_built).is_equal(1)
	assert_int(a.manual_landings).is_equal(1)
	assert_int(a.ore_mined).is_equal(40)
	assert_int(a.ice_delivered).is_equal(30)
	assert_int(a.score_pilot).is_equal(ScoringTestKit.score(_w, 0).x)
	assert_int(a.score_commander).is_equal(ScoringTestKit.score(_w, 0).y)


func test_pilot_time_counts_per_ship_class_in_the_04_order() -> void:
	var lancer: int = ScoringTestKit.spawn(_w, &"lancer", 0, 0)
	assert_bool(WorldTestKit.possess(_w, lancer, 0)).is_true()
	for _t: int in 3 * ScoringTestKit.hz():
		WorldTestKit.step_piloted(_w, 0)
	var t: PackedInt32Array = _row(_w.match_result(), 0).pilot_time_s
	assert_int(t[1]).is_greater_equal(3)                                      # dart 0, lancer 1, bomber 2, scout 3, hauler 4
	assert_int(t[0] + t[2] + t[3] + t[4]).is_equal(0)


func test_structure_value_is_the_cost_of_the_finished_structures_of_the_team() -> void:
	var c: ContentSet = WorldTestKit.content()
	var reactor: StructureDef = c.structures[WorldTestKit.def_id(&"reactor") - DefRanges.STRUCTURE_BASE]
	var pad: StructureDef = c.structures[WorldTestKit.def_id(&"pad") - DefRanges.STRUCTURE_BASE]
	var _r: int = ScoringTestKit.spawn(_w, &"reactor", 0, 0)
	var _p: int = ScoringTestKit.spawn(_w, &"pad", 0, 0)
	var _q: int = ScoringTestKit.spawn(_w, &"pad", 1, 1)
	var r: MatchResult = _w.match_result()
	assert_int(r.structure_value[0]).is_equal(reactor.cost_ore + reactor.cost_ice + pad.cost_ore + pad.cost_ice)
	assert_int(r.structure_value[1]).is_equal(pad.cost_ore + pad.cost_ice)
	assert_int(r.structure_value[2]).is_equal(0)


func test_match_end_tick_finalizes_the_win_and_the_result_reports_it() -> void:
	var w: SimWorld = WorldTestKit.world(7, WorldTestKit.rules(-1.0, 2.0))
	var _e: Array[SimEvent] = w.drain_events()
	w._state.winner_team = 1                                                  # Economy decides the winner (GD-20)
	for _t: int in 2 * ScoringTestKit.hz() + 2:
		w.step()
	assert_bool(w._state.ended()).is_true()
	var r: MatchResult = w.match_result()
	assert_int(r.winner_team).is_equal(1)
	assert_int(r.tick).is_equal(w._state.ended_tick)
	assert_int(_row(r, 1).score_commander).is_equal(ScoringTestKit.def().match_win)
	assert_int(_row(r, 0).score_commander).is_equal(0)


func test_the_ledger_round_trips_through_serialize() -> void:
	var dart: int = ScoringTestKit.spawn(_w, &"dart", 0, 0)
	assert_bool(WorldTestKit.possess(_w, dart, 0)).is_true()
	var helper: int = ScoringTestKit.spawn(_w, &"dart", 2, 0)
	var victim: int = ScoringTestKit.spawn(_w, &"lancer", 1, 1)
	ScoringTestKit.hit(_w, victim, helper, ScoringTestKit.hp(_w, victim) * 0.5)   # an assist waiting in the hit log
	_w.step()
	_k.ice_delivered(0, 55, true)
	_k.relay_held(2, 0.35)                                                    # a fraction waiting to carry
	var bytes: PackedByteArray = _w.serialize()
	var w2: SimWorld = SimWorld.deserialize(bytes, WorldTestKit.content(), null)
	assert_object(w2).is_not_null()
	assert_object(w2.view().player_score(0)).is_equal(_w.view().player_score(0))
	assert_int(w2.economy().score.ledger.ice_delivered[0]).is_equal(55)
	ScoringTestKit.kill(_w, victim, dart)
	ScoringTestKit.kill(w2, victim, dart)
	for s: int in [0, 1, 2]:
		assert_object(w2.view().player_score(s)).is_equal(_w.view().player_score(s))
	assert_int(w2.view().player_score(2).x + w2.view().player_score(2).y).is_greater(0)   # the assist survived the save
