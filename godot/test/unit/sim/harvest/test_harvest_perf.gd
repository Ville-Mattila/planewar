extends GdUnitTestSuite
## GD-12 H9 (sim/harvest/MODULE.md; 03 s4.2 row 10): the Harvester pass with 200 ground units (the standard cap), half
## mining in 4 fields, a quarter waiting at 3 Refineries, the rest travelling. The time goes through PerfGate
## (report-only unless PLANEWAR_PINNED_RUNNER=1); the pass must not change the units it has nothing to do for.

const K: GDScript = preload("res://test/unit/sim/harvest/harvest_test_kit.gd")
const CITE: String = "03 s4.2 row 10 (economy), GD-12 H9"
const REPS: int = 300
const BOUND_US: float = 1000.0     ## debug build, all 200 units active (a real team runs a few dozen)


func _scene() -> SimWorld:
	var w: SimWorld = K.world()
	for k: int in 3:
		var _r: int = K.refinery(w, -9000.0 - 400.0 * float(k))
	for k: int in 4:
		var _f: int = K.field(w, 2000.0 + 600.0 * float(k), 6000, 2.0, 150.0, 100)
	for n: int in 200:
		var east: float = 2000.0 + 600.0 * float(n % 4)
		var h: int = K.harvester(w, east + 0.5 * float(n / 4))
		if n % 4 == 3:
			w.store().cargo[h] = 300.0
	return w


func test_the_harvester_pass_at_the_unit_cap_is_cheap() -> void:
	var w: SimWorld = _scene()
	K.step(w, 2)                                                  # claims are made
	var mining: int = 0
	for s: int in w.store().ground:
		mining += 1 if Harvest.state_of(w.store().link[s]) == Harvest.State.MINING else 0
	assert_int(mining).is_greater(100)
	var hv: Harvest = w.economy().harvest
	var t0: int = Time.get_ticks_usec()
	for i: int in REPS:
		hv.step(w.tick() + 3 + i, 1.0 / 30.0)
	var us: float = float(Time.get_ticks_usec() - t0) / float(REPS)
	assert_bool(PerfGate.check("harvest_step_200_harvesters", us, BOUND_US, CITE)).is_true()


func test_no_ground_units_and_no_fields_costs_nothing() -> void:
	var w: SimWorld = K.world()
	var hv: Harvest = w.economy().harvest
	var t0: int = Time.get_ticks_usec()
	for i: int in 10000:
		hv.step(i, 1.0 / 30.0)
	var us: float = float(Time.get_ticks_usec() - t0) / 10000.0
	assert_bool(PerfGate.check("harvest_step_idle", us, 5.0, CITE)).is_true()
