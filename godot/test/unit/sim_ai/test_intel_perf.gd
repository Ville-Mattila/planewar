extends GdUnitTestSuite
## AI-22 perf (05 s10 "Threat maps (per team, 1 Hz, spread) 0.3 ms"; 05 s7.2 Commander slice 0 = perception + threat
## <= 0.7 ms; acceptance "threat update <= 0.3 ms per team at 1,200 entities") on the S-SIM-1 world (PerfTickWorld:
## 400 ships, 200 ground, 480 structures, 120 wrecks, 8 teams). Two knowledge levels: each team's own Vision (as the
## world stands) and the stress case "team 0 has every enemy entity in view" (943 contacts). Timing through PerfGate
## (R0 B.17 A-97: asserted only on the pinned runner, PERF_REPORT elsewhere); the work counters are hard everywhere.
## Dev laptop, standalone (no debugger): per-team update 38-45 us, refresh 260-270 us (visible_ids ~135 us of it);
## stress update 211-220 us, refresh ~1,240 us. Under the gdUnit runner (debug) ~3-4x: update 194 us worst team,
## slice 1,296 us; stress update 337 us, slice 3,329 us (report only, no row).

const UPDATE_ROW_US: float = 300.0     # 05 s10 threat-map row / AI-22 acceptance, per team (no factor)
const SLICE_US: float = 700.0          # 05 s7.2 slice 0 (perception + threat)
const CI_FACTOR: float = 2.0           # AI-40 / AI-11 / AI-13 precedent: row x 2 for the slice and the stress case
const REPS: int = 7

static var _pw: PerfTickWorld = null


func _world() -> PerfTickWorld:
	if _pw == null:
		_pw = PerfTickWorld.new(400, 200, 480, 120, 0, &"")
		for _i: int in 40:
			_pw.world.step()
			var _e: Array[SimEvent] = _pw.world.drain_events()
	return _pw


func test_threat_update_per_team_at_1200_entities() -> void:
	var w: SimWorld = _world().world
	assert_int(w.store().live_count()).is_greater_equal(1150)   # 1,200 spawned; a few die in 40 ticks
	var v: SimView = w.view()
	var worst_update: float = 0.0
	var worst_slice: float = 0.0
	for team: int in PlayerTable.TEAMS:
		var p: Perception = Perception.new(team, -1, IntelKit.profile("team"), IntelKit.tables())
		var m: ThreatMap = ThreatMap.new(IntelKit.tables())
		var r: Vector2 = _measure(p, m, v, w.tick())
		worst_slice = maxf(worst_slice, r.x + r.y)
		worst_update = maxf(worst_update, r.y)
		_counters(p, m, v)
	assert_bool(PerfGate.check("test_intel_perf.update_per_team", worst_update, UPDATE_ROW_US, "05 s10 threat maps row")).is_true()
	assert_bool(PerfGate.check("test_intel_perf.slice_per_team", worst_slice, SLICE_US * CI_FACTOR, "05 s7.2 slice 0")).is_true()


func test_threat_update_when_every_enemy_is_known() -> void:
	var w: SimWorld = PerfTickWorld.new(400, 200, 480, 120, 0, &"").world
	for _i: int in 40:
		w.step()
		var _e: Array[SimEvent] = w.drain_events()
	var st: EntityStore = w.store()
	for s: int in st.visible_mask.size():   # team 0 sees everything (test-only store write)
		st.visible_mask[s] = st.visible_mask[s] | 1
	var p: Perception = Perception.new(0, -1, IntelKit.profile("team"), IntelKit.tables())
	var m: ThreatMap = ThreatMap.new(IntelKit.tables())
	var r: Vector2 = _measure(p, m, w.view(), w.tick())
	assert_int(p.n_known).is_greater(900)
	_counters(p, m, w.view())
	assert_bool(PerfGate.check("test_intel_perf.update_all_known", r.y, UPDATE_ROW_US * CI_FACTOR, "05 s10 threat maps row")).is_true()
	print("PERF_INFO name=test_intel_perf.slice_all_known us=%.1f refresh_us=%.1f known=%d (stress case, no budget row)" % [
		r.x + r.y, r.x, p.n_known])


# Best of REPS (refresh us, update us) after one warm refresh (the id cache filled).
func _measure(p: Perception, m: ThreatMap, v: SimView, tick: int) -> Vector2:
	p.refresh(v, tick)
	m.update(v, p, tick)
	var best: Vector2 = Vector2(INF, INF)
	for k: int in REPS:
		var t0: int = Time.get_ticks_usec()
		p.refresh(v, tick + 1 + k)
		var t1: int = Time.get_ticks_usec()
		m.update(v, p, tick + 1 + k)
		var t2: int = Time.get_ticks_usec()
		best = Vector2(minf(best.x, float(t1 - t0)), minf(best.y, float(t2 - t1)))
	return best


# Hard work counters: a warm refresh is one visible_ids + one pos per listed ship / ground unit (no other reads);
# the update spreads exactly one bin per distinct (cell, range class) and writes exactly their ring lengths.
func _counters(p: Perception, m: ThreatMap, v: SimView) -> void:
	var vis: PackedInt32Array = v.visible_ids(p.team)
	var movers: int = 0
	for id: int in vis:
		var s: int = EntityId.slot(id)
		if s < Perception.MAX_SLOT and v.def_id(id) < DefRanges.STRUCTURE_BASE:
			movers += 1
	var c0: int = p.stats_view_calls
	p.refresh(v, p.last_refresh + 1)
	assert_int(p.stats_view_calls - c0).is_equal(1 + movers)
	m.update(v, p, p.last_refresh)
	var t: ThreatParams = IntelKit.tables()
	var keys: Dictionary = {}
	var cells: int = 0
	for i: int in p.n_known:
		var s: int = p.known[i]
		cells += _key(t, keys, p.k_cell[s], p.k_def[s], 0)
	for i: int in p.n_own:
		cells += _key(t, keys, p.own_cell[i], p.own_def[i], 1)
	assert_int(m.stats_bins).is_equal(keys.size())
	assert_int(m.stats_cells).is_equal(cells)


func _key(t: ThreatParams, keys: Dictionary, cell: int, def: int, side: int) -> int:
	var pr: int = t.profile_by_def[def]
	if pr == 0:
		return 0
	var k: int = t.prof_class[pr]
	var key: int = (cell * t.classes + k) * 2 + side
	if keys.has(key):
		return 0
	keys[key] = true
	var base: int = k * (ThreatParams.CELLS + 1) + cell
	return t.ring_start[base + 1] - t.ring_start[base]
