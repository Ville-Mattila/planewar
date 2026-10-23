class_name NetViewRig extends RefCounted
## Test helper (NET-17): a minimal in-process server for ClientSession over LocalTransport. It plays the
## ServerSession role NET-15 will own: HELLO -> WELCOME, LOADED -> ENTITY_META + the first FULL SNAPSHOT; then per
## `send_tick` it fills a SnapshotFrame from the SimWorld's LocalSimView (the NET-15 SimView adapter, test-side),
## runs prepare_tick once, and sends each client ENTITY_META for new entries, POSSESSED events, TEAM_STATE (own team)
## and its SNAPSHOT (every visible entity in tier A, against the client's acked baseline, pilot block for the
## client's possessed unit). `snap_world` moves every live entity onto the wire lattice (Codec round trip) so a
## decoded value can be compared exactly with the store (TEST-02 factory).

var world: SimWorld
var content: ContentSet
var local: SimView
var clock: LocalClock = LocalClock.new()
var server: LocalTransport
var codec: SnapshotCodec
var roster: Roster = Roster.new()
var frame: SnapshotFrame = SnapshotFrame.new()
var sessions: Array[ClientSession] = []
var conns: PackedInt32Array = PackedInt32Array()
var slots: PackedInt32Array = PackedInt32Array()
var teams: PackedInt32Array = PackedInt32Array()
var loaded: PackedByteArray = PackedByteArray()
var stores: Array[BaselineStore] = []
var known: Array[PackedByteArray] = []      ## per client: roster indices whose ENTITY_META was sent
var bytes_snapshot: PackedInt64Array = PackedInt64Array()
var tick: int = 0
var snapshot_ticks: int = 0


func _init(w: SimWorld, c: ContentSet, model: FaultModel = null) -> void:
	world = w
	content = c
	local = w.view()
	server = LocalTransport.new_server(clock)
	if model != null:
		server.set_fault_model(model)
	codec = SnapshotCodec.new(c.rules.gravity, c.rules.tick_hz)
	var _r: int = server.packet.connect(_on_server_packet)
	tick = w.tick()


func add_client(slot: int, team_id: int) -> ClientSession:
	var ep: LocalTransport = server.connect_client()
	var cs: ClientSession = ClientSession.new(ep, slot)
	cs.configure(content, world.terrain())
	var hash: PackedByteArray = PackedByteArray()
	var _r: int = hash.resize(Protocol.HASH_BYTES)
	var _ok: bool = cs.hello(hash, PackedByteArray([1, 2, 3]), Protocol.Platform.LINUX, Protocol.WireInputClass.POINTER, Protocol.Role.PLAYER)
	sessions.append(cs)
	var _a: bool = conns.push_back(ep.server_conn_of())
	var _b: bool = slots.push_back(slot)
	var _c: bool = teams.push_back(team_id)
	var _d: bool = loaded.push_back(0)
	stores.append(BaselineStore.new(team_id))
	var k: PackedByteArray = PackedByteArray()
	var _e: int = k.resize(Roster.CAPACITY)
	known.append(k)
	var _f: bool = bytes_snapshot.push_back(0)
	return cs


## Advance the shared clock one tick and poll server + clients (ClientSession.tick).
func pump(n: int = 1) -> void:
	for _i: int in n:
		clock.advance_tick()
		server.poll()
		for cs: ClientSession in sessions:
			cs.tick()
			if cs.state == ClientSession.State.LOADING:
				var mh: PackedByteArray = PackedByteArray()
				var _r: int = mh.resize(Protocol.HASH_BYTES)
				cs.mark_loaded(mh)


## One server tick at `tick` (the caller steps or edits the world first): snapshot, meta, events, team state.
func send_tick(at_tick: int) -> void:
	tick = at_tick
	fill_frame()
	codec.prepare_tick(frame)
	for k: int in sessions.size():
		if loaded[k] != 0:
			_send_client(k)


func _send_client(k: int) -> void:
	var t: int = teams[k]
	var vis: PackedInt32Array = PackedInt32Array()
	var fresh: PackedInt32Array = PackedInt32Array()
	for r: int in frame.count:
		var s: int = frame.slot[r]
		if t == frame.team[r] or ((frame.visible_mask[r] >> t) & 1) != 0:
			var _a: bool = vis.push_back(s)
			if known[k][s] == 0:
				known[k][s] = 1
				var _b: bool = fresh.push_back(s)
	if not fresh.is_empty():
		var metas: Array[PackedByteArray] = []
		var _m: int = RosterCodec.encode_meta(roster, fresh, metas)
		for m: PackedByteArray in metas:
			server.send(conns[k], Protocol.CH_EVENTS, m, true)
		_send_possessed(k, fresh)
	if tick % 15 == 0 or not fresh.is_empty():
		server.send(conns[k], Protocol.CH_SNAPSHOT, team_state_bytes(t), false)
	var out: Array[PackedByteArray] = []
	var _n: int = codec.encode(stores[k], tick, vis, PackedInt32Array(), PackedInt32Array(), pilot_for(slots[k]), out)
	for p: PackedByteArray in out:
		bytes_snapshot[k] += p.size()
		server.send(conns[k], Protocol.CH_SNAPSHOT, p, false)
	snapshot_ticks += 1


func _send_possessed(k: int, fresh: PackedInt32Array) -> void:
	var buf: PackedByteArray = PackedByteArray()
	var _r: int = buf.resize(1200)
	var at: int = EventCodec.write_header(buf, tick)
	var n: int = 0
	for s: int in fresh:
		var id: int = EntityId.make(s, roster.generation_of(s))
		if local.possessor(id) >= 0:
			at = EventCodec.write_event(buf, at, Protocol.EventKind.POSSESSED, PackedInt32Array([s, local.possessor(id)]), 0)
			n += 1
	if n > 0:
		buf[5] = n
		server.send(conns[k], Protocol.CH_EVENTS, buf.slice(0, at), true)


## Every live store entity (projectiles are not on the roster) into `frame`, roster kept in step.
func fill_frame() -> void:
	var ids: PackedInt32Array = PackedInt32Array()
	for list: PackedInt32Array in [local.structures(), local.ships(), local.wrecks()]:
		ids.append_array(list)
	frame.resize(ids.size())
	frame.tick = tick
	for r: int in ids.size():
		var id: int = ids[r]
		var s: int = EntityId.slot(id)
		if not roster.has(s) or roster.generation_of(s) != EntityId.gen(id):
			var _a: bool = roster.add(s, EntityId.gen(id), local.def_id(id), local.owner(id) & 0xFF, local.team(id) & 0xFF)
		var bits: int = Codec.FLAG_DOCKED if (local.flags(id) & EntityStore.F_DOCKED) != 0 else 0
		var vis: int = 0
		for t: int in 8:
			vis |= (1 << t) if local.visible_to(t, id) else 0
		frame.set_entity(r, s, local.pos(id), local.vel(id), local.basis(id).get_rotation_quaternion(), local.hp01(id),
				Codec.make_flags(local.control_state(id), bits), local.team(id) & 0xFF, local.ai_tag(id), false, vis)
		frame.gen[r] = EntityId.gen(id)


## The pilot block of player `slot`'s possessed unit, or null.
func pilot_for(slot: int) -> PilotBlock:
	for id: int in local.ships():
		if local.possessor(id) == slot:
			var p: PilotBlock = PilotBlock.new()
			var sd: ShipDef = content.ships[local.def_id(id) - DefRanges.SHIP_BASE]
			p.fuel_ds = roundi(local.fuel01(id) * sd.fuel_s * 10.0)
			p.ammo = local.ammo(id)
			p.bombs = local.bombs(id)
			p.rockets = local.rockets(id)
			p.hull = roundi(local.hp01(id) * float(sd.hp))
			p.incoming_rockets = local.incoming_rockets(id)
			p.boost_state = PilotBlock.boost_byte(local.boost_state(id), 0.0)
			p.flip_cooldown = roundi(local.flip_cooldown01(id) * 255.0)
			p.dock_state = local.dock_state(id)
			return p
	return null


func team_state_bytes(t: int) -> PackedByteArray:
	var ts: TeamStateView = local.team_state(t)
	var w: TeamStateWire = TeamStateWire.new()
	w.tick = maxi(tick, 1)
	w.ore = ts.ore
	w.ice = ts.ice
	w.ore_cap = ts.ore_cap
	w.ice_cap = ts.ice_cap
	w.power_supply = roundi(ts.power_supply)
	w.power_demand = roundi(ts.power_demand)
	w.unit_cap = ts.unit_cap
	w.structure_cap = ts.structure_cap
	w.flags = ts.flags & TeamStateCodec.FLAGS_MASK
	for m: int in ts.members:
		var ps: PlayerStateView = local.player_state(m)
		w.add_member(m, ps.unit_count, ps.structure_count)
	return TeamStateCodec.encode(w)


## Moves every live store entity onto the wire lattice: pos = dequantize(quantize(pos)) to a fixed point, vel and
## orientation through the decoder's own conversions (NetPose), so the decoded value equals the store exactly.
func snap_world() -> void:
	var st: EntityStore = world.store()
	for list: PackedInt32Array in [st.structures, st.ships, st.wrecks]:
		for s: int in list:
			var p: Vector3 = st.pos[s]
			for _k: int in 4:
				p = Codec.dequantize_pos(Codec.quantize_pos(p))
			st.pos[s] = p
			var cell: int = Codec.pos_cell(Codec.quantize_pos(p))
			st.vel[s] = NetPose.fine_to_world(DeadReckon.fine_from_bits(Codec.quantize_vel(st.vel[s], cell)), cell)
			var f: Vector3 = st.fwd[s]
			var u: Vector3 = st.up[s]
			var q: Quaternion = Basis(f.cross(u), u, -f).get_rotation_quaternion()
			for _k: int in 4:                     # near a largest-component tie a round trip moves once more
				q = NetPose.canonical(Codec.dequantize_quat(Codec.quantize_quat(q)))
			var b: Basis = Basis(q)
			st.fwd[s] = -b.z
			st.up[s] = b.y


func _on_server_packet(conn: int, channel: int, bytes: PackedByteArray) -> void:
	var k: int = conns.find(conn)
	if k < 0 or bytes.is_empty():
		return
	if bytes[0] == Protocol.HELLO and channel == Protocol.CH_CONTROL:
		server.send(conn, Protocol.CH_CONTROL, welcome_bytes(k), true)
	elif bytes[0] == Protocol.LOADED:
		loaded[k] = 1
	elif bytes[0] == Protocol.SNAPSHOT_ACK and bytes.size() == SessionCodec.ACK_BYTES:
		stores[k].ack(bytes.decode_u32(1))
	elif bytes[0] == Protocol.PING and bytes.size() == SessionCodec.PING_BYTES:
		server.send(conn, Protocol.CH_INPUT, SessionCodec.encode_pong(bytes.decode_u32(1), tick, int(clock.now_ms())), false)


func welcome_bytes(k: int) -> PackedByteArray:
	var w: WelcomeInfo = WelcomeInfo.new()
	w.conn_id = conns[k]
	w.slot = slots[k]
	w.team = teams[k]
	w.session_id = 1000 + k
	var _r: int = w.secret.resize(Protocol.SECRET_BYTES)
	w.tick = tick
	w.server_ms = int(clock.now_ms())
	w.map_id = "tiny_test"
	var _h: int = w.map_hash.resize(Protocol.HASH_BYTES)
	for i: int in sessions.size():
		w.add_player(slots[i], teams[i], Protocol.PlayerKind.HUMAN, Protocol.DOCTRINE_HIDDEN, 2, "p%d" % slots[i])
	return SessionCodec.encode_welcome(w)
