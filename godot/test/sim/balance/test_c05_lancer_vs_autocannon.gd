extends GdUnitTestSuite
## C-05 (02 s18.3, s4.1): a Lancer engaging an Autocannon Turret from 800 m (gun range 800 m, rockets 1,500 m, against the
## turret's 700 m) destroys it in under 25 s and takes no damage (`C05Rig`: the Lancer pinned level at 100 m over the
## turret with FIRE1 + FIRE2 held, the turret under the real TowerBrain). Control: the same Lancer 500 m out is inside the
## turret's reach, which then fires and hurts it, so the zero-damage result is the range, not a dead turret.

const SEEDS: int = 10
const KILL_MAX_S: float = 25.0
const HZ: int = 30


func _turret_range() -> float:
	for wd: WeaponDef in Ai17Kit.content().weapons:
		if wd.id == &"gun_turret":
			return wd.range_m
	return 0.0


func _lancer_gun_range() -> float:
	for wd: WeaponDef in Ai17Kit.content().weapons:
		if wd.id == &"gun_lancer":
			return wd.range_m
	return 0.0


func test_c05_the_standoff_distance_is_inside_the_lancer_gun_and_outside_the_turret() -> void:
	assert_float(_turret_range()).is_less(800.0)
	assert_float(_lancer_gun_range()).is_greater_equal(800.0)


func test_c05_a_lancer_at_800_m_destroys_the_autocannon_in_under_25_s_and_takes_no_damage() -> void:
	for sd: int in range(1, SEEDS + 1):
		var r: C05Rig = C05Rig.new()
		r.build(sd, 800.0)
		r.run()
		var what: String = "seed %d: kill tick %d, lancer hp %.2f, turret rounds %d" % [sd, r.kill_tick, r.min_hp01, r.turret_shots]
		assert_bool(r.kill_tick >= 0 and r.kill_tick < int(KILL_MAX_S) * HZ).override_failure_message(what).is_true()
		assert_float(r.min_hp01).override_failure_message(what).is_equal(1.0)
		assert_int(r.turret_shots).override_failure_message(what).is_equal(0)


func test_c05_control_the_lancer_500_m_out_is_shot_at_and_hurt() -> void:
	var hurt: int = 0
	for sd: int in range(1, SEEDS + 1):
		var r: C05Rig = C05Rig.new()
		r.build(sd, 500.0)
		r.run()
		assert_int(r.turret_shots).override_failure_message("seed %d: the turret never fired at 500 m" % sd).is_greater(0)
		hurt += 1 if r.min_hp01 < 1.0 else 0
	assert_int(hurt).is_equal(SEEDS)


func test_c05_is_deterministic() -> void:
	var a: C05Rig = C05Rig.new()
	a.build(4, 800.0)
	a.run()
	var b: C05Rig = C05Rig.new()
	b.build(4, 800.0)
	b.run()
	assert_int(a.kill_tick).is_equal(b.kill_tick)
	assert_bool(a.w.serialize() == b.w.serialize()).is_true()
