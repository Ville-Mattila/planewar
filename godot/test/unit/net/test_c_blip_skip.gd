extends GdUnitTestSuite
## NET-54: the tier-C encoder skips the C-BLIP for an entry whose blip is unknown (after a FULL or a DELTA) when the
## blip of the entry's dead-reckoned position at the encode tick (DeadReckon.entry_blip: the position a client shows,
## 04 s3.4 dr(t)) equals the true blip. Server-only rule: no wire change, the decoder is untouched, and the mirror stays
## identical to the client. Every C tick below checks that an unknown-blip entry's dead-reckoned position lies within
## one blip bucket of the truth (static, moving, demoted from B, DYING under gravity).

const G: float = 6.0
const HZ: int = 30
const DT: float = 1.0 / HZ
const SLOT: int = 9
const BUCKET_M: float = 10.5                 # e8 / n8 bucket (256 E/N quanta) + rounding
const BAND_M: float = 40.5                   # alt6 band (DeadReckon.BLIP_ALT_STEP) + rounding
enum T { A, B, C }

var _worst_plane: float = 0.0
var _worst_alt: float = 0.0


func _setup() -> Array:
	var r: Roster = Roster.new()
	var _a: bool = r.add(SLOT, 1, 1, 1, 1)
	_worst_plane = 0.0
	_worst_alt = 0.0
	return [SnapshotCodec.new(G, HZ), BaselineStore.new(0), SnapshotDecoder.new(G, HZ, 0, r)]


## A lattice point at the centre of its e8/n8 bucket and of its 40 m altitude band.
func _centre_q() -> int:
	var q: int = Codec.quantize_pos(Sphere.from_lat_lon(0.12, 0.34, Sphere.PLANET_RADIUS + 300.0))
	var p: Vector3 = Codec.dequantize_pos(Codec.pack_pos(Codec.pos_cell(q), (Codec.pos_e(q) & ~0xFF) | 0x80,
			(Codec.pos_n(q) & ~0xFF) | 0x80, Codec.pos_u(q)))
	var band: float = floorf((p.length() - Sphere.PLANET_RADIUS - Sphere.RELIEF_MIN) / DeadReckon.BLIP_ALT_STEP)
	var want: float = Sphere.RELIEF_MIN + (band + 0.5) * DeadReckon.BLIP_ALT_STEP
	return Codec.quantize_pos(p.normalized() * (Sphere.PLANET_RADIUS + want))


## The truth an exact dead reckoning from (q0, vel bits) at tick 1 reaches at tick t.
func _dr_truth(q0: int, vel_bits: int, t: int, grav: bool) -> Vector3:
	var lv: Vector3i = DeadReckon.dr_levels(q0, DeadReckon.fine_from_bits(vel_bits), t - 1, grav, G, DT)
	return Codec.dequantize_pos(Codec.pack_pos(Codec.pos_cell(q0), lv.x, lv.y, lv.z))


## Encodes tick `t` with SLOT at `p` / `v` in tier `tier`, decodes and acks it; returns the FULL + BLIP record count.
## C ticks: an unknown-blip entry's dead-reckoned position must be within one blip bucket / band of the truth.
func _tick(ctx: Array, t: int, p: Vector3, v: Vector3, flag_b: int, under_fire: int, tier: int = T.C) -> int:
	var codec: SnapshotCodec = ctx[0]
	var store: BaselineStore = ctx[1]
	var dec: SnapshotDecoder = ctx[2]
	var f: SnapshotFrame = SnapshotFrame.new()
	f.resize(1)
	f.tick = t
	f.set_entity(0, SLOT, p, v, Quaternion.IDENTITY, 1.0, flag_b, 1)
	f.under_fire[0] = under_fire
	codec.prepare_tick(f)
	var before: int = codec.n_full + codec.n_blip
	var out: Array[PackedByteArray] = []
	var one: PackedInt32Array = PackedInt32Array([SLOT])
	var none: PackedInt32Array = PackedInt32Array()
	var _n: int = codec.encode(store, t, one if tier == T.A else none, one if tier == T.B else none,
			one if tier == T.C else none, null, out)
	for pk: PackedByteArray in out:
		assert_int(dec.decode(pk)).is_equal(SnapshotDecoder.Status.OK)
	store.ack(dec.store.complete_tick)
	var e: BaselineFrame = store.frame_at(t)
	assert_bool(dec.current().same_state(e)).is_true()
	if tier == T.C and e.blip[SLOT] == DeadReckon.BLIP_UNKNOWN:
		var grav: bool = (e.flags[SLOT] & Codec.FLAG_DYING) != 0
		var lv: Vector3i = DeadReckon.dr_levels(e.pos[SLOT], e.vel[SLOT], t - e.etick[SLOT], grav, G, DT)
		var shown: Vector3 = Codec.dequantize_pos(Codec.pack_pos(Codec.pos_cell(e.pos[SLOT]), lv.x, lv.y, lv.z))
		var d: Vector3 = Codec.cell_frame(Codec.pos_cell(e.pos[SLOT])).transposed() * (shown - p)
		_worst_plane = maxf(_worst_plane, maxf(absf(d.x), absf(d.y)))
		_worst_alt = maxf(_worst_alt, absf(shown.length() - p.length()))
	return codec.n_full + codec.n_blip - before


func test_entry_blip_is_make_blip_of_the_dead_reckoned_entry() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 54
	for k: int in 2000:
		var p: Vector3 = Sphere.from_lat_lon(rng.randf_range(-1.4, 1.4), rng.randf_range(-3.1, 3.1),
				Sphere.PLANET_RADIUS + rng.randf_range(-400.0, 2000.0))
		var q: int = Codec.quantize_pos(p)
		var alt: float = Codec.dequantize_pos(q).length() - Sphere.PLANET_RADIUS
		var fine: int = 0 if k % 3 == 0 else DeadReckon.fine_from_bits(rng.randi() & 0xFFFFFF | 1)
		var fl: int = [0, Codec.FLAG_DOCKED, Codec.FLAG_DYING, Codec.FLAG_FIRING][k % 4]
		var st: int = DeadReckon.BlipState.MOVING
		if fl & Codec.FLAG_DYING:
			st = DeadReckon.BlipState.DYING
		elif fine == 0 or (fl & Codec.FLAG_DOCKED) != 0:
			st = DeadReckon.BlipState.STATIC
		var b: int = DeadReckon.entry_blip(q, fl, fine, 0, false, G, DT)
		var mb: int = DeadReckon.make_blip(q, alt, st)
		assert_int(DeadReckon.blip_state(b)).is_equal(st)
		assert_int(b & 0xFFFF).is_equal(mb & 0xFFFF)
		# float64 altitude of the lattice point vs the float32 dequantised one: same 40 m band or a neighbour.
		assert_int(absi(((b >> 16) & 0x3F) - ((mb >> 16) & 0x3F))).is_less_equal(1)
		# dticks > 0: the blip of the dead-reckoned levels (gravity term with DYING), or unknown off the cell.
		var dtk: int = 1 + k % 40
		var grav: bool = (fl & Codec.FLAG_DYING) != 0
		var lv: Vector3i = DeadReckon.dr_levels(q, fine, dtk, grav, G, DT)
		var want: int = DeadReckon.BLIP_UNKNOWN
		if DeadReckon.levels_ok(lv):
			want = DeadReckon.entry_blip(Codec.pack_pos(Codec.pos_cell(q), lv.x, lv.y, lv.z), fl, fine, 0, false, G, DT)
		assert_int(DeadReckon.entry_blip(q, fl, fine, dtk, grav, G, DT)).is_equal(want)
	var edge: int = Codec.pack_pos(5, 0xFFFF, 0x8000, 0x4000)
	var out: int = DeadReckon.entry_blip(edge, 0, DeadReckon.pack_fine(1 << 16, 0, 0), 30, false, G, DT)
	assert_int(out).is_equal(DeadReckon.BLIP_UNKNOWN)


func test_static_c_entity_full_then_no_blip() -> void:
	var ctx: Array = _setup()
	var p: Vector3 = Codec.dequantize_pos(_centre_q())
	assert_int(_tick(ctx, 1, p, Vector3.ZERO, 0, 0)).is_equal(1)              # FULL (no baseline)
	for t: int in range(2, 40):
		assert_int(_tick(ctx, t, p, Vector3.ZERO, 0, 0)).is_equal(0)          # the mirror implies the blip
	var codec: SnapshotCodec = ctx[0]
	assert_int(codec.n_blip).is_equal(0)
	var store: BaselineStore = ctx[1]
	assert_int(store.frame_at(39).blip[SLOT]).is_equal(DeadReckon.BLIP_UNKNOWN)


func test_motion_inside_the_bucket_sends_nothing_leaving_it_sends_one_blip() -> void:
	var ctx: Array = _setup()
	var p: Vector3 = Codec.dequantize_pos(_centre_q())
	var east: Vector3 = Codec.cell_frame(Codec.pos_cell(_centre_q())).x
	assert_int(_tick(ctx, 1, p, Vector3.ZERO, 0, 0)).is_equal(1)
	assert_int(_tick(ctx, 2, p + east * 1.5, Vector3.ZERO, 0, 0)).is_equal(0)
	assert_int(_tick(ctx, 3, p + east * 25.0, Vector3.ZERO, 0, 0)).is_equal(1)   # e8 changed: C-BLIP
	var store: BaselineStore = ctx[1]
	assert_int(store.frame_at(3).blip[SLOT]).is_not_equal(DeadReckon.BLIP_UNKNOWN)
	assert_int(_tick(ctx, 4, p + east * 25.0, Vector3.ZERO, 0, 0)).is_equal(0)   # known blip unchanged


## A moving C FULL whose motion dead-reckons exactly needs no C-BLIP, across bucket changes.
func test_moving_c_full_exact_dead_reckoning_sends_nothing_more() -> void:
	var ctx: Array = _setup()
	var q0: int = _centre_q()
	var v: Vector3 = Codec.cell_frame(Codec.pos_cell(q0)) * Vector3(10.0, -4.0, 0.0)
	var vb: int = Codec.quantize_vel(v, Codec.pos_cell(q0))
	assert_int(_tick(ctx, 1, _dr_truth(q0, vb, 1, false), v, 0, 0)).is_equal(1)
	var sent: int = 0
	for t: int in range(2, 61):
		sent += _tick(ctx, t, _dr_truth(q0, vb, t, false), v, 0, 0)
	assert_int(sent).is_less_equal(1)                       # at most one 40 m band rounding flip over 20 m of travel
	assert_float(_worst_plane).is_less_equal(0.1)


## A moving C FULL, then the truth hovers in the stored bucket while still reporting velocity: the client would
## dead-reckon away, so the encoder must send a C-BLIP before the shown position leaves the bucket.
func test_moving_c_full_then_hover_sends_a_blip_before_the_client_drifts_out() -> void:
	var ctx: Array = _setup()
	var p: Vector3 = Codec.dequantize_pos(_centre_q())
	var v: Vector3 = Codec.cell_frame(Codec.pos_cell(_centre_q())) * Vector3(10.0, 0.0, 0.0)
	assert_int(_tick(ctx, 1, p, v, 0, 0)).is_equal(1)
	for t: int in range(2, 91):
		var _r: int = _tick(ctx, t, p, v, 0, 0)
	var codec: SnapshotCodec = ctx[0]
	assert_int(codec.n_blip).is_greater_equal(1)
	assert_float(_worst_plane).is_less_equal(BUCKET_M)


## B DELTAs of a moving entity, then demoted to C (no section-C record yet, blip unknown, vel != 0) while it hovers.
func test_demoted_from_b_with_velocity_is_corrected() -> void:
	var ctx: Array = _setup()
	var q0: int = _centre_q()
	var v: Vector3 = Codec.cell_frame(Codec.pos_cell(q0)) * Vector3(0.0, 8.0, 0.0)
	var vb: int = Codec.quantize_vel(v, Codec.pos_cell(q0))
	for t: int in range(1, 11):
		var _r: int = _tick(ctx, t, _dr_truth(q0, vb, t, false), v, 0, 0, T.B)
	var store: BaselineStore = ctx[1]
	assert_int(DeadReckon.fine_axis(store.frame_at(10).vel[SLOT], 1)).is_not_equal(0)
	var hover: Vector3 = _dr_truth(q0, vb, 10, false)
	var blips: int = 0
	for t: int in range(11, 101):
		blips += _tick(ctx, t, hover, v, 0, 0)
	assert_int(blips).is_greater_equal(1)
	assert_float(_worst_plane).is_less_equal(BUCKET_M)


## DYING under gravity: an exact faller needs no C-BLIP; a DYING entity that hovers gets one before the client's
## falling dead reckoning leaves the 40 m band.
func test_dying_under_gravity_faller_and_hover() -> void:
	var ctx: Array = _setup()
	var q0: int = _centre_q()
	assert_int(_tick(ctx, 1, Codec.dequantize_pos(q0), Vector3.ZERO, Codec.FLAG_DYING, 0)).is_equal(1)
	var sent: int = 0
	for t: int in range(2, 61):
		sent += _tick(ctx, t, _dr_truth(q0, 0, t, true), Vector3.ZERO, Codec.FLAG_DYING, 0)
	assert_int(sent).is_less_equal(1)                       # 10.8 m of fall: at most one band flip
	assert_float(_worst_alt).is_less_equal(0.3)
	ctx = _setup()
	var p: Vector3 = Codec.dequantize_pos(q0)
	assert_int(_tick(ctx, 1, p, Vector3.ZERO, Codec.FLAG_DYING, 0)).is_equal(1)
	var blips: int = 0
	for t: int in range(2, 241):
		blips += _tick(ctx, t, p, Vector3.ZERO, Codec.FLAG_DYING, 0)
	assert_int(blips).is_greater_equal(1)
	assert_float(_worst_alt).is_less_equal(BAND_M)


func test_under_fire_or_new_dying_flag_after_full_sends_a_blip() -> void:
	var p: Vector3 = Codec.dequantize_pos(_centre_q())
	var cases: Array[Vector3i] = [Vector3i(0, 1, DeadReckon.BlipState.UNDER_FIRE),
			Vector3i(Codec.FLAG_DYING, 0, DeadReckon.BlipState.DYING)]
	for c: Vector3i in cases:
		var ctx: Array = _setup()
		assert_int(_tick(ctx, 1, p, Vector3.ZERO, 0, 0)).is_equal(1)
		# under_fire is server-only and the FULL's flags were not DYING: the implied state differs, so a C-BLIP.
		assert_int(_tick(ctx, 2, p, Vector3.ZERO, c.x, c.y)).is_equal(1)
		var store: BaselineStore = ctx[1]
		assert_int(DeadReckon.blip_state(store.frame_at(2).blip[SLOT])).is_equal(c.z)


func test_shown_blip_known_stored_unknown_dead_reckoned() -> void:
	var f: BaselineFrame = BaselineFrame.new()
	var q: int = _centre_q()
	var fine: int = DeadReckon.pack_fine(10 * DeadReckon.FINE_PER_MPS, 0, 0)
	f.set_full_cached(SLOT, 5, q, 0, 0, fine, 255, Codec.FLAG_DYING, -1)
	assert_int(f.shown_blip(SLOT, 35, false, G, DT)).is_equal(DeadReckon.entry_blip(q, Codec.FLAG_DYING, fine, 30, true, G, DT))
	f.flags[SLOT] = 0
	assert_int(f.shown_blip(SLOT, 35, true, G, DT)).is_equal(DeadReckon.entry_blip(q, 0, fine, 30, true, G, DT))
	assert_int(f.shown_blip(SLOT, 35, false, G, DT)).is_equal(DeadReckon.entry_blip(q, 0, fine, 30, false, G, DT))
	assert_int(f.shown_blip(SLOT, 35, false, G, DT)).is_not_equal(DeadReckon.entry_blip(q, 0, fine, 0, false, G, DT))
	f.set_blip(SLOT, 40, 0x123456)
	assert_int(f.shown_blip(SLOT, 70, true, G, DT)).is_equal(0x123456)
