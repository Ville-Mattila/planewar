extends GdUnitTestSuite
## GD-27 round 2 (review of #140): a shot that outlives its shooter still scores for the shooter's owner. A bomb from a
## Bomber shot down mid-fall, a rocket whose Dart has died and a shell from a destroyed tower name a shooter that is gone
## when the HIT or the death resolves; the keeper credits the owner, team and Pilot/Commander side the shooter had when it
## died (`ScoreShooters`), and a stale EntityId (wrong generation) credits nobody. Also: one sortie per ship flight.

var _w: SimWorld
var _d: ScoringDef


func before_test() -> void:
	_w = ScoringTestKit.world()
	_d = ScoringTestKit.def()


func _dead_shooter(def_id: StringName, possessed: bool) -> int:
	var shooter: int = ScoringTestKit.spawn(_w, def_id, 0, 0)
	if possessed:
		assert_bool(DockingTestKit.possess(_w, shooter, 0)).is_true()
	var enemy: int = ScoringTestKit.spawn(_w, &"dart", 1, 1)
	ScoringTestKit.kill(_w, shooter, enemy)
	assert_bool(_w.store().alive(shooter)).is_false()
	return shooter


func test_a_kill_by_a_shot_whose_possessed_shooter_died_pays_the_pilot() -> void:
	var shooter: int = _dead_shooter(&"bomber", true)
	var victim: int = ScoringTestKit.spawn(_w, &"lancer", 1, 1)
	ScoringTestKit.kill(_w, victim, shooter)
	assert_object(ScoringTestKit.score(_w, 0)).is_equal(Vector2i(int(_d.kill_points["lancer"]), 0))
	assert_int(ScoringTestKit.keeper(_w).ledger.kills[0]).is_equal(1)


func test_a_structure_kill_by_a_shot_whose_unpossessed_shooter_died_pays_the_commander_share() -> void:
	var shooter: int = _dead_shooter(&"dart", false)
	var core: int = ScoringTestKit.spawn(_w, &"core", 1, 1)
	var dealt: float = ScoringTestKit.hp(_w, core) + 1.0
	ScoringTestKit.kill(_w, core, shooter)
	var cmd: float = (float(_d.core_destroyed)) * _d.commander_auto_kill_share + dealt * _d.structure_damage_points_per_hp
	assert_object(ScoringTestKit.score(_w, 0)).is_equal(Vector2i(0, floori(cmd)))
	assert_int(ScoringTestKit.keeper(_w).ledger.structures_destroyed[0]).is_equal(1)


func test_a_shell_from_a_destroyed_tower_pays_structure_damage_and_the_kill() -> void:
	var shooter: int = _dead_shooter(&"pad", false)                      # any structure stands in for the tower
	var victim: int = ScoringTestKit.spawn(_w, &"scout", 1, 1)
	ScoringTestKit.kill(_w, victim, shooter)
	var want: int = floori(float(_d.kill_points["scout"]) * _d.commander_auto_kill_share)
	assert_object(ScoringTestKit.score(_w, 0)).is_equal(Vector2i(0, want))
	var pad: int = ScoringTestKit.spawn(_w, &"pad", 1, 1)
	var each: float = 1.0 / _d.structure_damage_points_per_hp
	ScoringTestKit.hit(_w, pad, shooter, each)                             # 10 hp from the dead tower: one point
	_w.step()
	assert_object(ScoringTestKit.score(_w, 0)).is_equal(Vector2i(0, want + 1))


func test_an_assist_by_a_dead_shooter_is_paid() -> void:
	var helper: int = _dead_shooter(&"dart", true)
	var killer: int = ScoringTestKit.spawn(_w, &"dart", 2, 0)
	var victim: int = ScoringTestKit.spawn(_w, &"lancer", 1, 1)
	ScoringTestKit.hit(_w, victim, helper, ScoringTestKit.hp(_w, victim) * 0.5)
	ScoringTestKit.kill(_w, victim, killer)
	var want: int = floori(float(_d.kill_points["lancer"]) * Def.num(_d.assist["kill_share"]))
	assert_object(ScoringTestKit.score(_w, 0)).is_equal(Vector2i(want, 0))


func test_a_stale_generation_credits_nobody() -> void:
	var live: int = ScoringTestKit.spawn(_w, &"dart", 0, 0)
	var stale: int = EntityId.make(EntityId.slot(live), EntityId.gen(live) + 1)
	var victim: int = ScoringTestKit.spawn(_w, &"lancer", 1, 1)
	ScoringTestKit.kill(_w, victim, stale)
	assert_object(ScoringTestKit.score(_w, 0)).is_equal(Vector2i.ZERO)
	assert_int(ScoringTestKit.keeper(_w).ledger.kills[0]).is_equal(0)


func test_the_shooter_record_survives_serialize() -> void:
	var shooter: int = _dead_shooter(&"bomber", true)
	var w2: SimWorld = SimWorld.deserialize(_w.serialize(), WorldTestKit.content(), null)
	assert_object(w2).is_not_null()
	var victim: int = ScoringTestKit.spawn(w2, &"lancer", 1, 1)
	ScoringTestKit.kill(w2, victim, shooter)
	assert_object(ScoringTestKit.score(w2, 0)).is_equal(Vector2i(int(_d.kill_points["lancer"]), 0))


# --- sorties: one per ship flight -----------------------------------------------------------------------------------------

func _sorties() -> int:
	return ScoringTestKit.keeper(_w).ledger.sorties[0]


func _release() -> void:
	var _r: CommandResult = _w.apply_command(Command.release(0))
	_w.step()
	var _e: Array[SimEvent] = _w.drain_events()


func test_re_possessing_the_same_flight_is_one_sortie() -> void:
	var dart: int = ScoringTestKit.spawn(_w, &"dart", 0, 0)
	assert_bool(DockingTestKit.possess(_w, dart, 0)).is_true()
	_release()
	assert_bool(DockingTestKit.possess(_w, dart, 0)).is_true()
	assert_int(_sorties()).is_equal(1)


func test_a_landing_ends_the_flight_and_the_next_possession_is_a_new_sortie() -> void:
	var dart: int = ScoringTestKit.spawn(_w, &"dart", 0, 0)
	assert_bool(DockingTestKit.possess(_w, dart, 0)).is_true()
	var _e: SimEvent = _w._events.emit(SimEvent.Kind.DOCKED, dart, 0, Vector3.ZERO, 0.0, 0)
	ScoringTestKit.keeper(_w).scan()
	_release()
	assert_bool(DockingTestKit.possess(_w, dart, 0)).is_true()
	assert_int(_sorties()).is_equal(2)


func test_possessing_a_docked_ship_counts_when_it_launches() -> void:
	var dart: int = ScoringTestKit.spawn(_w, &"dart", 0, 0)
	_w.store().flags[EntityId.slot(dart)] |= EntityStore.F_DOCKED
	assert_bool(DockingTestKit.possess(_w, dart, 0)).is_true()
	assert_int(_sorties()).is_equal(0)
	_w.store().flags[EntityId.slot(dart)] &= ~EntityStore.F_DOCKED
	var _e: SimEvent = _w._events.emit(SimEvent.Kind.LAUNCHED, dart, 0, Vector3.ZERO, 0.0, 0)
	ScoringTestKit.keeper(_w).scan()
	assert_int(_sorties()).is_equal(1)
	var _e2: SimEvent = _w._events.emit(SimEvent.Kind.LAUNCHED, dart, 0, Vector3.ZERO, 0.0, 0)
	ScoringTestKit.keeper(_w).scan()
	assert_int(_sorties()).is_equal(1)
