extends GdUnitTestSuite
## AI-11 perf note (05 s10 think row 25 us for 6 probes + 1 neighbour query + 1 choice point; act row 6 us per ship):
## EscortPilot.think (order read, roster, formation velocity, Separation.term: one ids_near on the collision hash's ring path every second think in steady formation, every think
## while a pair closes) and EscortPilot.act (track_velocity) on a real SimWorld with a Bomber, 4 escort Darts in
## slots, 12 more friendly Darts within ~300 m and FAR_SHIPS friendly Darts spread over the sphere (a match-sized
## population: a query that fell off the ring path would scan their cells). Three cases: no threat, an engage-gate case (a
## qualifying threat for the slot that may not break, so the gate runs every think) and act. Think timings are per call, so
## the mean includes the refresh calls and the held calls; mean and p95 are printed for the PR. Act is timed the way the
## 05 s10 act row is defined (a per-tick batch over the AI ships, divided by the count; `AiDriver` acts its ships back to
## back): `ACT_BATCHES` consecutive act loops over the escorts after one untimed warm-up loop, minimum batch mean (AI-40;
## the minimum is the robust location estimate for timing noise that only adds, Chen and Revels 2016, "Robust benchmarking
## in noisy environments"; the same statistic as the sim/steer per-call perf tests). Bounds are the 05 s10 rows with a CI
## factor of `CI_FACTOR` (shared runners are slower than the dev machine; 05 s11.1, R0 A-62). A fourth case times a
## think with a closing friendly neighbour, which refreshes every think (Separation.term).
## Host normalisation (AI-40): GitHub-hosted runners differ by up to ~1.7x on the same commit, and absolute perf gates
## belong on the pinned runner only (05 s11.1, R0 C1-11, ci.yml header; A-62: the rows stay). The test therefore times a
## fixed reference kernel (`_ref_step`: no project code, so no change under review can move it) in the same process,
## before and after the cases, and divides every figure by `host = clamp(ref / REF_ANCHOR_US, 1, MAX_HOST)`: a host at
## least as fast as the anchor host is compared on raw figures (bounds unchanged), a slower one on figures rescaled to
## the anchor host, never by more than `MAX_HOST`. R0 B.17 A-97: the timing bounds are asserted only on the pinned runner
## (PLANEWAR_PINNED_RUNNER=1); on hosted runners they print PERF_REPORT lines and the refresh-share counter is the gate.

const CALLS: int = 1000
const BATCHES: int = 6
const ACT_BATCHES: int = 30          ## act: one warm-up loop, then the best of 30 loops of CALLS acts (AI-40)
const FAR_SHIPS: int = 240
const THINK_ROW_US: float = 25.0
const ACT_ROW_US: float = 6.0
const CI_FACTOR: float = 2.0         ## 05 s11.1 (p95 assertions only on the pinned runner) and R0 A-62 (no row moves before it is measured)
const CLOSING_FACTOR: float = 2.0    ## a closing pair is transient: it refreshes every think, the pre-hold cost (two thinks' worth)
## `_ref_step` cost on the anchor host = the GitHub runner class the AI-11 bounds were accepted on (PR #69 run 39481307898,
## `Overlays.run` 17.2 us). AI-40 CI samples: 0.762 us (Overlays 10.2), 1.615 us (Overlays 22.7); interpolated 1.22-1.28.
const REF_ANCHOR_US: float = 1.25
const MAX_HOST: float = 1.5          ## the largest host slowdown the scaling absorbs (slowest sample: 1.29x the anchor)


func _world() -> Array:
	var rules: MatchRules = WorldTestKit.rules()
	rules.caps.units = 2000   # a match-sized population for one player
	var w: SimWorld = WorldTestKit.world(31, rules)
	var def_id: int = WorldTestKit.def_id(&"dart")
	for k: int in FAR_SHIPS:   # spread over many hash cells, 1.5 km and more from the formation; first, so the formation is fresh
		var lat: float = deg_to_rad(-60.0 + 120.0 * float(k % 20) / 19.0)
		var lon: float = deg_to_rad(8.0 + 340.0 * float(k) / float(FAR_SHIPS))
		var pos: Vector3 = Sphere.from_lat_lon(lat, lon, Sphere.PLANET_RADIUS + 300.0)
		var code: int = CommandResult.Code.REJECTED_RATE
		while code == CommandResult.Code.REJECTED_RATE:   # player 1 issues them, so player 0's token bucket stays full for the formation; set-up only, not timed
			code = w.apply_command(CommandPayload.debug_spawn(1, def_id, 0, 0, pos, Vector3.ZERO, Vector3(0, 1, 0))).code
			w.step()
		assert(code == CommandResult.Code.ACCEPTED, "spawn %d: code %d" % [k, code])
	var _old: Array[SimEvent] = w.drain_events()
	var vb: Vector3 = Vector3(0, 70, 0)
	# the formation spawns in one tick (one step for all), so its ships fly parallel: a steady formation, no closing pair
	var codes: PackedInt32Array = PackedInt32Array([WorldTestKit.queue_spawn(w, &"bomber", 0, 0, WorldTestKit.at(300.0, 0.0), vb)])
	for k: int in 16:
		var p: Vector3 = WorldTestKit.at(300.0 + 25.0 * float(k % 3), -60.0 - 35.0 * float(k))
		p.z += 45.0 * float((k % 5) - 2)
		var _a: bool = codes.push_back(WorldTestKit.queue_spawn(w, &"dart", 0, 0, p, vb))
	var _f: bool = codes.push_back(WorldTestKit.queue_spawn(w, &"dart", 1, 1, WorldTestKit.at(300.0, 600.0), Vector3(0, 60, 0)))
	for c: int in codes:
		assert(c == CommandResult.Code.ACCEPTED, "formation spawn refused: %d" % c)
	w.step()
	var made: PackedInt32Array = PackedInt32Array()
	for e: SimEvent in w.drain_events():
		if e.kind == SimEvent.Kind.SPAWN:
			var _m: bool = made.push_back(e.a)
	assert(made.size() == 18, "formation spawns: %d" % made.size())
	var bomber: int = made[0]
	var darts: PackedInt32Array = made.slice(1, 17)
	var foe: int = made[17]
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
	var ref0: float = _ref_us()
	var v: SimView = w.view()
	for i: int in 4:   # slots 0..3
		var _o: EscortPilot.Outcome = pilot.think(darts[i], v, st, 100)
	var inp: PilotInput = PilotInput.new()
	var sc: Vector3 = Vector3(INF, 0.0, 0.0)
	var sg: Vector3 = Vector3(INF, 0.0, 0.0)
	var refreshes: int = 0
	var gate_refreshes: int = 0
	for _b: int in BATCHES:   # best batch by mean: the desktop scheduler's noise is larger than the code
		var calm: PackedFloat32Array = PackedFloat32Array()
		var gate: PackedFloat32Array = PackedFloat32Array()
		var _n: int = calm.resize(CALLS) | gate.resize(CALLS)
		for k: int in CALLS:
			var id: int = darts[k % 4]
			var t0: int = Time.get_ticks_usec()
			var _a: EscortPilot.Outcome = pilot.think(id, v, st, 100 + k)
			var t1: int = Time.get_ticks_usec()
			calm[k] = float(t1 - t0)
			refreshes += st.sep_age[EntityId.slot(id)] & Separation.AGE_FRESH
			var _b2: EscortPilot.Outcome = pilot.think(darts[0], v, st, 100 + k, foe, 0.9)   # slot 0 may not break: the gate runs
			var t2: int = Time.get_ticks_usec()
			gate[k] = float(t2 - t1)
			gate_refreshes += st.sep_age[EntityId.slot(darts[0])] & Separation.AGE_FRESH
		sc = _best(sc, _stats(calm))
		sg = _best(sg, _stats(gate))
	var act_us: float = _act_batches(pilot, v, st, inp, darts)
	var sx: Vector3 = _closing_case(w, pilot, st, darts[2])
	var ref: float = minf(ref0, _ref_us())
	var host: float = clampf(ref / REF_ANCHOR_US, 1.0, MAX_HOST)
	print("separation refresh share: quiet thinks %.2f, gate thinks %.2f" % [float(refreshes) / float(BATCHES * CALLS),
		float(gate_refreshes) / float(BATCHES * CALLS)])
	print("AI-11 perf (%d far ships, best of %d batches of %d): think mean %.1f / median %.1f / p95 %.1f us; threat-gate think mean %.1f / median %.1f / p95 %.1f us (row %.0f); act %.2f us/ship (best of %d batch loops of %d after a warm-up; row %.0f); closing-neighbour think (refresh every think) mean %.1f / median %.1f / p95 %.1f us" % [
		FAR_SHIPS, BATCHES, CALLS, sc.x, sc.y, sc.z, sg.x, sg.y, sg.z, THINK_ROW_US, act_us, ACT_BATCHES, CALLS, ACT_ROW_US, sx.x, sx.y, sx.z])
	print("AI-40 host: reference kernel %.3f us (anchor %.3f), scale %.2f; asserted think %.1f, gate %.1f, act %.2f, closing %.1f us" % [
		ref, REF_ANCHOR_US, host, sc.x / host, sg.x / host, act_us / host, sx.x / host])
	assert_bool(_gate("test_escort_perf.quiet_think", sc.x, THINK_ROW_US * CI_FACTOR, host, "05 s10 / R0 A-84")).is_true()
	assert_bool(_gate("test_escort_perf.gate_think", sg.x, THINK_ROW_US * CI_FACTOR, host, "05 s10 / R0 A-84")).is_true()
	assert_bool(_gate("test_escort_perf.act", act_us, ACT_ROW_US * CI_FACTOR, host, "05 s10 / R0 A-84")).is_true()
	assert_bool(_gate("test_escort_perf.closing_think", sx.x, THINK_ROW_US * CI_FACTOR * CLOSING_FACTOR, host, "05 s10 / R0 A-84")).is_true()
	assert_float(float(refreshes) / float(BATCHES * CALLS)).is_equal_approx(0.5, 0.01)   # A-84 / A-97: quiet thinks hold every second


## Act per ship, as the 05 s10 act row counts it: back-to-back acts over the 4 slotted escorts (each returns true, so
## every call runs track_velocity), one untimed warm-up loop, then the minimum mean over ACT_BATCHES loops of CALLS.
func _act_batches(pilot: EscortPilot, v: SimView, st: AiState, inp: PilotInput, darts: PackedInt32Array) -> float:
	var best: float = INF
	var flying: int = 0
	for b: int in ACT_BATCHES + 1:
		var t0: int = Time.get_ticks_usec()
		for k: int in CALLS:
			flying += 1 if pilot.act(darts[k & 3], v, st, inp) else 0
		var us: float = float(Time.get_ticks_usec() - t0) / float(CALLS)
		if b > 0:   # loop 0 warms the caches and the clock
			best = minf(best, us)
	assert_int(flying).is_equal((ACT_BATCHES + 1) * CALLS)   # every timed act flies the formation (no early-out call)
	return best


## Host speed: one untimed warm-up loop, then the minimum mean over ACT_BATCHES loops of CALLS reference steps.
func _ref_us() -> float:
	var pts: PackedVector3Array = PackedVector3Array()
	var _r: int = pts.resize(64)
	for i: int in 64:
		pts[i] = Vector3(sin(float(i)), cos(float(i) * 1.3), float(i % 7) - 3.0)
	var best: float = INF
	var sink: float = 0.0
	for b: int in ACT_BATCHES + 1:
		var t0: int = Time.get_ticks_usec()
		for k: int in CALLS:
			sink += _ref_step(pts, k)
		var us: float = float(Time.get_ticks_usec() - t0) / float(CALLS)
		if b > 0:
			best = minf(best, us)
	assert_bool(is_finite(sink)).is_true()
	return best


## The reference kernel: GDScript-interpreter work of the act / think kind (packed reads, Vector3 algebra,
## transcendental calls, a call per step), frozen so its cost tracks only the host.
static func _ref_step(pts: PackedVector3Array, k: int) -> float:
	var a: Vector3 = pts[k & 63]
	var b: Vector3 = pts[(k * 7 + 3) & 63]
	var c: Vector3 = a.cross(b)
	var acc: float = 0.0
	for j: int in 8:
		c = (c + a * 0.5).normalized()
		acc += c.dot(b) + atan2(c.y, c.x) + (1.0 if c.z > 0.0 else -1.0)
	return acc


## A friendly Dart 150 m ahead of `escort`, head-on at 70 m/s: the escort refreshes on every think while it closes (the
## transient cost of the conditional hold). Returns the best batch's mean / median / p95.
func _closing_case(w: SimWorld, pilot: EscortPilot, st: AiState, escort: int) -> Vector3:
	var v: SimView = w.view()
	var ahead: Vector3 = v.pos(escort) + v.vel(escort).normalized() * 150.0
	var _c: int = WorldTestKit.spawn(w, &"dart", 0, 0, ahead, -v.vel(escort))
	v = w.view()
	var best: Vector3 = Vector3(INF, 0.0, 0.0)
	for _b: int in BATCHES:
		var us: PackedFloat32Array = PackedFloat32Array()
		var _n: int = us.resize(CALLS)
		for k: int in CALLS:
			var t0: int = Time.get_ticks_usec()
			var _a: EscortPilot.Outcome = pilot.think(escort, v, st, 200 + k)
			us[k] = float(Time.get_ticks_usec() - t0)
		assert((st.sep_age[EntityId.slot(escort)] & Separation.AGE_CLOSING) != 0, "the closing case must refresh every think")
		best = _best(best, _stats(us))
	return best


func _best(a: Vector3, b: Vector3) -> Vector3:
	return b if b.x < a.x else a

## R0 B.17 A-97 inline gate (until TEST-03's PerfGate): one PERF_REPORT line; the bound is asserted only on the pinned
## runner (PLANEWAR_PINNED_RUNNER == "1"); on hosted runners timing never fails a test.
static func _gate(name: String, us: float, bound_us: float, host: float, cite: String) -> bool:
	var pinned: bool = OS.get_environment("PLANEWAR_PINNED_RUNNER") == "1"
	print("PERF_REPORT name=%s us=%.2f bound_us=%.2f host=%.2f pinned=%d cite=%s" % [name, us, bound_us, host, 1 if pinned else 0, cite])
	return not pinned or us / host < bound_us
