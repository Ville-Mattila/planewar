extends SceneTree
## NET-10 micro-benchmark: EventRouter.route for 8 clients over a mixed tick of 60 events (HIT-heavy, one
## ALERT, a few team and roster kinds) plus route_shots for 40 shots, against rosters of 240 entities.
## godot --headless --path godot -s res://test/perf/bench_events.gd
## Prints: BENCH_EVENTS clients=8 events=60 route_us=.. shots_us=.. bytes_per_client_tick=.. kb_per_s_per_client=..
## Then mode=interest (NET-08): the canonical 940-entity scene (InterestRig) with each client's roster and event
## cells from real Interest, 60 events + 40 shots per tick naming random scene entities, p50 / p95 over 300 ticks.
## Cited rows: 04 s4.6 bandwidth, 03 s4.2 "events + interest + encode + replay" (R0 B.7).

const ROUNDS: int = 30
const CLIENTS: int = 8
const EVENTS: int = 60
const SHOTS: int = 40


func _init() -> void:
	var auds: Array[EventAudience] = []
	for c: int in CLIENTS:
		var r: Roster = Roster.new()
		for s: int in range(1, 241):
			var _ok: bool = r.add(s, 1, 100, c, c % 2, "")
		var a: EventAudience = EventAudience.new(r)
		a.team = c % 2
		a.player = c
		a.possessed_slot = 1 + c
		auds.append(a)
	var evs: Array[SimEvent] = []
	for n: int in EVENTS:
		var slot: int = 1 + (n * 7) % 240
		var kind: SimEvent.Kind = SimEvent.Kind.HIT
		if n % 12 == 5:
			kind = SimEvent.Kind.BUILD_DONE
		elif n % 20 == 7:
			kind = SimEvent.Kind.DEATH
		var e: SimEvent = SimEvent.new()
		e.kind = kind
		e.a = EntityId.make(slot, 1)
		e.b = EntityId.make(1 + (n * 13) % 300, 1)
		e.value = 20.0 + n
		e.team = n % 2
		e.extra = PackedByteArray([1, n & 0xFF])
		evs.append(e)
	var shots: ShotBuffer = ShotBuffer.new()
	for n: int in SHOTS:
		shots.add_q(EntityId.make(1 + n * 5, 1), 1, n, n - 20, 0, 6 if n % 4 == 0 else -1)
	var router: EventRouter = EventRouter.new()
	var best_route: int = 1 << 30
	var best_shots: int = 1 << 30
	var bytes: int = 0
	for _round: int in ROUNDS:
		for a: EventAudience in auds:
			a.clear_out()
		var t0: int = Time.get_ticks_usec()
		router.route(1, evs, auds)
		var t1: int = Time.get_ticks_usec()
		router.route_shots(1, shots, auds)
		var t2: int = Time.get_ticks_usec()
		best_route = mini(best_route, t1 - t0)
		best_shots = mini(best_shots, t2 - t1)
		bytes = 0
		for p: PackedByteArray in auds[0].outbox:
			bytes += p.size()
		for p: PackedByteArray in auds[0].shot_out:
			bytes += p.size()
	print("BENCH_EVENTS clients=%d events=%d route_us=%d shots_us=%d bytes_per_client_tick=%d kb_per_s_per_client=%.2f" %
			[CLIENTS, EVENTS, best_route, best_shots, bytes, bytes * 30.0 / 1000.0])
	_interest_mode()
	quit()


func _interest_mode() -> void:
	var rig: InterestRig = InterestRig.new()
	rig.build(CLIENTS, Vector3i(40, 200, 700), Vector3i(24, 70, 300), 6, 17)
	var auds: Array[EventAudience] = []
	for k: int in CLIENTS:
		var a: EventAudience = EventAudience.new(rig.rosters[k])
		a.team = rig.clients[k].team
		a.player = k
		a.possessed_slot = rig.clients[k].possessed
		auds.append(a)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 10
	var router: EventRouter = EventRouter.new()
	var route: PackedInt32Array = PackedInt32Array()
	var shot_t: PackedInt32Array = PackedInt32Array()
	var bytes: int = 0
	var n: int = rig.snap.frame.count
	for t: int in 330:
		rig.step_scene()
		rig.run_interest()
		var _meta: Array[PackedByteArray] = []
		for k: int in CLIENTS:
			rig.roster_packets(k, _meta)
			auds[k].set_cells(rig.clients[k].cells)
			auds[k].clear_out()
		var evs: Array[SimEvent] = _events(rng, n, rig.snap.frame.pos[rng.randi() % n])
		var shots: ShotBuffer = ShotBuffer.new()
		for i: int in SHOTS:
			shots.add_q(EntityId.make(rng.randi() % n, 1), 1, i, i - 20, 0, 6 if i % 4 == 0 else -1)
		var t0: int = Time.get_ticks_usec()
		router.route(rig.snap.tick, evs, auds)
		var t1: int = Time.get_ticks_usec()
		router.route_shots(rig.snap.tick, shots, auds)
		var t2: int = Time.get_ticks_usec()
		if t < 30:
			continue
		var _r: bool = route.push_back(t1 - t0)
		var _s: bool = shot_t.push_back(t2 - t1)
		for a: EventAudience in auds:
			for p: PackedByteArray in a.outbox + a.shot_out:
				bytes += p.size()
	var per: float = float(route.size() * CLIENTS)
	print("BENCH_EVENTS mode=interest clients=%d n=%d events=%d shots=%d route_us p50=%d p95=%d shots_us p50=%d p95=%d sum_p95=%d roster_mean=%d bytes_per_client_tick=%d kb_per_s_per_client=%.2f" % [
		CLIENTS, n, EVENTS, SHOTS, _pct(route, 0.5), _pct(route, 0.95), _pct(shot_t, 0.5), _pct(shot_t, 0.95),
		_pct(route, 0.95) + _pct(shot_t, 0.95), _roster_mean(rig), roundi(bytes / per), bytes * 30.0 / per / 1000.0])


## The NET-10 mix (HIT-heavy, BUILD_DONE, DEATH) over random scene entities, plus one BOMB_IMPACT (cell scope).
func _events(rng: RandomNumberGenerator, n: int, site: Vector3) -> Array[SimEvent]:
	var evs: Array[SimEvent] = []
	for i: int in EVENTS:
		var e: SimEvent = SimEvent.new()
		e.kind = SimEvent.Kind.HIT
		if i % 12 == 5:
			e.kind = SimEvent.Kind.BUILD_DONE
		elif i % 20 == 7:
			e.kind = SimEvent.Kind.DEATH
		elif i == 59:
			e.kind = SimEvent.Kind.BOMB_IMPACT
		e.a = EntityId.make(rng.randi() % n, 1)
		e.b = EntityId.make(rng.randi() % n, 1)
		e.value = 20.0 + i
		e.team = i % 3
		e.extra = PackedByteArray([1, i & 0xFF])
		e.pos = site
		evs.append(e)
	return evs


static func _roster_mean(rig: InterestRig) -> int:
	var total: int = 0
	for r: Roster in rig.rosters:
		total += r.count()
	return roundi(total / float(rig.rosters.size()))


static func _pct(values: PackedInt32Array, q: float) -> int:
	if values.is_empty():
		return 0
	var s: PackedInt32Array = values.duplicate()
	s.sort()
	return s[clampi(floori(float(s.size()) * q), 0, s.size() - 1)]
