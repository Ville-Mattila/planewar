extends GdUnitTestSuite
## GD-39 (sim/salvage/MODULE.md W11; 03 s4.2 row 10, the Economy row): the path-weight hook costs per wreck event only. The
## counters are hard asserts; the time of one leave (scan of 200 wrecks + a baked read) goes through PerfGate.

const K: GDScript = preload("res://test/unit/sim/salvage/salvage_test_kit.gd")
const CITE: String = "03 s4.2 row 10 (economy), GD-39 W11"
const REPS: int = 200


# A surface point `metres` of arc along +Y from +X (K.at is a flat offset and bunches up far out).
func _arc(metres: float) -> Vector3:
	var a: float = metres / Sphere.PLANET_RADIUS
	return Vector3(cos(a), sin(a), 0.0) * Sphere.PLANET_RADIUS


func test_a_leave_at_the_standard_cap_scans_once_and_reads_once() -> void:
	var w: SimWorld = K.world()
	var paths: WreckPaths = w.economy().salvage.paths
	var fill: int = 0
	while w.store().wrecks.size() < 200:
		var s: int = K.wreck_at(w, &"dart", 60.0, _arc(3000.0 + 80.0 * float(fill)))
		paths.pathing = w._pathing
		paths.rest(s)
		fill += 1
	assert_int(paths.sets).is_equal(200)
	var probe: int = w.store().wrecks[100]
	var scans: int = paths.scans
	var reads: int = paths.reads
	var t0: int = Time.get_ticks_usec()
	for i: int in REPS:
		paths.lift(probe)                                                       # tethered flag not set: the probe itself rests, so the scan finds it
	var us: float = float(Time.get_ticks_usec() - t0) / float(REPS)
	assert_int(paths.scans - scans).is_equal(REPS)                               # one scan per event
	assert_int(paths.reads).is_equal(reads)                                      # shared cell: no baked read
	assert_bool(PerfGate.check("wreck_paths_leave_200_wrecks", us, 300.0, CITE)).is_true()


func test_a_core_death_sets_seven_cells_and_no_idle_tick_touches_pathing() -> void:
	var w: SimWorld = K.world()
	var v: int = 0
	for f: int in PathGrid.FACES:
		v += w._pathing.version(f)
	var t0: int = Time.get_ticks_usec()
	var _ev: Array[SimEvent] = K.kill(w, K.put(w, &"core", 0, 0, 0.0, 1500.0))
	var us: float = float(Time.get_ticks_usec() - t0)
	var after: int = 0
	for f: int in PathGrid.FACES:
		after += w._pathing.version(f)
	assert_int(w.store().wrecks.size()).is_equal(7)
	assert_int(after - v).is_equal(w.economy().salvage.paths.sets)
	var idle: int = w.economy().salvage.paths.sets
	var _i: Array[SimEvent] = K.steps(w, 100)
	assert_int(w.economy().salvage.paths.sets).is_equal(idle)
	assert_bool(PerfGate.check("wreck_paths_core_death_tick", us, 3000.0, CITE)).is_true()
