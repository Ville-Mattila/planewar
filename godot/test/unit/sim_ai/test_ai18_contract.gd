extends GdUnitTestSuite
## AI-18 contract tests (sim_ai/brains/MODULE.md CR1-CR5, sim_ai/MODULE.md AiBrain): `CrawlerParams` from the shipped
## `ap_crawler` (the required `follow` block, R0 B.29 A-145; the required 12-key `siege` block, R0 B.33 A-161, and its band check), the
## `AiBrain` impact hooks' defaults, and `SiegeAim` (the lofted solve of R0 B.25 A-74, the ring, the heading error).

const R: float = Sphere.PLANET_RADIUS


func _ap() -> Dictionary:
	return Ai18Kit.ap().duplicate(true)


func test_the_shipped_ap_crawler_builds_the_params_with_the_05_band() -> void:
	var p: CrawlerParams = CrawlerParams.from_content(Ai18Kit.content(), _ap(), Ai18Kit.def())
	assert_object(p).is_not_null()
	assert_float(p.spot_min_m).is_equal(1000.0)
	assert_float(p.spot_max_m).is_equal(1150.0)
	assert_float(p.spot_mid_m).is_equal(1075.0)
	assert_float(p.slope_max_deg).is_equal(10.0)
	assert_float(p.relocate_m).is_equal(60.0)
	assert_float(p.range_m).is_equal(1200.0)
	assert_float(p.range_min_m).is_equal(300.0)
	assert_float(p.speed).is_equal(110.0)
	assert_float(p.ground.lookahead_m).is_equal(40.0)                          # the follow block (A-145)
	assert_int(p.ground.aim_every_ticks).is_equal(4)
	assert_bool(p.in_band(1075.0)).is_true()
	assert_bool(p.in_band(999.0)).is_false()


func test_follow_and_the_full_siege_block_are_required_and_checked() -> void:
	var c: ContentSet = Ai18Kit.content()
	var no_follow: Dictionary = _ap()
	var _e: bool = no_follow.erase("follow")
	assert_object(CrawlerParams.from_content(c, no_follow, Ai18Kit.def())).is_null()
	var bad_follow: Dictionary = _ap()
	var _e2: bool = (bad_follow["follow"] as Dictionary).erase("arrive_m")
	assert_object(CrawlerParams.from_content(c, bad_follow, Ai18Kit.def())).is_null()
	var no_block: Dictionary = _ap()                                               # R0 B.33 A-161: the block is required
	var _e3: bool = no_block.erase("siege")
	assert_object(CrawlerParams.from_content(c, no_block, Ai18Kit.def())).is_null()
	var own: Dictionary = _ap()
	own["siege"] = {"spot_min_m": 900, "spot_max_m": 1100, "spot_slope_deg": 8, "relocate_bomb_m": 80, "relocate_step_m": 120,
		"aim_tol_deg": 2, "spot_samples": 12, "loft_tol_m": 10, "solve_tol_m": 3, "loft_iters": 5, "solve_step_ticks": 1,
		"relocate_tries": 4}
	var p: CrawlerParams = CrawlerParams.from_content(c, own, Ai18Kit.def())
	assert_float(p.spot_mid_m).is_equal(1000.0)
	assert_float(p.relocate_m).is_equal(80.0)
	assert_float(p.slope_max_deg).is_equal(8.0)
	assert_int(p.samples).is_equal(12)
	assert_int(p.loft_iters).is_equal(5)
	assert_int(p.solve_step_ticks).is_equal(1)
	assert_int(p.relocate_tries).is_equal(4)
	assert_int(p.max_steps).is_equal(ceili(p.shell.lifetime_s / p.dt))              # one-tick step
	var full: Dictionary = (own["siege"] as Dictionary)
	for key: String in CrawlerParams.SIEGE_KEYS:                                   # a missing key, or a key <= 0, refuses
		var miss: Dictionary = own.duplicate(true)
		var _e4: bool = (miss["siege"] as Dictionary).erase(key)
		assert_object(CrawlerParams.from_content(c, miss, Ai18Kit.def())).override_failure_message("missing " + key).is_null()
		var zero: Dictionary = own.duplicate(true)
		(zero["siege"] as Dictionary)[key] = 0
		assert_object(CrawlerParams.from_content(c, zero, Ai18Kit.def())).override_failure_message("zero " + key).is_null()
	assert_int(full.size()).is_equal(CrawlerParams.SIEGE_KEYS.size())
	for bad: Dictionary in [{"spot_max_m": 1300}, {"spot_min_m": 200}, {"spot_min_m": 1100, "spot_max_m": 1000}, {"aim_tol_deg": 0}]:
		var ap: Dictionary = own.duplicate(true)
		(ap["siege"] as Dictionary).merge(bad, true)
		assert_object(CrawlerParams.from_content(c, ap, Ai18Kit.def())).is_null()


func test_the_crawler_brain_needs_a_terrain_and_the_base_brain_hears_no_impacts() -> void:
	assert_object(CrawlerBrain.create(Ai18Kit.content(), _ap(), Ai18Kit.def(), null)).is_null()
	var b: CrawlerBrain = CrawlerBrain.create(Ai18Kit.content(), _ap(), Ai18Kit.def(), Terrain.new())
	assert_bool(b.hears_impacts()).is_true()
	var base: AiBrain = AiBrain.new()
	assert_bool(base.hears_impacts()).is_false()
	assert_bool(base.on_impact(5, SimEvent.new(), AiState.new())).is_false()


func test_on_impact_marks_only_an_enemy_bomb_within_relocate_m_of_a_sieging_crawler() -> void:
	var b: CrawlerBrain = Ai18Kit.brain(Terrain.new())
	var st: AiState = AiState.new()
	var id: int = EntityId.make(7, 1)
	var s: int = EntityId.slot(id)
	st.aim_lead[s] = Vector3(R, 0, 0)
	st.sub[s] = 1                                                                # team 0
	var ev: SimEvent = SimEvent.new()
	ev.kind = SimEvent.Kind.BOMB_IMPACT
	ev.team = 1
	ev.pos = Vector3(R, 40.0, 0)
	st.mode[s] = AiTag.Tag.HOLD
	assert_bool(b.on_impact(id, ev, st)).is_false()                             # not sieging
	st.mode[s] = AiTag.Tag.SIEGE
	ev.team = 0
	assert_bool(b.on_impact(id, ev, st)).is_false()                             # friendly
	ev.team = 1
	ev.pos = Vector3(R, 70.0, 0)
	assert_bool(b.on_impact(id, ev, st)).is_false()                             # beyond 60 m
	ev.pos = Vector3(R, 40.0, 0)
	assert_bool(b.on_impact(id, ev, st)).is_true()
	assert_int(st.bflags[s] & CrawlerBrain.B_BLAST).is_equal(CrawlerBrain.B_BLAST)
	assert_vector(st.land_mark[s]).is_equal(ev.pos)


func test_loft_lands_a_siege_shell_on_the_aim_point_on_the_datum() -> void:
	# AI-18b: the solve flies the shell the sim fires (BarrelSlew.muzzle_dir, muzzle at p + dir x radius); checked here at
	# the sim's 1-tick step from that muzzle, so the old 1.7-2.1 m muzzle bias would show.
	var c: ContentSet = Ai18Kit.content()
	var p: CrawlerParams = CrawlerParams.from_content(c, _ap(), Ai18Kit.def())
	var t: Terrain = Terrain.new()
	var st: ProjectileState = ProjectileState.new()
	var pos: Vector3 = Ai16Kit.dir_at(0.0) * (R + 7.0)
	for want: float in [400.0, 1000.0, 1075.0, 1150.0]:
		var aim: Vector3 = Ai16Kit.dir_at(want) * R
		var e: float = SiegeAim.loft(pos, aim, p, t, st)
		assert_bool(is_nan(e)).is_false()
		assert_float(e).is_between(p.barrel_lo, p.barrel_hi)                        # inside the barrel's limits
		var n: Vector3 = pos.normalized()
		var dir: Vector3 = BarrelSlew.muzzle_dir(pos, SiegeAim.tangent_to(pos, aim), e)
		var r: Vector4 = Ballistics.predict_impact(pos + dir * p.radius, dir * p.speed, p.shell, c.rules, t, p.dt, p.dt, 0.0,
			4 * p.max_steps, st)
		var miss: float = absf(SiegeAim.arc(n, Vector3(r.x, r.y, r.z)) - want)
		assert_float(miss).override_failure_message("%.0f m: miss %.2f m" % [want, miss]).is_less(p.solve_tol_m + 2.0)   # + the 2-tick step
	var far: Vector3 = Ai16Kit.dir_at(3000.0) * R                                  # g d > v^2: beyond any elevation
	assert_bool(is_nan(SiegeAim.loft(pos, far, p, t, st))).is_true()
	var low: CrawlerParams = CrawlerParams.from_content(c, _ap(), Ai18Kit.def())
	low.barrel_hi = deg_to_rad(5.0)                                                # a 5 deg barrel cannot reach 1,075 m
	assert_bool(is_nan(SiegeAim.loft(pos, Ai16Kit.dir_at(1075.0) * R, low, t, st))).is_true()


func test_the_params_carry_the_barrel_and_turn_rate_and_refuse_a_def_without_a_barrel() -> void:
	var c: ContentSet = Ai18Kit.content()
	var p: CrawlerParams = CrawlerParams.from_content(c, _ap(), Ai18Kit.def())
	assert_float(p.barrel_rate).is_equal_approx(deg_to_rad(10.0), 1e-12)          # ground_units.json (R0 B.31 A-151)
	assert_float(p.barrel_lo).is_equal(0.0)
	assert_float(p.barrel_hi).is_equal_approx(deg_to_rad(45.0), 1e-12)
	assert_float(p.turn_rate).is_equal_approx(deg_to_rad(c.ground_common.ground_turn_rate_dps), 1e-12)
	assert_float(p.solve_tol_m).is_equal(2.0)
	var orig: GroundUnitDef = Ai18Kit.def()
	var bare: GroundUnitDef = GroundUnitDef.new()                                  # the typed barrel fields (CONTENT-5), not raw
	bare.weapon = orig.weapon
	bare.max_slope_deg = orig.max_slope_deg
	bare.bounding_radius = orig.bounding_radius
	bare.barrel_slew_dps = orig.barrel_slew_dps
	bare.barrel_min_deg = orig.barrel_min_deg
	bare.barrel_max_deg = orig.barrel_max_deg
	assert_object(CrawlerParams.from_content(c, _ap(), bare)).is_not_null()
	bare.barrel_slew_dps = 0.0
	assert_object(CrawlerParams.from_content(c, _ap(), bare)).is_null()
	var loose: Dictionary = _ap()
	(loose["siege"] as Dictionary)["solve_tol_m"] = 20                             # above loft_tol_m 15
	assert_object(CrawlerParams.from_content(c, loose, Ai18Kit.def())).is_null()


func test_ring_point_and_heading_error() -> void:
	var c: Vector3 = Ai16Kit.dir_at(0.0)
	var bearing: Vector3 = SiegeAim.tangent_to(c * R, Ai16Kit.dir_at(100.0) * R)
	var q: Vector3 = SiegeAim.ring_point(c, bearing, 0.0, 1075.0)
	assert_float(SiegeAim.arc(c, q * R)).is_equal_approx(1075.0, 0.01)
	assert_float(q.distance_to(Ai16Kit.dir_at(1075.0))).is_less(1e-6)
	var left: Vector3 = SiegeAim.ring_point(c, bearing, 0.5 * PI, 1075.0)
	assert_float(left.z).is_greater(0.0)                                            # + turn = counter-clockwise (toward +Z = north)
	var p: Vector3 = Ai16Kit.dir_at(0.0) * R
	var fwd: Vector3 = SiegeAim.tangent_to(p, Ai16Kit.dir_at(100.0) * R)
	assert_float(SiegeAim.heading_error(p, fwd, Ai16Kit.dir_at(100.0, 100.0) * R)).is_equal_approx(0.25 * PI, 0.01)   # left = +
	assert_float(SiegeAim.heading_error(p, fwd, Ai16Kit.dir_at(100.0, -100.0) * R)).is_equal_approx(-0.25 * PI, 0.01)


# AI-18b on relief (cradle, the GD-50 spot): from a snapped Crawler, the solve's elevation flown at the sim's one-tick step
# from the sim's muzzle lands within loft_tol_m of aim points 1,000-1,150 m out on four bearings; a NAN (a ridge in the
# way, the lifetime) is allowed but most aims solve.
func test_loft_on_cradle_relief_lands_within_loft_tol_of_the_aim_point() -> void:
	var c: ContentSet = Ai18Kit.content()
	var p: CrawlerParams = CrawlerParams.from_content(c, _ap(), Ai18Kit.def())
	var w: SimWorld = BarrelTestKit.world(null, &"cradle")
	var id: int = BarrelTestKit.crawler(w, Sphere.from_lat_lon(0.1, 0.2, 1.0))
	var s: int = EntityId.slot(id)
	var pos: Vector3 = w.store().pos[s]
	var n: Vector3 = pos.normalized()
	var st: ProjectileState = ProjectileState.new()
	var solved: int = 0
	var worst: float = 0.0
	for k: int in 4:
		var fwd: Vector3 = Quaternion(n, 0.5 * PI * float(k)) * w.store().fwd[s]
		for d: float in [1000.0, 1075.0, 1150.0]:
			var a: Vector3 = BarrelTestKit.ahead(pos, fwd, d)
			var aim: Vector3 = a * (R + w.terrain().height_at(a))
			var e: float = SiegeAim.loft(pos, aim, p, w.terrain(), st)
			if is_nan(e):
				continue
			solved += 1
			var dir: Vector3 = BarrelSlew.muzzle_dir(pos, SiegeAim.tangent_to(pos, aim), e)
			var r: Vector4 = BarrelTestKit.predict_from(w, pos + dir * p.radius, dir * p.speed)
			assert_bool(Ballistics.has_impact(r)).is_true()
			worst = maxf(worst, SiegeAim.arc(a, Vector3(r.x, r.y, r.z)))
	assert_int(solved).is_greater_equal(9)
	assert_float(worst).is_less_equal(p.loft_tol_m)
	print("AI-18b loft on cradle: %d of 12 aims solved, worst miss %.2f m" % [solved, worst])
