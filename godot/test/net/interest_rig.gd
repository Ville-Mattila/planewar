class_name InterestRig extends RefCounted
## Test / bench helper (NET-08): the SnapRig scene driven by real Interest for N clients. Client k possesses A-tier
## mover slot `bombs + k` (team slot % 3), targets B mover 40 + k (another team), chase camera with the focus on
## its own cell. Each client has a server-side Roster mirror filled from InterestClient.added / removed with the
## scene's def / owner / team, a BaselineStore, and the 04 s4.3 rolling refresh (ceil(|C| / 300) FULLs per tick,
## round robin over the visible part of c_set; NET-07 owns the real one).

const REFRESH_DIVISOR: int = 300

var snap: SnapRig = SnapRig.new()
var interest: Interest = Interest.new()
var clients: Array[InterestClient] = []
var rosters: Array[Roster] = []
var stores: Array[BaselineStore] = []
var refresh: PackedInt32Array = PackedInt32Array()
var _rr: PackedInt32Array = PackedInt32Array()


func build(n_clients: int, sizes: Vector3i, movers: Vector3i, bombs: int, seed_value: int) -> void:
	snap.build(sizes, movers, bombs, seed_value)
	snap.frame.gen.fill(1)
	var _r: int = _rr.resize(n_clients)
	_rr.fill(0)
	for k: int in n_clients:
		var own: int = bombs + k
		var cl: InterestClient = InterestClient.new(k, snap.roster.team_of(own))
		cl.possessed = own
		cl.target = 40 + k
		clients.append(cl)
		rosters.append(Roster.new())
		stores.append(BaselineStore.new(cl.team))


## Moves the scene one tick and runs prepare_tick (untimed helper; benches time the parts themselves).
func step_scene() -> void:
	snap.tick += 1
	snap.frame.tick = snap.tick
	snap.step_motion()
	snap.codec.prepare_tick(snap.frame)


## Interest for this tick: begin_tick once, then assign per client (focus = the possessed entity's cell).
func run_interest() -> void:
	interest.begin_tick(snap.frame, snap.codec)
	for cl: InterestClient in clients:
		if interest.present(cl.possessed):
			cl.focus_cell = interest.cell[cl.possessed]
		interest.assign(cl)


## Applies client k's roster joins / leaves to its server-side mirror; returns ENTITY_META and ROSTER_REMOVE packets.
func roster_packets(k: int, out: Array[PackedByteArray]) -> void:
	var cl: InterestClient = clients[k]
	var r: Roster = rosters[k]
	for s: int in cl.added:
		var _ok: bool = r.add(s, interest.gen[s], snap.roster.def_of(s), snap.roster.owner_of(s), snap.roster.team_of(s))
	if not cl.added.is_empty():
		var _m: int = RosterCodec.encode_meta(r, cl.added, out)
	if not cl.removed.is_empty():
		for s: int in cl.removed:
			var _ok: bool = r.remove(s, cl.removed_reason[cl.removed.find(s)])
		var _n: int = RosterCodec.encode_remove(cl.removed, cl.removed_reason, out)


## ceil(|c_set| / 300) rolling-refresh slots for client k, round robin, visible ones only (04 s4.3).
func refresh_for(k: int) -> PackedInt32Array:
	var cl: InterestClient = clients[k]
	refresh.clear()
	var n: int = cl.c_set.size()
	if n == 0:
		return refresh
	var want: int = ceili(float(n) / float(REFRESH_DIVISOR))
	var tries: int = 0
	while refresh.size() < want and tries < n:
		var s: int = cl.c_set[_rr[k] % n]
		_rr[k] += 1
		tries += 1
		if interest.visible(s, cl.team):
			var _p: bool = refresh.push_back(s)
	return refresh


## Encodes client k's tick (a, b, c, refresh) into `out`; returns the packet count.
func encode(k: int, out: Array[PackedByteArray]) -> int:
	var cl: InterestClient = clients[k]
	return snap.codec.encode(stores[k], snap.tick, cl.a, cl.b, cl.c, null, out, refresh_for(k))
