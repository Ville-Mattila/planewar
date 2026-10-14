extends GdUnitTestSuite
## NET-06 unit tests: the 04 s3.5 worked example reproduced byte for byte (53 B) and decoded; per-tier record
## round trips (FULL, A-DELTA, B-DELTA, C-BLIP) with server mirror == client frame; dead reckoning helpers;
## residual masks; pilot block; the A-24 tier-B flag mapping pinned on the wire.

const G: float = 6.0
const HZ: int = 30
const EXAMPLE: String = "84 7A 46 00 00 77 46 00 00 2B 02 11 0D 00 00 01 9A 2F 4C 71 37 00 F4 06 05 FE 03 00 12 C0 87 3E " \
		+ "01 12 01 01 00 00 B4 08 7E 01 02 00 64 00 00 00 00 00 00 00 00"
const T0: int = 18039
const T1: int = 18042


func _hex(s: String) -> PackedByteArray:
	var out: PackedByteArray = PackedByteArray()
	for h: String in s.split(" ", false):
		var _a: bool = out.push_back(h.hex_to_int())
	return out


func _lattice(lat: float, lon: float, alt: float) -> int:
	return Codec.quantize_pos(Sphere.from_lat_lon(lat, lon, Sphere.PLANET_RADIUS + alt))


func _enu(q: int, e: float, n: float, u: float) -> Vector3:
	return Codec.cell_frame(Codec.pos_cell(q)) * Vector3(e, n, u)


func _roster() -> Roster:
	var r: Roster = Roster.new()
	var _a: bool = r.add(17, 1, 2, 0, 0)
	var _b: bool = r.add(23, 1, 2, 4, 1)
	var _c: bool = r.add(41, 1, 5, 0, 0)
	return r


## Frame at T0 (baseline) or T1 (the example tick). Entities: 17 own Dart, 23 enemy Dart, 41 own Harvester.
func _example_frame(t: int) -> SnapshotFrame:
	var f: SnapshotFrame = SnapshotFrame.new()
	f.resize(3)
	f.tick = t
	var q17: int = _lattice(0.20, 0.50, 500.0)
	var q23: int = _lattice(0.20, 0.52, 650.0)
	var q41: int = _lattice(0.21, 0.50, 40.0)
	var v17: Vector3 = _enu(q17, 108.0, 0.0, -24.0)
	var v23: Vector3 = _enu(q23, 40.0, 10.0, 0.0)
	var v41: Vector3 = _enu(q41, 12.0, 0.0, 0.0)
	var r17: Quaternion = Codec.dequantize_quat(0x714C2F9A)
	var r23: Quaternion = Codec.dequantize_quat(0x3E87C012)
	var p17: Vector3 = Codec.dequantize_pos(q17)
	var p23: Vector3 = Codec.dequantize_pos(q23)
	var p41: Vector3 = Codec.dequantize_pos(q41)
	if t == T1:
		p17 = Codec.dequantize_pos(_moved(q17, 0xF40036, Vector3i(0, 0, 4)))
		p23 = Codec.dequantize_pos(_moved(q23, Codec.quantize_vel(v23, Codec.pos_cell(q23)), Vector3i(-8, 12, 0)))
		p41 = Codec.dequantize_pos(_moved(q41, 6, Vector3i(4, 0, 0)))
		v17 = _enu(q17, 110.0, 0.0, -24.0)
	else:
		r17 = r17 * Quaternion(Vector3.UP, deg_to_rad(4.0))
		r23 = r23 * Quaternion(Vector3.RIGHT, deg_to_rad(3.0))
	var possessed: int = Codec.make_flags(Protocol.ControlState.POSSESSED, 0)
	f.set_entity(0, 17, p17, v17, r17, 1.0, possessed, 0, 5)
	f.set_entity(1, 23, p23, v23, r23, 0.8, 0, 1)
	f.set_entity(2, 41, p41, v41, Quaternion.IDENTITY, 0.6, 0, 0, 2)
	return f


func _moved(q: int, vel_bits: int, add: Vector3i) -> int:
	var dr: Vector3i = DeadReckon.dr_levels(q, DeadReckon.fine_from_bits(vel_bits), T1 - T0, false, G, 1.0 / HZ) + add
	return Codec.pack_pos(Codec.pos_cell(q), dr.x, dr.y, dr.z)


func _example_pilot() -> PilotBlock:
	var p: PilotBlock = PilotBlock.new()
	p.fuel_ds = 2228
	p.ammo = 382
	p.bombs = 2
	p.hull = 100
	return p


func test_worked_example_53_bytes_reproduced_and_decoded() -> void:
	# The fixture is exact: lattice points and quaternions survive a quantise round trip.
	for q: int in [0x714C2F9A, 0x3E87C012]:
		assert_int(Codec.quantize_quat(Codec.dequantize_quat(q))).is_equal(q)
	var codec: SnapshotCodec = SnapshotCodec.new(G, HZ)
	assert_int(codec.max_packets).is_equal(SnapshotCodec.MAX_PACKETS_PER_TICK)   # A-36 default 4
	var store: BaselineStore = BaselineStore.new(0)
	var dec: SnapshotDecoder = SnapshotDecoder.new(G, HZ, 0, _roster())
	var out: Array[PackedByteArray] = []
	codec.prepare_tick(_example_frame(T0))
	assert_int(codec.encode(store, T0, PackedInt32Array([17, 23]), PackedInt32Array([41]), PackedInt32Array(), null, out)).is_equal(1)
	assert_int(out[0].size()).is_equal(10 + 1 + 20 + 19 + 1 + 20)       # FULL records, own team +1 ai_tag
	assert_int(dec.decode(out[0])).is_equal(SnapshotDecoder.Status.OK)
	store.ack(dec.store.complete_tick)
	out.clear()
	codec.prepare_tick(_example_frame(T1))
	assert_int(codec.encode(store, T1, PackedInt32Array([17, 23]), PackedInt32Array([41]), PackedInt32Array(), _example_pilot(), out)).is_equal(1)
	assert_int(out[0].size()).is_equal(53)
	assert_int(out[0][9]).is_equal(0x2B)                                 # index 0 + LAST (A-36): byte unchanged
	assert_array(Array(out[0])).is_equal(Array(_hex(EXAMPLE)))
	assert_int(dec.decode(out[0])).is_equal(SnapshotDecoder.Status.OK)
	assert_bool(dec.current().same_state(store.frame_at(T1))).is_true()
	assert_array(Array(dec.pilot.to_bytes())).is_equal(Array(_example_pilot().to_bytes()))
	assert_int(dec.pilot_tick).is_equal(T1)
	# The decoded Dart sits 0.25 m (4 u quanta) above its dead-reckoned point, velocity (110, 0, -24) m/s.
	var cur: BaselineFrame = dec.current()
	var v: Vector3 = Codec.dequantize_vel(DeadReckon.bits_from_fine(cur.vel[17]), Codec.pos_cell(cur.pos[17]))
	assert_float(v.distance_to(_enu(cur.pos[17], 110.0, 0.0, -24.0))).is_less(0.01)


func test_pos_mask_and_residual_rounding() -> void:
	assert_int(SnapshotCodec.pos_mask(Vector3i.ZERO)).is_equal(0)
	assert_int(SnapshotCodec.pos_mask(Vector3i(3, -3, 2))).is_equal(0)       # under one 4-quanta step: not sent
	assert_int(SnapshotCodec.pos_mask(Vector3i(4, 0, 0))).is_equal(SnapshotCodec.MASK_POS_SMALL)
	assert_int(SnapshotCodec.pos_mask(Vector3i(0, -4, 1))).is_equal(SnapshotCodec.MASK_POS_SMALL)
	assert_int(SnapshotCodec.pos_mask(Vector3i(509, 0, -510))).is_equal(SnapshotCodec.MASK_POS_SMALL)
	assert_int(SnapshotCodec.pos_mask(Vector3i(510, 0, 0))).is_equal(SnapshotCodec.MASK_POS_LARGE)
	assert_int(SnapshotCodec.pos_mask(Vector3i(0, 32767, -32767))).is_equal(SnapshotCodec.MASK_POS_LARGE)
	assert_int(SnapshotCodec.pos_mask(Vector3i(0, 0, 32768))).is_equal(-1)
	for r: int in range(-600, 601):
		var res: Vector3i = Vector3i(r, -r, r >> 1)
		var m: int = SnapshotCodec.pos_mask(res)
		var err: Vector3i = res - SnapshotCodec.applied_residual(m, res)
		var lim: int = 3 if m == 0 else 2                                    # unsent < 4; sent leaves [-2, 1]
		assert_bool(absi(err.x) <= lim and absi(err.y) <= lim and absi(err.z) <= lim).is_true()
	# POS_SMALL step is 4 quanta: 15.6 cm E/N, 25 cm U; range +-127 steps.
	assert_float(Codec.POS_EN_QUANTUM * 4.0 * SnapshotCodec.SMALL_MAX).is_greater(15.9)
	assert_int(SnapshotCodec.delta_body_bytes(0x0D, false, true)).is_equal(11)
	assert_int(SnapshotCodec.delta_body_bytes(0x05, false, false)).is_equal(8)
	assert_int(SnapshotCodec.delta_body_bytes(0x25, true, true)).is_equal(8)
	assert_int(SnapshotCodec.delta_body_bytes(0x3E, false, true)).is_equal(1 + 6 + 4 + 3 + 1 + 2)
	assert_int(SnapshotCodec.FULL_BODY_BYTES + 1).is_equal(Codec.FULL_RECORD_BYTES)


func test_dead_reckoning_linear_is_exact_and_gravity_bends_toward_centre() -> void:
	var q: int = _lattice(-0.4, 2.0, 1200.0)
	var vb: int = DeadReckon.fine_from_bits(Codec.quantize_vel(_enu(q, 50.0, -20.0, 10.0), Codec.pos_cell(q)))
	var dt: float = 1.0 / HZ
	var lin: Vector3i = DeadReckon.dr_levels(q, vb, 30, false, G, dt)
	# 1 s at (50, -20, 10) m/s = (1280, -512, 160) levels exactly.
	assert_that(lin - Vector3i(Codec.pos_e(q), Codec.pos_n(q), Codec.pos_u(q))).is_equal(Vector3i(1280, -512, 160))
	var grav: Vector3i = DeadReckon.dr_levels(q, vb, 30, true, G, dt)
	# 0.5 * 6 * 1^2 = 3 m mostly downwards: 48 u levels.
	assert_int(lin.z - grav.z).is_between(47, 49)
	assert_that(DeadReckon.dr_levels(q, vb, 0, true, G, dt)).is_equal(Vector3i(Codec.pos_e(q), Codec.pos_n(q), Codec.pos_u(q)))
	assert_int(DeadReckon.dr_fine(q, vb, 30, false, G, dt)).is_equal(vb)
	assert_int(DeadReckon.bits_from_fine(vb)).is_equal(Codec.quantize_vel(_enu(q, 50.0, -20.0, 10.0), Codec.pos_cell(q)))
	var vf: int = DeadReckon.dr_fine(q, vb, 30, true, G, dt)
	assert_int(DeadReckon.fine_axis(vf, 2)).is_between(4000, 4200)   # 10 - 6 * rz/L m/s, kept at 1/1024 m/s
	var vg: Vector3 = Codec.dequantize_vel(DeadReckon.bits_from_fine(vf), Codec.pos_cell(q))
	assert_float((Codec.cell_frame(Codec.pos_cell(q)).transposed() * vg).z).is_equal_approx(4.0, 1.01)
	assert_bool(DeadReckon.levels_ok(Vector3i(0, 65535, 3))).is_true()
	assert_bool(DeadReckon.levels_ok(Vector3i(-1, 0, 0)) or DeadReckon.levels_ok(Vector3i(0, 65536, 0))).is_false()


func test_blip_geometry() -> void:
	var p: Vector3 = Sphere.from_lat_lon(0.1, -0.7, Sphere.PLANET_RADIUS + 733.0)
	var q: int = Codec.quantize_pos(p)
	var b: int = DeadReckon.make_blip(q, 733.0, DeadReckon.BlipState.UNDER_FIRE)
	assert_int(DeadReckon.blip_state(b)).is_equal(DeadReckon.BlipState.UNDER_FIRE)
	assert_int(b & 0xFF).is_less_equal(DeadReckon.BLIP_E8_MAX)
	var back: Vector3 = Codec.dequantize_pos(DeadReckon.blip_pos(Codec.pos_cell(q), b))
	assert_float(absf(back.length() - p.length())).is_less_equal(20.1)
	var f: Basis = Codec.cell_frame(Codec.pos_cell(q))
	var d: Vector3 = f.transposed() * (back - p)
	assert_float(maxf(absf(d.x), absf(d.y))).is_less_equal(5.1)
	# e8 never reads 0xFF (that byte marks a FULL record in section C).
	var edge: int = Codec.pack_pos(5, 0xFFFF, 0x8000, 0x4000)
	assert_int(DeadReckon.make_blip(edge, 0.0, 0) & 0xFF).is_equal(254)
	assert_int((DeadReckon.make_blip(edge, -900.0, 0) >> 16) & 0x3F).is_equal(0)
	assert_int((DeadReckon.make_blip(edge, 9000.0, 3) >> 16) & 0x3F).is_equal(63)


func test_pilot_block_roundtrip_and_clamps() -> void:
	var p: PilotBlock = PilotBlock.new()
	p.fuel_ds = 65535
	p.ammo = 70000
	p.bombs = 3
	p.rockets = 300
	p.hull = 1234
	p.incoming_rockets = 2
	p.boost_state = PilotBlock.boost_byte(PilotBlock.Boost.COOLDOWN, 0.5)
	p.flip_cooldown = 128
	p.dock_state = Protocol.DockState.DOCKED
	p.service_refuel = 255
	p.service_rearm = 10
	p.service_repair = 0
	var bytes: PackedByteArray = p.to_bytes()
	assert_int(bytes.size()).is_equal(PilotBlock.BYTES)
	var q: PilotBlock = PilotBlock.new()
	assert_bool(q.read(bytes, 0)).is_true()
	assert_array([q.fuel_ds, q.ammo, q.bombs, q.rockets, q.hull, q.incoming_rockets, q.boost_state & 3, q.boost_state >> 2,
		q.flip_cooldown, q.dock_state, q.service_refuel, q.service_rearm, q.service_repair]) \
		.is_equal([65535, 65535, 3, 255, 1234, 2, 2, 32, 128, 2, 255, 10, 0])
	assert_bool(q.read(bytes.slice(0, 14), 0)).is_false()
	assert_int(p.write(bytes, 1)).is_equal(-1)


func test_tier_b_flag_mapping_on_the_wire() -> void:
	# A-24: a tier-B ORI carries flags 0-4, 6, 7 in the coarse spare bits; braking reads false on the client.
	var codec: SnapshotCodec = SnapshotCodec.new(G, HZ)
	var store: BaselineStore = BaselineStore.new(0)
	var r: Roster = Roster.new()
	var _ok: bool = r.add(9, 1, 2, 1, 1)
	var dec: SnapshotDecoder = SnapshotDecoder.new(G, HZ, 0, r)
	var p: Vector3 = Sphere.from_lat_lon(0.3, 0.3, Sphere.PLANET_RADIUS + 400.0)
	var f: SnapshotFrame = SnapshotFrame.new()
	f.resize(1)
	var all_bits: int = Codec.make_flags(Protocol.ControlState.ORDERED, 0xFC)
	for t: int in [1, 2, 3]:
		f.tick = t
		f.set_entity(0, 9, p, Vector3.ZERO, Quaternion.IDENTITY, 1.0, 0 if t == 1 else all_bits, 1)
		codec.prepare_tick(f)
		var out: Array[PackedByteArray] = []
		var _n: int = codec.encode(store, t, PackedInt32Array(), PackedInt32Array([9]), PackedInt32Array(), null, out)
		assert_int(dec.decode(out[0])).is_equal(SnapshotDecoder.Status.OK)
		store.ack(t)
		if t == 2:
			assert_int(out[0][12]).is_equal(SnapshotCodec.MASK_ORI)              # B-DELTA, ORI only
			assert_int(Codec.coarse_spare(Codec.read_u24(out[0], 13))).is_equal(Codec.flags_to_spare(all_bits))
	assert_int(dec.current().flags[9]).is_equal(all_bits & ~Codec.FLAG_BRAKING)
	assert_bool(dec.current().same_state(store.frame_at(3))).is_true()


## NET-49 (A-40): the byte cache reproduces put_full / set_full / set_blip exactly, own team and other team.
func test_byte_cache_matches_uncached_records() -> void:
	var bc: SnapshotByteCache = SnapshotByteCache.new()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 40
	var w_plain: SnapshotWriter = SnapshotWriter.new()
	var w_cache: SnapshotWriter = SnapshotWriter.new()
	var fa: BaselineFrame = BaselineFrame.new()
	var fb: BaselineFrame = BaselineFrame.new()
	for n: int in 200:
		var s: int = n % 7
		var q: int = Codec.pack_pos(rng.randi_range(0, Codec.CELL_COUNT - 1), rng.randi_range(0, 0xFFFF),
				rng.randi_range(0, 0xFFFF), rng.randi_range(0, 0xFFFF))
		var ori: int = rng.randi() & 0xFFFFFFFF
		var vel: int = rng.randi() & 0xFFFFFF
		var hp: int = rng.randi_range(0, 255)
		var fl: int = rng.randi_range(0, 255)
		var ai: int = rng.randi_range(0, 255)
		var own: bool = n % 2 == 0
		bc.full(s, n + 1, q, ori, vel, hp | (fl << 8) | (ai << 16))
		var plain: Array[PackedByteArray] = []
		var cached: Array[PackedByteArray] = []
		w_plain.start(n + 1, 0, null, plain, 1)
		w_cache.start(n + 1, 0, null, cached, 1)
		var _p1: bool = w_plain.place(s, SnapshotCodec.Tier.C, SnapshotCodec.FULL_BODY_BYTES + 1)
		var _p2: bool = w_cache.place(s, SnapshotCodec.Tier.C, SnapshotCodec.FULL_BODY_BYTES + 1)
		w_plain.put_full(q, ori, vel, hp, fl, ai if own else -1)
		w_cache.put_full_words(bc.w0[s], bc.w1[s], bc.w2[s], own)
		var _f1: int = w_plain.finish()
		var _f2: int = w_cache.finish()
		assert_array(Array(cached[0])).is_equal(Array(plain[0]))
		fa.set_full(s, n, q, ori, vel, hp, fl, ai if own else -1)
		fb.set_full_cached(s, n, q, ori, bc.oc[s], DeadReckon.fine_from_bits(vel), hp, fl, ai if own else -1)
		var blip: int = rng.randi() & 0xFFFFFF
		fa.set_blip(s + 7, n, blip)
		fb.set_blip_at(s + 7, n, blip, bc.blip_pos(s + 7, n + 1, fb.pos[s + 7], blip))
		assert_bool(fa.same_state(fb)).is_true()
