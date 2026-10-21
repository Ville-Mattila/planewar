extends GdUnitTestSuite
## TA-63 (R0 B.17 A-95): SimView.visible_enemy_ships(team, out) -> int reads Vision's per-team InterestGrid list
## (V5, V10), not the store. 258 ships (the AI-40 host scale: 240 far + 18 near) of four teams and neutral, moving, so
## ships die while lists are stale over the 60 ticks; the brute force is the TeamPicture rule (ships() filtered by
## team != t and visible_to) on the same view.

const R: float = Sphere.PLANET_RADIUS
const SHIPS: int = 258
const TICKS: int = 60


func _world() -> SimWorld:
	var w: SimWorld = VisionTestKit.world()
	var rng: Rng = Rng.new(63)
	var defs: Array[StringName] = [&"dart", &"scout", &"bomber", &"lancer"]
	for k: int in SHIPS:
		var team: int = k % 5 if k % 5 < 4 else -1                    # teams 0..3 and neutral
		var lon: float = float(k % 43) * 0.0007 + (0.004 if k >= 240 else 0.0)
		var lat: float = float(k % 6) * 0.0006 + rng.range_f(0.0, 0.0002)
		var alt: float = 250.0 + float(k % 9) * 90.0
		var id: int = VisionTestKit.put(w, defs[k % defs.size()], team, Sphere.from_lat_lon(lat, lon, R + alt))
		assert(id != EntityId.NULL_ID)
		var s: int = EntityId.slot(id)
		var tf: Basis = Sphere.tangent_frame(w.store().pos[s])
		w.store().vel[s] = tf.x * (60.0 + float(k % 7) * 10.0)
		w.store().fwd[s] = tf.x
		w.store().fuel[s] = 1000.0
	w.spatial.rebuild()
	return w


func _brute(v: SimView, team: int) -> Array:
	var out: Array = []
	for id: int in v.ships():
		if v.team(id) != team and v.visible_to(team, id):
			out.append(id)
	out.sort()
	return out


func _got(v: SimView, team: int, buf: PackedInt32Array) -> Array:
	var n: int = v.visible_enemy_ships(team, buf)
	var a: Array = Array(buf.slice(0, n))
	a.sort()
	return a


## Every team, every tick of 60: the answer equals the brute-force picture, each id is alive, a ship, seen, in ships()
## and not own-team; the population is non-trivial.
func test_matches_brute_force_picture_every_team_every_tick() -> void:
	var w: SimWorld = _world()
	var v: SimView = w.view()
	var buf: PackedInt32Array = PackedInt32Array()
	var seen_total: int = 0
	var ships_before: int = v.ships().size()
	for _t: int in TICKS:
		w.step()
		var _e: Array[SimEvent] = w.drain_events()
		var in_ships: Dictionary = {}
		for id: int in v.ships():
			in_ships[id] = true
		for team: int in PlayerTable.TEAMS:
			var got: Array = _got(v, team, buf)
			assert_array(got).override_failure_message("tick %d team %d" % [w.tick(), team]).is_equal(_brute(v, team))
			for id: int in got:
				assert_bool(v.alive(id) and v.visible_to(team, id) and in_ships.has(id) and v.team(id) != team).is_true()
			seen_total += got.size()
	assert_int(seen_total).is_greater(1000)
	assert_int(ships_before).is_equal(SHIPS)


## A ship killed after the team's last pass is not returned (alive check), and a fresh ship in the world is not either.
func test_ship_dead_since_the_pass_is_not_returned() -> void:
	var w: SimWorld = VisionTestKit.world()
	var a: int = VisionTestKit.put(w, &"dart", 0, VisionTestKit.at(500.0))
	var b: int = VisionTestKit.put(w, &"dart", 1, VisionTestKit.at(500.0, 120.0))
	var c: int = VisionTestKit.put(w, &"dart", 1, VisionTestKit.at(500.0, 180.0))
	VisionTestKit.sense(w)
	var v: SimView = w.view()
	var buf: PackedInt32Array = PackedInt32Array()
	var both: Array = [b, c]
	both.sort()
	assert_array(_got(v, 0, buf)).is_equal(both)
	assert_bool(w.store().free_slot(EntityId.slot(b), w.tick())).is_true()
	var fresh: int = VisionTestKit.put(w, &"dart", 1, VisionTestKit.at(500.0, 150.0))    # after the pass: not listed
	var got: Array = _got(v, 0, buf)
	assert_array(got).is_equal([c])
	assert_bool(got.has(fresh) or got.has(b) or got.has(a)).is_false()


## Structures, ground units and wrecks the team sees are not ships: never listed.
func test_only_ships_not_structures_ground_or_wrecks() -> void:
	var w: SimWorld = VisionTestKit.world()
	var _a: int = VisionTestKit.put(w, &"dart", 0, VisionTestKit.at(500.0))
	var e: int = VisionTestKit.put(w, &"dart", 1, VisionTestKit.at(500.0, 100.0))
	var _s: int = VisionTestKit.put(w, &"core", 1, VisionTestKit.at(0.0, 150.0))
	var _g: int = VisionTestKit.put(w, &"harvester", 1, VisionTestKit.at(0.0, 160.0))
	var _k: int = VisionTestKit.put(w, &"dart", 1, VisionTestKit.at(0.0, 170.0), EntityStore.K_WRECK)
	VisionTestKit.sense(w)
	var buf: PackedInt32Array = PackedInt32Array()
	assert_array(_got(w.view(), 0, buf)).is_equal([e])
	assert_int(w.vision.grid.list_size[0]).is_greater(1)    # the other kinds are in the list, just filtered out


## Neutral ships count as enemies; bad team numbers give 0 and leave `out` alone.
func test_neutral_ships_included_and_bad_teams_empty() -> void:
	var w: SimWorld = VisionTestKit.world()
	var _a: int = VisionTestKit.put(w, &"dart", 0, VisionTestKit.at(500.0))
	var n: int = VisionTestKit.put(w, &"dart", -1, VisionTestKit.at(500.0, 100.0))
	VisionTestKit.sense(w)
	var buf: PackedInt32Array = PackedInt32Array([5])
	assert_array(_got(w.view(), 0, buf)).is_equal([n])
	var one: PackedInt32Array = PackedInt32Array([5])
	for bad: int in [-1, PlayerTable.TEAMS, 99]:
		assert_int(w.view().visible_enemy_ships(bad, one)).is_equal(0)
	assert_int(one.size()).is_equal(1)
	assert_int(one[0]).is_equal(5)


## `out` is grown once (to at most the list size) and never reallocated when large enough; contents past the count
## are untouched.
func test_out_is_grown_once_and_reused() -> void:
	var w: SimWorld = _world()
	for _i: int in 12:
		w.step()
	var v: SimView = w.view()
	var buf: PackedInt32Array = PackedInt32Array()
	var n: int = v.visible_enemy_ships(0, buf)
	assert_int(n).is_greater(0)
	var size: int = buf.size()
	assert_int(size).is_greater_equal(n)
	assert_int(size).is_less_equal(w.vision.grid.list_size[0])
	var big: PackedInt32Array = PackedInt32Array()
	var _r: int = big.resize(w.vision.grid.list_size[0] + 50)
	big.fill(-3)
	var m: int = v.visible_enemy_ships(0, big)
	assert_int(m).is_equal(n)
	assert_int(big.size()).is_equal(w.vision.grid.list_size[0] + 50)
	assert_int(big[m]).is_equal(-3)
	assert_int(v.visible_enemy_ships(0, buf)).is_equal(n)
	assert_int(buf.size()).is_equal(size)


## S4: the same output (as sets) after serialize -> deserialize (lists rebuilt by Vision.rebuild_lists), after another
## rebuild_lists, and while both worlds keep stepping.
func test_identical_after_deserialize_and_rebuild_lists() -> void:
	var w1: SimWorld = _world()
	for _i: int in 20:
		w1.step()
		var _e: Array[SimEvent] = w1.drain_events()
	var w2: SimWorld = SimWorld.deserialize(w1.serialize(), WorldTestKit.content(), null)
	assert_object(w2).is_not_null()
	var b1: PackedInt32Array = PackedInt32Array()
	var b2: PackedInt32Array = PackedInt32Array()
	var total: int = 0
	for team: int in PlayerTable.TEAMS:
		var want: Array = _got(w1.view(), team, b1)
		total += want.size()
		assert_array(_got(w2.view(), team, b2)).is_equal(want)
	assert_int(total).is_greater(0)
	w2.vision.rebuild_lists()
	for team: int in PlayerTable.TEAMS:
		assert_array(_got(w2.view(), team, b2)).is_equal(_got(w1.view(), team, b1))
	for _i: int in 12:
		w1.step()
		w2.step()
		var _a: Array[SimEvent] = w1.drain_events()
		var _b: Array[SimEvent] = w2.drain_events()
		for team: int in PlayerTable.TEAMS:
			assert_array(_got(w2.view(), team, b2)).is_equal(_got(w1.view(), team, b1))


## Work counter (A-97: hard, no wall clock): the result never exceeds the team's list and equals the brute force;
## per-team us per call and the brute-force figure beside it are PERF_REPORT lines. The bound is half of
## TeamPicture's 222 us (PR #87), asserted only on the pinned runner.
func test_perf_us_per_call_per_team_at_ai40_scale() -> void:
	var w: SimWorld = _world()
	for _i: int in 12:
		w.step()
	var v: SimView = w.view()
	var buf: PackedInt32Array = PackedInt32Array()
	var grid: InterestGrid = w.vision.grid
	var visible_total: int = 0
	for team: int in PlayerTable.TEAMS:
		var n: int = v.visible_enemy_ships(team, buf)
		assert_int(n).is_less_equal(grid.list_size[team])
		assert_int(n).is_equal(_brute(v, team).size())
		visible_total += n
	assert_int(visible_total).is_greater(0)
	const CALLS: int = 400
	var fast_sum: float = 0.0
	var brute_sum: float = 0.0
	for team: int in PlayerTable.TEAMS:
		var t0: int = Time.get_ticks_usec()
		for _k: int in CALLS:
			var _n: int = v.visible_enemy_ships(team, buf)
		var fast: float = float(Time.get_ticks_usec() - t0) / float(CALLS)
		t0 = Time.get_ticks_usec()
		var sink: int = 0
		for _k: int in 40:
			sink = 0
			for id: int in v.ships():
				if v.team(id) != team and v.visible_to(team, id):
					sink += 1
		var brute: float = float(Time.get_ticks_usec() - t0) / 40.0
		fast_sum += fast
		brute_sum += brute
		print("TA-63 team %d: visible_enemy_ships %.2f us (%d listed, %d returned) vs brute force %.1f us (%d)" % [
				team, fast, grid.list_size[team], v.visible_enemy_ships(team, buf), brute, sink])
		assert_bool(PerfGate.check("visible_enemy_ships_team%d" % team, fast, 222.0 / 2.0, "R0 B.17 A-95 (TeamPicture 222 us)")).is_true()
	assert_bool(PerfGate.check("visible_enemy_ships_vs_brute", fast_sum, brute_sum, "R0 B.17 A-95")).is_true()
