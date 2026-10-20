extends GdUnitTestSuite
## AI-11 perf note (05 s10 think row 25 us for 6 probes + 1 neighbour query + 1 choice point; act row 6 us per ship):
## EscortPilot.think (order read, formation velocity, Separation.push = one ids_near over the collision hash) and
## EscortPilot.act (track_velocity) per call on a real SimWorld with a Bomber, 4 escort Darts in slots and 12 more friendly
## Darts within ~300 m. Best of 6 batches; printed for the PR, the bounds are loose regression guards.

const N: int = 200


func _world() -> Array:
	var w: SimWorld = WorldTestKit.world(31)
	var vb: Vector3 = Vector3(0, 70, 0)
	var bomber: int = WorldTestKit.spawn(w, &"bomber", 0, 0, WorldTestKit.at(300.0, 0.0), vb)
	var darts: PackedInt32Array = PackedInt32Array()
	for k: int in 16:
		var p: Vector3 = WorldTestKit.at(300.0 + 25.0 * float(k % 3), -60.0 - 35.0 * float(k)).rotated(Vector3(1, 0, 0), 0.0)
		p.z += 45.0 * float((k % 5) - 2)
		var _a: bool = darts.push_back(WorldTestKit.spawn(w, &"dart", 0, 0, p, vb))
	return [w, bomber, darts]


func test_perf_think_and_act() -> void:
	var r: Array = _world()
	var w: SimWorld = r[0]
	var bomber: int = r[1]
	var darts: PackedInt32Array = r[2]
	var st: AiState = AiState.new()
	var pilot: EscortPilot = FormationKit.pilot(&"dart")
	for i: int in 4:
		st.cls[EntityId.slot(darts[i])] = 0
		FormationKit.escort_order(w, PackedInt32Array([darts[i]]), bomber)
	for id: int in darts:
		st.cls[EntityId.slot(id)] = 0
	var v: SimView = w.view()
	var inp: PilotInput = PilotInput.new()
	var us_think: float = INF
	var us_act: float = INF
	for _b: int in 6:
		var t0: int = Time.get_ticks_usec()
		for k: int in N:
			var _o: EscortPilot.Outcome = pilot.think(darts[k % 4], v, st, 100 + k)
		var t1: int = Time.get_ticks_usec()
		for k: int in N:
			var _a: bool = pilot.act(darts[k % 4], v, st, inp)
		var t2: int = Time.get_ticks_usec()
		us_think = minf(us_think, float(t1 - t0) / float(N))
		us_act = minf(us_act, float(t2 - t1) / float(N))
	print("AI-11 perf: EscortPilot.think %.1f us (05 s10 think row 25 us), act %.1f us (act row 6 us), dev machine, 17 ships near" % [us_think, us_act])
	assert_float(us_think).is_less(200.0)
	assert_float(us_act).is_less(100.0)
