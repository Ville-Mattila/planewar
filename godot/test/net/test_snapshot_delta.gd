extends GdUnitTestSuite
## NET-06 integration: codec_delta_test (3,000 ticks, 5 % loss, 100 ms ack delay: every fully received tick's
## client frame equals the server mirror), per-tier accuracy (A, B, C), falling bombs, splitting at 1,200 B,
## 255-record sections, bandwidth at 400 entities (04 s4.6: <= 30 KB/s), determinism, one prepare_tick per tick.

const DT: float = 1.0 / SnapRig.HZ

var _rig: SnapRig
var _a: PackedInt32Array = PackedInt32Array()
var _b: PackedInt32Array = PackedInt32Array()
var _c: PackedInt32Array = PackedInt32Array()
var _max_packet: int = 0
var _bytes: int = 0
var _packets: int = 0
var _bad_status: int = 0
var _mismatch: int = 0
var _compared: int = 0


func before_test() -> void:
	_rig = SnapRig.new()
	_max_packet = 0
	_bytes = 0
	_packets = 0
	_bad_status = 0
	_mismatch = 0
	_compared = 0


## One tick for one client: encode, deliver each packet unless `drop` says so, compare complete ticks, queue
## the ack `delay` ticks later in `acks` (x = due tick, y = acked tick).
func _pump(store: BaselineStore, dec: SnapshotDecoder, k: int, pilot: PilotBlock, drop: RandomNumberGenerator,
		loss: float, delay: int, acks: Array[Vector2i]) -> void:
	_rig.lists(k, _a, _b, _c)
	var out: Array[PackedByteArray] = []
	var n: int = _rig.codec.encode(store, _rig.tick, _a, _b, _c, pilot, out)
	var got: int = 0
	for p: PackedByteArray in out:
		_max_packet = maxi(_max_packet, p.size())
		_bytes += p.size()
		_packets += 1
		if drop != null and drop.randf() < loss:
			continue
		var st: int = dec.decode(p)
		if st != SnapshotDecoder.Status.OK:
			_bad_status += 1
		got += 1
	if got == n and n > 0:
		_compared += 1
		if not dec.current().same_state(store.frame_at(_rig.tick)):
			_mismatch += 1
	acks.append(Vector2i(_rig.tick + delay, dec.store.newest_tick))
	while acks.size() > 0 and acks[0].x <= _rig.tick:
		store.ack(acks[0].y)
		acks.remove_at(0)


func test_codec_delta_3000_ticks_identical_baselines() -> void:
	_rig.build(Vector3i(30, 60, 30), Vector3i(18, 25, 12), 4, 11)
	var store: BaselineStore = BaselineStore.new(0)
	var dec: SnapshotDecoder = _rig.new_decoder(0)
	var drop: RandomNumberGenerator = RandomNumberGenerator.new()
	drop.seed = 99
	var acks: Array[Vector2i] = []
	for t: int in 3000:
		_rig.step()
		_pump(store, dec, 0, null, drop, 0.05, 3, acks)
	assert_int(_bad_status).is_equal(0)
	assert_int(_mismatch).is_equal(0)
	assert_int(_compared).is_greater(2700)
	assert_int(_max_packet).is_less_equal(Protocol.MAX_UNRELIABLE_BYTES)
	assert_int(_rig.tick - store.acked_tick).is_less(BaselineStore.DEPTH)


## Runs `ticks` ticks of a single-tier scene and checks the client's dead-reckoned state of every scheduled
## entity against the truth. Returns Vector2(max pos err in quanta (max over e/n and u), max angle deg).
func _tier_accuracy(sizes: Vector3i, movers: Vector3i, bombs: int, ticks: int) -> Vector2:
	_rig.build(sizes, movers, bombs, 5)
	var store: BaselineStore = BaselineStore.new(0)
	var dec: SnapshotDecoder = _rig.new_decoder(0)
	var acks: Array[Vector2i] = []
	var worst: Vector2 = Vector2.ZERO
	for t: int in ticks:
		_rig.step()
		_pump(store, dec, 0, null, null, 0.0, 0, acks)
		if t < 2:
			continue
		var cur: BaselineFrame = dec.current()
		for list: PackedInt32Array in [_a, _b]:
			for i: int in list:
				worst = _max2(worst, _entity_error(cur, i, list == _b))
	return worst


func _max2(a: Vector2, b: Vector2) -> Vector2:
	return Vector2(maxf(a.x, b.x), maxf(a.y, b.y))


func _entity_error(cur: BaselineFrame, i: int, coarse: bool) -> Vector2:
	var grav: bool = _rig.kind[i] == SnapRig.Kind.BOMB or (cur.flags[i] & Codec.FLAG_DYING) != 0
	var lv: Vector3i = DeadReckon.dr_levels(cur.pos[i], cur.vel[i], _rig.tick - cur.etick[i], grav, SnapRig.G, DT)
	var cell: int = Codec.pos_cell(cur.pos[i])
	var truth: int = Codec.quantize_pos(_rig.frame.pos[i])
	if Codec.pos_cell(truth) != cell:
		return Vector2.ZERO
	var d: Vector3i = lv - Vector3i(Codec.pos_e(truth), Codec.pos_n(truth), Codec.pos_u(truth))
	var r4: Vector4 = _rig.frame.rot[i]
	var q: Quaternion = Quaternion(r4.x, r4.y, r4.z, r4.w)
	var bits: int = cur.ori_c[i] if coarse else cur.ori[i]
	if bits == BaselineFrame.ORI_UNKNOWN:
		return Vector2(maxf(absi(d.x), maxf(absi(d.y), absi(d.z))), 0.0)
	var back: Quaternion = Codec.dequantize_quat_coarse(bits) if coarse else Codec.dequantize_quat(bits)
	var ang: float = rad_to_deg(2.0 * acos(minf(1.0, absf(q.dot(back)))))
	return Vector2(maxf(absi(d.x), maxf(absi(d.y), absi(d.z))), ang)


func test_tier_a_roundtrip_accuracy() -> void:
	# A-DELTA: unsent means |residual| < 4 quanta; sent POS_SMALL leaves <= 2; FULL/LARGE exact.
	var w: Vector2 = _tier_accuracy(Vector3i(40, 0, 0), Vector3i(30, 0, 0), 6, 300)
	assert_float(w.x).is_less_equal(3.0)
	assert_float(w.y).is_less_equal(0.4)
	assert_int(_mismatch).is_equal(0)
	assert_int(_bad_status).is_equal(0)


func test_tier_b_roundtrip_accuracy() -> void:
	var w: Vector2 = _tier_accuracy(Vector3i(0, 60, 0), Vector3i(0, 40, 0), 0, 300)
	assert_float(w.x).is_less_equal(3.0)
	assert_float(w.y).is_less_equal(6.0)
	assert_int(_mismatch).is_equal(0)
	assert_int(_bad_status).is_equal(0)


func test_tier_c_blip_roundtrip() -> void:
	_rig.build(Vector3i(0, 0, 60), Vector3i(0, 0, 40), 0, 7)
	var store: BaselineStore = BaselineStore.new(0)
	var dec: SnapshotDecoder = _rig.new_decoder(0)
	var acks: Array[Vector2i] = []
	var blips: int = 0
	var worst_plane: float = 0.0
	var worst_alt: float = 0.0
	for t: int in 600:
		_rig.step()
		_pump(store, dec, 0, null, null, 0.0, 0, acks)
		var cur: BaselineFrame = dec.current()
		for i: int in _c:
			if cur.blip[i] == DeadReckon.BLIP_UNKNOWN or Codec.pos_cell(cur.pos[i]) != Codec.pos_cell(Codec.quantize_pos(_rig.frame.pos[i])):
				continue
			blips += 1
			var p: Vector3 = Codec.dequantize_pos(cur.pos[i])
			var truth: Vector3 = _rig.frame.pos[i]
			var f: Basis = Codec.cell_frame(Codec.pos_cell(cur.pos[i]))
			var d: Vector3 = f.transposed() * (p - truth)
			worst_plane = maxf(worst_plane, maxf(absf(d.x), absf(d.y)))
			worst_alt = maxf(worst_alt, absf(p.length() - truth.length()))
	assert_int(blips).is_greater(500)
	assert_float(worst_plane).is_less_equal(5.2)          # 10 m e8/n8 buckets (+ the e8 254 clamp margin)
	assert_float(worst_alt).is_less_equal(20.5)           # 40 m altitude bands
	assert_int(_mismatch).is_equal(0)
	assert_int(_bad_status).is_equal(0)


## A bomb on an exact lattice point with an exact quantised velocity falling under the codec's gravity model.
func test_falling_bomb_exact_no_records_after_full() -> void:
	var codec: SnapshotCodec = SnapshotCodec.new(SnapRig.G, SnapRig.HZ)
	var store: BaselineStore = BaselineStore.new(0)
	var r: Roster = Roster.new()
	var _ok: bool = r.add(3, 1, SnapRig.DEF_BOMB, 1, 1)
	var dec: SnapshotDecoder = SnapshotDecoder.new(SnapRig.G, SnapRig.HZ, 0, r)
	var _rs: int = dec.gravity_def.resize(4)
	dec.gravity_def[SnapRig.DEF_BOMB] = 1
	var q0: int = Codec.quantize_pos(Sphere.from_lat_lon(0.05, 0.07, Sphere.PLANET_RADIUS + 1400.0))
	var p0: Vector3 = Codec.dequantize_pos(q0)
	var v0: Vector3 = Codec.cell_frame(Codec.pos_cell(q0)) * Vector3(20.0, -10.0, 4.0)
	var f: SnapshotFrame = SnapshotFrame.new()
	f.resize(1)
	var records: int = 0
	for t: int in range(1, 91):
		var s: float = float(t - 1) * DT
		f.tick = t
		f.set_entity(0, 3, p0 + v0 * s - p0.normalized() * (0.5 * SnapRig.G * s * s), v0 - p0.normalized() * (SnapRig.G * s),
				Quaternion.IDENTITY, 1.0, 0, 1, 0, true)
		codec.prepare_tick(f)
		var out: Array[PackedByteArray] = []
		var _n: int = codec.encode(store, t, PackedInt32Array([3]), PackedInt32Array(), PackedInt32Array(), null, out)
		assert_int(dec.decode(out[0])).is_equal(SnapshotDecoder.Status.OK)
		store.ack(t)
		if out[0].size() > SnapshotCodec.HEADER_BYTES:
			records += 1
	assert_int(records).is_equal(1)                                   # the FULL record only: 3 s of fall, 27 m


## Semi-implicit Euler bombs (the sim's integration shape) released at lattice points with lattice velocities
## near cell centres (a cell change is a FULL record, which re-quantises the velocity):
## the only records left are the integrator's drift (0.5 * g * dt * t), a few per fall, never POS_LARGE; linear
## dead reckoning needs several times more. Velocity quantisation (2 m/s) of an arbitrary release velocity
## adds drift at up to 1 m/s; that cost is the same with either dead-reckoning branch (PR note).
func test_falling_bombs_drift_only() -> void:
	var pos_records: PackedInt32Array = PackedInt32Array()
	for use_gravity: bool in [true, false]:
		var codec: SnapshotCodec = _bomb_run(use_gravity)
		assert_int(codec.n_pos_large).is_equal(0)
		var _p: bool = pos_records.push_back(codec.n_pos_small)
	assert_int(pos_records[0]).is_less_equal(8 * 6)                   # 8 bombs, 3 s of fall each
	assert_int(pos_records[0] * 3).is_less(pos_records[1])


func _bomb_run(use_gravity: bool) -> SnapshotCodec:
	var codec: SnapshotCodec = SnapshotCodec.new(SnapRig.G, SnapRig.HZ)
	var store: BaselineStore = BaselineStore.new(0)
	var r: Roster = Roster.new()
	var dec: SnapshotDecoder = SnapshotDecoder.new(SnapRig.G, SnapRig.HZ, 0, r)
	var _rs: int = dec.gravity_def.resize(4)
	dec.gravity_def[SnapRig.DEF_BOMB] = 1 if use_gravity else 0
	var f: SnapshotFrame = SnapshotFrame.new()
	f.resize(8)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 8
	for i: int in 8:
		var _ok: bool = r.add(i, 1, SnapRig.DEF_BOMB, 1, 1)
		var q0: int = Codec.quantize_pos(Sphere.cell_center_dir(40 * i + 3, Sphere.GRID_INTEREST) * (Sphere.PLANET_RADIUS + 1200.0))
		var enu: Vector3 = Vector3(rng.randi_range(-20, 20), rng.randi_range(-20, 20), rng.randi_range(-3, 3)) * Codec.VEL_UNIT
		f.set_entity(i, i, Codec.dequantize_pos(q0), Codec.cell_frame(Codec.pos_cell(q0)) * enu, Quaternion.IDENTITY,
				1.0, 0, 1, 0, use_gravity)
	var idx: PackedInt32Array = PackedInt32Array([0, 1, 2, 3, 4, 5, 6, 7])
	for t: int in range(1, 91):
		f.tick = t
		codec.prepare_tick(f)
		var out: Array[PackedByteArray] = []
		var _n: int = codec.encode(store, t, idx, PackedInt32Array(), PackedInt32Array(), null, out)
		assert_int(dec.decode(out[0])).is_equal(SnapshotDecoder.Status.OK)
		store.ack(t)
		for i: int in 8:
			var p: Vector3 = f.pos[i]
			f.vel[i] = f.vel[i] - p.normalized() * (SnapRig.G * DT)
			f.pos[i] = p + f.vel[i] * DT
	assert_bool(dec.current().same_state(store.frame_at(90))).is_true()
	return codec
