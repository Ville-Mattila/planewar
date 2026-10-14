extends GdUnitTestSuite
## Step 9 damage through SimWorld (02 s4.3, GD-08): one test per rule. Entities are pinned exactly, projectiles are
## written into the pool with their weapon, and one `step()` runs Collision then Combat. Scenario C-09 (bomb 14 m from
## a docked Dart: Pad destroys it, Hangar spares it) is `test_c09_*`. Team 0 is the target side, team 1 the shooter.

const R: float = Sphere.PLANET_RADIUS
const CELL_M: float = Sphere.PLANET_RADIUS * PI * 0.5 / float(Sphere.GRID_BUILD)


func _at(alt: float, east: float = 0.0, north: float = 0.0) -> Vector3:
	return Vector3(R + alt, east, north)


## East offset that puts a ship of `radius` flying at `alt` exactly `gap` metres (sphere edge) from a ground-level bomb.
func _east_for_gap(alt: float, radius: float, gap: float) -> float:
	return sqrt((gap + radius) * (gap + radius) - (alt - 0.5) * (alt - 0.5))


func _step(w: SimWorld) -> Array[SimEvent]:
	w.step()
	return w.drain_events()


## Bomb at ground level `east` metres from `centre` (the ground contact detonates it).
func _bomb(w: SimWorld, east: float, owner: int = 1, team: int = 1) -> int:
	return CombatTestKit.shot(w, &"bomb", &"bomb", _at(0.5, east), owner, team)


# --- rule 1: gun hit ---------------------------------------------------------------------------------------------

func test_gun_hit_rolls_damage_and_frees_the_slug() -> void:
	var w: SimWorld = CombatTestKit.world()
	var tgt: int = CombatTestKit.spawn(w, &"lancer", 0, 0, _at(500.0))
	var shot: int = CombatTestKit.shot(w, &"slug_light", &"gun_dart", _at(500.0), 1, 1, 77)
	var hits: Array[SimEvent] = CombatTestKit.of_kind(_step(w), SimEvent.Kind.HIT)
	assert_int(hits.size()).is_equal(1)
	assert_int(hits[0].a).is_equal(tgt)
	assert_int(hits[0].b).is_equal(77)
	assert_float(hits[0].value).is_between(6.0, 14.0)
	assert_float(CombatTestKit.hp(w, tgt)).is_equal(220.0 - hits[0].value)
	assert_bool(w.projectiles().alive(shot)).is_false()
	assert_int(w.store().last_damage_tick[EntityId.slot(tgt)]).is_equal(w.tick())


func test_gun_hit_vs_structure_uses_structure_mult() -> void:
	var w: SimWorld = CombatTestKit.world()
	var tgt: int = CombatTestKit.spawn(w, &"refinery", 0, 0, _at(0.0))
	var _s: int = CombatTestKit.shot(w, &"slug_light", &"gun_dart", _at(5.0), 1, 1)
	var hits: Array[SimEvent] = CombatTestKit.of_kind(_step(w), SimEvent.Kind.HIT)
	assert_int(hits.size()).is_equal(1)
	assert_float(hits[0].value).is_between(1.0, 2.0)          # 6..14 x 0.15
	assert_float(CombatTestKit.hp(w, tgt)).is_equal(1000.0 - hits[0].value)


func test_gun_hit_vs_ground_unit_uses_ground_mult() -> void:
	var w: SimWorld = CombatTestKit.world()
	var tgt: int = CombatTestKit.spawn(w, &"harvester", 0, 0, _at(0.0))
	var _s: int = CombatTestKit.shot(w, &"slug_light", &"gun_dart", _at(0.0), 1, 1)
	var hits: Array[SimEvent] = CombatTestKit.of_kind(_step(w), SimEvent.Kind.HIT)
	assert_int(hits.size()).is_equal(1)
	assert_float(hits[0].value).is_between(6.0, 14.0)         # ground_mult 1.0
	assert_float(CombatTestKit.hp(w, tgt)).is_equal(150.0 - hits[0].value)


func test_rail_slug_does_250() -> void:
	var w: SimWorld = CombatTestKit.world()
	var tgt: int = CombatTestKit.spawn(w, &"bomber", 0, 0, _at(500.0))
	var _s: int = CombatTestKit.shot(w, &"rail_slug", &"rail_gun", _at(500.0), 1, 1)
	var _ev: Array[SimEvent] = _step(w)
	assert_float(CombatTestKit.hp(w, tgt)).is_equal(50.0)


func test_lethal_hit_kills_through_the_deferred_free() -> void:
	var w: SimWorld = CombatTestKit.world()
	var tgt: int = CombatTestKit.spawn(w, &"scout", 0, 0, _at(500.0))
	var _s: int = CombatTestKit.shot(w, &"rail_slug", &"rail_gun", _at(500.0), 1, 1, 9)
	var ev: Array[SimEvent] = _step(w)
	var deaths: Array[SimEvent] = CombatTestKit.of_kind(ev, SimEvent.Kind.DEATH)
	assert_int(deaths.size()).is_equal(1)
	assert_int(deaths[0].a).is_equal(tgt)
	assert_int(deaths[0].b).is_equal(9)                       # the killer
	assert_bool(CombatTestKit.alive(w, tgt)).is_false()


func test_doctrine_folded_damage_is_not_scaled_twice() -> void:
	var w: SimWorld = CombatTestKit.world()
	var tgt: int = CombatTestKit.spawn(w, &"lancer", 0, 0, _at(500.0))
	var before: float = CombatTestKit.hp(w, tgt)
	var _s: int = CombatTestKit.shot(w, &"slug_light", &"gun_dart", _at(500.0), 3, 1)      # slot 3 = Foundry
	var hits: Array[SimEvent] = CombatTestKit.of_kind(_step(w), SimEvent.Kind.HIT)
	assert_int(hits.size()).is_equal(1)
	assert_float(hits[0].value).is_between(5.0, 12.0)
	assert_float(CombatTestKit.hp(w, tgt)).is_equal(before - hits[0].value)


# --- rule 8: no friendly fire -----------------------------------------------------------------------------------

func test_no_friendly_fire_for_slugs() -> void:
	var w: SimWorld = CombatTestKit.world()
	var tgt: int = CombatTestKit.spawn(w, &"lancer", 0, 0, _at(500.0))
	var shot: int = CombatTestKit.shot(w, &"slug_light", &"gun_dart", _at(500.0), 0, 0)
	var ev: Array[SimEvent] = _step(w)
	assert_int(CombatTestKit.of_kind(ev, SimEvent.Kind.HIT).size()).is_equal(0)
	assert_float(CombatTestKit.hp(w, tgt)).is_equal(220.0)
	assert_bool(w.projectiles().alive(shot)).is_true()        # flew on


func test_no_friendly_fire_for_bombs_and_flak() -> void:
	var w: SimWorld = CombatTestKit.world()
	var ship: int = CombatTestKit.spawn(w, &"dart", 0, 0, _at(6.5))
	var _b: int = _bomb(w, 8.0, 0, 0)
	var _f: int = CombatTestKit.shot(w, &"flak_shell", &"flak_gun", _at(6.5), 0, 0)
	var _ev: Array[SimEvent] = _step(w)
	assert_bool(CombatTestKit.alive(w, ship)).is_true()
	assert_float(CombatTestKit.hp(w, ship)).is_equal(100.0)


func test_friendly_fire_rule_lets_a_team_hurt_itself() -> void:
	var rules: MatchRules = WorldTestKit.rules()
	rules.friendly_fire = true
	var w: SimWorld = CombatTestKit.world(7, rules)
	var tgt: int = CombatTestKit.spawn(w, &"lancer", 0, 0, _at(500.0))
	var _s: int = CombatTestKit.shot(w, &"slug_light", &"gun_dart", _at(500.0), 0, 0)
	var _ev: Array[SimEvent] = _step(w)
	assert_float(CombatTestKit.hp(w, tgt)).is_less(220.0)


# --- rules 2-3: bomb ---------------------------------------------------------------------------------------------

func test_bomb_destroys_a_ship_within_15m_of_its_bounding_sphere_not_beyond() -> void:
	var w: SimWorld = CombatTestKit.world()
	var alt: float = 6.5                                                      # clear of the ground push-out
	var near: int = CombatTestKit.spawn(w, &"dart", 0, 0, _at(alt, _east_for_gap(alt, 6.0, 14.5)))
	var far: int = CombatTestKit.spawn(w, &"dart", 0, 0, _at(alt, -_east_for_gap(alt, 6.0, 15.5)))
	var _b: int = _bomb(w, 0.0)
	var ev: Array[SimEvent] = _step(w)
	assert_bool(CombatTestKit.alive(w, near)).is_false()
	assert_bool(CombatTestKit.alive(w, far)).is_true()
	assert_float(CombatTestKit.hp(w, far)).is_equal(100.0)
	assert_int(CombatTestKit.of_kind(ev, SimEvent.Kind.BOMB_IMPACT).size()).is_equal(1)


func test_bomb_kill_is_outright_whatever_the_hp() -> void:
	var w: SimWorld = CombatTestKit.world()
	var big: int = CombatTestKit.spawn(w, &"bomber", 0, 0, _at(10.5, 5.0))
	var _b: int = _bomb(w, 0.0)
	var _ev: Array[SimEvent] = _step(w)
	assert_bool(CombatTestKit.alive(w, big)).is_false()


func test_bomb_hits_ground_units_within_20m_for_400() -> void:
	var w: SimWorld = CombatTestKit.world()
	var in_range: int = CombatTestKit.spawn(w, &"siege_crawler", 0, 0, _at(0.0, 26.5))   # radius 7: gap 19.5
	var out: int = CombatTestKit.spawn(w, &"siege_crawler", 0, 0, _at(0.0, -27.5))        # gap 20.5
	var _b: int = _bomb(w, 0.0)
	var ev: Array[SimEvent] = _step(w)
	var hits: Array[SimEvent] = CombatTestKit.of_kind(ev, SimEvent.Kind.HIT)
	assert_int(hits.size()).is_equal(1)
	assert_float(hits[0].value).is_equal(400.0)
	assert_bool(CombatTestKit.alive(w, in_range)).is_false()                           # hp 400
	assert_float(CombatTestKit.hp(w, out)).is_equal(400.0)


func test_bomb_hits_structures_by_footprint_edge_for_400() -> void:
	var w: SimWorld = CombatTestKit.world()
	var s: int = CombatTestKit.spawn(w, &"outpost", 0, 0, _at(0.0))                    # 6 x 6 cells; fwd = +east
	var half: float = 6.0 * CELL_M * 0.5
	var _b: int = _bomb(w, half + 19.0)
	var _ev: Array[SimEvent] = _step(w)
	assert_float(CombatTestKit.hp(w, s)).is_equal(1200.0 - 400.0)
	var _b2: int = _bomb(w, half + 21.0)
	var ev2: Array[SimEvent] = _step(w)
	assert_float(CombatTestKit.hp(w, s)).is_equal(800.0)
	assert_int(CombatTestKit.of_kind(ev2, SimEvent.Kind.HIT).size()).is_equal(0)


func test_bomb_on_the_hangar_roof_does_a_quarter() -> void:
	var w: SimWorld = CombatTestKit.world()
	var h: int = CombatTestKit.spawn(w, &"hangar", 0, 0, _at(0.0))
	var _b: int = _bomb(w, 0.0)
	var _ev: Array[SimEvent] = _step(w)
	assert_float(CombatTestKit.hp(w, h)).is_equal(900.0 - 100.0)


func test_core_takes_125_percent_after_exposure_only() -> void:
	var w: SimWorld = CombatTestKit.world()
	var core: int = CombatTestKit.spawn(w, &"core", 0, 0, _at(0.0))
	var _b: int = _bomb(w, 0.0)
	var _ev: Array[SimEvent] = _step(w)
	assert_float(CombatTestKit.hp(w, core)).is_equal(3000.0 - 400.0)
	var late: SimWorld = CombatTestKit.world(7, WorldTestKit.rules(0.0))              # Exposure from tick 0
	var core2: int = CombatTestKit.spawn(late, &"core", 0, 0, _at(0.0))
	var _b2: int = _bomb(late, 0.0)
	var _ev2: Array[SimEvent] = _step(late)
	assert_float(CombatTestKit.hp(late, core2)).is_equal(3000.0 - 500.0)


func test_bomb_not_yet_armed_passes_through_a_ship() -> void:
	var w: SimWorld = CombatTestKit.world()
	var ship: int = CombatTestKit.spawn(w, &"dart", 0, 0, _at(500.0))
	var young: int = CombatTestKit.shot(w, &"bomb", &"bomb", _at(500.0), 1, 1, 0, 0.1)    # arm_s 0.5
	var _ev: Array[SimEvent] = _step(w)
	assert_bool(CombatTestKit.alive(w, ship)).is_true()
	assert_bool(w.projectiles().alive(young)).is_true()


func test_armed_bomb_touching_a_ship_destroys_it() -> void:
	var w: SimWorld = CombatTestKit.world()
	var ship: int = CombatTestKit.spawn(w, &"lancer", 0, 0, _at(500.0))
	var _b: int = CombatTestKit.shot(w, &"bomb", &"bomb", _at(500.0), 1, 1, 0, 0.6)
	var _ev: Array[SimEvent] = _step(w)
	assert_bool(CombatTestKit.alive(w, ship)).is_false()


func test_c09_pad_dock_dies_hangar_dock_lives() -> void:
	var w: SimWorld = CombatTestKit.world()
	var pad: int = CombatTestKit.spawn(w, &"pad", 0, 0, _at(0.0))
	var dart: int = CombatTestKit.spawn(w, &"dart", 0, 0, _at(0.0))
	CombatTestKit.dock(w, dart, pad)
	var _b: int = _bomb(w, 14.0)
	var _ev: Array[SimEvent] = _step(w)
	assert_bool(CombatTestKit.alive(w, dart)).is_false()                                # Pad: destroyed
	var w2: SimWorld = CombatTestKit.world()
	var hangar: int = CombatTestKit.spawn(w2, &"hangar", 0, 0, _at(0.0))
	var dart2: int = CombatTestKit.spawn(w2, &"dart", 0, 0, _at(0.0))
	CombatTestKit.dock(w2, dart2, hangar)
	var _b2: int = _bomb(w2, 14.0)
	var _ev2: Array[SimEvent] = _step(w2)
	assert_bool(CombatTestKit.alive(w2, dart2)).is_true()                               # Hangar: unharmed
	assert_float(CombatTestKit.hp(w2, dart2)).is_equal(100.0)
	assert_float(CombatTestKit.hp(w2, hangar)).is_equal(800.0)                          # the roof took 25 %


# --- rule 4: rockets ---------------------------------------------------------------------------------------------

func test_rocket_does_40_to_the_target_and_no_splash() -> void:
	var w: SimWorld = CombatTestKit.world()
	var tgt: int = CombatTestKit.spawn(w, &"lancer", 0, 0, _at(500.0))
	var other: int = CombatTestKit.spawn(w, &"lancer", 0, 0, _at(500.0, 3.5 + 8.0 + 8.0))   # 3.5 m beyond contact
	var _r: int = CombatTestKit.shot(w, &"rocket", &"rocket_lancer", _at(500.0), 1, 1)
	var _ev: Array[SimEvent] = _step(w)
	assert_float(CombatTestKit.hp(w, tgt)).is_equal(180.0)
	assert_float(CombatTestKit.hp(w, other)).is_equal(220.0)


func test_bulwark_hangar_blocks_rockets_but_other_hangars_do_not() -> void:
	var w: SimWorld = CombatTestKit.world()
	var hb: int = CombatTestKit.spawn(w, &"hangar", 4, 0, _at(0.0))
	var db: int = CombatTestKit.spawn(w, &"dart", 4, 0, _at(0.0))
	w.store().radius[EntityId.slot(hb)] = 1.0               # isolate the ship from the roof sphere
	CombatTestKit.dock(w, db, hb)
	var _r: int = CombatTestKit.shot(w, &"rocket", &"rocket_lancer", _at(0.0, 4.0), 1, 1)
	var _ev: Array[SimEvent] = _step(w)
	assert_float(CombatTestKit.hp(w, db)).is_equal(100.0)
	var w2: SimWorld = CombatTestKit.world()
	var h0: int = CombatTestKit.spawn(w2, &"hangar", 0, 0, _at(0.0))
	var d0: int = CombatTestKit.spawn(w2, &"dart", 0, 0, _at(0.0))
	w2.store().radius[EntityId.slot(h0)] = 1.0
	CombatTestKit.dock(w2, d0, h0)
	var _r2: int = CombatTestKit.shot(w2, &"rocket", &"rocket_lancer", _at(0.0, 4.0), 1, 1)
	var _ev2: Array[SimEvent] = _step(w2)
	assert_float(CombatTestKit.hp(w2, d0)).is_equal(60.0)


# --- rule 5: flak ------------------------------------------------------------------------------------------------

func test_flak_hits_every_enemy_ship_within_25m_and_nothing_on_the_ground() -> void:
	var w: SimWorld = CombatTestKit.world()
	var a: int = CombatTestKit.spawn(w, &"lancer", 0, 0, _at(500.0))                 # the burst touches this one
	var b: int = CombatTestKit.spawn(w, &"lancer", 0, 0, _at(500.0, 30.0))         # gap 22
	var far: int = CombatTestKit.spawn(w, &"lancer", 0, 0, _at(500.0, 60.0))      # gap 52
	var g: int = CombatTestKit.spawn(w, &"harvester", 0, 0, _at(500.0, 0.0, 12.0))
	var s: int = CombatTestKit.spawn(w, &"solar_array", 0, 0, _at(500.0, 0.0, -36.0))
	var _f: int = CombatTestKit.shot(w, &"flak_shell", &"flak_gun", _at(500.0), 1, 1)
	var _ev: Array[SimEvent] = _step(w)
	assert_float(CombatTestKit.hp(w, a)).is_equal(190.0)
	assert_float(CombatTestKit.hp(w, b)).is_equal(190.0)
	assert_float(CombatTestKit.hp(w, far)).is_equal(220.0)
	assert_float(CombatTestKit.hp(w, g)).is_equal(150.0)
	assert_float(CombatTestKit.hp(w, s)).is_equal(300.0)


# --- siege shells ------------------------------------------------------------------------------------------------

func test_siege_shell_blast_hits_ground_and_structures_inside_12m() -> void:
	var w: SimWorld = CombatTestKit.world()
	var near: int = CombatTestKit.spawn(w, &"siege_crawler", 0, 0, _at(0.0, 18.0))     # gap 11
	var out: int = CombatTestKit.spawn(w, &"siege_crawler", 0, 0, _at(0.0, -20.5))     # gap 13.5
	var _s: int = CombatTestKit.shot(w, &"siege_shell", &"siege_gun", _at(0.5), 1, 1, 0, 2.0)
	var _ev: Array[SimEvent] = _step(w)
	assert_float(CombatTestKit.hp(w, near)).is_equal(280.0)
	assert_float(CombatTestKit.hp(w, out)).is_equal(400.0)


# --- rule 7: ramming ---------------------------------------------------------------------------------------------

func test_ramming_destroys_both_ships_teams_ignored() -> void:
	for team_b: int in [0, 1]:
		var w: SimWorld = CombatTestKit.world()
		var a: int = CombatTestKit.spawn(w, &"lancer", 0, 0, _at(500.0))
		var b: int = CombatTestKit.spawn(w, &"lancer", 0, team_b, _at(500.0, 300.0))
		CombatTestKit.move(w, b, _at(500.0, 10.0))
		var _ev: Array[SimEvent] = _step(w)
		assert_bool(CombatTestKit.alive(w, a)).is_false()
		assert_bool(CombatTestKit.alive(w, b)).is_false()


func test_ship_into_structure_dies_and_the_structure_takes_its_remaining_hp() -> void:
	var w: SimWorld = CombatTestKit.world()
	var st: int = CombatTestKit.spawn(w, &"refinery", 0, 1, _at(500.0))
	var ship: int = CombatTestKit.spawn(w, &"lancer", 0, 0, _at(500.0, 300.0))
	w.store().hp[EntityId.slot(ship)] = 90.0
	CombatTestKit.move(w, ship, _at(500.0, 3.0))
	var _ev: Array[SimEvent] = _step(w)
	assert_bool(CombatTestKit.alive(w, ship)).is_false()
	assert_float(CombatTestKit.hp(w, st)).is_equal(1000.0 - 90.0)


func test_ship_into_own_non_pad_structure_also_rams() -> void:
	var w: SimWorld = CombatTestKit.world()
	var st: int = CombatTestKit.spawn(w, &"refinery", 0, 0, _at(500.0))
	var ship: int = CombatTestKit.spawn(w, &"lancer", 0, 0, _at(500.0, 300.0))
	CombatTestKit.move(w, ship, _at(500.0, 3.0))
	var _ev: Array[SimEvent] = _step(w)
	assert_bool(CombatTestKit.alive(w, ship)).is_false()
	assert_float(CombatTestKit.hp(w, st)).is_equal(1000.0 - 220.0)


func test_invulnerable_structures_take_no_damage() -> void:
	var w: SimWorld = CombatTestKit.world()
	var st: int = CombatTestKit.spawn(w, &"relay_station", 0, 0, _at(0.0))
	var _b: int = _bomb(w, 0.0)
	var _ev: Array[SimEvent] = _step(w)
	assert_float(CombatTestKit.hp(w, st)).is_equal(1.0)
	assert_bool(CombatTestKit.alive(w, st)).is_true()
