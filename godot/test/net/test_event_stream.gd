extends GdUnitTestSuite
## NET-10 events_reliable_order_test: EVENTS packets sent on CH_EVENTS (reliable, ordered) over a LocalTransport
## with the BAD preset (250 ms +-40, 5 % loss, 2 % reorder, 0.5 % dup) arrive complete, in send order and exactly
## once; PROJECTILE_BATCH on channel 2 sent twice survives the same link with no double spawn.

const TICKS: int = 600


func _events_for(tick: int) -> Array[SimEvent]:
	var evs: Array[SimEvent] = []
	for n: int in 1 + tick % 3:
		evs.append(EventRig.ev(SimEvent.Kind.HIT, EventRig.id(5), EventRig.id(6), float(tick), 0, PackedByteArray([0, n])))
	return evs


func test_reliable_events_arrive_in_order_over_bad_link() -> void:
	var link: LocalRig = LocalRig.new(FaultModel.preset(FaultModel.Preset.BAD, 11), true, false)
	var rig: EventRig = EventRig.new()
	var router: EventRouter = EventRouter.new()
	var auds: Array[EventAudience] = [rig.aud]
	var got: Array[PackedByteArray] = []
	link.client.packet.connect(func(_c: int, ch: int, b: PackedByteArray) -> void:
		if ch == Protocol.CH_EVENTS:
			got.append(b))
	var sent: Array[PackedByteArray] = []
	for t: int in TICKS:
		router.route(t, _events_for(t), auds)
		for p: PackedByteArray in rig.aud.outbox:
			sent.append(p)
			link.server.send(link.server_conn, Protocol.CH_EVENTS, p, true)
		rig.aud.clear_out()
		link.step()
	link.run_ticks(120)
	assert_int(got.size()).is_equal(sent.size())
	var last_tick: int = -1
	for i: int in sent.size():
		assert_array(got[i]).is_equal(sent[i])
		var w: Array[WireEvent] = []
		assert_int(EventCodec.decode(got[i], w)).is_greater(0)
		assert_int(w[0].tick).is_greater_equal(last_tick)
		last_tick = w[0].tick


## Fires one shot per tick over a BAD link; returns [registered, duplicates]. `resend` off clears the re-send state.
func _shot_run(resend: bool) -> Vector2i:
	var link: LocalRig = LocalRig.new(FaultModel.preset(FaultModel.Preset.BAD, 12), true, false)
	var rig: EventRig = EventRig.new()
	var router: EventRouter = EventRouter.new()
	var auds: Array[EventAudience] = [rig.aud]
	var tracker: ShotTracker = ShotTracker.new()
	link.client.packet.connect(func(_c: int, ch: int, b: PackedByteArray) -> void:
		if ch == Protocol.CH_SNAPSHOT:
			var _n: int = tracker.accept(b, 0))
	for t: int in TICKS:
		var s: ShotBuffer = ShotBuffer.new()
		s.clear(t)
		s.add_q(EventRig.id(5), 1, t & 0xFF, 0, 0)
		router.route_shots(t, s, auds)
		for p: PackedByteArray in rig.aud.shot_out:
			link.server.send(link.server_conn, Protocol.CH_SNAPSHOT, p, false)
		rig.aud.clear_out()
		if not resend:
			rig.aud.shots_last.clear()
		link.step()
	link.run_ticks(120)
	return Vector2i(tracker.count(), tracker.duplicates)


func test_resent_shot_batches_never_double_spawn_over_bad_link() -> void:
	var twice: Vector2i = _shot_run(true)
	var once: Vector2i = _shot_run(false)
	assert_int(twice.x).is_less_equal(TICKS)                 # never more spawns than shots, duplicates included
	assert_int(twice.x).is_greater(once.x)                   # the second send recovers shots the first lost
	assert_int(twice.x).is_greater(int(TICKS * 0.8))
	assert_int(twice.y).is_greater(0)                        # the re-send really arrived and was discarded
