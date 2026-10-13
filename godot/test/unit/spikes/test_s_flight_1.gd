extends GdUnitTestSuite
## S-FLIGHT-1 spike (TA-30) smoke tests: the tail-down landing rule (03 s6.4, R0 B.5 / O-2), the landing grade,
## the auto-dock assist and harness autopilot landing through Kinematics.step_ship, co-altitude slugs, the
## speed-scaled AoA, and replay determinism of the spike world. Defs come from the spike's loader (real defs).

var _d: SfDefs


func before_test() -> void:
	_d = SfDefs.load_all()


func _td(v_vert: float, v_hor: float, tilt_deg: float, offset: float, on_pad: bool, manual: bool) -> SfTouchdown:
	var n: Vector3 = Vector3(1, 0, 0)
	var east: Vector3 = Vector3(0, 1, 0)
	var pad_p: Vector3 = n * Sphere.PLANET_RADIUS
	var p: Vector3 = pad_p + n * _d.ship.bounding_radius + east * offset
	var t: float = deg_to_rad(tilt_deg)
	var fwd: Vector3 = n * cos(t) + east * sin(t)
	var v: Vector3 = -n * v_vert + east * v_hor
	return SfLanding.evaluate(p, v, fwd, v_vert, pad_p, n, on_pad, manual, _d, SfTouchdown.new())


func test_tail_down_safe_landing_is_landed() -> void:
	var t: SfTouchdown = _td(_d.common.landing_safe_v_vert * 0.5, 2.0, 5.0, 1.0, true, true)
	assert_int(t.outcome).is_equal(SfTouchdown.Outcome.LANDED)
	assert_float(t.damage_hp).is_equal(0.0)


func test_damage_band_lands_hard_with_damage() -> void:
	var c: FlightCommonDef = _d.common
	var t: SfTouchdown = _td((c.landing_safe_v_vert + c.landing_damage_v_vert) * 0.5, 0.0, 0.0, 0.0, true, true)
	assert_int(t.outcome).is_equal(SfTouchdown.Outcome.HARD)
	assert_int(t.grade).is_equal(SfTouchdown.GRADE_BENT)
	assert_float(t.damage_hp).is_greater(0.0)
	var tilt: SfTouchdown = _td(1.0, 0.0, c.landing_safe_pitch_deg + 5.0, 0.0, true, true)
	assert_int(tilt.outcome).is_equal(SfTouchdown.Outcome.HARD)


func test_beyond_damage_limits_crashes() -> void:
	var c: FlightCommonDef = _d.common
	assert_int(_td(c.landing_damage_v_vert + 1.0, 0.0, 0.0, 0.0, true, true).outcome).is_equal(SfTouchdown.Outcome.CRASH)
	assert_int(_td(1.0, c.landing_damage_v_hor + 1.0, 0.0, 0.0, true, true).outcome).is_equal(SfTouchdown.Outcome.CRASH)


func test_no_level_landing_variant() -> void:
	# a slow, belly-down (level) touchdown on the pad is not a landing (R0 O-2: tail-down only)
	var t: SfTouchdown = _td(1.0, 1.0, 90.0, 0.0, true, true)
	assert_int(t.outcome).is_equal(SfTouchdown.Outcome.CRASH)


func test_off_pad_contact_classified_by_terrain_speeds() -> void:
	var c: FlightCommonDef = _d.common
	assert_int(_td(c.terrain_kill_speed + 1.0, 0.0, 0.0, 50.0, false, true).outcome).is_equal(SfTouchdown.Outcome.CRASH)
	assert_int(_td(c.terrain_damage_speed + 1.0, 0.0, 0.0, 50.0, false, true).outcome).is_equal(SfTouchdown.Outcome.DAMAGED)
	assert_int(_td(1.0, 0.0, 0.0, 50.0, false, true).outcome).is_equal(SfTouchdown.Outcome.SCRAPE)


func test_grade_quality_and_auto() -> void:
	var perfect: SfTouchdown = _td(0.0, 0.0, 0.0, 0.0, true, true)
	assert_float(perfect.q).is_equal_approx(1.0, 1e-6)
	assert_int(perfect.grade).is_equal(SfTouchdown.GRADE_ACE)
	assert_int(_td(0.0, 0.0, 0.0, 0.0, true, false).grade).is_equal(SfTouchdown.GRADE_AUTO)


func _fly_until_docked(w: SfWorld, dock_only: bool, seconds: float) -> bool:
	var ap: SfAutopilot = SfAutopilot.new(_d)
	var inp: PilotInput = PilotInput.new()
	for i: int in int(seconds * _d.rules.tick_hz):
		if dock_only:
			inp.thrust = 0.0
			inp.buttons = PilotInput.DOCK
		else:
			ap.approach_step(w.s, _d.ship, w.pad_p, w.pad_n, inp)
			inp.buttons &= ~PilotInput.DOCK
		w.step(inp)
		var _e: Array[SfEvent] = w.drain_events()
		if w.state == SfWorld.State.DOCKED or w.state == SfWorld.State.DEAD:
			break
	return w.state == SfWorld.State.DOCKED


func test_auto_dock_assist_lands_tail_down() -> void:
	var w: SfWorld = SfWorld.new(_d, 1)
	var east: Vector3 = Sphere.tangent_frame(w.pad_p).x
	var p: Vector3 = SfArena.place(w.pad_p, 90.0, 80.0, 50.0)
	w.place(p, east, p.normalized(), east * 30.0)
	assert_bool(_fly_until_docked(w, true, 90.0)).is_true()
	assert_int(w.last_touchdown.outcome).is_equal(SfTouchdown.Outcome.LANDED)
	assert_int(w.last_touchdown.grade).is_equal(SfTouchdown.GRADE_AUTO)
	assert_float(w.last_touchdown.tilt_deg).is_less_equal(_d.common.landing_safe_pitch_deg)


func test_harness_autopilot_lands_from_a_kilometre() -> void:
	var w: SfWorld = SfWorld.new(_d, 2)
	var p: Vector3 = SfArena.place(w.pad_p, 200.0, 1000.0, 150.0)
	var n: Vector3 = p.normalized()
	var to_pad: Vector3 = (w.pad_p - p)
	to_pad = (to_pad - n * to_pad.dot(n)).normalized()
	w.place(p, to_pad, n, to_pad * _d.ship.v_cruise)
	assert_bool(_fly_until_docked(w, false, 120.0)).is_true()
	assert_int(w.last_touchdown.outcome).is_equal(SfTouchdown.Outcome.LANDED)


func test_coaltitude_slugs_hit_when_aimed() -> void:
	# straight-line rule only: weapon spread off (the harness reports hit rates with gun_dart's 0.6 deg spread)
	_d.gun_spread_deg = 0.0
	for dist: float in [200.0, 400.0, 650.0, 800.0]:
		var w: SfWorld = SfWorld.new(_d, 3)
		w.arena.clear_targets()
		var alt: float = 300.0
		var p: Vector3 = w.pad_n * (Sphere.PLANET_RADIUS + alt)
		var tgt: Vector3 = SfArena.place(p, 90.0, dist * Sphere.PLANET_RADIUS / (Sphere.PLANET_RADIUS + alt), alt)   # dist = range at altitude
		var _k: int = w.arena.add_target(tgt, false)
		var los: Vector3 = (tgt - p).normalized()
		w.place(p, los, w.pad_n, Vector3.ZERO)
		var inp: PilotInput = PilotInput.new()
		inp.buttons = PilotInput.FIRE1
		w.step(inp)
		inp.buttons = 0
		for i: int in _d.rules.tick_hz * 2:
			w.step(inp)
		assert_int(w.arena.slug_hits).override_failure_message("miss at %d m" % int(dist)).is_equal(1)


func test_speed_scaled_cruise_aoa_within_6_degrees() -> void:
	var w: SfWorld = SfWorld.new(_d, 4)
	var east: Vector3 = Sphere.tangent_frame(w.pad_p).x
	var h0: float = 300.0
	var v: float = 0.9 * _d.ship.v_cruise
	w.place(w.pad_n * (Sphere.PLANET_RADIUS + h0 + _d.ship.bounding_radius), east, w.pad_n, east * v)
	var ap: SfAutopilot = SfAutopilot.new(_d)
	var inp: PilotInput = PilotInput.new()
	var aoa: float = 0.0
	for i: int in 40 * _d.rules.tick_hz:
		ap.hold(w.s, _d.ship, h0, v, Vector3.ZERO, inp)
		w.step(inp)
		aoa = w.aoa_deg()
	assert_float(absf(w.altitude() - h0)).is_less(1.0)
	assert_float(aoa).is_between(0.0, 6.0)


func test_spike_world_replay_is_identical() -> void:
	var a: SfWorld = SfWorld.new(_d, 5)
	var b: SfWorld = SfWorld.new(_d, 5)
	var rng: Rng = Rng.new(77)
	var inp: PilotInput = PilotInput.new()
	inp.thrust = 1.0
	for i: int in 900:
		if i % 30 == 0:
			inp.pitch = rng.range_f(-1.0, 1.0)
			inp.roll = rng.range_f(-1.0, 1.0)
			inp.buttons = PilotInput.FIRE1 if rng.next_float() < 0.5 else 0
		a.step(inp)
		b.step(inp)
	assert_vector(a.s.p).is_equal(b.s.p)
	assert_vector(a.s.v).is_equal(b.s.v)
	assert_int(a.arena.shots).is_equal(b.arena.shots)
