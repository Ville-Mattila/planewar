extends GdUnitTestSuite
## Unit tests for sim_ai/autopilot/landing_pilot.gd (AI-09; 05 s5.5 pad selection and reservation, s6 RTB rule)
## and the AI-09 AiState fields: pad scoring (eta, queue weights, fuel rejection, nearest fallback, exclusion,
## enemy pads), team-local pad claims (busy for the second ship, stale claims ignored), the RTB rule's distance
## term, DONE on dock, divert on an invalid pad or too many attempts, and the S4 round trip. The world is the
## LandingWorld FakeSimView of test/sim/ai.
## timing: runaway guards only (R0 B.17 A-97)

const R: float = Sphere.PLANET_RADIUS

var _world: LandingWorld
var _st: AiState
var _dart: ShipDef
var _pilot: LandingPilot


func before_test() -> void:
	_world = LandingWorld.new(Terrain.new(), FlightTestKit.common(), FlightTestKit.rules())
	_st = AiState.new(512)
	_dart = FlightTestKit.ship(&"dart")
	_pilot = Ai09Kit.pilot(_dart, _world)


func _dir(dist: float, az_deg: float) -> Vector3:
	var c: Vector3 = Vector3.RIGHT
	var f: Basis = Sphere.tangent_frame(c)
	var b: Vector3 = f.y * cos(deg_to_rad(az_deg)) + f.x * sin(deg_to_rad(az_deg))
	return c * cos(dist / R) + b * sin(dist / R)


func _ship_at(dist: float, az_deg: float, alt: float = 300.0, fuel01: float = 1.0) -> int:
	var p: Vector3 = _dir(dist, az_deg) * (R + alt)
	var n: Vector3 = p.normalized()
	var fwd: Vector3 = Sphere.tangent_frame(n).y
	var s: ShipState = FlightTestKit.spawn(_dart, p, fwd, n, fwd * _dart.v_cruise)
	s.fuel = fuel01 * _dart.fuel_s
	return _world.add_ship(_dart, s)


func test_select_pad_prefers_near_and_free() -> void:
	var near: int = _world.add_pad(_dir(1000.0, 0.0))
	var far: int = _world.add_pad(_dir(3000.0, 0.0))
	var id: int = _ship_at(0.0, 0.0)
	assert_int(_pilot.select_pad(id, _world, 0, _st)).is_equal(near)
	assert_int(_pilot.select_pad(id, _world, near, _st)).is_equal(far)     # divert: the current pad excluded
	# the near pad occupied: eta + 15 s and w_free 0.6 -> 0.6 / (1 + (9.1 + 15) / 60) = 0.43 < 1 / (1 + 27.3 / 60) = 0.69
	var other: int = _ship_at(1000.0, 0.0, 0.0)
	_world.dock_pad[_world.ship_index(other)] = near
	assert_int(_pilot.select_pad(id, _world, 0, _st)).is_equal(far)


func test_select_pad_ignores_enemy_and_dead_pads() -> void:
	var enemy: int = _world.add_pad(_dir(500.0, 0.0), 1)
	var dead: int = _world.add_pad(_dir(600.0, 0.0))
	var mine: int = _world.add_pad(_dir(4000.0, 0.0))
	_world.pad_alive[_world.pad_index(dead)] = 0
	var id: int = _ship_at(0.0, 0.0)
	assert_int(_pilot.select_pad(id, _world, 0, _st)).is_equal(mine)
	assert_int(enemy).is_not_equal(mine)


func test_select_pad_fuel_rejects_far_pads_and_falls_back_to_nearest() -> void:
	var near: int = _world.add_pad(_dir(2000.0, 0.0))
	var far: int = _world.add_pad(_dir(5000.0, 180.0))
	var id: int = _ship_at(0.0, 0.0, 300.0, 1.0)
	# full tank: occupy near so far scores better (0.6 / (1 + 33.2 / 60) < 1 / (1 + 45.5 / 60))
	var other: int = _ship_at(2000.0, 0.0, 0.0)
	_world.dock_pad[_world.ship_index(other)] = near
	assert_int(_pilot.select_pad(id, _world, 0, _st)).is_equal(far)
	_world.ss[_world.ship_index(id)].fuel = 0.2 * _dart.fuel_s    # 48 s: far needs 45.5 s * cruise burn + 30 s
	assert_int(_pilot.select_pad(id, _world, 0, _st)).is_equal(near)
	_world.ss[_world.ship_index(id)].fuel = 0.0                    # all rejected: nearest
	assert_int(_pilot.select_pad(id, _world, 0, _st)).is_equal(near)


func test_claim_makes_the_second_ship_hold() -> void:
	var pad: int = _world.add_pad(_dir(0.0, 0.0))
	var a: int = _ship_at(1000.0, 0.0)
	var b: int = _ship_at(1050.0, 10.0)
	_pilot.begin(a, pad, _st)
	_pilot.begin(b, pad, _st)
	_pilot.think(a, _world, _st)          # inside the gate: bearing, claim
	assert_int(_st.pad_claim[EntityId.slot(pad)]).is_equal(a)
	_pilot.think(b, _world, _st)
	assert_int(_st.land_flags[EntityId.slot(b)] & AiState.LAND_BUSY).is_equal(AiState.LAND_BUSY)
	assert_int(_st.land_flags[EntityId.slot(a)] & AiState.LAND_BUSY).is_equal(0)
	var out: PilotInput = PilotInput.new()
	assert_int(_pilot.act(b, _world, _st, out)).is_equal(LandingController.Phase.HOLD)
	# the claimant dies: the claim is stale, the pad is free for b
	_world.outcome[_world.ship_index(a)] = LandingWorld.Outcome.CRASHED
	_pilot.think(b, _world, _st)
	assert_int(_st.land_flags[EntityId.slot(b)] & AiState.LAND_BUSY).is_equal(0)
	assert_int(_pilot.act(b, _world, _st, out)).is_equal(LandingController.Phase.TRANSIT)   # HOLD ends
	_pilot.think(b, _world, _st)
	assert_int(_st.pad_claim[EntityId.slot(pad)]).is_equal(b)


func test_needs_rtb_distance_term() -> void:
	var _pad: int = _world.add_pad(_dir(0.0, 0.0))
	var near: int = _ship_at(1000.0, 0.0, 300.0, 0.30)
	var far: int = _ship_at(9000.0, 0.0, 300.0, 0.30)
	var low: int = _ship_at(1000.0, 0.0, 300.0, 0.24)
	assert_bool(_pilot.needs_rtb(near, _world)).is_false()     # 30 % > max(25 %, (9 + 30) / 240 * 1.2)
	assert_bool(_pilot.needs_rtb(far, _world)).is_true()       # (82 + 30) / 240 * 1.2 = 56 %
	assert_bool(_pilot.needs_rtb(low, _world)).is_true()       # below the 25 % floor


func test_think_marks_done_when_docked_and_diverts_on_invalid_pad() -> void:
	var pad_a: int = _world.add_pad(_dir(0.0, 0.0))
	var pad_b: int = _world.add_pad(_dir(1500.0, 90.0))
	var id: int = _ship_at(800.0, 0.0)
	_pilot.begin(id, pad_a, _st)
	_world.pad_alive[_world.pad_index(pad_a)] = 0
	_pilot.think(id, _world, _st)
	assert_int(_st.aux_id[EntityId.slot(id)]).is_equal(pad_b)
	assert_int(_pilot.phase(id, _st)).is_equal(LandingController.Phase.TRANSIT)
	_st.land_attempts[EntityId.slot(id)] = 4                      # > max_attempts (3): select another pad
	_world.pad_alive[_world.pad_index(pad_a)] = 1
	_pilot.think(id, _world, _st)
	assert_int(_st.aux_id[EntityId.slot(id)]).is_equal(pad_a)
	assert_int(_st.land_attempts[EntityId.slot(id)]).is_equal(0)
	_world.dock_pad[_world.ship_index(id)] = pad_a
	_pilot.think(id, _world, _st)
	assert_int(_pilot.phase(id, _st)).is_equal(LandingController.Phase.DONE)


func test_ai_state_round_trip_with_landing_fields() -> void:
	var st: AiState = AiState.new(64)
	var id: int = EntityId.make(7, 3)
	st.cls[7] = 1
	st.eid[7] = id
	st.land_phase[7] = LandingController.Phase.HOVER
	st.land_attempts[7] = 2
	st.land_abort[7] = LandingController.Abort.GLIDE
	st.land_flags[7] = AiState.LAND_BUSY
	st.land_bearing[7] = Vector3(0.0, 0.6, 0.8)
	st.land_mark[7] = Vector3(1.0, 0.0, 0.0)
	st.land_ga_dir[7] = Vector3(0.0, -0.6, -0.8)
	st.integ[7] = Vector2(0.25, -0.5)
	st.ground_h[7] = 123.5
	st.lift[7] = 4.25
	st.pad_claim[40] = id
	var bytes: PackedByteArray = st.serialize()
	var b: AiState = AiState.new(8)
	assert_bool(b.deserialize(bytes)).is_true()
	assert_bool(b.serialize() == bytes).is_true()
	assert_int(b.land_phase[7]).is_equal(LandingController.Phase.HOVER)
	assert_vector(b.land_bearing[7]).is_equal(Vector3(0.0, 0.6, 0.8))
	assert_vector(b.integ[7]).is_equal(Vector2(0.25, -0.5))
	assert_int(b.pad_claim[40]).is_equal(id)
	assert_bool(b.deserialize(bytes.slice(0, bytes.size() - 2))).is_false()
	assert_int(b.pad_claim[40]).is_equal(0)


func test_think_and_act_cost() -> void:
	# Perf note (05 s10): one LandingPilot.think (TerrainProbe 6 samples + 1 height, pad flags, claim) against the
	# 25 us think row, one act (snapshot fill + LandingController.step) against the 6 us act row. Best of 6.
	var pad: int = _world.add_pad(_dir(0.0, 0.0))
	var id: int = _ship_at(900.0, 0.0)
	_pilot.begin(id, pad, _st)
	var out: PilotInput = PilotInput.new()
	var n: int = 2000
	var us_t: float = INF
	var us_a: float = INF
	for batch: int in 6:
		var t0: int = Time.get_ticks_usec()
		for i: int in n:
			_pilot.think(id, _world, _st)
		us_t = minf(us_t, float(Time.get_ticks_usec() - t0) / float(n))
		t0 = Time.get_ticks_usec()
		for i: int in n:
			var _p: int = _pilot.act(id, _world, _st, out)
		us_a = minf(us_a, float(Time.get_ticks_usec() - t0) / float(n))
	print("PERF LandingPilot.think %.2f us/call, act %.2f us/call (LandingWorld view)" % [us_t, us_a])
	# runaway guards (R0 B.17 A-97): measured think 19.5 us (bound 500), act 19.9 us (bound 200, 10x)
	assert_float(us_t).is_less(500.0)
	assert_float(us_a).is_less(200.0)
