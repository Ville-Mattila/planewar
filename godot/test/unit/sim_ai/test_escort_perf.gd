extends GdUnitTestSuite
## AI-11 perf note (05 s10 think row 25 us for 6 probes + 1 neighbour query + 1 choice point; act row 6 us per ship):
## EscortPilot.think (order read, roster, formation velocity, Separation.push every second think = one ids_near on the
## collision hash's ring path) and EscortPilot.act (track_velocity) on a real SimWorld with a Bomber, 4 escort Darts in
## slots, 12 more friendly Darts within ~300 m and FAR_SHIPS friendly Darts spread over the sphere (a match-sized
## population: a query that fell off the ring path would scan their cells). Three cases: no threat, an engage-gate case (a
## qualifying threat for the slot that may not break, so the gate runs every think) and act. Per-call timings, so the
## mean includes the refresh calls and the held calls; mean and p95 are printed for the PR. Bounds are the 05 s10 rows with
## a CI factor of `CI_FACTOR` (shared runners are slower than the dev machine; precedent test_overlays_perf).

const CALLS: int = 1000
const BATCHES: int = 6
const FAR_SHIPS: int = 240
const THINK_ROW_US: float = 25.0
const ACT_ROW_US: float = 6.0
const CI_FACTOR: float = 2.0


func _world() -> Array:
	var rules: MatchRules = WorldTestKit.rules()
	rules.caps.units = 2000   # a match-sized population for one player
	var w: SimWorld = WorldTestKit.world(31, rules)
	var vb: Vector3 = Vector3(0, 70, 0)
	var bomber: int = WorldTestKit.spawn(w, &"bomber", 0, 0, WorldTestKit.at(300.0, 0.0), vb)
	var darts: PackedInt32Array = PackedInt32Array()
	for k: int in 16:
		var p: Vector3 = WorldTestKit.at(300.0 + 25.0 * float(k % 3), -60.0 - 35.0 * float(k))
		p.z += 45.0 * float((k % 5) - 2)
		var _a: bool = darts.push_back(WorldTestKit.spawn(w, &"dart", 0, 0, p, vb))
	var foe: int = WorldTestKit.spawn(w, &"dart", 1, 1, WorldTestKit.at(300.0, 600.0), Vector3(0, 60, 0))
	var def_id: int = WorldTestKit.def_id(&"dart")
	for k: int in FAR_SHIPS:   # spread over many hash cells, 1.5 km and more from the formation
		var lat: float = deg_to_rad(-60.0 + 120.0 * float(k % 20) / 19.0)
		var lon: float = deg_to_rad(8.0 + 340.0 * float(k) / float(FAR_SHIPS))
		var pos: Vector3 = Sphere.from_lat_lon(lat, lon, Sphere.PLANET_RADIUS + 300.0)
		var code: int = CommandResult.Code.REJECTED_RATE
		while code == CommandResult.Code.REJECTED_RATE:   # the debug spawns share the player's command token bucket
			code = w.apply_command(CommandPayload.debug_spawn(0, def_id, 0, 0, pos, Vector3.ZERO, Vector3(0, 1, 0))).code
			w.step()
		assert(code == CommandResult.Code.ACCEPTED, "spawn %d: code %d" % [k, code])
	w.step()
	return [w, bomber, darts, foe]


func _stats(us: PackedFloat32Array) -> Vector3:   # mean, median, p95
	var a: PackedFloat32Array = us.duplicate()
	a.sort()
	var sum: float = 0.0
	for x: float in us:
		sum += x
	return Vector3(sum / float(us.size()), a[a.size() / 2], a[int(float(a.size()) * 0.95)])


func test_perf_think_and_act() -> void:
	var r: Array = _world()
	var w: SimWorld = r[0]
	var bomber: int = r[1]
	var darts: PackedInt32Array = r[2]
	var st: AiState = AiState.new()
	var pilot: EscortPilot = FormationKit.pilot(&"dart")
	for id: int in darts:
		st.cls[EntityId.slot(id)] = 0
		st.eid[EntityId.slot(id)] = id
	for i: int in 4:
		FormationKit.escort_order(w, PackedInt32Array([darts[i]]), bomber)
	var foe: int = r[3]
	for _k: int in 12:
		w.step()
	var v: SimView = w.view()
	for i: int in 4:   # slots 0..3
		var _o: EscortPilot.Outcome = pilot.think(darts[i], v, st, 100)
	var inp: PilotInput = PilotInput.new()
	var sc: Vector3 = Vector3(INF, 0.0, 0.0)
	var sg: Vector3 = Vector3(INF, 0.0, 0.0)
	var sa: Vector3 = Vector3(INF, 0.0, 0.0)
	for _b: int in BATCHES:   # best batch by mean: the desktop scheduler's noise is larger than the code
		var calm: PackedFloat32Array = PackedFloat32Array()
		var gate: PackedFloat32Array = PackedFloat32Array()
		var act: PackedFloat32Array = PackedFloat32Array()
		var _n: int = calm.resize(CALLS) | gate.resize(CALLS) | act.resize(CALLS)
		for k: int in CALLS:
			var id: int = darts[k % 4]
			var t0: int = Time.get_ticks_usec()
			var _a: EscortPilot.Outcome = pilot.think(id, v, st, 100 + k)
			var t1: int = Time.get_ticks_usec()
			calm[k] = float(t1 - t0)
			var _b2: EscortPilot.Outcome = pilot.think(darts[0], v, st, 100 + k, foe, 0.9)   # slot 0 may not break: the gate runs
			var t2: int = Time.get_ticks_usec()
			gate[k] = float(t2 - t1)
			var _c: bool = pilot.act(id, v, st, inp)
			act[k] = float(Time.get_ticks_usec() - t2)
		sc = _best(sc, _stats(calm))
		sg = _best(sg, _stats(gate))
		sa = _best(sa, _stats(act))
	print("AI-11 perf (%d far ships, best of %d batches of %d): think mean %.1f / median %.1f / p95 %.1f us; threat-gate think mean %.1f / median %.1f / p95 %.1f us (row %.0f); act mean %.1f / p95 %.1f us (row %.0f)" % [
		FAR_SHIPS, BATCHES, CALLS, sc.x, sc.y, sc.z, sg.x, sg.y, sg.z, THINK_ROW_US, sa.x, sa.z, ACT_ROW_US])
	assert_float(sc.x).is_less(THINK_ROW_US * CI_FACTOR)
	assert_float(sg.x).is_less(THINK_ROW_US * CI_FACTOR)
	assert_float(sa.x).is_less(ACT_ROW_US * CI_FACTOR)


func _best(a: Vector3, b: Vector3) -> Vector3:
	return b if b.x < a.x else a
