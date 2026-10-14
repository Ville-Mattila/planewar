extends GdUnitTestSuite
## Unit tests for sim/collision.gd (03 s6.1, s6.4, R0 B.9 A-30 / A-31, TA-14): swept projectile hits and their
## filters, 8b ground contact behind the relief prefilter, the ship-terrain classification table from
## flight_common, the scrape episode rule, per-tick pad-volume landing evaluation, rams.

const R: float = Sphere.PLANET_RADIUS
const MAP_WORLD: String = "res://content/maps/s_world1_r6000"

var _kit: CollisionTestKit


func before_test() -> void:
	_kit = CollisionTestKit.new()


func _at(alt: float, east: float = 0.0) -> Vector3:
	var base: Vector3 = Vector3(R + alt, 0.0, 0.0)
	return base + Vector3(0.0, east, 0.0)


# region pure helpers
func test_sweep_sphere_entry_parameter() -> void:
	var c: Vector3 = Vector3(10.0, 0.0, 0.0)
	assert_float(Collision.sweep_sphere(Vector3.ZERO, Vector3(20.0, 0.0, 0.0), c, 2.0)).is_equal_approx(0.4, 1e-6)
	assert_float(Collision.sweep_sphere(Vector3(10.0, 1.0, 0.0), Vector3(30.0, 1.0, 0.0), c, 2.0)).is_equal(0.0)
	assert_float(Collision.sweep_sphere(Vector3.ZERO, Vector3(5.0, 0.0, 0.0), c, 2.0)).is_equal(-1.0)
	assert_float(Collision.sweep_sphere(Vector3.ZERO, Vector3(20.0, 2.5, 0.0), c, 1.0)).is_equal(-1.0)
	assert_float(Collision.sweep_sphere(Vector3(20.0, 0.0, 0.0), Vector3(40.0, 0.0, 0.0), c, 2.0)).is_equal(-1.0)
	assert_float(Collision.sweep_sphere(Vector3.ZERO, Vector3.ZERO, c, 2.0)).is_equal(-1.0)


func test_terrain_classification_table_from_flight_common() -> void:
	var c: FlightCommonDef = _kit.common
	var dmg: float = c.terrain_damage_speed
	var kill: float = c.terrain_kill_speed
	var rows: Array = [[0.0, Collision.T_SCRAPE], [dmg - 0.1, Collision.T_SCRAPE], [dmg, Collision.T_SCRAPE],
		[dmg + 0.1, Collision.T_DAMAGE], [kill - 0.1, Collision.T_DAMAGE], [kill, Collision.T_DAMAGE],
		[kill + 0.1, Collision.T_DESTROY], [kill * 4.0, Collision.T_DESTROY]]
	for row: Array in rows:
		assert_int(Collision.classify_terrain(row[0] as float, c)).is_equal(row[1] as int)


func test_landing_band_table_from_flight_common() -> void:
	var c: FlightCommonDef = _kit.common
	var sv: float = c.landing_safe_v_vert
	var sh: float = c.landing_safe_v_hor
	var st: float = c.landing_safe_pitch_deg
	assert_int(Collision.landing_band(sv, sh, st, c)).is_equal(Collision.L_SAFE)
	assert_int(Collision.landing_band(-20.0, 0.0, 0.0, c)).is_equal(Collision.L_SAFE)     # climbing away
	assert_int(Collision.landing_band(sv + 0.1, 0.0, 0.0, c)).is_equal(Collision.L_DAMAGE)
	assert_int(Collision.landing_band(0.0, sh + 0.1, 0.0, c)).is_equal(Collision.L_DAMAGE)
	assert_int(Collision.landing_band(0.0, 0.0, st + 0.1, c)).is_equal(Collision.L_DAMAGE)
	assert_int(Collision.landing_band(c.landing_damage_v_vert, c.landing_damage_v_hor, c.landing_damage_tilt_deg, c)).is_equal(Collision.L_DAMAGE)
	assert_int(Collision.landing_band(c.landing_damage_v_vert + 0.1, 0.0, 0.0, c)).is_equal(Collision.L_DESTROY)
	assert_int(Collision.landing_band(0.0, c.landing_damage_v_hor + 0.1, 0.0, c)).is_equal(Collision.L_DESTROY)
	assert_int(Collision.landing_band(0.0, 0.0, c.landing_damage_tilt_deg + 0.1, c)).is_equal(Collision.L_DESTROY)
# endregion


# region 8: projectile vs entity
func test_earliest_entry_wins_and_records_point() -> void:
	var near: int = _kit.entity(EntityStore.K_SHIP, _at(300.0, 20.0), 6.0, 1)
	var _far: int = _kit.entity(EntityStore.K_SHIP, _at(300.0, 40.0), 6.0, 1)
	var i: int = _kit.projectile("slug_light", _at(300.0, 0.0), Vector3.ZERO, 0)
	_kit.proj.pos[i] = _at(300.0, 60.0)
	_kit.detect(1)
	assert_int(_kit.count(Collision.C_HIT)).is_equal(1)
	var k: int = _kit.first(Collision.C_HIT)
	assert_int(_kit.collision.c_a[k]).is_equal(_kit.proj.id_of(i))
	assert_int(_kit.collision.c_b[k]).is_equal(_kit.store.id_of(near))
	assert_float(_kit.collision.c_value[k]).is_equal_approx((20.0 - 6.5) / 60.0, 1e-4)
	assert_vector(_kit.collision.c_point[k]).is_equal_approx(_at(300.0, 13.5), Vector3.ONE * 1e-3)


func test_hit_filters_team_wreck_and_friendly_fire() -> void:
	var friend: int = _kit.entity(EntityStore.K_SHIP, _at(300.0, 10.0), 6.0, 0)
	var _wreck: int = _kit.entity(EntityStore.K_WRECK, _at(300.0, 25.0), 6.0, 1)
	var i: int = _kit.projectile("slug_light", _at(300.0, 0.0), Vector3.ZERO, 0)
	_kit.proj.pos[i] = _at(300.0, 40.0)
	_kit.detect(1)
	assert_int(_kit.count(Collision.C_HIT)).is_equal(0)
	_kit.collision.friendly_fire = true
	_kit.detect(2)
	assert_int(_kit.collision.c_b[_kit.first(Collision.C_HIT)]).is_equal(_kit.store.id_of(friend))


func test_shooter_is_skipped_for_grace_ticks_only() -> void:
	_kit.collision.friendly_fire = true
	_kit.collision.shooter_grace_ticks = 10
	var me: int = _kit.entity(EntityStore.K_SHIP, _at(300.0, 10.0), 6.0, 0)
	var i: int = _kit.projectile("slug_light", _at(300.0, 0.0), Vector3.ZERO, 0, _kit.store.id_of(me))
	_kit.proj.pos[i] = _at(300.0, 20.0)
	for t: int in range(5, 15):
		_kit.detect(t)
		assert_int(_kit.count(Collision.C_HIT)).is_equal(0)
	_kit.detect(15)
	assert_int(_kit.count(Collision.C_HIT)).is_equal(1)


func test_ground_units_and_structures_are_hit() -> void:
	var g: int = _kit.entity(EntityStore.K_GROUND, _at(5.0, 10.0), 4.5, 1)
	var s: int = _kit.entity(EntityStore.K_STRUCTURE, _at(5.0, 200.0), 20.0, 1)
	var a: int = _kit.projectile("slug_light", _at(5.0, 0.0), Vector3.ZERO, 0)
	_kit.proj.pos[a] = _at(5.0, 20.0)
	var b: int = _kit.projectile("slug_light", _at(5.0, 160.0), Vector3.ZERO, 0)
	_kit.proj.pos[b] = _at(5.0, 190.0)
	_kit.detect(1)
	assert_int(_kit.count(Collision.C_HIT)).is_equal(2)
	assert_int(_kit.collision.c_b[0]).is_equal(_kit.store.id_of(g))
	assert_int(_kit.collision.c_b[1]).is_equal(_kit.store.id_of(s))
# endregion


# region 8b: projectile vs terrain
func test_ground_contact_on_map_and_prefilter_skips_every_high_projectile() -> void:
	var kit: CollisionTestKit = CollisionTestKit.new(MAP_WORLD)
	var rng: Rng = Rng.new(8)
	var low: int = 0
	var below: PackedInt32Array = PackedInt32Array()
	for k: int in 600:
		var d: Vector3 = Vector3(rng.range_f(-1.0, 1.0), rng.range_f(-1.0, 1.0), rng.range_f(-1.0, 1.0)).normalized()
		var h: float = kit.terrain.height_at(d)
		var alt: float
		match k % 3:
			0: alt = Sphere.RELIEF_MAX + rng.range_f(0.6, 1500.0)    # above the prefilter: never sampled
			1: alt = h + rng.range_f(0.6, 50.0)                         # low but clear of the ground
			_: alt = h + rng.range_f(-20.0, 0.4)                        # inside slug radius of the ground
		if R + alt <= R + Sphere.RELIEF_MAX + 0.5:
			low += 1
		var i: int = kit.projectile("slug_light", d * (R + alt), Vector3.ZERO, 0)
		if k % 3 == 2:
			var _a: bool = below.push_back(kit.proj.id_of(i))
	kit.detect(1)
	assert_int(kit.collision.prefilter_passed).is_equal(low)                # every high projectile skipped
	assert_int(kit.collision.terrain_samples).is_less_equal(low)
	assert_int(kit.collision.terrain_samples).is_greater_equal(below.size())
	assert_int(kit.count(Collision.C_GROUND)).is_equal(below.size())
	for k: int in kit.collision.contact_count:
		assert_bool(below.has(kit.collision.c_a[k])).is_true()
		var p: Vector3 = kit.collision.c_point[k]
		assert_float(p.length() - R).is_equal_approx(kit.terrain.height_at(p), 2e-3)


func test_hit_takes_precedence_over_ground() -> void:
	var _t: int = _kit.entity(EntityStore.K_GROUND, _at(4.0, 10.0), 4.5, 1)
	var i: int = _kit.projectile("slug_light", _at(4.0, 0.0), Vector3.ZERO, 0)
	_kit.proj.pos[i] = _at(0.2, 20.0)
	_kit.detect(1)
	assert_int(_kit.count(Collision.C_HIT)).is_equal(1)
	assert_int(_kit.count(Collision.C_GROUND)).is_equal(0)
# endregion


# region ship vs terrain: the A-30 episode rule
func _terrain_contacts(s: int, pattern: PackedFloat32Array, start: int) -> Array[int]:
	var classes: Array[int] = []
	for k: int in pattern.size():
		if pattern[k] >= 0.0:
			_kit.collision.report_terrain(s, start + k, pattern[k])
		_kit.detect(start + k)
		for c: int in _kit.collision.contact_count:
			if _kit.collision.c_kind[c] == Collision.C_TERRAIN:
				classes.append(_kit.collision.c_class[c])
	return classes


func test_bounce_is_one_damage_event_per_episode() -> void:
	# A-30 acceptance: a ship bouncing for 0.7 s (21 ticks) at damage speed is hit once, not every contact tick.
	var s: int = _kit.entity(EntityStore.K_SHIP, _at(6.0), 6.0, 0)
	var hns: float = (_kit.common.terrain_damage_speed + _kit.common.terrain_kill_speed) * 0.5
	var pattern: PackedFloat32Array = PackedFloat32Array()
	for k: int in roundi(0.7 / _kit.dt):
		var _a: bool = pattern.push_back(hns if k % 4 == 0 else -1.0)
	var got: Array[int] = _terrain_contacts(s, pattern, 1)
	assert_array(got).is_equal([Collision.T_DAMAGE])


func test_episode_ends_after_scrape_clear_s() -> void:
	var s: int = _kit.entity(EntityStore.K_SHIP, _at(6.0), 6.0, 0)
	var clear: int = roundi(_kit.common.scrape_clear_s / _kit.dt)
	var scrape: float = _kit.common.terrain_damage_speed * 0.5
	var pattern: PackedFloat32Array = PackedFloat32Array([scrape])
	for _k: int in clear - 1:
		var _a: bool = pattern.push_back(-1.0)                   # gap shorter than scrape_clear_s: same episode
	var _b: bool = pattern.push_back(scrape)
	assert_array(_terrain_contacts(s, pattern, 1)).is_equal([Collision.T_SCRAPE])
	var next: int = 1 + pattern.size()
	pattern = PackedFloat32Array()
	for _k: int in clear:
		var _c: bool = pattern.push_back(-1.0)                   # exactly scrape_clear_s clear: new episode
	var _d: bool = pattern.push_back(scrape)
	assert_array(_terrain_contacts(s, pattern, next)).is_equal([Collision.T_SCRAPE])


func test_kill_speed_destroys_inside_an_episode() -> void:
	var s: int = _kit.entity(EntityStore.K_SHIP, _at(6.0), 6.0, 0)
	var scrape: float = _kit.common.terrain_damage_speed * 0.5
	var kill: float = _kit.common.terrain_kill_speed + 1.0
	var got: Array[int] = _terrain_contacts(s, PackedFloat32Array([scrape, scrape, -1.0, kill]), 1)
	assert_array(got).is_equal([Collision.T_SCRAPE, Collision.T_DESTROY])


func test_stale_or_foreign_report_is_ignored() -> void:
	var s: int = _kit.entity(EntityStore.K_SHIP, _at(6.0), 6.0, 0)
	_kit.collision.report_terrain(s, 1, 30.0)
	_kit.detect(2)                                                   # report was for tick 1
	assert_int(_kit.count(Collision.C_TERRAIN)).is_equal(0)
	_kit.collision.report_terrain(s, 3, 30.0)
	var _f: bool = _kit.store.free_slot(s, 3)                        # dead: not in the ships list
	_kit.detect(3)
	assert_int(_kit.count(Collision.C_TERRAIN)).is_equal(0)
# endregion


# region landing: the A-31 per-tick pad volume
func _pad_and_ship(team_ship: int) -> Vector2i:
	var pad: int = _kit.entity(EntityStore.K_STRUCTURE, _at(0.0), 15.0, 0, CollisionTestKit.PAD_DEF)
	var s: int = _kit.entity(EntityStore.K_SHIP, _at(6.0, 3.0), 6.0, team_ship)
	_kit.store.fwd[s] = _kit.store.up[pad]                            # tail-down, nose up
	return Vector2i(pad, s)


func test_pad_volume_is_evaluated_every_tick_while_inside() -> void:
	var ps: Vector2i = _pad_and_ship(0)
	var up: Vector3 = _kit.store.up[ps.x]
	# Sliding in from a terrain episode that began off the pad: graded every tick by current speeds.
	_kit.store.pos[ps.y] = _at(6.0, 40.0)
	_kit.store.vel[ps.y] = Vector3(0.0, -4.0, 0.0)
	_kit.collision.report_terrain(ps.y, 1, _kit.common.terrain_damage_speed * 0.5)
	_kit.detect(1)
	assert_int(_kit.count(Collision.C_PAD)).is_equal(0)
	assert_int(_kit.count(Collision.C_TERRAIN)).is_equal(1)
	for t: int in range(2, 8):
		_kit.store.pos[ps.y] = _at(6.0, 9.0 - float(t))
		_kit.collision.report_terrain(ps.y, t, 1.0)
		_kit.detect(t)
		assert_int(_kit.count(Collision.C_PAD)).is_equal(1)
		assert_int(_kit.count(Collision.C_TERRAIN)).is_equal(0)
		assert_int(_kit.count(Collision.C_RAM)).is_equal(0)          # inside the volume: a landing, not a crash
		var k: int = _kit.first(Collision.C_PAD)
		assert_int(_kit.collision.c_b[k]).is_equal(_kit.store.id_of(ps.x))
		assert_int(_kit.collision.c_class[k]).is_equal(Collision.L_SAFE)
		assert_float(_kit.collision.c_value[k]).is_equal_approx(absf(9.0 - float(t)), 1e-3)
		assert_vector(_kit.collision.c_vec[k]).is_equal_approx(Vector3(0.0, 4.0, 0.0), Vector3.ONE * 1e-3)
	assert_vector(up).is_equal(Vector3(1, 0, 0))


func test_pad_bands_from_current_speed_and_tilt() -> void:
	var ps: Vector2i = _pad_and_ship(0)
	var up: Vector3 = _kit.store.up[ps.x]
	_kit.store.vel[ps.y] = -up * (_kit.common.landing_safe_v_vert + 1.0)
	_kit.detect(1)
	assert_int(_kit.collision.c_class[_kit.first(Collision.C_PAD)]).is_equal(Collision.L_DAMAGE)
	_kit.store.vel[ps.y] = -up * (_kit.common.landing_damage_v_vert + 1.0)
	_kit.detect(2)
	assert_int(_kit.collision.c_class[_kit.first(Collision.C_PAD)]).is_equal(Collision.L_DESTROY)
	_kit.store.vel[ps.y] = Vector3.ZERO
	_kit.store.fwd[ps.y] = Sphere.tangent_frame(_at(6.0)).x                # nose level: 90 degrees off
	_kit.detect(3)
	var k: int = _kit.first(Collision.C_PAD)
	assert_float(_kit.collision.c_vec[k].z).is_equal_approx(90.0, 1e-3)
	assert_int(_kit.collision.c_class[k]).is_equal(Collision.L_DESTROY)


func test_no_pad_contact_outside_volume_enemy_pad_or_docked() -> void:
	var ps: Vector2i = _pad_and_ship(0)
	_kit.store.pos[ps.y] = _at(6.0 + 0.6, 0.0)                         # 0.1 m above radius + 0.5
	_kit.detect(1)
	assert_int(_kit.count(Collision.C_PAD)).is_equal(0)
	_kit.store.pos[ps.y] = _at(6.0, _kit.pad_radius + 0.1)               # just outside pad_radius_m
	_kit.detect(2)
	assert_int(_kit.count(Collision.C_PAD)).is_equal(0)
	_kit.store.pos[ps.y] = _at(6.0, 0.0)
	_kit.store.team[ps.y] = 1                                            # enemy pad: a ram, not a landing
	_kit.detect(3)
	assert_int(_kit.count(Collision.C_PAD)).is_equal(0)
	assert_int(_kit.count(Collision.C_RAM)).is_equal(1)
	_kit.store.team[ps.y] = 0
	_kit.store.flags[ps.y] |= EntityStore.F_DOCKED
	_kit.store.link[ps.y] = _kit.store.id_of(ps.x)
	_kit.collision.report_terrain(ps.y, 4, 1.0)
	_kit.detect(4)
	assert_int(_kit.collision.contact_count).is_equal(0)                  # docked: exempt against its own pad
# endregion


# region rams
func test_ship_pairs_ram_once_and_structures_from_the_ship_side() -> void:
	var a: int = _kit.entity(EntityStore.K_SHIP, _at(300.0, 0.0), 6.0, 0)
	var b: int = _kit.entity(EntityStore.K_SHIP, _at(300.0, 10.0), 6.0, 1)
	var _far: int = _kit.entity(EntityStore.K_SHIP, _at(300.0, 40.0), 6.0, 1)
	var st: int = _kit.entity(EntityStore.K_STRUCTURE, _at(300.0, -20.0), 15.0, 1)
	var _g: int = _kit.entity(EntityStore.K_GROUND, _at(300.0, 5.0), 4.5, 1)    # ground units collide with nothing
	_kit.detect(1)
	assert_int(_kit.count(Collision.C_RAM)).is_equal(2)
	var pairs: Array[Vector2i] = []
	for k: int in _kit.collision.contact_count:
		pairs.append(Vector2i(_kit.collision.c_a[k], _kit.collision.c_b[k]))
	assert_array(pairs).contains_exactly_in_any_order([Vector2i(_kit.store.id_of(a), _kit.store.id_of(b)),
		Vector2i(_kit.store.id_of(a), _kit.store.id_of(st))])
# endregion


func test_slug_hits_coaltitude_target() -> void:
	# C1-03 through the collision pipeline: shooter 300 m AGL, co-altitude Dart at 200 / 400 / 650 / 800 m,
	# fired along the line of sight; straight slugs (no transport, no gravity) hit every one.
	var slug: ProjectileDef = FlightTestKit.projectile(&"slug_light")
	var dart: ShipDef = FlightTestKit.ship(&"dart")
	var r_alt: float = R + 300.0
	var shooter: int = _kit.entity(EntityStore.K_SHIP, Vector3(r_alt, 0.0, 0.0), dart.bounding_radius, 0)
	for d: float in [200.0, 400.0, 650.0, 800.0]:
		var ang: float = 2.0 * asin(d / (2.0 * r_alt))
		var target: int = _kit.entity(EntityStore.K_SHIP, Vector3(cos(ang), sin(ang), 0.0) * r_alt, dart.bounding_radius, 1)
		var p0: Vector3 = _kit.store.pos[shooter]
		var i: int = _kit.projectile("slug_light", p0, (_kit.store.pos[target] - p0).normalized() * slug.speed_mps, 0,
			_kit.store.id_of(shooter))
		var hit: bool = false
		for t: int in ceili(slug.lifetime_s / _kit.dt):
			_kit.tick(t + 1, slug)
			if _kit.first(Collision.C_HIT) >= 0:
				assert_int(_kit.collision.c_b[_kit.first(Collision.C_HIT)]).is_equal(_kit.store.id_of(target))
				hit = true
				break
		assert_bool(hit).override_failure_message("missed at %.0f m" % d).is_true()
		var _f1: bool = _kit.proj.free_slot(i, 0)
		var _f2: bool = _kit.store.free_slot(target, 0)
