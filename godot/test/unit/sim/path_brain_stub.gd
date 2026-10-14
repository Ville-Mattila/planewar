class_name PathBrainStub extends SimAiHook
## TA-50 brain stub: reaches the sim's Pathing only through `CommandSinkBase.pathing()` (R0 B.11 A-55), never a
## SimWorld reference. Unit k shuttles between endpoint A[k] and B[k] (Harvester-style loops: the cache warms up);
## units with `roam[k]` set pick a new B from `pool` by its own Rng after each leg (Crawler-style, cold queries).
## Every tick: poll each ticket, record a finished one (tick, unit, status, cell count, cell hash), release it, flip
## the leg; a unit without a ticket re-requests on ticks where (t + k) % every == 0. The whole stub state is in its
## S4 bytes, so a restored world continues identically.

var a_pts: PackedVector3Array = PackedVector3Array()
var b_pts: PackedVector3Array = PackedVector3Array()
var masks: PackedInt32Array = PackedInt32Array()
var roam: PackedByteArray = PackedByteArray()
var pool: PackedVector3Array = PackedVector3Array()
var every: int = 10
var tickets: PackedInt32Array = PackedInt32Array()
var leg: PackedByteArray = PackedByteArray()
var record: PackedInt32Array = PackedInt32Array()       ## 5 ints per finished ticket
var requests: int = 0
var rejected: int = 0
var rng: Rng = Rng.new(50)
var seen: Pathing = null                                ## what sink.pathing() returned on the last tick (tests)
var check: bool = false                                 ## validate every DONE route with NavTestKit (tests)
var failures: PackedStringArray = PackedStringArray()


func add_unit(a: Vector3, b: Vector3, mask: int, roams: bool) -> void:
	var _a: bool = a_pts.push_back(a)
	_a = b_pts.push_back(b)
	_a = masks.push_back(mask)
	_a = roam.push_back(1 if roams else 0)
	_a = tickets.push_back(Pathing.NO_TICKET)
	_a = leg.push_back(0)


## Test setup (reads p.grid directly; the brain itself only uses the sink): `loops` shuttling units alternating
## `mask_a` / `mask_b`, then `roams` roaming units on `mask_b` with a pool of 16 goals, all within ~4 km of `centre`.
func populate(p: Pathing, centre: Vector3, loops: int, roams: int, mask_a: int, mask_b: int) -> void:
	for _k: int in 16:
		var _a: bool = pool.push_back(_near(p, centre, rng.range_f(500.0, 4000.0), mask_b) * Sphere.PLANET_RADIUS)
	for k: int in loops + roams:
		var m: int = mask_a if k % 2 == 0 and k < loops else mask_b
		var a: Vector3 = _near(p, centre, rng.range_f(0.0, 800.0), m)
		var b: Vector3 = _near(p, a, rng.range_f(800.0, 4000.0), m)
		add_unit(a * Sphere.PLANET_RADIUS, b * Sphere.PLANET_RADIUS, m, k >= loops)


# A unit direction about `m_dist` metres from `a` on a random bearing whose path cell is passable for `mask`.
func _near(p: Pathing, a: Vector3, m_dist: float, mask: int) -> Vector3:
	var reach: float = m_dist
	for _t: int in 400:
		var f: Basis = Sphere.tangent_frame(a)
		var brg: float = rng.range_f(-PI, PI)
		var axis: Vector3 = (f.y * cos(brg) + f.x * sin(brg)).cross(a).normalized()
		var b: Vector3 = a.rotated(-axis, reach / Sphere.PLANET_RADIUS).normalized() if reach > 0.0 else a
		if p.grid.passable(PathGrid.cell_of(b), PathGrid.limit_q_of(mask)):
			return b
		reach += 20.0
	return a


func done_count() -> int:
	return floori(float(record.size()) / 5.0)


func on_tick(t: int, _view: SimView, sink: CommandSinkBase) -> void:
	var p: Pathing = sink.pathing()
	seen = p
	if p == null:
		return
	for k: int in tickets.size():
		var tk: int = tickets[k]
		if tk != Pathing.NO_TICKET and p.status(tk) != Pathing.ST_PENDING:
			var cells: PackedInt32Array = p.result_cells(tk)
			if check and p.status(tk) == Pathing.ST_DONE:
				var s0: int = PathGrid.cell_of(a_pts[k] if leg[k] == 0 else b_pts[k])
				var g0: int = PathGrid.cell_of(b_pts[k] if leg[k] == 0 else a_pts[k])
				var why: String = NavTestKit.validate(p, cells, s0, g0, masks[k])
				if why != "":
					var _f: bool = failures.push_back("unit %d tick %d: %s" % [k, t, why])
			record.append_array(PackedInt32Array([t, k, p.status(tk), cells.size(), hash(cells)]))
			p.release(tk)
			tickets[k] = Pathing.NO_TICKET
			leg[k] = 1 - leg[k]
			if roam[k] != 0 and leg[k] == 1:
				b_pts[k] = pool[rng.range_i(0, pool.size() - 1)]
		if tickets[k] == Pathing.NO_TICKET and (t + k) % every == 0:
			var from: Vector3 = a_pts[k] if leg[k] == 0 else b_pts[k]
			var to: Vector3 = b_pts[k] if leg[k] == 0 else a_pts[k]
			tickets[k] = p.request(from, to, masks[k])
			requests += 1
			if tickets[k] == Pathing.NO_TICKET:
				rejected += 1


func serialize() -> PackedByteArray:
	var buf: StreamPeerBuffer = StreamPeerBuffer.new()
	for v: Variant in [a_pts, b_pts, masks, roam, pool, every, tickets, leg, record, requests, rejected, rng.state()]:
		buf.put_var(v)
	return buf.data_array


func deserialize(bytes: PackedByteArray) -> void:
	var buf: StreamPeerBuffer = StreamPeerBuffer.new()
	buf.data_array = bytes
	a_pts = buf.get_var()
	b_pts = buf.get_var()
	masks = buf.get_var()
	roam = buf.get_var()
	pool = buf.get_var()
	every = buf.get_var()
	tickets = buf.get_var()
	leg = buf.get_var()
	record = buf.get_var()
	requests = buf.get_var()
	rejected = buf.get_var()
	var st: PackedByteArray = buf.get_var()
	rng = Rng.from_state(st)
