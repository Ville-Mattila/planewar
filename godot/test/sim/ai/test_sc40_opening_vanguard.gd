extends GdUnitTestSuite
## SC-40 commander_opening_vanguard (05 s11.2; AI-23): one Normal bot on cradle slot 0, the Vanguard book, the R0 B.6
## start kit, no enemy. Pass: a Dart is airborne by 0:45; every book step up to the first Outpost executed by 6:00; the
## Outpost is placed with a friendly unit inside 300 m and >= 800 m from the Core; no REJECTED_PLACEMENT repeated for the
## same site; no REJECTED_LOCKED. The run is a real world: the sim validates every BUILD / PRODUCE the bot submits.

const HZ: int = Ai23Kit.HZ
const AIRBORNE_BY_S: int = 45
const TOTAL_S: int = 360


func test_sc40_commander_opening_vanguard() -> void:
	var w: SimWorld = Ai23Kit.world(40, &"cradle", false)
	var cb: CommanderBrain = Ai23Kit.commander(&"cradle", [Ai23Kit.book(&"vanguard_standard")])
	var _d: AiDriver = Ai23Kit.driver(w, cb, [0])
	var dart: int = Ai23Kit.def(&"dart")
	var outpost: int = Ai23Kit.def(&"outpost")
	var airborne_tick: int = -1
	var placed_dist: float = -1.0
	var presence: float = INF
	var core: Vector3 = Ai23Kit.sites().slot_dir(0)
	var st: EntityStore = w.store()
	for tick: int in TOTAL_S * HZ:
		w.step()
		var _e: Array[SimEvent] = w.drain_events()
		if airborne_tick < 0:
			for s: int in st.ships:
				if st.def_id[s] == dart and st.owner[s] == 0 and (st.flags[s] & (EntityStore.F_DOCKED | EntityStore.F_LANDED)) == 0 \
						and Sphere.altitude(st.pos[s]) - w.terrain().height_at(st.pos[s]) > 20.0:   # above the ground (BUG-3: cradle's terrain)
					airborne_tick = tick
		if placed_dist < 0.0:
			for s: int in st.structures:
				if st.def_id[s] == outpost and st.owner[s] == 0:
					placed_dist = st.pos[s].normalized().angle_to(core) * Sphere.PLANET_RADIUS
					presence = _nearest_unit_m(w, st.pos[s])
	assert_int(airborne_tick).override_failure_message("no Dart airborne").is_greater_equal(0)
	assert_int(airborne_tick).override_failure_message("Dart airborne at %.1f s" % (float(airborne_tick) / HZ)).is_less_equal(AIRBORNE_BY_S * HZ)
	var run: BookRun = cb.run_of(0)
	assert_object(run).is_not_null()
	assert_str(String(cb.book_of(0).id)).is_equal("vanguard_standard")
	var first_outpost: int = 0   # the first `build outpost` step of the book
	while cb.book_of(0).kind_of(first_outpost) != OpeningBook.Do.BUILD or cb.book_of(0).def_of(first_outpost) != outpost:
		first_outpost += 1
	for i: int in first_outpost + 1:
		var ok: bool = run.outcome[i] == BookRun.DONE or run.outcome[i] == BookRun.SKIPPED_HAVE
		assert_bool(ok).override_failure_message("step %d outcome %d" % [i, run.outcome[i]]).is_true()
	assert_float(placed_dist).override_failure_message("no Outpost placed").is_greater_equal(800.0)
	assert_float(presence).override_failure_message("no friendly unit near the Outpost site: %.0f m" % presence).is_less_equal(300.0)
	assert_int(cb.host.st_repeat_rejects).is_equal(0)
	assert_int(cb.host.st_locked).is_equal(0)
	assert_int(cb.host.st_cmds - cb.host.st_accepted).override_failure_message("refused: %s" % str(cb.host.st_by_code)).is_equal(0)
	assert_int(cb.st_thinks).is_greater(300)


# Distance to the nearest team-0 ship or ground unit that is not docked.
func _nearest_unit_m(w: SimWorld, p: Vector3) -> float:
	var st: EntityStore = w.store()
	var best: float = INF
	for list: PackedInt32Array in [st.ships, st.ground]:
		for s: int in list:
			if st.team[s] == 0 and (st.flags[s] & EntityStore.F_DOCKED) == 0:
				best = minf(best, st.pos[s].distance_to(p))
	return best
