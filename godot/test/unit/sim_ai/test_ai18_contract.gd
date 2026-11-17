extends GdUnitTestSuite
## AI-18 contract tests (sim_ai/brains/MODULE.md CR1-CR5, sim_ai/MODULE.md AiBrain): `CrawlerParams` from the shipped
## `ap_crawler` (the required `follow` block, R0 B.29 A-145; the optional `siege` block and its band check), the
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


func test_follow_is_required_and_the_siege_block_is_optional_but_checked() -> void:
	var c: ContentSet = Ai18Kit.content()
	var no_follow: Dictionary = _ap()
	var _e: bool = no_follow.erase("follow")
	assert_object(CrawlerParams.from_content(c, no_follow, Ai18Kit.def())).is_null()
	var bad_follow: Dictionary = _ap()
	var _e2: bool = (bad_follow["follow"] as Dictionary).erase("arrive_m")
	assert_object(CrawlerParams.from_content(c, bad_follow, Ai18Kit.def())).is_null()
	var own: Dictionary = _ap()
	own["siege"] = {"spot_min_m": 900, "spot_max_m": 1100, "relocate_bomb_m": 80}
	var p: CrawlerParams = CrawlerParams.from_content(c, own, Ai18Kit.def())
	assert_float(p.spot_mid_m).is_equal(1000.0)
	assert_float(p.relocate_m).is_equal(80.0)
	assert_float(p.slope_max_deg).is_equal(10.0)                                # absent keys keep the default
	for bad: Dictionary in [{"spot_max_m": 1300}, {"spot_min_m": 200}, {"spot_min_m": 1100, "spot_max_m": 1000}, {"aim_tol_deg": 0}]:
		var ap: Dictionary = _ap()
		ap["siege"] = bad
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
	var c: ContentSet = Ai18Kit.content()
	var p: CrawlerParams = CrawlerParams.from_content(c, _ap(), Ai18Kit.def())
	var t: Terrain = Terrain.new()
	var st: ProjectileState = ProjectileState.new()
	var muzzle: Vector3 = Ai16Kit.dir_at(0.0) * (R + 7.0)
	for want: float in [400.0, 1000.0, 1075.0, 1150.0]:
		var aim: Vector3 = Ai16Kit.dir_at(want) * R
		var e: float = SiegeAim.loft(muzzle, aim, p.speed, p.shell, c.rules, t, 2.0 * p.dt, p.max_steps,
			CrawlerParams.LOFT_ITERS, p.loft_tol_m, st)
		assert_bool(is_nan(e)).is_false()
		assert_float(e).is_between(0.0, 0.25 * PI)                                 # the low arc
		var h: Vector3 = SiegeAim.tangent_to(muzzle, aim)
		var n: Vector3 = muzzle.normalized()
		var v: Vector3 = (h * cos(e) + n * sin(e)) * p.speed
		var r: Vector4 = Ballistics.predict_impact(muzzle, v, p.shell, c.rules, t, p.dt, p.dt, 0.0, 4 * p.max_steps, st)
		assert_float(absf(SiegeAim.arc(n, Vector3(r.x, r.y, r.z)) - want)).is_less(p.loft_tol_m + 3.0)   # + the solve's 2-tick step
	var far: Vector3 = Ai16Kit.dir_at(3000.0) * R                                  # g d > v^2: beyond any elevation
	assert_bool(is_nan(SiegeAim.loft(muzzle, far, p.speed, p.shell, c.rules, t, 2.0 * p.dt, p.max_steps,
		CrawlerParams.LOFT_ITERS, p.loft_tol_m, st))).is_true()


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
