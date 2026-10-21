extends GdUnitTestSuite
## NET-54: the tier-C encoder skips the C-BLIP after a FULL (or any record that leaves the entry's blip unknown) when
## the blip the server mirror implies (DeadReckon.entry_blip of the entry's position, flags and velocity) equals the
## true blip. Server-only rule: no wire change, the decoder is untouched, and the mirror stays identical to the client.

const G: float = 6.0
const HZ: int = 30
const SLOT: int = 9


func _setup() -> Array:
	var r: Roster = Roster.new()
	var _a: bool = r.add(SLOT, 1, 1, 1, 1)
	return [SnapshotCodec.new(G, HZ), BaselineStore.new(0), SnapshotDecoder.new(G, HZ, 0, r)]


## A C entity at the centre of its e8/n8 bucket and 40 m altitude band, so a few metres of motion keep the blip.
func _centre_pos() -> Vector3:
	var q: int = Codec.quantize_pos(Sphere.from_lat_lon(0.12, 0.34, Sphere.PLANET_RADIUS + 300.0))
	var lv: int = Codec.pack_pos(Codec.pos_cell(q), (Codec.pos_e(q) & ~0xFF) | 0x80, (Codec.pos_n(q) & ~0xFF) | 0x80, Codec.pos_u(q))
	var p: Vector3 = Codec.dequantize_pos(lv)
	var alt: float = p.length() - Sphere.PLANET_RADIUS
	var band: float = floorf((alt - Sphere.RELIEF_MIN) / DeadReckon.BLIP_ALT_STEP)
	var want: float = Sphere.RELIEF_MIN + (band + 0.5) * DeadReckon.BLIP_ALT_STEP
	return p.normalized() * (Sphere.PLANET_RADIUS + want)


## Encodes tick `t` with SLOT in the C list, decodes and acks it; returns the section-C record count.
func _tick(ctx: Array, t: int, p: Vector3, flag_b: int, under_fire: int) -> int:
	var codec: SnapshotCodec = ctx[0]
	var store: BaselineStore = ctx[1]
	var dec: SnapshotDecoder = ctx[2]
	var f: SnapshotFrame = SnapshotFrame.new()
	f.resize(1)
	f.tick = t
	f.set_entity(0, SLOT, p, Vector3.ZERO, Quaternion.IDENTITY, 1.0, flag_b, 1)
	f.under_fire[0] = under_fire
	codec.prepare_tick(f)
	var before: int = codec.n_full + codec.n_blip
	var out: Array[PackedByteArray] = []
	var _n: int = codec.encode(store, t, PackedInt32Array(), PackedInt32Array(), PackedInt32Array([SLOT]), null, out)
	for pk: PackedByteArray in out:
		assert_int(dec.decode(pk)).is_equal(SnapshotDecoder.Status.OK)
	store.ack(dec.store.complete_tick)
	assert_bool(dec.current().same_state(store.frame_at(t))).is_true()
	return codec.n_full + codec.n_blip - before


func test_entry_blip_is_make_blip_of_the_entry() -> void:
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
		var b: int = DeadReckon.entry_blip(q, fl, fine)
		assert_int(DeadReckon.blip_state(b)).is_equal(st)
		assert_int(b & 0xFFFF).is_equal(DeadReckon.make_blip(q, alt, st) & 0xFFFF)
		# float64 altitude of the lattice point vs the float32 dequantised one: same 40 m band or a neighbour.
		assert_int(absi(((b >> 16) & 0x3F) - ((DeadReckon.make_blip(q, alt, st) >> 16) & 0x3F))).is_less_equal(1)


func test_static_c_entity_full_then_no_blip() -> void:
	var ctx: Array = _setup()
	var p: Vector3 = _centre_pos()
	assert_int(_tick(ctx, 1, p, 0, 0)).is_equal(1)              # FULL (no baseline)
	for t: int in range(2, 40):
		assert_int(_tick(ctx, t, p, 0, 0)).is_equal(0)          # the mirror implies the blip: nothing sent
	var codec: SnapshotCodec = ctx[0]
	assert_int(codec.n_blip).is_equal(0)
	var store: BaselineStore = ctx[1]
	assert_int(store.frame_at(39).blip[SLOT]).is_equal(DeadReckon.BLIP_UNKNOWN)


func test_motion_inside_the_bucket_sends_nothing_leaving_it_sends_one_blip() -> void:
	var ctx: Array = _setup()
	var p: Vector3 = _centre_pos()
	var east: Vector3 = Codec.cell_frame(Codec.pos_cell(Codec.quantize_pos(p))).x
	assert_int(_tick(ctx, 1, p, 0, 0)).is_equal(1)
	assert_int(_tick(ctx, 2, p + east * 1.5, 0, 0)).is_equal(0)
	assert_int(_tick(ctx, 3, p + east * 25.0, 0, 0)).is_equal(1)   # e8 changed: C-BLIP
	var store: BaselineStore = ctx[1]
	assert_int(store.frame_at(3).blip[SLOT]).is_not_equal(DeadReckon.BLIP_UNKNOWN)
	assert_int(_tick(ctx, 4, p + east * 25.0, 0, 0)).is_equal(0)   # known blip unchanged


func test_under_fire_or_new_dying_flag_after_full_sends_a_blip() -> void:
	var p: Vector3 = _centre_pos()
	var cases: Array[Vector3i] = [Vector3i(0, 1, DeadReckon.BlipState.UNDER_FIRE),
			Vector3i(Codec.FLAG_DYING, 0, DeadReckon.BlipState.DYING)]
	for c: Vector3i in cases:
		var ctx: Array = _setup()
		assert_int(_tick(ctx, 1, p, 0, 0)).is_equal(1)
		# under_fire is server-only and the FULL's flags were not DYING: the implied state differs, so a C-BLIP.
		assert_int(_tick(ctx, 2, p, c.x, c.y)).is_equal(1)
		var store: BaselineStore = ctx[1]
		assert_int(DeadReckon.blip_state(store.frame_at(2).blip[SLOT])).is_equal(c.z)


func test_dying_full_implies_dying_blip() -> void:
	var ctx: Array = _setup()
	var p: Vector3 = _centre_pos()
	assert_int(_tick(ctx, 1, p, Codec.FLAG_DYING, 0)).is_equal(1)
	assert_int(_tick(ctx, 2, p, Codec.FLAG_DYING, 0)).is_equal(0)
	assert_int(_tick(ctx, 3, p, Codec.FLAG_DYING, 1)).is_equal(0)   # DYING outranks UNDER_FIRE
