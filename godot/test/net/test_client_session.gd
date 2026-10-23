extends GdUnitTestSuite
## NET-17 integration (04 s2.2, s5.1, s5.6; R0 B.10 A-36): one NetViewRig server and N ClientSessions over
## LocalTransport in one process, with FaultModel loss / reorder / jitter. Asserted numerically: the state machine
## (CONNECTING -> LOADING -> PLAYING, REFUSE / MATCH_END -> ENDED, loss -> RECONNECTING), acks name complete ticks only,
## the clock converges within 2 s under TARGET, every received entity's sampled position stays within 1 m of the
## server's history at the render tick under TARGET, extrapolation stops after 3 ticks (stale, frozen), held records
## apply after their ENTITY_META, and 100,000 mutated server messages through ClientSession.receive never error.

const DARTS: int = 6


func _world() -> SimWorld:
	var w: SimWorld = WorldTestKit.world()
	var _c0: int = WorldTestKit.spawn(w, &"core", 0, 0, WorldTestKit.at(0.0, 0.0))
	var _c1: int = WorldTestKit.spawn(w, &"core", 1, 1, WorldTestKit.at(0.0, 600.0))
	for k: int in DARTS:
		var _d: int = WorldTestKit.spawn(w, &"dart", k & 1, k & 1, WorldTestKit.at(400.0 + 30.0 * k, 100.0 * k),
				Vector3(0.0, 50.0 + 5.0 * k, 3.0 * k))
	for _i: int in 3:
		w.step()
	return w


## Server history: positions of every live store entity per tick (id -> pos).
var _history: Dictionary = {}


func _step(rig: NetViewRig, send: bool = true) -> void:
	rig.world.step()
	var at: Dictionary = {}
	for id: int in rig.local.ships():
		at[id] = rig.local.pos(id)
	for id: int in rig.local.structures():
		at[id] = rig.local.pos(id)
	_history[rig.world.tick()] = at
	if send:
		rig.send_tick(rig.world.tick())
	rig.pump()


func _truth(id: int, r: float) -> Vector3:
	var t0: int = floori(r)
	var a: Dictionary = _history.get(t0, {})
	var b: Dictionary = _history.get(t0 + 1, {})
	if not a.has(id) or not b.has(id):
		return Vector3.INF
	var pa: Vector3 = a[id]
	var pb: Vector3 = b[id]
	return pa.lerp(pb, r - float(t0))


func _join(rig: NetViewRig) -> void:
	for _i: int in 4:
		rig.pump()


func test_state_machine_connecting_loading_playing() -> void:
	var rig: NetViewRig = NetViewRig.new(_world(), WorldTestKit.content())
	var cs: ClientSession = rig.add_client(0, 0)
	var seen: Array[int] = []
	var _c: int = cs.state_changed.connect(func(s: int) -> void: seen.append(s))
	assert_int(cs.state).is_equal(ClientSession.State.CONNECTING)
	_join(rig)
	assert_int(cs.state).is_equal(ClientSession.State.LOADING)
	assert_int(cs.welcome.slot).is_equal(0)
	assert_int(cs.view().team_id).is_equal(0)
	_step(rig)
	_step(rig)
	assert_int(cs.state).is_equal(ClientSession.State.PLAYING)
	assert_array(seen).is_equal([ClientSession.State.LOADING, ClientSession.State.PLAYING])
	var ms: PackedByteArray = SessionCodec.encode_match_state(Protocol.SessionPhase.COUNTDOWN, 5, 90, 1)
	cs.receive(Protocol.CH_CONTROL, ms)
	assert_int(cs.phase).is_equal(Protocol.SessionPhase.COUNTDOWN)
	cs.receive(Protocol.CH_SNAPSHOT, ms)                                    # wrong channel: dropped, not parsed
	assert_int(cs.phase).is_equal(Protocol.SessionPhase.COUNTDOWN)
	assert_int(cs.dropped).is_greater(0)
	var end: PackedByteArray = PackedByteArray([Protocol.MATCH_END, 1, Protocol.MatchEndReason.SURRENDER, 9, 0, 0, 0])
	var _r: int = end.resize(SessionCodec.MATCH_END_HEAD_BYTES)
	cs.receive(Protocol.CH_CONTROL, end)
	assert_int(cs.state).is_equal(ClientSession.State.ENDED)
	assert_int(cs.end_reason).is_equal(Protocol.MatchEndReason.SURRENDER)


func test_refuse_ends_and_a_lost_link_reconnects() -> void:
	var rig: NetViewRig = NetViewRig.new(_world(), WorldTestKit.content())
	var a: ClientSession = rig.add_client(0, 0)
	var b: ClientSession = rig.add_client(1, 1)
	a.receive(Protocol.CH_CONTROL, SessionCodec.encode_refuse(Protocol.RefuseReason.MATCH_FULL, 1, "full"))
	assert_int(a.state).is_equal(ClientSession.State.ENDED)
	assert_int(a.refuse_reason).is_equal(Protocol.RefuseReason.MATCH_FULL)
	_join(rig)
	assert_int(b.state).is_equal(ClientSession.State.LOADING)
	rig.server.close(rig.conns[1], Transport.DisconnectReason.LOCAL_CLOSE)
	rig.pump(2)
	assert_int(b.state).is_equal(ClientSession.State.RECONNECTING)


func test_three_clients_under_target_track_the_server_within_1_m_and_ack_complete_ticks() -> void:
	_history = {}
	var rig: NetViewRig = NetViewRig.new(_world(), WorldTestKit.content(), FaultModel.preset(FaultModel.Preset.TARGET, 17))
	var cls: Array[ClientSession] = [rig.add_client(0, 0), rig.add_client(1, 1), rig.add_client(2, 0)]
	_join(rig)
	rig.pump(8)
	var worst: float = 0.0
	var samples: int = 0
	var stale_ticks: int = 0
	for t: int in 300:
		_step(rig)
		if t < 60:
			continue
		for cs: ClientSession in cls:
			var v: NetSimView = cs.view()
			stale_ticks += 1 if v.stale else 0
			for id: int in v.ships():
				var want: Vector3 = _truth(id, cs.render_tick())
				if want != Vector3.INF:
					worst = maxf(worst, v.pos(id).distance_to(want))
					samples += 1
			# A-36: the ack the client sends is a tick whose every packet arrived
			assert_int(cs.ack_tick()).is_equal(cs.decoder.store.complete_tick)
	for cs: ClientSession in cls:
		assert_int(cs.state).is_equal(ClientSession.State.PLAYING)
		assert_int(cs.acks_sent).is_greater(50)
		assert_int(cs.malformed).is_equal(0)
	print("PERF_REPORT name=test_client_session.target_tracking worst_m=%.3f samples=%d stale=%d" % [worst, samples, stale_ticks])
	assert_int(samples).is_greater(1000)
	assert_float(worst).is_less(1.0)


func test_clock_converges_within_2_s_under_target() -> void:
	_history = {}
	var rig: NetViewRig = NetViewRig.new(_world(), WorldTestKit.content(), FaultModel.preset(FaultModel.Preset.TARGET, 3))
	var cs: ClientSession = rig.add_client(0, 0)
	_join(rig)
	var first: int = -1
	var worst_after: float = 0.0
	for t: int in 240:
		_step(rig)
		if first < 0 and cs.decoder.store.newest_tick > 0:
			first = t
		if first >= 0 and t >= first + 60:
			# the estimate reads the server tick minus the one-way latency (TARGET 100 ms = 3 ticks)
			worst_after = maxf(worst_after, absf(cs.clock.clock - (float(rig.world.tick()) - 3.0)))
	print("PERF_REPORT name=test_client_session.clock worst_tick_err=%.3f resyncs=%d" % [worst_after, cs.clock.resyncs])
	assert_int(first).is_greater_equal(0)
	assert_float(worst_after).is_less(1.0)
	assert_int(cs.clock.resyncs).is_less_equal(2)                           # WELCOME sync + at most one first-snapshot resync


func test_extrapolation_stops_after_3_ticks_end_to_end() -> void:
	_history = {}
	var rig: NetViewRig = NetViewRig.new(_world(), WorldTestKit.content())
	var cs: ClientSession = rig.add_client(0, 0)
	_join(rig)
	for _t: int in 30:
		_step(rig)
	var v: NetSimView = cs.view()
	assert_bool(v.stale).is_false()
	var id: int = v.ships()[0]
	var frozen: Vector3 = Vector3.ZERO
	var stale_from: int = -1
	for k: int in 12:
		_step(rig, false)                                                    # the server goes silent
		if v.stale and stale_from < 0:
			stale_from = k
			frozen = v.pos(id)
		elif v.stale:
			assert_vector(v.pos(id)).is_equal(frozen)
	assert_int(stale_from).is_greater_equal(0)
	assert_float(cs.render_tick() - float(cs.decoder.store.newest_tick)).is_greater(float(NetPose.EXTRAP_MAX_TICKS))


func test_held_snapshot_applies_after_its_entity_meta() -> void:
	var rig: NetViewRig = NetViewRig.new(_world(), WorldTestKit.content())
	var cs: ClientSession = rig.add_client(0, 0)
	_join(rig)
	rig.fill_frame()
	rig.codec.prepare_tick(rig.frame)
	var vis: PackedInt32Array = PackedInt32Array()
	for r: int in rig.frame.count:
		var _a: bool = vis.push_back(rig.frame.slot[r])
	var out: Array[PackedByteArray] = []
	var _n: int = rig.codec.encode(BaselineStore.new(0), rig.tick, vis, PackedInt32Array(), PackedInt32Array(), null, out)
	cs.receive(Protocol.CH_SNAPSHOT, out[0])
	assert_int(cs.held).is_equal(1)
	assert_int(cs.decoder.store.newest_tick).is_equal(0)
	var metas: Array[PackedByteArray] = []
	var _m: int = RosterCodec.encode_meta(rig.roster, vis, metas)
	for m: PackedByteArray in metas:
		cs.receive(Protocol.CH_EVENTS, m)
	cs.tick()
	assert_int(cs.snapshots_ok).is_equal(1)
	assert_int(cs.decoder.store.newest_tick).is_equal(rig.tick)


func test_fuzz_100000_mutated_server_messages_never_error() -> void:
	var rig: NetViewRig = NetViewRig.new(_world(), WorldTestKit.content())
	var _cs: ClientSession = rig.add_client(0, 0)
	_join(rig)
	for _t: int in 20:
		_step(rig)
	var corpus: Array[PackedByteArray] = [SessionCodec.encode_welcome(_welcome_info())]
	var channels: PackedInt32Array = PackedInt32Array([Protocol.CH_CONTROL])
	_capture(rig, corpus, channels)
	assert_int(corpus.size()).is_greater(8)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 0x17
	var target: ClientSession = _fresh(rig)
	var ended: int = 0
	var received: int = 0
	for i: int in NetFuzz.MUTATIONS:
		var k: int = rng.randi_range(0, corpus.size() - 1)
		var ch: int = channels[k] if rng.randf() < 0.9 else rng.randi_range(0, Protocol.CHANNEL_COUNT - 1)
		target.receive(ch, NetFuzz.mutate(rng, corpus[k], 12))
		received += 1
		if i % 64 == 0:
			target.tick()
		if target.state == ClientSession.State.ENDED:
			ended += 1
			target = _fresh(rig)
	assert_int(received).is_equal(NetFuzz.MUTATIONS)
	var clean: ClientSession = _fresh(rig)                                    # the decoders kept no state across sessions
	for k: int in corpus.size():
		if corpus[k][0] == Protocol.ENTITY_META:
			clean.receive(Protocol.CH_EVENTS, corpus[k])
	for k: int in corpus.size():
		if corpus[k][0] == Protocol.SNAPSHOT:
			clean.receive(Protocol.CH_SNAPSHOT, corpus[k])
	assert_int(clean.snapshots_ok).is_greater(0)
	assert_int(clean.malformed).is_equal(0)
	print("PERF_REPORT name=test_client_session.fuzz sessions_ended=%d corpus=%d" % [ended, corpus.size()])


func _welcome_info() -> WelcomeInfo:
	var w: WelcomeInfo = WelcomeInfo.new()
	w.slot = 0
	var _s: int = w.secret.resize(Protocol.SECRET_BYTES)
	var _h: int = w.map_hash.resize(Protocol.HASH_BYTES)
	w.tick = 5
	w.add_player(0, 0, 0, 0, 0, "a")
	return w


## A session in LOADING (WELCOME applied, LOADED sent) that the fuzz feeds directly.
func _fresh(rig: NetViewRig) -> ClientSession:
	var ep: LocalTransport = rig.server.connect_client()
	var cs: ClientSession = ClientSession.new(ep, 0)
	cs.configure(rig.content, rig.world.terrain())
	cs.receive(Protocol.CH_CONTROL, SessionCodec.encode_welcome(_welcome_info()))
	var mh: PackedByteArray = PackedByteArray()
	var _r: int = mh.resize(Protocol.HASH_BYTES)
	cs.mark_loaded(mh)
	return cs


## A valid server message of every kind the client parses, as the rig would send it to client 0.
func _capture(rig: NetViewRig, corpus: Array[PackedByteArray], channels: PackedInt32Array) -> void:
	var all: PackedInt32Array = PackedInt32Array()
	for r: int in rig.frame.count:
		var _a: bool = all.push_back(rig.frame.slot[r])
	var metas: Array[PackedByteArray] = []
	var _m: int = RosterCodec.encode_meta(rig.roster, all, metas)
	for m: PackedByteArray in metas:
		corpus.append(m)
		var _b: bool = channels.push_back(Protocol.CH_EVENTS)
	var out: Array[PackedByteArray] = []
	var st: BaselineStore = BaselineStore.new(0)
	var _n: int = rig.codec.encode(st, rig.tick, all, PackedInt32Array(), PackedInt32Array(), rig.pilot_for(0), out)
	for p: PackedByteArray in out:
		corpus.append(p)
		var _c: bool = channels.push_back(Protocol.CH_SNAPSHOT)
	var kc: KeyframeCodec = KeyframeCodec.new()
	corpus.append(kc.encode(rig.codec, BaselineStore.new(0), rig.tick, 1, Protocol.KeyframeScope.ALL, all))
	var _d: bool = channels.push_back(Protocol.CH_EVENTS)
	corpus.append(rig.team_state_bytes(0))
	var _e: bool = channels.push_back(Protocol.CH_SNAPSHOT)
	var ev: PackedByteArray = PackedByteArray()
	var _r: int = ev.resize(64)
	var at: int = EventCodec.write_header(ev, rig.tick)
	at = EventCodec.write_event(ev, at, Protocol.EventKind.POSSESSED, PackedInt32Array([all[0], 0]), 0)
	at = EventCodec.write_event(ev, at, Protocol.EventKind.RELEASED, PackedInt32Array([all[0], 0, 0]), 0)
	ev[5] = 2
	corpus.append(ev.slice(0, at))
	var _f: bool = channels.push_back(Protocol.CH_EVENTS)
	for b: PackedByteArray in [SessionCodec.encode_pong(1, 2, 3), SessionCodec.encode_match_state(5, 9, 0, 1),
			SessionCodec.encode_refuse(1, 1, "x")]:
		corpus.append(b)
		var _g: bool = channels.push_back(Protocol.channel_of(b[0]))
	var rm: PackedByteArray = PackedByteArray([Protocol.ROSTER_REMOVE, 1, all[0] & 0xFF, all[0] >> 8, 0])
	corpus.append(rm)
	var _h: bool = channels.push_back(Protocol.CH_EVENTS)
