extends GdUnitTestSuite
## GD-23 R10 (sim/relay/MODULE.md; 03 s4.2 row 10): the relay pass with 2 Relay Stations, a Hauler docked on one, and 200 ships
## and 200 ground units around. Time goes through PerfGate (report-only unless PLANEWAR_PINNED_RUNNER=1).

const K: GDScript = preload("res://test/unit/sim/relay/relay_test_kit.gd")
const CITE: String = "03 s4.2 row 10 (economy), GD-23 R10"
const REPS: int = 300
const BOUND_US: float = 300.0
const IDLE_US: float = 20.0


func test_the_relay_pass_at_full_load_is_cheap() -> void:
	var w: SimWorld = K.world()
	var r0: int = K.relay(w, 0.0)
	var _r1: int = K.relay(w, 3000.0)
	var _h: int = K.docked(w, &"hauler", 0, r0)
	for k: int in 100:
		var _s: int = K.unit(w, &"dart", 1, 1000.0 + 20.0 * float(k))
	for k: int in 100:
		var _g: int = K.unit(w, &"harvester", 1, -1000.0 - 20.0 * float(k))
	var relay: RelayCapture = K.capture(w)
	K.pass_n(w, 2)
	var t0: int = Time.get_ticks_usec()
	for _i: int in REPS:
		relay.step(K.DT)
	var us: float = float(Time.get_ticks_usec() - t0) / float(REPS)
	assert_bool(PerfGate.check("relay_step_2_relays_200_units", us, BOUND_US, CITE)).is_true()


func test_a_world_without_a_relay_station_costs_next_to_nothing() -> void:
	var w: SimWorld = K.world()
	for k: int in 50:
		var _s: int = K.unit(w, &"dart", 1, 1000.0 + 20.0 * float(k))
	var relay: RelayCapture = K.capture(w)
	var t0: int = Time.get_ticks_usec()
	for _i: int in 10000:
		relay.step(K.DT)
	var us: float = float(Time.get_ticks_usec() - t0) / 10000.0
	assert_bool(PerfGate.check("relay_step_none", us, IDLE_US, CITE)).is_true()
