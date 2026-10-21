extends GdUnitTestSuite
## GD-19 W10 (sim/salvage/MODULE.md; 03 s4.2 row 10): the wreck pass on a scene where wrecks exist: 200 live wrecks (the
## standard cap), 8 Foundry Haulers towing two each, 8 Haulers with a TOW order on a wreck out of reach, 6 Refineries.
## The work counters are hard asserts; the time goes through PerfGate (report-only unless PLANEWAR_PINNED_RUNNER=1).

const K: GDScript = preload("res://test/unit/sim/salvage/salvage_test_kit.gd")
const CITE: String = "03 s4.2 row 10 (economy), GD-19 W10"
const REPS: int = 300
const BOUND_US: float = 200.0


func _scene() -> SimWorld:
	var w: SimWorld = K.world()
	for k: int in 6:
		var _r: int = K.put(w, &"refinery", 0, 0, 0.0, -9000.0 - 400.0 * float(k))
	for k: int in 8:
		var east: float = 300.0 * float(k)
		var h: int = K.put(w, &"hauler", K.FOUNDRY_SLOT, 0, 20.0, east)
		var a: int = K.wreck_at(w, &"shipyard", 80.0, K.at(0.0, east))
		var b: int = K.wreck_at(w, &"shipyard", 80.0, K.at(0.0, east + 4.0))
		assert_int(w.economy().salvage.try_attach(h, a)).is_equal(Salvage.Hook.OK)
		assert_int(w.economy().salvage.try_attach(h, b)).is_equal(Salvage.Hook.OK)
	var fill: int = 0
	while w.store().wrecks.size() < 200:
		var _x: int = K.wreck_at(w, &"dart", 60.0, K.at(0.0, 3000.0 + 30.0 * float(fill)))
		fill += 1
	for k: int in 8:
		var h: int = K.put(w, &"hauler", 0, 0, 20.0, 6000.0 + 300.0 * float(k))
		K.haul(w, h, OrderSpec.HaulMode.TOW, w.store().id_of(w.store().wrecks[40 + k]))
	return w


func test_the_wreck_pass_at_the_standard_cap_is_cheap() -> void:
	var w: SimWorld = _scene()
	var st: EntityStore = w.store()
	var sal: Salvage = w.economy().salvage
	assert_int(st.wrecks.size()).is_equal(200)
	var tethered: int = 0
	for s: int in st.wrecks:
		tethered += 1 if K.tethered(w, s) else 0
	assert_int(tethered).is_equal(16)
	var _spawned: Array[SimEvent] = w.drain_events()                          # the SPAWN events of the scene setup
	var before: PackedByteArray = WorldTestKit.store_bytes(w)
	var t0: int = Time.get_ticks_usec()
	for i: int in REPS:
		sal.step(w.tick() + i)
	var us: float = float(Time.get_ticks_usec() - t0) / float(REPS)
	assert_array(WorldTestKit.store_bytes(w)).override_failure_message("a pass with nothing to do changes the store").is_equal(before)
	assert_int(w.drain_events().size()).is_equal(0)
	assert_bool(PerfGate.check("salvage_step_200_wrecks_16_tows", us, BOUND_US, CITE)).is_true()


func test_no_wrecks_costs_nothing() -> void:
	var w: SimWorld = K.world()
	var sal: Salvage = w.economy().salvage
	var t0: int = Time.get_ticks_usec()
	for i: int in 10000:
		sal.step(i)
	var us: float = float(Time.get_ticks_usec() - t0) / 10000.0
	assert_int(w.store().wrecks.size()).is_equal(0)
	assert_bool(PerfGate.check("salvage_step_no_wrecks", us, 5.0, CITE)).is_true()
