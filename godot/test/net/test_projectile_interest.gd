extends GdUnitTestSuite
## NET-58 (R0 B.22 A-112; 04 s3.1, s3.6, s4.1, s4.6) integration: the canonical 940-entity scene with ~60 live replicated
## projectile entities (~12 spawns/s) plus slug churn through real Interest for 3 clients. ENTITY_META precedes every
## first record (the decoders never see MISSING_ROSTER), ROSTER_REMOVE DEATH follows a projectile's death by
## ProjectileMembers.HOLD_TICKS (100 ms, no 30 s ghost), slugs never enter a list, mirrors equal, projectiles are tiered by position, and the ENTITY_META +
## ROSTER_REMOVE bytes they add stay <= 0.3 KB/s per client. Then over LocalTransport (TARGET: 100 ms, jitter, 3 % loss,
## reorder) through ClientSession: the views show the projectiles and hold no projectile entry once all have died.

const CLIENTS: int = 3
const TICKS: int = 450
const WARMUP: int = 150                                    # population reaches its ~60 steady state
const META_BUDGET_BPS: float = 300.0                       # 04 s4.6 ENTITY_META row note (A-112): <= 0.3 KB/s

var _rig: ProjectileRig
var _died_at: PackedInt32Array = PackedInt32Array()


func _build(with_projectiles: bool) -> void:
	_rig = ProjectileRig.new()
	_rig.build(CLIENTS, Vector3i(40, 200, 700), Vector3i(24, 70, 300), 6, 17)
	if not with_projectiles:
		_rig.rate_per_s = 0.0
		_rig.slugs_per_tick = 0


## Runs the in-process pipeline; returns the ENTITY_META + ROSTER_REMOVE bytes per client after WARMUP.
func _run(with_projectiles: bool, checks: bool) -> PackedInt64Array:
	_build(with_projectiles)
	var rosters: Array[Roster] = []
	var decs: Array[SnapshotDecoder] = []
	for k: int in CLIENTS:
		rosters.append(Roster.new())
		decs.append(_rig.new_projectile_decoder(_rig.clients[k].team, rosters[k]))
	var meta: PackedInt64Array = PackedInt64Array([0, 0, 0])
	var tiers: Vector3i = Vector3i.ZERO
	var got: PackedInt32Array = PackedInt32Array()
	var _r: int = _died_at.resize(Roster.CAPACITY)
	_died_at.fill(-1)
	for t: int in TICKS:
		_rig.step_scene()
		_rig.run_interest()
		for s: int in _rig.died:
			_died_at[s] = _rig.snap.tick
		for k: int in CLIENTS:
			var reliable: Array[PackedByteArray] = []
			_rig.roster_packets(k, reliable)
			for p: PackedByteArray in reliable:
				var n: int = RosterCodec.decode_meta(p, rosters[k], got) if p[0] == Protocol.ENTITY_META \
						else RosterCodec.decode_remove(p, rosters[k], got)
				assert_int(n).is_greater(0)
				meta[k] += p.size() if t >= WARMUP else 0
			var out: Array[PackedByteArray] = []
			var _n: int = _rig.encode(k, out)
			for p: PackedByteArray in out:
				assert_int(decs[k].decode(p)).is_equal(SnapshotDecoder.Status.OK)
			_rig.stores[k].ack(decs[k].store.complete_tick)
			if checks:
				tiers += _check_tick(k, rosters[k])
	if checks:
		for k: int in CLIENTS:
			var cur: int = decs[k].store.complete_tick
			assert_bool(decs[k].store.frame_at(cur).same_state(_rig.stores[k].frame_at(cur))).is_true()
		print("PROJECTILE_INTEREST tiers a=%d b=%d c=%d spawned=%d live=%d" % [tiers.x, tiers.y, tiers.z, _rig.spawned, _rig.live_replicated().size()])
		assert_int(tiers.x).is_greater(0)                   # tiered by position: near the anchor -> A ...
		assert_int(tiers.z).is_greater(0)                   # ... far -> C
	return meta


## Per client and tick: client roster == server roster; a projectile that died HOLD_TICKS ago is gone from the client
## roster (no ghost; its slot's next generation is still held then); lists hold only replicated kinds. Returns the
## projectile counts in A / B / C this tick.
func _check_tick(k: int, client: Roster) -> Vector3i:
	var cl: InterestClient = _rig.clients[k]
	assert_int(client.state_hash()).is_equal(_rig.rosters[k].state_hash())
	for i: int in _rig.p_kind.size():
		var s: int = Roster.PROJECTILE_INDEX_MIN + i
		if _died_at[s] >= 0 and _rig.snap.tick - _died_at[s] == ProjectileMembers.HOLD_TICKS:
			assert_bool(client.has(s)).override_failure_message("ghost %d" % s).is_false()
	return Vector3i(_count_projectiles(cl.a), _count_projectiles(cl.b), _count_projectiles(cl.c))


func _count_projectiles(list: PackedInt32Array) -> int:
	var n: int = 0
	for s: int in list:
		if s >= Roster.PROJECTILE_INDEX_MIN:
			assert_bool(SnapshotFrame.replicated_kind(_rig.p_kind[s - Roster.PROJECTILE_INDEX_MIN])).is_true()
			n += 1
	return n


func test_meta_first_remove_on_death_no_slugs_mirrors_equal() -> void:
	var _m: PackedInt64Array = _run(true, true)
	assert_int(_rig.spawned).is_greater(120)                 # ~12/s over 15 s
	var n: int = _rig.live_replicated().size()
	assert_int(n).is_between(30, 100)                       # ~60 live
	for s: int in _rig.live_replicated():                   # every live projectile is cached; no slug ever is
		assert_int(_rig.snap.codec.c_tick[s]).is_equal(_rig.snap.tick)
	for i: int in _rig.live:
		if not SnapshotFrame.replicated_kind(_rig.p_kind[i]):
			assert_int(_rig.snap.codec.c_tick[Roster.PROJECTILE_INDEX_MIN + i]).is_not_equal(_rig.snap.tick)


func test_meta_and_remove_bytes_for_projectiles_stay_under_300_bytes_per_second() -> void:
	var with_p: PackedInt64Array = _run(true, false)
	var without: PackedInt64Array = _run(false, false)
	var secs: float = float(TICKS - WARMUP) / float(SnapRig.HZ)
	for k: int in CLIENTS:
		var bps: float = float(with_p[k] - without[k]) / secs
		print("PROJECTILE_META client=%d added_Bps=%.1f (with %d, without %d B over %.0f s)" % [k, bps, with_p[k], without[k], secs])
		assert_float(bps).is_less_equal(META_BUDGET_BPS)
		assert_float(bps).is_greater(50.0)                  # the projectiles do reach the client


func test_determinism() -> void:
	var a: PackedInt64Array = _run(true, false)
	var ha: int = hash(_rig.snap.codec.c_pos.slice(Roster.PROJECTILE_INDEX_MIN)) ^ _rig.rosters[0].state_hash()
	var b: PackedInt64Array = _run(true, false)
	var hb: int = hash(_rig.snap.codec.c_pos.slice(Roster.PROJECTILE_INDEX_MIN)) ^ _rig.rosters[0].state_hash()
	assert_array(Array(a)).is_equal(Array(b))
	assert_int(ha).is_equal(hb)


## Over LocalTransport (TARGET, then BAD, both ways) through ClientSession: META / REMOVE on channel 3, snapshots on
## channel 2, acks back. While spawning, live projectiles near a client show in its view; recycled slots never reach a
## client before their ENTITY_META (no malformed snapshot, no ROSTER_GAP request: InterestClient.REUSE_HOLD_TICKS);
## after spawning stops and every projectile has died, no client holds a projectile entry (no 30 s ghost).
func test_over_local_transport_with_loss_and_reorder(preset: int, test_parameters: Array = [
		[FaultModel.Preset.TARGET], [FaultModel.Preset.BAD]]) -> void:
	_build(true)
	_rig.blind_share = 0.5                                  # half leave other teams' V just before they die ...
	_rig.slugs_per_tick = 0                                 # ... and the LIFO stack hands their slot to the next projectile
	_rig.rate_per_s = 30.0
	var clock: LocalClock = LocalClock.new()
	var server: LocalTransport = LocalTransport.new_server(clock)
	server.set_fault_model(FaultModel.preset(preset, 58))
	var sessions: Array[ClientSession] = []
	var conns: PackedInt32Array = PackedInt32Array()
	var defs: NetDefs = NetDefs.new()
	defs.gravity = SnapRig.G
	defs.gravity_def[SnapRig.DEF_BOMB] = 1
	defs.gravity_def[ProjectileRig.DEFS[1]] = 1
	defs.gravity_def[ProjectileRig.DEFS[2]] = 1
	for k: int in CLIENTS:
		var ep: LocalTransport = server.connect_client()
		var cs: ClientSession = ClientSession.new(ep, k)
		cs.configure_defs(defs, null)
		var w: WelcomeInfo = WelcomeInfo.new()
		w.slot = k
		w.team = _rig.clients[k].team
		var _s: int = w.secret.resize(Protocol.SECRET_BYTES)
		var _h: int = w.map_hash.resize(Protocol.HASH_BYTES)
		w.tick = 1
		cs.receive(Protocol.CH_CONTROL, SessionCodec.encode_welcome(w))
		cs.mark_loaded(w.map_hash)
		sessions.append(cs)
		var _c: bool = conns.push_back(ep.server_conn_of())
	var _p: int = server.packet.connect(func(cn: int, _ch: int, b: PackedByteArray) -> void:
		if b.size() == SessionCodec.ACK_BYTES and b[0] == Protocol.SNAPSHOT_ACK:
			_rig.stores[conns.find(cn)].ack(b.decode_u32(1)))
	var seen: int = 0
	for t: int in 900:
		_rig.spawning = t < 400
		_rig.step_scene()
		_rig.run_interest()
		for k: int in CLIENTS:
			var reliable: Array[PackedByteArray] = []
			_rig.roster_packets(k, reliable)
			for p: PackedByteArray in reliable:
				server.send(conns[k], Protocol.CH_EVENTS, p, true)
			var out: Array[PackedByteArray] = []
			var _n: int = _rig.encode(k, out)
			for p: PackedByteArray in out:
				server.send(conns[k], Protocol.CH_SNAPSHOT, p, false)
		clock.advance_tick()
		server.poll()
		for cs: ClientSession in sessions:
			cs.tick()
		if t == 300:
			seen = _visible_in_views(sessions)
	print("PROJECTILE_LINK preset=%d seen_at_300=%d malformed=%d,%d,%d" % [preset, seen, sessions[0].malformed, sessions[1].malformed, sessions[2].malformed])
	assert_int(seen).is_greater(10)
	assert_int(_rig.live_replicated().size()).is_equal(0)
	for k: int in CLIENTS:
		var cs: ClientSession = sessions[k]
		assert_int(cs.state).is_equal(ClientSession.State.PLAYING)
		assert_int(cs.malformed).is_equal(0)
		assert_int(cs.roster_sync.requests_sent).is_equal(0)
		for i: int in range(Roster.PROJECTILE_INDEX_MIN, Roster.CAPACITY):
			assert_bool(cs.roster_sync.roster.has(i)).override_failure_message("client %d ghost %d" % [k, i]).is_false()
		assert_int(_rig.clients[k].roster_count()).is_equal(_rig.rosters[k].count())


## Projectiles of client k's server-side A list that are alive in its view, within 5 m of the truth, summed.
func _visible_in_views(sessions: Array[ClientSession]) -> int:
	var n: int = 0
	for k: int in CLIENTS:
		var v: NetSimView = sessions[k].view()
		for s: int in _rig.clients[k].a:
			if s < Roster.PROJECTILE_INDEX_MIN:
				continue
			var i: int = s - Roster.PROJECTILE_INDEX_MIN
			var id: int = EntityId.make(Roster.slot_of_index(s), _rig.p_gen[i])
			if v.alive(id):
				n += 1
				assert_float(v.pos(id).distance_to(_rig.p_pos[i])).is_less(80.0)   # render delay (latency + 3 ticks) at <= 150 m/s
	return n
