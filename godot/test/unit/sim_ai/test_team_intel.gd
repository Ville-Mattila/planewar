extends GdUnitTestSuite
## AI-22 TeamIntel and its AiDriver wiring (05 s6 sampler, 1 Hz per team): one slice per tracked team per period on
## distinct odd ticks (never a bot's even phase), the driver's accessors, AiDriver FORMAT 2 refusing FORMAT 1 bytes, and
## the S4 byte-exact restore of a brain-flown world saved mid-fight with intel on both teams.

const HOME: Vector3 = Vector3(1, 0, 0)


func test_each_tracked_team_refreshes_once_per_period_on_its_own_tick() -> void:
	var w: SimWorld = DartKit.world(5)
	var intel: TeamIntel = IntelKit.intel()
	for t: int in PlayerTable.TEAMS:
		intel.track(t, true)
	var per_tick: Dictionary = {}
	for tick: int in 60:
		var before: int = intel.stats_updates
		intel.step(tick, w.view())
		var n: int = intel.stats_updates - before
		assert_int(n).is_less_equal(1)
		if n == 1:
			per_tick[tick] = true
			assert_int(tick % 2).is_equal(1)                       # odd: bots think on even residues of 30
	assert_int(intel.stats_updates).is_equal(2 * PlayerTable.TEAMS)
	assert_int(per_tick.size()).is_equal(2 * PlayerTable.TEAMS)
	intel.track(3, false)
	assert_object(intel.perception(3)).is_null()
	assert_object(intel.threat_map(3)).is_null()
	assert_bool(intel.tracked(4)).is_true()


func test_driver_refreshes_tracked_teams_before_the_brains() -> void:
	var w: SimWorld = DartKit.world(5)
	var d: AiDriver = DartKit.driver(w)
	assert_object(d.threat_map(0)).is_null()
	var intel: TeamIntel = IntelKit.intel()
	intel.track(0, true)
	d.set_intel(intel)
	var _own: int = IntelKit.spawn(w, &"dart", 0, 0, IntelKit.at(w, HOME, 0.0, 0.0, 300.0))
	var _gun: int = IntelKit.spawn(w, &"autocannon_turret", 1, 1, IntelKit.at(w, HOME, 800.0, 0.0))
	IntelKit.run(w, 40)
	assert_object(d.threat_map(1)).is_null()
	assert_object(d.perception(0)).is_not_null()
	assert_int(d.perception(0).n_known).is_equal(1)
	assert_int(d.threat_map(0).updated).is_greater(0)
	assert_int(intel.stats_updates).is_between(1, 2)


func test_driver_format_2_refuses_format_1_bytes() -> void:
	assert_int(AiDriver.FORMAT).is_equal(2)
	var w: SimWorld = DartKit.world(5)
	var d: AiDriver = DartKit.driver(w)
	var intel: TeamIntel = IntelKit.intel()
	intel.track(0, true)
	d.set_intel(intel)
	var _own: int = IntelKit.spawn(w, &"dart", 0, 0, IntelKit.at(w, HOME, 0.0, 0.0, 300.0))
	IntelKit.run(w, 31)
	var bytes: PackedByteArray = d.serialize()
	assert_int(d.state.registered_count()).is_equal(1)
	bytes[0] = 1
	d.deserialize(bytes)
	assert_int(d.state.registered_count()).is_equal(0)
	assert_bool(intel.tracked(0)).is_false()
	var bad: PackedByteArray = intel.serialize()
	bad[0] = TeamIntel.FORMAT + 1
	assert_bool(intel.deserialize(bad)).is_false()


func test_s4_restore_mid_fight_is_byte_exact() -> void:
	var a: Array = _fight(41)
	var wa: SimWorld = a[0]
	var ia: TeamIntel = a[1]
	assert_int(ia.perception(0).n_known).is_greater(0)
	assert_int(wa.projectiles().live.size()).is_greater(0)   # saved mid-burst
	var bytes: PackedByteArray = wa.serialize()
	var d2: AiDriver = AiDriver.new(Rng.new(99))
	d2.set_class_table(AiClassTable.from_content(DartKit.content()))
	d2.set_brain(DartKit.CLS_DART, DartBrain.from_content(DartKit.content(), DartKit.ap(), DartKit.ship(&"dart"), Terrain.new(),
		FormationKit.ring2_m()))
	d2.set_overlay_params(DartKit.CLS_DART, OverlayParams.for_ship(DartKit.ap(), DartKit.ship(&"dart"), DartKit.content().rules, 30,
		DartKit.content().flight_common))
	var i2: TeamIntel = IntelKit.intel()
	d2.set_intel(i2)
	var w2: SimWorld = SimWorld.deserialize(bytes, DartKit.content(), d2)
	assert_object(w2).is_not_null()
	d2.set_terrain(w2.terrain())
	assert_bool(w2.serialize() == bytes).is_true()
	assert_bool(i2.tracked(0) and i2.tracked(1)).is_true()
	for t: int in 2:
		assert_bool(i2.threat_map(t).ch == ia.threat_map(t).ch).is_true()
		assert_bool(i2.perception(t).serialize() == ia.perception(t).serialize()).is_true()
	var u0: int = ia.stats_updates
	for _k: int in 150:
		wa.step()
		w2.step()
		var _x: Array[SimEvent] = wa.drain_events()
		var _y: Array[SimEvent] = w2.drain_events()
	assert_int(ia.stats_updates - u0).is_greater_equal(8)
	assert_bool(w2.serialize() == wa.serialize()).is_true()
	for t: int in 2:
		assert_bool(i2.threat_map(t).ch == ia.threat_map(t).ch).is_true()


# Review round 1 (05 C18 capture): a structure that changes team mid-run. The continuous run and a run restored before
# the flip read the same team every refresh (no stale cache), so they stay byte-exact; the losing team drops the
# captured Relay's sensor cover (its contact becomes a kept ghost) and the winner lists the Relay as its own.
func test_capture_keeps_continuous_and_restored_runs_byte_exact() -> void:
	var w: SimWorld = DartKit.world(17)
	var d: AiDriver = AiDriver.new(Rng.new(3))   # no class table: the Darts are plain sensors (no brain)
	var intel: TeamIntel = IntelKit.intel()
	intel.track(0, true)
	intel.track(1, true)
	d.set_intel(intel)
	w.set_ai_hook(d)
	var relay: int = IntelKit.spawn(w, &"relay_station", 0, 0, IntelKit.at(w, HOME, 0.0, 0.0))
	var gun: int = IntelKit.spawn(w, &"autocannon_turret", 1, 1, IntelKit.at(w, HOME, 1000.0, 0.0))   # inside the Relay's deck reveal
	var _own: int = IntelKit.spawn(w, &"dart", 0, 0, IntelKit.at(w, HOME, -900.0, 0.0, 300.0))        # sees the Relay, not the turret
	var _foe: int = IntelKit.spawn(w, &"dart", 1, 1, IntelKit.at(w, HOME, 0.0, 800.0, 300.0))         # team 1 knows the Relay as a contact
	IntelKit.run(w, 40)
	assert_bool(intel.perception(0).knows(gun, w.tick())).is_true()
	assert_bool(intel.perception(1).knows(relay, w.tick())).is_true()
	var bytes: PackedByteArray = w.serialize()
	var d2: AiDriver = AiDriver.new(Rng.new(99))
	var i2: TeamIntel = IntelKit.intel()
	d2.set_intel(i2)
	var w2: SimWorld = SimWorld.deserialize(bytes, DartKit.content(), d2)
	assert_object(w2).is_not_null()
	for world: SimWorld in [w, w2]:   # the capture: team and owner bytes flip to the foe (test-only store write)
		world.store().team[EntityId.slot(relay)] = DartKit.FOE
		world.store().owner[EntityId.slot(relay)] = 1
	for _k: int in 60:
		w.step()
		w2.step()
		var _x: Array[SimEvent] = w.drain_events()
		var _y: Array[SimEvent] = w2.drain_events()
	assert_bool(w2.serialize() == w.serialize()).is_true()
	for t: int in 2:
		assert_bool(i2.threat_map(t).ch == intel.threat_map(t).ch).is_true()
		assert_bool(i2.perception(t).serialize() == intel.perception(t).serialize()).is_true()
	var p0: Perception = intel.perception(0)
	assert_bool(p0.own_id.slice(0, p0.n_own).has(relay)).is_false()
	assert_bool(p0.knows(relay, w.tick())).is_true()           # still seen, now an enemy contact
	assert_bool(p0.cover.covers(w.view().pos(gun), IntelKit.cell(w.view().pos(gun)), false)).is_false()   # the Relay's cover is gone
	assert_bool(p0.knows(gun, w.tick())).is_true()             # remembered as a ghost: its spot is no longer covered
	assert_int(p0.k_seen[EntityId.slot(gun)]).is_less(w.tick())
	var p1: Perception = intel.perception(1)
	assert_bool(p1.own_id.slice(0, p1.n_own).has(relay)).is_true()
	assert_bool(p1.knows(relay, w.tick())).is_false()          # joined the team: no longer a contact


# [world, intel]: three Darts ENGAGEd on an enemy Bomber near a Core and an enemy turret; intel on teams 0 and 1.
func _fight(seed_value: int) -> Array:
	var w: SimWorld = DartKit.world(seed_value)
	var d: AiDriver = DartKit.driver(w)
	var intel: TeamIntel = IntelKit.intel()
	intel.track(0, true)
	intel.track(1, true)
	d.set_intel(intel)
	var _core: int = DartKit.spawn(w, &"core", 0, DartKit.above(w, HOME, 0.0), Vector3.ZERO, Vector3(0, 1, 0))
	var _gun: int = IntelKit.spawn(w, &"autocannon_turret", 1, 1, IntelKit.at(w, HOME, 1200.0, 900.0))
	var pb: Vector3 = DartKit.above(w, DartKit.offset(HOME, 0.0, 600.0), 400.0)
	var hb: Vector3 = DartKit.heading(pb, DartKit.above(w, DartKit.offset(HOME, 500.0, 600.0), 400.0))
	var bomber: int = DartKit.spawn(w, &"bomber", DartKit.FOE, pb, hb * 70.0, hb)
	for k: int in 3:
		var pd: Vector3 = DartKit.above(w, DartKit.offset(HOME, -300.0, 600.0 + 80.0 * float(k - 1)), 400.0 + 30.0 * float(k))
		var dart: int = DartKit.spawn(w, &"dart", 0, pd, hb * 90.0, hb)
		DartKit.order(w, dart, OrderSpec.make(OrderSpec.Kind.ATTACK, bomber))
	IntelKit.run(w, 45)
	return [w, intel]
