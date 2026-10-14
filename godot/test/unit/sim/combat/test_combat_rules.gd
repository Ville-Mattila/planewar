extends GdUnitTestSuite
## Combat.roll_gun_damage (02 s4.3 rule 1, GD-08): the gun roll distribution, the structure and ground multipliers,
## the minimum of 1, no draw for a point range, doctrine factors folded into the resolved def and never applied
## twice (A-3: Foundry's x0.85 is ship mounts only), and determinism of the roll stream. Pure; no world.

const ROLLS: int = 90000


func _dart() -> WeaponDef:
	return CombatTestKit.weapon(&"", &"gun_dart")


func test_gun_roll_is_uniform_over_the_def_range() -> void:
	var w: WeaponDef = _dart()
	var rng: Rng = Rng.new(11)
	var counts: PackedInt32Array = PackedInt32Array()
	assert_int(counts.resize(w.damage_max + 1)).is_equal(OK)
	var sum: int = 0
	for _i: int in ROLLS:
		var d: int = Combat.roll_gun_damage(w, EntityStore.K_SHIP, rng)
		counts[d] += 1
		sum += d
	var span: int = w.damage_max - w.damage_min + 1
	var expect: float = float(ROLLS) / float(span)
	for v: int in range(0, w.damage_max + 1):
		if v < w.damage_min:
			assert_int(counts[v]).is_equal(0)
		else:
			assert_float(float(counts[v])).is_between(expect * 0.94, expect * 1.06)
	assert_float(float(sum) / float(ROLLS)).is_equal_approx(float(w.damage_min + w.damage_max) * 0.5, 0.05)


func test_structure_multiplier_rounds_and_floors_at_one() -> void:
	var w: WeaponDef = _dart()
	var a: Rng = Rng.new(5)
	var b: Rng = Rng.new(5)
	for _i: int in 2000:
		var raw: int = b.range_i(w.damage_min, w.damage_max)
		var d: int = Combat.roll_gun_damage(w, EntityStore.K_STRUCTURE, a)
		assert_int(d).is_equal(maxi(roundi(float(raw) * w.structure_mult), 1))
		assert_int(d).is_between(1, 2)                       # 6..14 x 0.15 = 0.9 .. 2.1


func test_lancer_structure_multiplier_is_035() -> void:
	var w: WeaponDef = CombatTestKit.weapon(&"", &"gun_lancer")
	var rng: Rng = Rng.new(6)
	for _i: int in 2000:
		assert_int(Combat.roll_gun_damage(w, EntityStore.K_STRUCTURE, rng)).is_between(3, 6)   # 8..16 x 0.35


func test_ground_multiplier_applies_to_ground_units_only() -> void:
	var w: WeaponDef = _dart()
	w.ground_mult = 0.5
	w.structure_mult = 3.0
	var rng: Rng = Rng.new(8)
	for _i: int in 500:
		assert_int(Combat.roll_gun_damage(w, EntityStore.K_GROUND, rng)).is_between(3, 7)      # 6..14 x 0.5
	for _i: int in 500:
		assert_int(Combat.roll_gun_damage(w, EntityStore.K_SHIP, rng)).is_between(6, 14)       # no multiplier


func test_ships_take_the_unscaled_roll() -> void:
	var w: WeaponDef = _dart()
	var a: Rng = Rng.new(2)
	var b: Rng = Rng.new(2)
	for _i: int in 200:
		var raw: int = b.range_i(w.damage_min, w.damage_max)
		assert_int(Combat.roll_gun_damage(w, EntityStore.K_SHIP, a)).is_equal(raw)


func test_point_range_draws_nothing_from_the_rng() -> void:
	var bomb: WeaponDef = CombatTestKit.weapon(&"", &"bomb")
	var rail: WeaponDef = CombatTestKit.weapon(&"", &"rail_gun")
	var rng: Rng = Rng.new(3)
	var before: PackedByteArray = rng.state()
	assert_int(Combat.roll_gun_damage(bomb, EntityStore.K_STRUCTURE, rng)).is_equal(400)
	assert_int(Combat.roll_gun_damage(rail, EntityStore.K_SHIP, rng)).is_equal(250)
	assert_bool(rng.state() == before).is_true()


func test_extra_multiplier_is_applied_before_the_single_rounding() -> void:
	var bomb: WeaponDef = CombatTestKit.weapon(&"", &"bomb")
	assert_int(Combat.roll_gun_damage(bomb, EntityStore.K_STRUCTURE, Rng.new(1), 0.25)).is_equal(100)
	assert_int(Combat.roll_gun_damage(bomb, EntityStore.K_STRUCTURE, Rng.new(1), 1.25)).is_equal(500)


func test_foundry_folds_its_factor_into_ship_mounts_once() -> void:
	var base: WeaponDef = _dart()
	var fnd: WeaponDef = CombatTestKit.weapon(&"foundry", &"gun_dart")
	assert_int(fnd.damage_min).is_equal(roundi(float(base.damage_min) * 0.85))       # 5
	assert_int(fnd.damage_max).is_equal(roundi(float(base.damage_max) * 0.85))       # 12
	var rng: Rng = Rng.new(21)
	var sum: int = 0
	var hi: int = 0
	for _i: int in 20000:
		var d: int = Combat.roll_gun_damage(fnd, EntityStore.K_SHIP, rng)
		assert_int(d).is_between(fnd.damage_min, fnd.damage_max)
		sum += d
		hi = maxi(hi, d)
	assert_int(hi).is_equal(fnd.damage_max)
	assert_float(float(sum) / 20000.0).is_equal_approx(float(fnd.damage_min + fnd.damage_max) * 0.5, 0.1)
	assert_int(_dart().damage_max).is_equal(base.damage_max)                           # base def untouched


func test_foundry_leaves_ground_mounted_siege_gun_alone() -> void:
	var siege: WeaponDef = CombatTestKit.weapon(&"foundry", &"siege_gun")
	assert_int(siege.damage_min).is_equal(CombatTestKit.weapon(&"", &"siege_gun").damage_min)
	assert_int(siege.damage_max).is_equal(120)


func test_the_roll_stream_is_a_function_of_seed_and_call_order() -> void:
	var w: WeaponDef = _dart()
	var a: Rng = Rng.new(99)
	var b: Rng = Rng.new(99)
	var c: Rng = Rng.new(100)
	var same: bool = true
	var diff: bool = false
	for _i: int in 500:
		var da: int = Combat.roll_gun_damage(w, EntityStore.K_SHIP, a)
		same = same and da == Combat.roll_gun_damage(w, EntityStore.K_SHIP, b)
		diff = diff or da != Combat.roll_gun_damage(w, EntityStore.K_SHIP, c)
	assert_bool(same).is_true()
	assert_bool(diff).is_true()


func test_rect_distance_is_zero_on_the_footprint_and_euclidean_off_it() -> void:
	var fwd: Vector3 = Vector3(0, 1, 0)
	var up: Vector3 = Vector3(1, 0, 0)                          # right = fwd x up = (0, 0, -1)
	assert_float(Blast.rect_distance(Vector3.ZERO, fwd, up, 10.0, 20.0)).is_equal(0.0)
	assert_float(Blast.rect_distance(Vector3(0, 20, 0), fwd, up, 10.0, 20.0)).is_equal(0.0)
	assert_float(Blast.rect_distance(Vector3(0, 35, 0), fwd, up, 10.0, 20.0)).is_equal_approx(15.0, 0.0001)
	assert_float(Blast.rect_distance(Vector3(0, 0, 10), fwd, up, 10.0, 20.0)).is_equal(0.0)
	assert_float(Blast.rect_distance(Vector3(0, 0, -13), fwd, up, 10.0, 20.0)).is_equal_approx(3.0, 0.0001)
	assert_float(Blast.rect_distance(Vector3(0, 23, -14), fwd, up, 10.0, 20.0)).is_equal_approx(5.0, 0.0001)
	assert_float(Blast.rect_distance(Vector3(12, 0, 0), fwd, up, 10.0, 20.0)).is_equal_approx(12.0, 0.0001)
