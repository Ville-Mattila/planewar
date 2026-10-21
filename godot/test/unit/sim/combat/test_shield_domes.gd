extends GdUnitTestSuite
## GD-10 (02 s4.3 rule 6, s5.1, s5.2; R0 C3-05): absorption and collapse of the Shield Projector and the Core's integrated
## shield. Contract SH1-SH6 of sim/combat/MODULE.md; scenarios C-07 and C-13. Recharge, power, Exposure and S4 are in
## test_shield_recharge.gd. Geometry on the flat datum: the Core of player 0 at +X, a Projector 300 m east of it.

const K: GDScript = preload("res://test/unit/sim/combat/shield_test_kit.gd")
const HZ: int = 30


func test_the_core_starts_with_a_full_integrated_shield_over_its_footprint() -> void:
	var w: SimWorld = K.world()
	var core: int = K.core_slot(w)
	var eco: Dictionary = K.sdef(&"core").integrated_shield
	assert_float(w.shields().charge_of(core)).is_equal(float(eco["charge_max"]))     # 2,400, no Ice, no power
	assert_float(w.shields().dome_radius(core)).is_equal(float(eco["dome_radius"]))                    # a def key (A-99): 75 m
	assert_float(w.shields().dome_radius(core)).is_equal(75.0)
	assert_bool(w.shields().is_up(core, w.tick())).is_true()
	assert_bool(w.shields().core_up(0)).is_true()
	assert_bool(w.shields().core_up(1)).is_false()


# 02 s5.1 bound (R0 B.18 A-99): every integrated shield covers the footprint half-diagonal plus the largest structure blast of
# an absorbed projectile, so a bomb enters the dome before it touches the bounding sphere; 52.07 + 20 = 72.07 m for the Core.
func test_every_integrated_shield_radius_covers_the_footprint_plus_the_largest_absorbed_blast() -> void:
	var reach: float = 0.0
	for pd: ProjectileDef in WorldTestKit.content().projectiles:
		if pd.shield_absorbed:
			reach = maxf(reach, pd.blast_radius_structure_m)
	assert_float(reach).is_equal(20.0)
	var seen: int = 0
	for sd: StructureDef in WorldTestKit.content().structures:
		if sd.integrated_shield.is_empty():
			continue
		seen += 1
		var half_diag: float = Vector2(float(sd.footprint[0]), float(sd.footprint[1])).length() * WorldDefs.build_cell_m() * 0.5
		assert_float(float(sd.integrated_shield["dome_radius"])).is_greater_equal(half_diag + reach)
		assert_float(half_diag + reach).is_equal_approx(72.07, 0.01)
		assert_float(float(sd.integrated_shield["collapse_s"])).is_equal(10.0)             # 02 s4.3 rule 6: "collapses to 0 for 10 s"
	assert_int(seen).is_equal(1)


func test_a_projector_has_its_dome_radius_and_starts_empty() -> void:
	var w: SimWorld = K.world()
	var p: int = K.projector(w, 300.0)
	assert_float(w.shields().dome_radius(p)).is_equal(250.0)
	assert_float(w.shields().charge_of(p)).is_less(5.0)                               # built at 0, charging from the first tick
	assert_float(w.shields().charge_of(EconomyTestKit.find(w, &"refinery"))).is_equal(0.0)   # no dome on other structures
	assert_float(w.shields().dome_radius(-1)).is_equal(0.0)


func test_a_bomb_entering_a_charged_dome_is_absorbed_and_charge_drops_by_its_damage() -> void:
	var w: SimWorld = K.world()
	var p: int = K.projector(w, 300.0)
	var _filled: int = K.fill(w, p)
	var id: int = K.shot(w, p)
	assert_int(K.absorb(w)).is_equal(1)
	assert_bool(w.projectiles().alive(id)).is_false()
	assert_float(w.shields().charge_of(p)).is_equal(800.0)                            # a bomb is 400 (weapons.json)
	assert_int(w.shields().absorbed_total).is_equal(1)
	assert_int(K.kinds(w.drain_events(), SimEvent.Kind.SHIELD_COLLAPSE)).is_equal(0)


func test_c07_four_bombs_within_five_seconds_three_absorbed_fourth_passes_and_the_dome_collapses() -> void:
	var w: SimWorld = K.world()
	var p: int = K.projector(w, 300.0)
	var _filled: int = K.fill(w, p)
	var _old: Array[SimEvent] = w.drain_events()
	var absorbed: int = 0
	var ids: PackedInt32Array = PackedInt32Array()
	for k: int in 4:
		ids.append(K.shot(w, p))
		absorbed += K.absorb(w)
		for _t: int in 30:                                                            # one bomb a second: all inside 5 s
			w.step()
	assert_int(absorbed).is_equal(3)
	assert_bool(w.projectiles().alive(ids[3])).is_true()                             # the 4th flew on unchanged
	assert_float(w.shields().charge_of(p)).is_equal(0.0)
	var collapses: int = K.kinds(w.drain_events(), SimEvent.Kind.SHIELD_COLLAPSE)
	assert_int(collapses).is_equal(1)
	assert_int(w.shields().collapse_left(p, w.tick())).is_greater(0)


func test_a_collapsed_dome_lets_everything_through_for_ten_seconds_then_returns_empty() -> void:
	var w: SimWorld = K.world()
	var p: int = K.projector(w, 300.0)
	var collapse_ticks: int = roundi(Def.num(K.sdef(&"shield_projector").shield["collapse_s"]) * float(HZ))
	assert_int(collapse_ticks).is_equal(10 * HZ)
	var first: int = K.shot(w, p)                                                     # 100 < 400: passes, collapses
	assert_int(K.absorb(w)).is_equal(0)
	assert_bool(w.projectiles().alive(first)).is_true()
	var t0: int = w.tick()
	assert_int(w.shields().collapse_left(p, t0)).is_equal(collapse_ticks)
	assert_bool(w.shields().is_up(p, t0)).is_false()
	var second: int = K.shot(w, p)
	assert_int(K.absorb(w)).is_equal(0)                                              # down: nothing is absorbed
	assert_bool(w.projectiles().alive(second)).is_true()
	while w.tick() < t0 + collapse_ticks - 1:
		w.step()
	assert_float(w.shields().charge_of(p)).is_equal(0.0)
	assert_bool(w.shields().is_up(p, w.tick())).is_false()
	w.step()
	assert_bool(w.shields().is_up(p, w.tick())).is_true()                            # back after collapse_s, at 0


func test_a_projectile_that_starts_inside_the_dome_is_never_absorbed() -> void:
	var w: SimWorld = K.world()
	var p: int = K.projector(w, 300.0)
	var _filled: int = K.fill(w, p)
	var id: int = K.shot(w, p, &"bomb", &"bomb", 1, -10.0, 20.0)                      # prev inside, now deeper inside
	assert_int(K.absorb(w)).is_equal(0)
	assert_bool(w.projectiles().alive(id)).is_true()
	assert_float(w.shields().charge_of(p)).is_equal(1200.0)


func test_a_projectile_that_misses_the_dome_is_not_absorbed() -> void:
	var w: SimWorld = K.world()
	var p: int = K.projector(w, 300.0)
	var _filled: int = K.fill(w, p)
	var id: int = K.shot(w, p, &"bomb", &"bomb", 1, 40.0, -30.0)                      # ends 30 m outside
	assert_int(K.absorb(w)).is_equal(0)
	assert_bool(w.projectiles().alive(id)).is_true()


func test_friendly_projectiles_pass_and_only_shield_absorbed_defs_are_taken() -> void:
	var w: SimWorld = K.world()
	var p: int = K.projector(w, 300.0)
	var _filled: int = K.fill(w, p)
	var own: int = K.shot(w, p, &"bomb", &"bomb", 0)                                  # the dome's own team
	var slug: int = K.shot(w, p, &"slug_light", &"gun_dart")
	var flak: int = K.shot(w, p, &"flak_shell", &"flak_gun")
	var rail: int = K.shot(w, p, &"rail_slug", &"rail_gun")
	assert_int(K.absorb(w)).is_equal(0)
	for id: int in [own, slug, flak, rail]:
		assert_bool(w.projectiles().alive(id)).is_true()
	assert_float(w.shields().charge_of(p)).is_equal(1200.0)


func test_rockets_and_siege_shells_are_absorbed_for_their_own_damage() -> void:
	var w: SimWorld = K.world()
	var p: int = K.projector(w, 300.0)
	var _filled: int = K.fill(w, p)
	var rocket: int = K.shot(w, p, &"rocket", &"rocket_lancer")
	var shell: int = K.shot(w, p, &"siege_shell", &"siege_gun")
	assert_int(K.absorb(w)).is_equal(2)
	assert_bool(w.projectiles().alive(rocket)).is_false()
	assert_bool(w.projectiles().alive(shell)).is_false()
	assert_float(w.shields().charge_of(p)).is_equal(1200.0 - 40.0 - 120.0)


func test_absorbed_damage_is_the_owners_resolved_weapon_damage() -> void:
	var w: SimWorld = K.world()
	var p: int = K.projector(w, 300.0)
	var _filled: int = K.fill(w, p)
	var id: int = K.shot(w, p, &"bomb", &"bomb", 3)                                   # Foundry: bombs x0.85 = 340
	assert_int(K.absorb(w)).is_equal(1)
	assert_bool(w.projectiles().alive(id)).is_false()
	assert_float(w.shields().charge_of(p)).is_equal(1200.0 - 340.0)


func test_a_ship_passes_through_a_dome_freely() -> void:
	var w: SimWorld = K.world()
	var p: int = K.projector(w, 300.0)
	var _filled: int = K.fill(w, p)
	var c: Vector3 = w.store().pos[p]
	var dart: int = WorldTestKit.spawn(w, &"dart", 1, 1, c + c.normalized() * 30.0)
	w.step()
	assert_bool(w.store().alive(dart)).is_true()
	assert_float(w.shields().charge_of(p)).is_equal_approx(1200.0, 1.0)


func test_two_overlapping_domes_the_one_entered_first_takes_the_shot() -> void:
	var w: SimWorld = K.world()
	var a: int = K.projector(w, 300.0)
	var b: int = K.projector(w, 360.0)
	var _filled: int = K.fill(w, a, b)
	var id: int = K.shot(w, a)                                                        # enters dome a on its far side first
	var ps: ProjectileStore = w.projectiles()
	var i: int = ps.index_of(id)
	ps.prev_pos[i] = w.store().pos[a] + w.store().pos[a].normalized() * 252.0 + Vector3(0.0, -60.0, 0.0)
	ps.pos[i] = w.store().pos[a] + w.store().pos[a].normalized() * 100.0
	var _n: int = K.absorb(w)
	var taken: float = (1200.0 - w.shields().charge_of(a)) + (1200.0 - w.shields().charge_of(b))
	assert_float(taken).is_equal(400.0)                                               # exactly one dome paid, once


func test_c13_eight_bombs_on_a_towerless_core_six_absorbed_the_core_keeps_600_hp() -> void:
	var w: SimWorld = K.world()
	var core: int = K.core_slot(w)
	var c: Vector3 = w.store().pos[core]
	var up: Vector3 = c.normalized()
	var ps: ProjectileStore = w.projectiles()
	var hp0: float = w.store().hp[core]
	var _old: Array[SimEvent] = w.drain_events()
	for k: int in 8:                                                                  # a low pass from +Y, 110 m out, 8 m up
		var lateral: Vector3 = Vector3(0.0, 0.0, 1.5 * float(k) - 5.0)
		var id: int = CombatTestKit.shot(w, &"bomb", &"bomb", c + up * 8.0 + Vector3(0.0, 110.0, 0.0) + lateral, 1, 1)
		ps.vel[ps.index_of(id)] = Vector3(0.0, -60.0, 0.0)
	var events: Array[SimEvent] = EconomyTestKit.run(w, 150)
	assert_int(w.shields().absorbed_total).is_equal(6)                               # 2,400 / 400
	assert_int(K.kinds(events, SimEvent.Kind.SHIELD_COLLAPSE)).is_equal(1)
	assert_int(K.kinds(events, SimEvent.Kind.BOMB_IMPACT)).is_equal(2)               # the 7th and 8th reached the ground
	assert_float(w.store().hp[core]).is_greater_equal(600.0)
	assert_float(w.store().hp[core]).is_equal(hp0 - 2.0 * 400.0)
	assert_int(EconomyTestKit.count_alert(events, AlertKind.Kind.CORE_SHIELD_DOWN)).is_equal(1)
	assert_bool(w.shields().core_up(0)).is_false()


func test_the_integrated_shield_protects_only_the_core_not_a_neighbouring_structure() -> void:
	var w: SimWorld = K.world()
	var yard: int = EconomyTestKit.find(w, &"shipyard")
	var id: int = K.shot(w, yard, &"bomb", &"bomb", 1)
	assert_int(K.absorb(w)).is_equal(0)                                              # the Shipyard has no dome
	assert_bool(w.projectiles().alive(id)).is_true()


func test_a_dome_dies_with_its_structure_and_a_new_one_in_the_slot_starts_fresh() -> void:
	var w: SimWorld = K.world()
	var p: int = K.projector(w, 300.0)
	var _filled: int = K.fill(w, p)
	var id: int = w.store().id_of(p)
	assert_int(EconomyTestKit.code(w, CommandPayload.debug_set(0, id, CommandPayload.SET_KILL, 0.0))).is_equal(CommandResult.Code.ACCEPTED)
	w.step()
	assert_float(w.shields().charge_of(p)).is_equal(0.0)
	assert_bool(w.shields().is_up(p, w.tick())).is_false()
	var q: int = K.projector(w, 300.0)
	assert_float(w.shields().charge_of(q)).is_less(5.0)                               # never inherits the old charge
