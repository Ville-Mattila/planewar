extends GdUnitTestSuite
## 05 s11.2 scenarios of the Dart brain (AI-13) through SimWorld.step() with an AiDriver hook (DartKit): SC-01 (AUTO
## patrol from the home pad), SC-28 (the Bomber over the Scout, killed within 60 s in >= 8 / 10 seeds) and SC-29 (an
## ATTACK on a Flak-covered structure flies the Deck band). Flat datum (the tiny_test scenario recipe is not built).

const HZ: int = 30


func _yard(w: SimWorld, at: Vector3) -> int:
	return DartKit.spawn(w, &"shipyard", 0, at, Vector3.ZERO, DartKit.heading(at, Vector3(0, 1, 0)))


# A Dart parked DOCKED on the Shipyard's launch socket (A-82: pos + up * radius); the LaunchBay launches it next step.
func _parked_dart(w: SimWorld, yard: int) -> int:
	var v: SimView = w.view()
	var up: Vector3 = v.pos(yard).normalized()
	var id: int = DartKit.spawn(w, &"dart", 0, v.pos(yard) + up * DartKit.ship(&"dart").bounding_radius, Vector3.ZERO, up)
	w.economy().production.launch.dock(EntityId.slot(id), EntityId.slot(yard))
	return id


# SC-01 auto_patrol_holds: 1 Dart AUTO on its home pad, empty map. Pass: launches within 3 s (LAUNCHED and above
# pitch_over_agl_m); flies 120 s; once it has reached 150 m AGL the AGL stays in 150-450 m; within 1,400 m of the pad;
# no terrain contact (full hull, alive).
func test_sc01_auto_patrol_holds() -> void:
	var w: SimWorld = DartKit.world(1)
	var d: AiDriver = DartKit.driver(w)
	var pad_p: Vector3 = Vector3(DartKit.R, 0.0, 0.0)
	var yard: int = _yard(w, pad_p)
	var id: int = _parked_dart(w, yard)
	var t0: int = w.tick()
	var launched: int = -1
	var airborne: int = -1
	var in_band: bool = false
	var agl_min: float = INF
	var agl_max: float = 0.0
	var far: float = 0.0
	var tags: Dictionary = {}
	for k: int in 125 * HZ:
		w.step()
		for e: SimEvent in w.drain_events():
			if e.kind == SimEvent.Kind.LAUNCHED and e.a == id:
				launched = w.tick()
		var h: float = DartKit.agl(w, id)
		if airborne < 0 and h > DartKit.params().pitch_over_agl:
			airborne = w.tick()
		in_band = in_band or h >= 150.0
		if in_band:
			agl_min = minf(agl_min, h)
			agl_max = maxf(agl_max, h)
		far = maxf(far, Guidance.ground_dist(w.view().pos(id), w.view().pos(yard)))
		tags[w.view().ai_tag(id)] = true
	var what: String = "SC-01: launched +%d ticks, above 20 m at +%.2f s, AGL %.0f-%.0f m, farthest %.0f m, hp %.2f, tags %s, thinks %d" % [
		launched - t0, float(airborne - t0) / float(HZ), agl_min, agl_max, far, w.view().hp01(id), str(tags.keys()), d.stats()["thinks"]]
	print(what)
	assert_int(launched).override_failure_message(what).is_between(t0, t0 + 3 * HZ)
	assert_int(airborne).override_failure_message(what).is_between(t0, t0 + 3 * HZ)
	assert_bool(in_band).override_failure_message(what).is_true()
	assert_float(agl_min).override_failure_message(what).is_greater_equal(150.0)
	assert_float(agl_max).override_failure_message(what).is_less_equal(450.0)
	assert_float(far).override_failure_message(what).is_less_equal(1400.0)
	assert_bool(w.view().alive(id)).override_failure_message(what).is_true()
	assert_float(w.view().hp01(id)).override_failure_message(what).is_equal(1.0)
	assert_bool(tags.has(AiTag.Tag.PATROL)).override_failure_message(what).is_true()


# One SC-28 seed: a Core (team 0, the home pad; its 2 km sensor is the team's picture), a Dart AUTO on its patrol
# circle, an enemy Bomber crossing 1,500 m from the Core at 400 m AGL / 70 m/s and an enemy Scout 500-800 m from the
# Core. Returns [first target, bomber killed at tick or -1, start tick, dart id, bomber id, scout id].
func _sc28(seed_value: int) -> Array:
	var r: Array = _sc28_setup(seed_value)
	var w: SimWorld = r[0]
	var d: AiDriver = r[1]
	var dart: int = r[2]
	var bomber: int = r[3]
	var t0: int = w.tick()
	var first: int = 0
	var killed: int = -1
	var engaged: bool = false
	var s: int = EntityId.slot(dart)
	for k: int in 60 * HZ:
		w.step()
		var _e: Array[SimEvent] = w.drain_events()
		if first == 0 and d.state.target[s] != 0:
			first = d.state.target[s]
		engaged = engaged or (d.state.mode[s] == AiTag.Tag.ENGAGE and d.state.target[s] == bomber)
		if not w.view().alive(bomber):
			killed = w.tick()
			break
	var rammed: bool = not w.view().alive(dart)   # ramming kills both (01 s3.1.3); the Dart has no other killer here
	return [first, killed if engaged else -1, t0, dart, bomber, r[4], w, d, rammed]


## [world, driver, dart, bomber, scout] of SC-28 seed `seed_value`.
func _sc28_setup(seed_value: int) -> Array:
	var rng: Rng = Rng.new(2800 + seed_value)
	var w: SimWorld = DartKit.world(seed_value)
	var d: AiDriver = DartKit.driver(w)
	var cruise: DartKit.CruiseBrain = DartKit.CruiseBrain.new(DartKit.gains_of(&"bomber"), w.terrain())
	var scout_brain: DartKit.CruiseBrain = DartKit.CruiseBrain.new(DartKit.gains_of(&"scout"), w.terrain())
	scout_brain.speed = 60.0
	scout_brain.agl = 250.0
	d.set_brain(DartKit.class_of(&"bomber"), cruise)
	d.set_brain(DartKit.class_of(&"scout"), scout_brain)
	var home: Vector3 = Vector3(1, 0, 0)
	var _core: int = DartKit.spawn(w, &"core", 0, DartKit.above(w, home, 0.0), Vector3.ZERO, Vector3(0, 1, 0))
	var a0: float = rng.range_f(0.0, TAU)
	var pd: Vector3 = DartKit.offset(home, 1200.0 * cos(a0), 1200.0 * sin(a0))
	var p_dart: Vector3 = DartKit.above(w, pd, 300.0)
	var tang: Vector3 = p_dart.normalized().cross(home).normalized()
	var dart: int = DartKit.spawn(w, &"dart", 0, p_dart, tang * 110.0, tang)
	var side: float = 1.0 if rng.range_f(0.0, 1.0) < 0.5 else -1.0
	var x0: float = rng.range_f(-1100.0, -700.0)
	var pb: Vector3 = DartKit.above(w, DartKit.offset(home, x0, 1500.0 * side), 400.0)
	var hb: Vector3 = DartKit.heading(pb, DartKit.above(w, DartKit.offset(home, x0 + 500.0, 1500.0 * side), 400.0))
	var bomber: int = DartKit.spawn(w, &"bomber", DartKit.FOE, pb, hb * 70.0, hb)
	cruise.heading[bomber] = hb
	var sa: float = rng.range_f(0.0, TAU)
	var sr: float = rng.range_f(500.0, 800.0)
	var ps: Vector3 = DartKit.above(w, DartKit.offset(home, sr * cos(sa), sr * sin(sa)), 250.0)
	var hs: Vector3 = DartKit.heading(ps, DartKit.above(w, home, 250.0)).rotated(ps.normalized(), PI * 0.5)
	var scout: int = DartKit.spawn(w, &"scout", DartKit.FOE, ps, hs * 60.0, hs)
	scout_brain.heading[scout] = hs
	return [w, d, dart, bomber, scout]


# SC-28 dart_intercepts_bomber: enemy Bomber crossing 1,500 m from the Dart's patrol, a nearby enemy Scout. Pass: the
# Dart targets the Bomber over the Scout; engages (ENGAGE on the Bomber, a kill counts only then); the Bomber is
# destroyed within 60 s in >= 8 of 10 seeds.
func test_sc28_dart_intercepts_bomber() -> void:
	var kills: int = 0
	var rams: int = 0
	var bomber_first: int = 0
	var lines: PackedStringArray = PackedStringArray()
	for seed_value: int in 10:
		var r: Array = _sc28(seed_value)
		var first: int = r[0]
		var killed: int = r[1]
		var t0: int = r[2]
		var w: SimWorld = r[6]
		var d: AiDriver = r[7]
		var dart: int = r[3]
		bomber_first += 1 if first == r[4] else 0
		rams += 1 if r[8] else 0
		kills += 1 if killed >= 0 else 0
		var line: String = "seed %d: first target %s, bomber %s, dart hp %.2f ammo %d, mode %d" % [seed_value,
			"bomber" if first == r[4] else ("scout" if first == r[5] else str(first)),
			("killed at %.1f s" % (float(killed - t0) / float(HZ))) if killed >= 0 else "alive",
			w.view().hp01(dart), w.view().ammo(dart), d.state.mode[EntityId.slot(dart)]]
		var _a: bool = lines.push_back(line)
	var what: String = "SC-28: %d / 10 kills, %d rams, bomber first in %d / 10\n  %s" % [kills, rams, bomber_first, "\n  ".join(lines)]
	print(what)
	assert_int(bomber_first).override_failure_message(what).is_equal(10)
	assert_int(kills).override_failure_message(what).is_greater_equal(8)
	assert_int(rams).override_failure_message(what).is_less_equal(1)   # R0 B.17 A-93


# SC-29 dart_avoids_flak_band: an enemy Flak Battery covers the target (an enemy Refinery 400 m from it); a friendly
# Sensor Mast gives the team the picture (no threat map yet: the band reads visible towers). Dart ATTACK on
# the Refinery from 300 m AGL, 5 km out. (A ground sensor sees ground targets only inside its deck-reveal radius: the
# datum hides them beyond, so the mast stands 1 km from the Refinery.) Pass: ingress band Deck; time below 150 m AGL inside the Flak's range >= 80 %.
func test_sc29_dart_avoids_flak_band() -> void:
	var w: SimWorld = DartKit.world(29)
	var d: AiDriver = DartKit.driver(w)
	var tgt_dir: Vector3 = Vector3(1, 0, 0)
	var flak_dir: Vector3 = DartKit.offset(tgt_dir, 0.0, 400.0)
	var refinery: int = DartKit.spawn(w, &"refinery", DartKit.FOE, DartKit.above(w, tgt_dir, 0.0), Vector3.ZERO, Vector3(0, 1, 0))
	var flak: int = DartKit.spawn(w, &"flak_battery", DartKit.FOE, DartKit.above(w, flak_dir, 0.0), Vector3.ZERO, Vector3(0, 1, 0))
	var _mast: int = DartKit.spawn(w, &"sensor_mast", 0, DartKit.above(w, DartKit.offset(tgt_dir, -1000.0, 0.0), 0.0),
		Vector3.ZERO, Vector3(0, 1, 0))
	var p0: Vector3 = DartKit.above(w, DartKit.offset(tgt_dir, -5000.0, 300.0), 300.0)
	var h0: Vector3 = DartKit.heading(p0, DartKit.above(w, tgt_dir, 300.0))
	var dart: int = DartKit.spawn(w, &"dart", 0, p0, h0 * 110.0, h0)
	for _k: int in 3:
		w.step()
	assert_bool(w.view().visible_to(0, refinery) and w.view().visible_to(0, flak)).is_true()
	DartKit.order(w, dart, OrderSpec.make(OrderSpec.Kind.ATTACK, refinery))
	var s: int = EntityId.slot(dart)
	var flak_range: float = DartKit.params().threat_range[DartKit.def_id(&"flak_battery")]
	var inside: int = 0
	var low: int = 0
	var band: int = -1
	var bombs0: int = w.view().bombs(dart)
	var impacts: int = 0
	var steps: PackedInt32Array = PackedInt32Array()
	for _k: int in 150 * HZ:
		w.step()
		for e: SimEvent in w.drain_events():
			impacts += 1 if e.kind == SimEvent.Kind.BOMB_IMPACT else 0
		var v: SimView = w.view()
		var step: int = AttackRun.step_of(d.state, s)
		if steps.is_empty() or steps[steps.size() - 1] != step:
			var _a: bool = steps.push_back(step)
		if band < 0 and d.state.mode[s] == AiTag.Tag.BOMB:
			band = AttackRun.band_of(d.state, s)
		if v.pos(dart).distance_to(v.pos(flak)) <= flak_range:
			inside += 1
			low += 1 if DartKit.agl(w, dart) < 150.0 else 0
		if (d.state.bflags[s] & DartBrain.B_RUN_DONE) != 0:
			break
	for _k: int in 12:   # the run's RETURN request (05 s6.2 BOMB row: bombs = 0) is applied in the next ticks
		w.step()
	var share: float = float(low) / float(maxi(inside, 1))
	var what: String = "SC-29: band %d (deck %d), %.0f %% of %.1f s inside flak range below 150 m AGL; bombs %d -> %d, impacts %d, refinery hp %.2f, steps %s, dart hp %.2f" % [
		band, AttackRun.Band.DECK, 100.0 * share, float(inside) / float(HZ), bombs0, w.view().bombs(dart), impacts,
		w.view().hp01(refinery), str(steps), w.view().hp01(dart)]
	print(what)
	assert_int(band).override_failure_message(what).is_equal(AttackRun.Band.DECK)
	assert_int(inside).override_failure_message(what).is_greater(0)
	assert_float(share).override_failure_message(what).is_greater_equal(0.8)
	assert_float(w.view().hp01(dart)).override_failure_message(what).is_equal(1.0)
	assert_int(w.view().bombs(dart)).override_failure_message(what).is_equal(0)
	assert_int(w.view().order_head(dart).kind).override_failure_message(what).is_equal(OrderSpec.Kind.RETURN)
	assert_int(w.view().order_issuer(dart)).override_failure_message(what).is_equal(-1)
