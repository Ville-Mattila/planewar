extends GdUnitTestSuite
## GD-14 I9 (sim/harvest/MODULE.md; 03 s4.2 row 10): the Ice pass with 24 Extractors on 24 nodes (half piped), 40 Haulers
## (half loading, half unloading) and 3 Refineries. The time goes through PerfGate (report-only unless
## PLANEWAR_PINNED_RUNNER=1); an idle pass (no Extractor, no Hauler) costs next to nothing.

const K: GDScript = preload("res://test/unit/sim/harvest/ice_test_kit.gd")
const CITE: String = "03 s4.2 row 10 (economy), GD-14 I9"
const REPS: int = 300
const BOUND_US: float = 300.0     ## debug build: ~40 % of the 0.8 ms row-10 budget at the full load below
const IDLE_US: float = 5.0


func _scene() -> SimWorld:
	var w: SimWorld = K.world()
	for k: int in 3:
		var _r: int = HarvestTestKit.refinery(w, -9000.0 - 400.0 * float(k))
	for k: int in 24:
		var east: float = 2000.0 + 400.0 * float(k)
		var _n: int = K.node(w, east, 6000, 1.5)
		var e: int = K.extractor(w, east)
		w.store().cargo[e] = 300.0
	for k: int in 40:
		if k % 2 == 0:
			var h: int = K.hauler(w, 2000.0 + 400.0 * float(k % 24))
			w.store().cargo[h] = 0.0
		else:
			var u: int = K.hauler(w, -9000.0 - 400.0 * float(k % 3))
			w.store().cargo[u] = 200.0
	return w


func test_the_ice_pass_at_full_load_is_cheap() -> void:
	var w: SimWorld = _scene()
	K.pass_n(w, 2)
	var ice: IceExtract = w.economy().ice
	var t0: int = Time.get_ticks_usec()
	for _i: int in REPS:
		ice.step(K.DT)
	var us: float = float(Time.get_ticks_usec() - t0) / float(REPS)
	assert_bool(PerfGate.check("ice_step_24_extractors_40_haulers", us, BOUND_US, CITE)).is_true()


func _idle_world() -> SimWorld:
	var w: SimWorld = K.world()
	var _r: int = HarvestTestKit.refinery(w, 0.0)          # every match has a Refinery
	for k: int in 30:
		var _h: int = K.hauler(w, 2000.0 + 100.0 * float(k))   # Haulers with empty holds; no Extractor, no Ice anywhere
	return w


func test_an_idle_pass_in_a_realistic_world_scans_no_ship() -> void:
	var w: SimWorld = _idle_world()
	K.pass_n(w, 100)
	assert_int(w.economy().ice.ship_scans).is_equal(0)         # I9: no Extractor and no Ice in a hold: no ship pass
	var ice: IceExtract = w.economy().ice
	var t0: int = Time.get_ticks_usec()
	for _i: int in 10000:
		ice.step(K.DT)
	var us: float = float(Time.get_ticks_usec() - t0) / 10000.0
	assert_bool(PerfGate.check("ice_step_idle_realistic", us, IDLE_US, CITE)).is_true()


func test_a_hold_with_ice_wakes_the_pass_and_an_emptied_one_sleeps_again() -> void:
	var w: SimWorld = _idle_world()
	K.pass_n(w, 5)
	assert_int(w.economy().ice.ship_scans).is_equal(0)
	var h: int = w.store().ships[0]
	w.store().cargo[h] = 100.0
	w.store().cargo_kind[h] = 2
	w.store().pos[h] = w.store().pos[w.store().structures[0]]
	K.pass_n(w, 5)                                              # the ship count did not change: the count is stale, rescan on change
	var _extra: int = K.hauler(w, 9000.0)                       # a spawn re-counts the holds
	K.pass_n(w, 200)
	assert_float(w.store().cargo[h]).is_equal(0.0)              # unloaded at the Refinery (100 Ice at 40/s)
	var scans: int = w.economy().ice.ship_scans
	K.pass_n(w, 50)
	assert_int(w.economy().ice.ship_scans).is_equal(scans)      # empty again: asleep
