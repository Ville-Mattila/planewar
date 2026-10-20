extends GdUnitTestSuite
## GD-36 fuses (02 s4.2 / s4.3 rules 4-5, left open by GD-08): a rocket's proximity burst on its lock target, flak's
## timed burst at its burst tick and its early burst near a hostile ship; arming gates both; the flak battery fuses
## its shells for the closest approach to the ship nearest its boresight. Projectiles are written with
## `ProjectileStore.spawn` (the call weapon fire uses); team 1 shoots, team 0 is the target side.

const R: float = Sphere.PLANET_RADIUS


func _at(alt: float, east: float = 0.0, north: float = 0.0) -> Vector3:
	return FireTestKit.at(alt, east, north)


func _local(index: Dictionary, id: StringName, base: int) -> int:
	var d: int = index.get(id, -1)
	return d - base


## A projectile of `proj` from `weapon`, `age` seconds old, at `p` with velocity `v`; `target` per kind.
func _shot(w: SimWorld, kind: int, proj: StringName, weapon: StringName, p: Vector3, v: Vector3, target: int,
		age: float, flags: int = 0) -> int:
	var c: ContentSet = WorldTestKit.content()
	var pl: int = _local(c.projectile_index, proj, DefRanges.PROJECTILE_BASE)
	var wl: int = _local(c.weapon_index, weapon, DefRanges.WEAPON_BASE)
	var life: float = c.projectiles[pl].lifetime_s
	return w.projectiles().spawn(kind, w.tick(), p, v, life - age, pl, wl, 1, 1, 0, target, flags)


func _flak_delay() -> float:
	var c: ContentSet = WorldTestKit.content()
	return Def.num(c.projectiles[_local(c.projectile_index, &"flak_shell", DefRanges.PROJECTILE_BASE)].raw.get("fuse_delay_s", 0.0))


func _step(w: SimWorld) -> Array[SimEvent]:
	w.step()
	return w.drain_events()


# --- rule 4: rocket proximity ----------------------------------------------------------------------------------

func test_rocket_bursts_on_its_target_within_the_proximity_radius() -> void:
	var w: SimWorld = CombatTestKit.world()
	var tgt: int = CombatTestKit.spawn(w, &"lancer", 0, 0, _at(500.0))
	var other: int = CombatTestKit.spawn(w, &"dart", 0, 0, _at(500.0, 0.0, -30.0))
	# passes 10 m to the side: outside the contact sweep (0.8 + 8), inside the fuse (4 + 8)
	var r: int = _shot(w, ProjectileStore.ROCKET, &"rocket", &"rocket_lancer", _at(500.0, -4.0, 10.0),
		Vector3(0.0, 250.0, 0.0), tgt, 1.0)
	var hits: Array[SimEvent] = CombatTestKit.of_kind(_step(w), SimEvent.Kind.HIT)
	assert_int(hits.size()).is_equal(1)
	assert_int(hits[0].a).is_equal(tgt)
	assert_float(CombatTestKit.hp(w, tgt)).is_equal(220.0 - 40.0)
	assert_float(CombatTestKit.hp(w, other)).is_equal(100.0)   # no splash (rule 4)
	assert_bool(w.projectiles().alive(r)).is_false()


func test_rocket_outside_the_fuse_radius_or_unarmed_flies_on() -> void:
	var w: SimWorld = CombatTestKit.world()
	var tgt: int = CombatTestKit.spawn(w, &"lancer", 0, 0, _at(500.0))
	var wide: int = _shot(w, ProjectileStore.ROCKET, &"rocket", &"rocket_lancer", _at(500.0, -4.0, 13.0),
		Vector3(0.0, 250.0, 0.0), tgt, 1.0)
	var green: int = _shot(w, ProjectileStore.ROCKET, &"rocket", &"rocket_lancer", _at(500.0, -4.0, -10.0),
		Vector3(0.0, 250.0, 0.0), tgt, 0.0)                     # arm_s 0.2 not reached
	var _ev: Array[SimEvent] = _step(w)
	assert_float(CombatTestKit.hp(w, tgt)).is_equal(220.0)
	assert_bool(w.projectiles().alive(wide)).is_true()
	assert_bool(w.projectiles().alive(green)).is_true()


# --- rule 5: flak ------------------------------------------------------------------------------------------------

func test_flak_bursts_at_its_burst_tick_and_not_before() -> void:
	var w: SimWorld = CombatTestKit.world()
	var tgt: int = CombatTestKit.spawn(w, &"dart", 0, 0, _at(500.0, 20.0))   # 20 m: gap 14 < 25, but > 12 + 6
	var due: int = w.tick() + 5
	var f: int = _shot(w, ProjectileStore.FLAK, &"flak_shell", &"flak_gun", _at(500.0), Vector3.ZERO, due, 1.0)
	for _k: int in 4:
		var _e: Array[SimEvent] = _step(w)
		assert_float(CombatTestKit.hp(w, tgt)).is_equal(100.0)
		assert_bool(w.projectiles().alive(f)).is_true()
	var hits: Array[SimEvent] = CombatTestKit.of_kind(_step(w), SimEvent.Kind.HIT)
	assert_int(w.tick()).is_equal(due)
	assert_int(hits.size()).is_equal(1)
	assert_float(CombatTestKit.hp(w, tgt)).is_equal(70.0)
	assert_bool(w.projectiles().alive(f)).is_false()


func test_flak_bursts_early_within_12m_of_a_hostile_ship_once_armed() -> void:
	var w: SimWorld = CombatTestKit.world()
	var tgt: int = CombatTestKit.spawn(w, &"dart", 0, 0, _at(500.0, 15.0))   # centre 15 m: within 12 + 6
	var f: int = _shot(w, ProjectileStore.FLAK, &"flak_shell", &"flak_gun", _at(500.0), Vector3.ZERO, 0, 1.0)
	var green: int = _shot(w, ProjectileStore.FLAK, &"flak_shell", &"flak_gun", _at(500.0, 0.0, 300.0),
		Vector3.ZERO, 0, 0.0)
	var _green_tgt: int = CombatTestKit.spawn(w, &"dart", 0, 0, _at(500.0, 15.0, 300.0))
	var _e: Array[SimEvent] = _step(w)
	assert_bool(w.projectiles().alive(f)).is_false()
	assert_float(CombatTestKit.hp(w, tgt)).is_equal(70.0)
	assert_bool(w.projectiles().alive(green)).is_true()        # arm_s 0.5 not reached


func test_flak_never_bursts_on_friendly_ships() -> void:
	var w: SimWorld = CombatTestKit.world()
	var mate: int = CombatTestKit.spawn(w, &"dart", 1, 1, _at(500.0, 15.0))
	var full: float = CombatTestKit.hp(w, mate)
	var f: int = _shot(w, ProjectileStore.FLAK, &"flak_shell", &"flak_gun", _at(500.0), Vector3.ZERO, 0, 1.0)
	var _e: Array[SimEvent] = _step(w)
	assert_bool(w.projectiles().alive(f)).is_true()
	assert_float(CombatTestKit.hp(w, mate)).is_equal(full)


func test_flak_battery_fuses_for_the_closest_approach_plus_delay() -> void:
	var w: SimWorld = CombatTestKit.world()
	CombatTestKit.power(w, 1, 1)
	var flak: int = CombatTestKit.spawn(w, &"flak_battery", 1, 1, _at(0.0))
	var tgt: int = CombatTestKit.spawn(w, &"dart", 0, 0, _at(400.0, 600.0))
	FireTestKit.hook(w).hold(flak, PilotInput.FIRE1)
	w.step()
	var mine: PackedInt32Array = FireTestKit.fired_by(w, flak)
	assert_int(mine.size()).is_equal(2)
	var ps: ProjectileStore = w.projectiles()
	for i: int in mine:
		assert_int(ps.kind[i]).is_equal(ProjectileStore.FLAK)
		var dp: Vector3 = w.store().pos[EntityId.slot(tgt)] - ps.pos[i]
		var dv: Vector3 = w.store().vel[EntityId.slot(tgt)] - ps.vel[i]
		var tc: float = -dp.dot(dv) / dv.length_squared()
		var want: int = w.tick() + clampi(roundi((tc + _flak_delay()) * 30.0), 15, 149)
		assert_int(ps.target[i]).is_equal(want)
		assert_int(ps.target[i]).is_greater(w.tick())


func test_flak_without_a_target_bursts_at_the_end_of_its_life() -> void:
	var w: SimWorld = CombatTestKit.world()
	CombatTestKit.power(w, 1, 1)
	var flak: int = CombatTestKit.spawn(w, &"flak_battery", 1, 1, _at(0.0))
	FireTestKit.hook(w).hold(flak, PilotInput.FIRE1)
	w.step()
	var mine: PackedInt32Array = FireTestKit.fired_by(w, flak)
	assert_int(mine.size()).is_equal(2)
	assert_int(w.projectiles().target[mine[0]]).is_equal(w.tick() + 149)   # 5.0 s life, one tick short
