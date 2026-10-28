extends GdUnitTestSuite
## GD-27 score events, part 1 (02 s17.1): one test per kill / structure / assist event of `defs/scoring.json`, each read
## through `SimView.player_score` (pilot, commander). The killer is player 0's Dart (team 0); the victim belongs to
## player 1 (team 1). A possessed killer scores to the Pilot side in full, an unpossessed one to the Commander side at
## `commander_auto_kill_share`.

var _w: SimWorld
var _d: ScoringDef


func before_test() -> void:
	_w = ScoringTestKit.world()
	_d = ScoringTestKit.def()


func _kill_by_pilot(victim_def: StringName) -> Vector2i:
	var killer: int = ScoringTestKit.spawn(_w, &"dart", 0, 0)
	assert_bool(DockingTestKit.possess(_w, killer, 0)).is_true()
	var victim: int = ScoringTestKit.spawn(_w, victim_def, 1, 1)
	ScoringTestKit.kill(_w, victim, killer)
	return ScoringTestKit.score(_w, 0)


func _points(unit: String) -> int:
	return int(_d.kill_points[unit])


func test_kill_scout() -> void:
	assert_object(_kill_by_pilot(&"scout")).is_equal(Vector2i(_points("scout"), 0))


func test_kill_dart() -> void:
	assert_object(_kill_by_pilot(&"dart")).is_equal(Vector2i(_points("dart"), 0))


func test_kill_hauler() -> void:
	assert_object(_kill_by_pilot(&"hauler")).is_equal(Vector2i(_points("hauler"), 0))


func test_kill_lancer() -> void:
	assert_object(_kill_by_pilot(&"lancer")).is_equal(Vector2i(_points("lancer"), 0))


func test_kill_bomber() -> void:
	assert_object(_kill_by_pilot(&"bomber")).is_equal(Vector2i(_points("bomber"), 0))


func test_kill_harvester() -> void:
	assert_object(_kill_by_pilot(&"harvester")).is_equal(Vector2i(_points("harvester"), 0))


func test_kill_siege_crawler() -> void:
	assert_object(_kill_by_pilot(&"siege_crawler")).is_equal(Vector2i(_points("siege_crawler"), 0))


func test_kill_hauler_loaded_bonus_for_cargo_and_for_a_tow() -> void:
	var killer: int = ScoringTestKit.spawn(_w, &"dart", 0, 0)
	assert_bool(DockingTestKit.possess(_w, killer, 0)).is_true()
	var cargo: int = ScoringTestKit.spawn(_w, &"hauler", 1, 1)
	_w.store().cargo[EntityId.slot(cargo)] = 10.0
	ScoringTestKit.kill(_w, cargo, killer)
	var want: int = _points("hauler") + _d.kill_hauler_loaded_bonus
	assert_object(ScoringTestKit.score(_w, 0)).is_equal(Vector2i(want, 0))
	var tow: int = ScoringTestKit.spawn(_w, &"hauler", 1, 1)
	_w.store().flags[EntityId.slot(tow)] |= EntityStore.F_TETHERED
	ScoringTestKit.kill(_w, tow, killer)
	assert_object(ScoringTestKit.score(_w, 0)).is_equal(Vector2i(2 * want, 0))


func test_structure_destroyed_is_a_fifth_of_the_cost() -> void:
	var killer: int = ScoringTestKit.spawn(_w, &"dart", 0, 0)
	assert_bool(DockingTestKit.possess(_w, killer, 0)).is_true()
	var sd: StructureDef = WorldTestKit.content().structures[WorldTestKit.def_id(&"reactor") - DefRanges.STRUCTURE_BASE]
	var reactor: int = ScoringTestKit.spawn(_w, &"reactor", 1, 1)
	var dealt: float = ScoringTestKit.hp(_w, reactor) + 1.0                   # the killing hit is paid as structure_damage too
	ScoringTestKit.kill(_w, reactor, killer)
	var want: int = floori(float(sd.cost_ore + sd.cost_ice) * _d.structure_destroyed_ratio + dealt * _d.structure_damage_points_per_hp)
	assert_object(ScoringTestKit.score(_w, 0)).is_equal(Vector2i(want, 0))


func test_core_destroyed_is_flat() -> void:
	var killer: int = ScoringTestKit.spawn(_w, &"dart", 0, 0)
	assert_bool(DockingTestKit.possess(_w, killer, 0)).is_true()
	var core: int = ScoringTestKit.spawn(_w, &"core", 1, 1)
	var dealt: float = ScoringTestKit.hp(_w, core) + 1.0
	ScoringTestKit.kill(_w, core, killer)
	assert_object(ScoringTestKit.score(_w, 0)).is_equal(Vector2i(floori(float(_d.core_destroyed) + dealt * _d.structure_damage_points_per_hp), 0))


func test_structure_damage_is_one_point_per_ten_hp_and_the_fraction_carries() -> void:
	var killer: int = ScoringTestKit.spawn(_w, &"dart", 0, 0)
	assert_bool(DockingTestKit.possess(_w, killer, 0)).is_true()
	var pad: int = ScoringTestKit.spawn(_w, &"pad", 1, 1)
	var each: float = 0.3 / _d.structure_damage_points_per_hp                  # 3 hp: 0.3 points, none whole
	for _i: int in 7:
		ScoringTestKit.hit(_w, pad, killer, each)
	_w.step()
	assert_object(ScoringTestKit.score(_w, 0)).is_equal(Vector2i(2, 0))        # 2.1 points: two whole


func test_commander_auto_kill_scores_half_to_the_commander_side() -> void:
	var killer: int = ScoringTestKit.spawn(_w, &"dart", 0, 0)            # never possessed: AUTO
	var victim: int = ScoringTestKit.spawn(_w, &"lancer", 1, 1)
	ScoringTestKit.kill(_w, victim, killer)
	var want: int = floori(float(_points("lancer")) * _d.commander_auto_kill_share)
	assert_object(ScoringTestKit.score(_w, 0)).is_equal(Vector2i(0, want))


func test_friendly_and_unattributed_deaths_score_nothing() -> void:
	var killer: int = ScoringTestKit.spawn(_w, &"dart", 0, 0)
	assert_bool(DockingTestKit.possess(_w, killer, 0)).is_true()
	var mate: int = ScoringTestKit.spawn(_w, &"dart", 2, 0)
	ScoringTestKit.kill(_w, mate, killer)                                  # team kill
	var lone: int = ScoringTestKit.spawn(_w, &"dart", 1, 1)
	ScoringTestKit.kill(_w, lone, 0)                                       # no attacker
	assert_object(ScoringTestKit.score(_w, 0)).is_equal(Vector2i.ZERO)


func test_assist_pays_half_the_kill_value_at_a_quarter_of_the_damage_within_the_window() -> void:
	var killer: int = ScoringTestKit.spawn(_w, &"dart", 0, 0)
	var helper: int = ScoringTestKit.spawn(_w, &"dart", 2, 0)
	var victim: int = ScoringTestKit.spawn(_w, &"lancer", 1, 1)
	var total: float = ScoringTestKit.hp(_w, victim)
	assert_bool(DockingTestKit.possess(_w, helper, 2)).is_true()
	ScoringTestKit.hit(_w, victim, helper, total * (Def.num(_d.assist["min_share"]) + 0.01))
	ScoringTestKit.kill(_w, victim, killer)
	var want: int = floori(float(_points("lancer")) * Def.num(_d.assist["kill_share"]))
	assert_object(ScoringTestKit.score(_w, 2)).is_equal(Vector2i(want, 0))   # the helper was possessed: Pilot side


func test_no_assist_below_the_share_or_outside_the_window() -> void:
	var killer: int = ScoringTestKit.spawn(_w, &"dart", 0, 0)
	var helper: int = ScoringTestKit.spawn(_w, &"dart", 2, 0)
	var low: int = ScoringTestKit.spawn(_w, &"lancer", 1, 1)
	ScoringTestKit.hit(_w, low, helper, ScoringTestKit.hp(_w, low) * 0.1)           # 10 %: under min_share
	ScoringTestKit.kill(_w, low, killer)
	assert_object(ScoringTestKit.score(_w, 2)).is_equal(Vector2i.ZERO)
	var old: int = ScoringTestKit.spawn(_w, &"lancer", 1, 1)
	ScoringTestKit.hit(_w, old, helper, ScoringTestKit.hp(_w, old) * 0.5)
	for _t: int in roundi(Def.num(_d.assist["window_s"]) * float(ScoringTestKit.hz())) + 2:
		_w.step()
	ScoringTestKit.kill(_w, old, killer)                                   # the half-hull hit is older than window_s
	assert_object(ScoringTestKit.score(_w, 2)).is_equal(Vector2i.ZERO)
