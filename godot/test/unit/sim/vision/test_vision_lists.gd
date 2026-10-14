extends GdUnitTestSuite
## TA-37 Vision in the tick (03 s3.7, s4.1 step 11): stagger per team at 10 Hz and 5 Hz (cut rung 2), latency
## bound, per-team interest lists vs the mask (the NET-08 shape through SimWorld.interest_*), determinism of two
## identical worlds and S4 (serialize -> deserialize -> step equals step; lists rebuilt from the mask).

const R: float = Sphere.PLANET_RADIUS


## Every team runs exactly once per period, on ticks with tick % period == team % period; at most
## ceil(8 / period) teams share a tick. Rung 1 only: 10 Hz (period 3); default profile [1, 2]: 5 Hz (period 6).
func test_stagger_each_team_once_per_period() -> void:
	var w: SimWorld = VisionTestKit.world()
	var _d: int = VisionTestKit.put(w, &"dart", 0, VisionTestKit.at(500.0))
	assert_int(w.vision.period(PackedInt32Array([1, 2]))).is_equal(6)
	for level: int in [1, 2, 0]:
		w.set_budget_profile(level)
		var p: int = 6 if level == 2 else 3
		assert_int(w.vision.period(_rungs(level))).is_equal(p)
		var prev: PackedInt32Array = PackedInt32Array([-1, -1, -1, -1, -1, -1, -1, -1])
		for _i: int in 4 * p:
			w.step()
			var _e: Array[SimEvent] = w.drain_events()
			var t: int = w.tick()
			var ran: int = 0
			for team: int in Vision.TEAMS:
				var did: bool = w.vision.last_pass[team] == t
				assert_bool(w.vision.runs(team, t, _rungs(level))).is_equal(did)
				assert_bool(did).override_failure_message("level %d tick %d team %d" % [level, t, team]) \
					.is_equal(MathX.posmod_i(t, p) == team % p)
				if did:
					ran += 1
					if prev[team] >= 0:
						assert_int(t - prev[team]).is_equal(p)
					prev[team] = t
			assert_int(ran).is_between(MathX.floori_div(Vision.TEAMS, p), MathX.floori_div(Vision.TEAMS + p - 1, p))
		for team: int in Vision.TEAMS:
			assert_int(prev[team]).is_greater(0)


## A target that enters range is visible within one period of its team's stagger, never later.
func test_visibility_latency_bounded_by_period() -> void:
	var w: SimWorld = VisionTestKit.world()
	w.set_budget_profile(1)
	var _core: int = VisionTestKit.put(w, &"core", 0, VisionTestKit.at(1.0))
	for _i: int in 5:
		w.step()
	var enemy: int = VisionTestKit.put(w, &"dart", 1, VisionTestKit.at(600.0, 900.0))
	var waited: int = 0
	while not VisionTestKit.visible(w, 0, enemy) and waited < 10:
		w.step()
		waited += 1
	assert_int(waited).is_between(1, w.vision.period(_rungs(1)))


## Team t's list holds exactly the live slots with bit t, each under its interest cell; SimWorld.interest_*
## expose the same arrays (flat layout of sim/vision/MODULE.md).
func test_interest_lists_match_mask_and_world_accessors() -> void:
	var w: SimWorld = VisionTestKit.world()
	VisionTestKit.scatter(w, Rng.new(17), 300)
	VisionTestKit.sense(w)
	var st: EntityStore = w.store()
	var start: PackedInt32Array = w.interest_start()
	var count: PackedInt32Array = w.interest_count()
	var ids: PackedInt32Array = w.interest_ids()
	assert_int(start.size()).is_equal(Vision.TEAMS * InterestGrid.CELLS)
	assert_int(count.size()).is_equal(Vision.TEAMS * InterestGrid.CELLS)
	assert_int(ids.size()).is_equal(Vision.TEAMS * InterestGrid.STRIDE)
	for t: int in Vision.TEAMS:
		var want: Dictionary = {}
		var n: int = 0
		for list: PackedInt32Array in [st.structures, st.ships, st.ground, st.wrecks]:
			for s: int in list:
				if (st.visible_mask[s] >> t) & 1 == 1:
					var c: int = Sphere.cell_of(st.pos[s], Sphere.GRID_INTEREST)
					var a: Array = want.get(c, [])
					a.append(st.id_of(s))
					want[c] = a
					n += 1
				elif st.team[s] == t:
					fail("own-team slot %d without bit %d" % [s, t])
		assert_int(w.vision.grid.list_size[t]).is_equal(n)
		for c: int in InterestGrid.CELLS:
			var got: PackedInt32Array = w.vision.ids_in_cell(t, c)
			var flat: PackedInt32Array = ids.slice(start[t * InterestGrid.CELLS + c], start[t * InterestGrid.CELLS + c] + count[t * InterestGrid.CELLS + c])
			assert_array(Array(flat)).is_equal(Array(got))
			var g: Array = Array(got)
			g.sort()
			var e: Array = want.get(c, [])
			e.sort()
			assert_array(g).is_equal(e)


## Two identically built worlds produce identical masks and identical interest arrays tick by tick.
func test_two_worlds_identical() -> void:
	var w1: SimWorld = _moving_world()
	var w2: SimWorld = _moving_world()
	for _i: int in 45:
		w1.step()
		w2.step()
		var _a: Array[SimEvent] = w1.drain_events()
		var _b: Array[SimEvent] = w2.drain_events()
		assert_bool(w1.store().visible_mask == w2.store().visible_mask).is_true()
	assert_bool(w1.interest_ids() == w2.interest_ids()).is_true()
	assert_bool(w1.interest_start() == w2.interest_start()).is_true()
	assert_bool(w1.interest_count() == w2.interest_count()).is_true()
	var any_other: bool = false
	for s: int in w1.store().ships:
		if w1.store().visible_mask[s] & ~(1 << w1.store().team[s]) & 0xFF != 0:
			any_other = true
	assert_bool(any_other).is_true()


## S4 with Vision live: serialize mid-stagger, deserialize, step both: identical bytes and masks every tick. The
## deserialized world's lists are rebuilt from the mask with current cells: the same ids per team at once, and the
## same ids per cell once every team has passed again (an entity may cross a cell between its team's passes).
func test_serialize_round_trip_keeps_vision() -> void:
	var w1: SimWorld = _moving_world()
	for _i: int in 20:
		w1.step()
		var _a: Array[SimEvent] = w1.drain_events()
	var w3: SimWorld = SimWorld.deserialize(w1.serialize(), WorldTestKit.content(), null)
	assert_object(w3).is_not_null()
	for t: int in Vision.TEAMS:
		var x: Array = Array(w1.interest_ids().slice(t * InterestGrid.STRIDE, t * InterestGrid.STRIDE + w1.vision.grid.list_size[t]))
		var y: Array = Array(w3.interest_ids().slice(t * InterestGrid.STRIDE, t * InterestGrid.STRIDE + w3.vision.grid.list_size[t]))
		x.sort()
		y.sort()
		assert_array(y).is_equal(x)
	for _i: int in 25:
		w1.step()
		w3.step()
		var _a: Array[SimEvent] = w1.drain_events()
		var _b: Array[SimEvent] = w3.drain_events()
		assert_bool(w1.store().visible_mask == w3.store().visible_mask).is_true()
	assert_bool(w1.serialize() == w3.serialize()).is_true()
	_assert_same_lists(w1, w3)


## rebuild_lists (deserialize) never changes a bit: an own-team unit added after its team's pass keeps bit 0 clear
## and stays out of the list until the next pass; the lists hold exactly the slots with the bit.
func test_rebuild_lists_keeps_mask() -> void:
	var w: SimWorld = VisionTestKit.world()
	VisionTestKit.scatter(w, Rng.new(23), 120)
	VisionTestKit.sense(w)
	var late: int = VisionTestKit.put(w, &"dart", 0, VisionTestKit.at(700.0, 50.0))
	w.spatial.rebuild()
	var before: PackedByteArray = w.store().visible_mask.duplicate()
	w.vision.rebuild_lists()
	assert_bool(w.store().visible_mask == before).is_true()
	assert_bool(VisionTestKit.visible(w, 0, late)).is_false()
	for t: int in Vision.TEAMS:
		var n: int = 0
		for list: PackedInt32Array in [w.store().structures, w.store().ships, w.store().ground, w.store().wrecks]:
			for s: int in list:
				n += (w.store().visible_mask[s] >> t) & 1
		assert_int(w.vision.grid.list_size[t]).is_equal(n)


func _rungs(level: int) -> PackedInt32Array:
	var r: PackedInt32Array = PackedInt32Array()
	for k: int in level:
		var _a: bool = r.push_back(k + 1)
	return r


func _moving_world() -> SimWorld:
	var w: SimWorld = VisionTestKit.world()
	VisionTestKit.scatter(w, Rng.new(7), 220)
	var st: EntityStore = w.store()
	for s: int in st.ships:
		st.pos[s] = st.pos[s].normalized() * (R + 400.0 + float(s % 7) * 100.0)
		st.vel[s] = Sphere.tangent_frame(st.pos[s]).x * 120.0
		st.fwd[s] = Sphere.tangent_frame(st.pos[s]).x
		st.fuel[s] = 1000.0
	return w


func _assert_same_lists(a: SimWorld, b: SimWorld) -> void:
	for t: int in Vision.TEAMS:
		assert_int(b.vision.grid.list_size[t]).is_equal(a.vision.grid.list_size[t])
		for c: int in InterestGrid.CELLS:
			var x: Array = Array(a.vision.ids_in_cell(t, c))
			var y: Array = Array(b.vision.ids_in_cell(t, c))
			x.sort()
			y.sort()
			assert_array(y).is_equal(x)
