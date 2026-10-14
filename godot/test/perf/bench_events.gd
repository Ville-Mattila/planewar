extends SceneTree
## NET-10 micro-benchmark: EventRouter.route for 8 clients over a mixed tick of 60 events (HIT-heavy, one
## ALERT, a few team and roster kinds) plus route_shots for 40 shots, against rosters of 240 entities.
## godot --headless --path godot -s res://test/perf/bench_events.gd
## Prints: BENCH_EVENTS clients=8 events=60 route_us=.. shots_us=.. bytes_per_client_tick=.. kb_per_s_per_client=..
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
	quit()
