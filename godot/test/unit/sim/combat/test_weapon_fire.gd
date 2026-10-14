extends GdUnitTestSuite
## GD-36 weapon fire through SimWorld.step (02 s4.4 fire pipeline, R0 C2-23): rate of fire and the 30 Hz grid,
## ammo draw and empty, bombs (doctrine-resolved load-out), tower bursts, unsupplied 50 % rate, lock acquisition, load-out, spread, docked ships.
## Shooters are team 1 (slot 1), targets team 0. A shot is a drop of the shooter's ammo field (FireTestKit).

const FIRE1: int = PilotInput.FIRE1
const FIRE2: int = PilotInput.FIRE2


func _at(alt: float, east: float = 0.0, north: float = 0.0) -> Vector3:
	return FireTestKit.at(alt, east, north)


# --- guns: rate of fire and ammo -------------------------------------------------------------------------------

func test_dart_fires_10_rps_spending_one_round_per_shot() -> void:
	var w: SimWorld = CombatTestKit.world()
	var dart: int = CombatTestKit.spawn(w, &"dart", 1, 1, _at(500.0))
	FireTestKit.hook(w).hold(dart, FIRE1)
	var t0: int = w.tick()
	var shots: PackedInt32Array = FireTestKit.shot_ticks(w, dart, 90)
	assert_int(shots.size()).is_equal(30)                     # 3 s x 10 rps
	assert_int(shots[0]).is_equal(t0 + 1)                     # the tick the trigger is first held
	for g: int in FireTestKit.gaps(shots):
		assert_int(g).is_equal(3)                             # 0.1 s on the 30 Hz grid, no drift
	assert_int(w.store().ammo[EntityId.slot(dart)]).is_equal(400 - 30)


func test_gun_shot_is_a_slug_from_the_muzzle_with_the_carrier_velocity_and_spread() -> void:
	var w: SimWorld = CombatTestKit.world()
	var dart: int = CombatTestKit.spawn(w, &"dart", 1, 1, _at(500.0))
	FireTestKit.hook(w).hold(dart, FIRE1)
	w.step()
	var s: int = EntityId.slot(dart)
	var ps: ProjectileStore = w.projectiles()
	var mine: PackedInt32Array = FireTestKit.fired_by(w, dart)
	assert_int(mine.size()).is_equal(1)
	var i: int = mine[0]
	assert_int(ps.kind[i]).is_equal(ProjectileStore.SLUG)
	assert_int(ps.team[i]).is_equal(1)
	assert_int(ps.owner[i]).is_equal(1)
	assert_float(ps.ttl[i]).is_equal_approx(1.15, 0.0001)
	var rel: Vector3 = ps.vel[i] - w.store().vel[s]
	assert_float(rel.length()).is_equal_approx(700.0, 0.01)
	assert_float(rad_to_deg(rel.angle_to(w.store().fwd[s]))).is_less_equal(0.6 * sqrt(2.0) + 0.001)
	assert_float(ps.pos[i].distance_to(w.store().pos[s])).is_equal_approx(6.0, 0.01)   # bounding radius ahead


func test_empty_gun_stops_and_never_goes_negative() -> void:
	var w: SimWorld = CombatTestKit.world()
	var dart: int = CombatTestKit.spawn(w, &"dart", 1, 1, _at(500.0))
	w.store().ammo[EntityId.slot(dart)] = 5
	FireTestKit.hook(w).hold(dart, FIRE1)
	var shots: PackedInt32Array = FireTestKit.shot_ticks(w, dart, 60)
	assert_int(shots.size()).is_equal(5)
	assert_int(w.store().ammo[EntityId.slot(dart)]).is_equal(0)
	assert_int(FireTestKit.fired_by(w, dart).size()).is_less_equal(5)


func test_released_trigger_banks_no_shots() -> void:
	var w: SimWorld = CombatTestKit.world()
	var dart: int = CombatTestKit.spawn(w, &"dart", 1, 1, _at(500.0))
	var h: FireTestKit.TriggerHook = FireTestKit.hook(w)
	h.hold(dart, FIRE1)
	var first: PackedInt32Array = FireTestKit.shot_ticks(w, dart, 1)
	h.hold(dart, 0)
	var idle: PackedInt32Array = FireTestKit.shot_ticks(w, dart, 30)
	h.hold(dart, FIRE1)
	var again: PackedInt32Array = FireTestKit.shot_ticks(w, dart, 3)
	assert_int(first.size()).is_equal(1)
	assert_int(idle.size()).is_equal(0)
	assert_int(again.size()).is_equal(1)                      # one shot at once, then the 3-tick cadence
	assert_int(again[0]).is_equal(first[0] + 31)


func test_bomber_drops_at_the_refire_rate_until_its_bombs_are_gone() -> void:
	var w: SimWorld = CombatTestKit.world()
	var bomber: int = CombatTestKit.spawn(w, &"bomber", 1, 1, _at(500.0))
	var s: int = EntityId.slot(bomber)
	assert_int(w.store().bombs[s]).is_equal(6)
	w.store().bombs[s] = 3
	FireTestKit.hook(w).hold(bomber, FIRE2)
	var drops: PackedInt32Array = FireTestKit.shot_ticks(w, bomber, 60, &"bombs")
	assert_int(drops.size()).is_equal(3)
	for g: int in FireTestKit.gaps(drops):
		assert_int(g).is_equal(12)                            # rof 2.5 = 0.4 s refire
	assert_int(w.store().bombs[s]).is_equal(0)


func test_bomb_leaves_with_the_carrier_velocity_plus_the_eject() -> void:
	var w: SimWorld = CombatTestKit.world()
	var dart: int = CombatTestKit.spawn(w, &"dart", 1, 1, _at(500.0))
	FireTestKit.hook(w).hold(dart, FIRE2)
	w.step()
	var s: int = EntityId.slot(dart)
	var mine: PackedInt32Array = FireTestKit.fired_by(w, dart)
	assert_int(mine.size()).is_equal(1)
	var i: int = mine[0]
	assert_int(w.projectiles().kind[i]).is_equal(ProjectileStore.BOMB)
	assert_int(w.store().bombs[s]).is_equal(0)                # Vanguard Dart carries one bomb
	var p: Vector3 = w.store().pos[s]
	var want: Vector3 = w.store().vel[s] - p.normalized() * 40.0
	assert_float(w.projectiles().vel[i].distance_to(want)).is_less(0.001)


func test_docked_ship_does_not_fire() -> void:
	var w: SimWorld = CombatTestKit.world()
	var pad: int = CombatTestKit.spawn(w, &"pad", 1, 1, _at(0.0, 500.0))
	var dart: int = CombatTestKit.spawn(w, &"dart", 1, 1, _at(500.0))
	CombatTestKit.dock(w, dart, pad)
	FireTestKit.hook(w).hold(dart, FIRE1 | FIRE2)
	var shots: PackedInt32Array = FireTestKit.shot_ticks(w, dart, 30)
	assert_int(shots.size()).is_equal(0)
	assert_int(w.store().bombs[EntityId.slot(dart)]).is_equal(1)


# --- load-out --------------------------------------------------------------------------------------------------

func test_spawn_loads_primary_secondary_tower_pool_and_ground_rounds() -> void:
	var w: SimWorld = CombatTestKit.world()
	var st: EntityStore = w.store()
	var dart: int = EntityId.slot(CombatTestKit.spawn(w, &"dart", 0, 0, _at(500.0)))
	var vanguard: int = EntityId.slot(CombatTestKit.spawn(w, &"dart", 1, 1, _at(500.0, -100.0)))
	var lancer: int = EntityId.slot(CombatTestKit.spawn(w, &"lancer", 1, 1, _at(500.0, 100.0)))
	var gun: int = EntityId.slot(CombatTestKit.spawn(w, &"autocannon_turret", 1, 1, _at(0.0, 300.0)))
	var flak: int = EntityId.slot(CombatTestKit.spawn(w, &"flak_battery", 1, 1, _at(0.0, 400.0)))
	var mt: int = EntityId.slot(CombatTestKit.spawn(w, &"missile_tower", 1, 1, _at(0.0, 500.0)))
	var crawler: int = EntityId.slot(CombatTestKit.spawn(w, &"siege_crawler", 1, 1, _at(0.0, 600.0)))
	assert_int(st.ammo[dart]).is_equal(400)
	assert_int(st.bombs[dart]).is_equal(2)
	assert_int(st.rockets[dart]).is_equal(0)
	assert_int(st.bombs[vanguard]).is_equal(1)                # doctrine-resolved: Vanguard sets secondary.count 1
	assert_int(st.ammo[lancer]).is_equal(300)
	assert_int(st.rockets[lancer]).is_equal(8)
	assert_int(st.bombs[lancer]).is_equal(0)
	assert_int(st.ammo[gun]).is_equal(300)
	assert_int(st.ammo[flak]).is_equal(40)
	assert_int(st.ammo[mt]).is_equal(12)
	assert_int(st.ammo[crawler]).is_equal(20)


# --- tower bursts and supply -----------------------------------------------------------------------------------

## Splits shot ticks into bursts (a gap above 2 shot spacings starts a new one).
func _bursts(shots: PackedInt32Array, split: int) -> Array[PackedInt32Array]:
	var out: Array[PackedInt32Array] = []
	var cur: PackedInt32Array = PackedInt32Array()
	for k: int in shots.size():
		if k > 0 and shots[k] - shots[k - 1] > split:
			out.append(cur)
			cur = PackedInt32Array()
		cur.push_back(shots[k])
	if not cur.is_empty():
		out.append(cur)
	return out


func test_tower_fires_5_round_bursts_every_1_2_s() -> void:
	var w: SimWorld = CombatTestKit.world()
	CombatTestKit.power(w, 1, 1)
	var gun: int = CombatTestKit.spawn(w, &"autocannon_turret", 1, 1, _at(0.0))
	FireTestKit.hook(w).hold(gun, FIRE1)
	var t0: int = w.tick()
	var shots: PackedInt32Array = FireTestKit.shot_ticks(w, gun, 108)          # 3.6 s
	var bursts: Array[PackedInt32Array] = _bursts(shots, 5)
	assert_int(bursts.size()).is_equal(3)
	for k: int in bursts.size():
		var b: PackedInt32Array = bursts[k]
		assert_int(b.size()).is_equal(5)
		assert_int(b[0]).is_equal(t0 + 1 + 36 * k)            # 1.2 s = 36 ticks, start to start
		assert_int(b[4] - b[0]).is_equal(10)                  # 4 spacings of 1 / 12 s = 10 ticks
		for g: int in FireTestKit.gaps(b):
			assert_int(g).is_between(2, 3)
	assert_int(w.store().ammo[EntityId.slot(gun)]).is_equal(300 - 15)


func test_unsupplied_tower_fires_at_half_rate() -> void:
	var w: SimWorld = CombatTestKit.world()
	CombatTestKit.power(w, 1, 1)
	var fed: int = CombatTestKit.spawn(w, &"autocannon_turret", 1, 1, _at(0.0))
	var cut: int = CombatTestKit.spawn(w, &"autocannon_turret", 1, 1, _at(0.0, 0.0, 300.0))
	FireTestKit.combat(w).fire.unsupplied[EntityId.slot(cut)] = 1
	var h: FireTestKit.TriggerHook = FireTestKit.hook(w)
	h.hold(fed, FIRE1)
	h.hold(cut, FIRE1)
	var s_fed: int = EntityId.slot(fed)
	var s_cut: int = EntityId.slot(cut)
	var shots_cut: PackedInt32Array = PackedInt32Array()
	var last: int = w.store().ammo[s_cut]
	for _k: int in 216:                                       # 7.2 s
		w.step()
		var _e: Array[SimEvent] = w.drain_events()
		if w.store().ammo[s_cut] < last:
			shots_cut.push_back(w.tick())
		last = w.store().ammo[s_cut]
	assert_int(300 - w.store().ammo[s_fed]).is_equal(30)     # 6 bursts of 5
	assert_int(300 - w.store().ammo[s_cut]).is_equal(15)     # 50 %: 3 bursts of 5
	var bursts: Array[PackedInt32Array] = _bursts(shots_cut, 10)
	assert_int(bursts.size()).is_equal(3)
	assert_int(bursts[1][0] - bursts[0][0]).is_equal(72)     # 2.4 s window
	assert_int(bursts[0][4] - bursts[0][0]).is_equal(20)     # rof 6


func test_flak_battery_fires_a_two_shell_salvo_per_reload() -> void:
	var w: SimWorld = CombatTestKit.world()
	CombatTestKit.power(w, 1, 1)
	var flak: int = CombatTestKit.spawn(w, &"flak_battery", 1, 1, _at(0.0))
	FireTestKit.hook(w).hold(flak, FIRE1)
	var shots: PackedInt32Array = FireTestKit.shot_ticks(w, flak, 61)
	assert_int(shots.size()).is_equal(4)
	assert_int(shots[0]).is_equal(shots[1])                  # salvo 2 in one tick
	assert_int(shots[2] - shots[0]).is_equal(60)             # reload 2.0 s


# --- lock --------------------------------------------------------------------------------------------------------

func test_rocket_launches_only_after_lock_time() -> void:
	var w: SimWorld = CombatTestKit.world()
	var lancer: int = CombatTestKit.spawn(w, &"lancer", 1, 1, _at(500.0))
	var tgt: int = CombatTestKit.spawn(w, &"dart", 0, 0, _at(500.0, 300.0))
	FireTestKit.hook(w).hold(lancer, FIRE2)
	var t0: int = w.tick()
	var acquired: int = -1
	var launches: PackedInt32Array = PackedInt32Array()
	var s: int = EntityId.slot(lancer)
	for _k: int in 30:
		var before: int = w.store().rockets[s]
		w.step()
		for e: SimEvent in w.drain_events():
			if e.kind == SimEvent.Kind.LOCK_ACQUIRED:
				assert_int(e.a).is_equal(lancer)
				assert_int(e.b).is_equal(tgt)
				acquired = w.tick()
		if w.store().rockets[s] < before:
			launches.push_back(w.tick())
	assert_int(acquired).is_equal(t0 + 1 + 24)                # lock_time_s 0.8 = 24 ticks after first sight
	assert_int(launches.size()).is_equal(1)
	assert_int(launches[0]).is_equal(acquired)
	var mine: PackedInt32Array = FireTestKit.fired_by(w, lancer)
	assert_int(mine.size()).is_equal(1)
	assert_int(w.projectiles().target[mine[0]]).is_equal(tgt)
	assert_int(w.projectiles().flags[mine[0]] & ProjectileStore.F_GUIDED).is_equal(ProjectileStore.F_GUIDED)


func test_no_launch_without_a_target_in_the_cone() -> void:
	var w: SimWorld = CombatTestKit.world()
	var lancer: int = CombatTestKit.spawn(w, &"lancer", 1, 1, _at(500.0))
	var _behind: int = CombatTestKit.spawn(w, &"dart", 0, 0, _at(500.0, -300.0))
	var _wide: int = CombatTestKit.spawn(w, &"dart", 0, 0, _at(500.0, 300.0, 300.0))      # 45 deg off, cone 20
	var _far: int = CombatTestKit.spawn(w, &"dart", 0, 0, _at(500.0, 1600.0))             # beyond range_m 1,500
	var _mate: int = CombatTestKit.spawn(w, &"dart", 1, 1, _at(500.0, 200.0))             # friendly
	FireTestKit.hook(w).hold(lancer, FIRE2)
	var launches: PackedInt32Array = FireTestKit.shot_ticks(w, lancer, 60, &"rockets")
	assert_int(launches.size()).is_equal(0)


func test_lock_restarts_when_the_target_leaves_the_cone() -> void:
	var w: SimWorld = CombatTestKit.world()
	var lancer: int = CombatTestKit.spawn(w, &"lancer", 1, 1, _at(500.0))
	var tgt: int = CombatTestKit.spawn(w, &"dart", 0, 0, _at(500.0, 300.0))
	FireTestKit.hook(w).hold(lancer, FIRE2)
	var t0: int = w.tick()
	var early: PackedInt32Array = FireTestKit.shot_ticks(w, lancer, 12, &"rockets")
	var p: Vector3 = w.store().pos[EntityId.slot(tgt)]
	CombatTestKit.move(w, tgt, _at(500.0, -300.0))
	var gone: PackedInt32Array = FireTestKit.shot_ticks(w, lancer, 1, &"rockets")
	CombatTestKit.move(w, tgt, p)
	var late: PackedInt32Array = FireTestKit.shot_ticks(w, lancer, 30, &"rockets")
	assert_int(early.size() + gone.size()).is_equal(0)
	assert_int(late.size()).is_equal(1)
	assert_int(late[0]).is_equal(t0 + 14 + 24)               # seen again at t0 + 14, held 0.8 s


func test_missile_tower_salvo_after_one_second_of_lock() -> void:
	var w: SimWorld = CombatTestKit.world()
	CombatTestKit.power(w, 1, 1)
	var mt: int = CombatTestKit.spawn(w, &"missile_tower", 1, 1, _at(0.0))
	var _tgt: int = CombatTestKit.spawn(w, &"dart", 0, 0, _at(300.0, 400.0))
	FireTestKit.hook(w).hold(mt, FIRE1)
	var t0: int = w.tick()
	var shots: PackedInt32Array = FireTestKit.shot_ticks(w, mt, 40)
	assert_int(shots.size()).is_equal(2)                     # salvo 2, then reload 6 s
	assert_int(shots[0]).is_equal(t0 + 1 + 30)
	assert_int(shots[1]).is_equal(shots[0])
	assert_int(w.store().ammo[EntityId.slot(mt)]).is_equal(10)
