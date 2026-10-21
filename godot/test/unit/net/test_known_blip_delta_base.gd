extends GdUnitTestSuite
## NET-57 (R0 B.19 A-103, 04 s3.4 baseline policy (4)): a mirror entry whose last record was a C-BLIP (a known blip)
## is never dead-reckoned on the wire. Its DELTA base is the stored bucket levels (BaselineFrame.shown_levels) with no
## velocity advance and no gravity term, DYING or not, on the encoder and the decoder alike; A/B and unknown-blip
## entries dead-reckon as before. Every tick asserts mirror == client (same_state).

const G: float = 6.0
const HZ: int = 30
const DT: float = 1.0 / HZ
const SLOT: int = 9
const REST_TICKS: int = 300
enum T { A, B, C }


func _setup() -> Array:
	var r: Roster = Roster.new()
	var _a: bool = r.add(SLOT, 1, 1, 1, 1)
	return [SnapshotCodec.new(G, HZ), BaselineStore.new(0), SnapshotDecoder.new(G, HZ, 0, r)]


func _p0() -> Vector3:
	return Sphere.from_lat_lon(0.12, 0.34, Sphere.PLANET_RADIUS + 300.0)


func _levels(q: int) -> Vector3i:
	return Vector3i(Codec.pos_e(q), Codec.pos_n(q), Codec.pos_u(q))


## Encodes tick `t` with SLOT at `p` (velocity `v`) in tier `tier`, decodes and acks it, asserts mirror == client.
func _tick(ctx: Array, t: int, p: Vector3, v: Vector3, flag_b: int, tier: int) -> void:
	var codec: SnapshotCodec = ctx[0]
	var store: BaselineStore = ctx[1]
	var dec: SnapshotDecoder = ctx[2]
	var f: SnapshotFrame = SnapshotFrame.new()
	f.resize(1)
	f.tick = t
	f.set_entity(0, SLOT, p, v, Quaternion.IDENTITY, 1.0, flag_b, 1)
	codec.prepare_tick(f)
	var out: Array[PackedByteArray] = []
	var one: PackedInt32Array = PackedInt32Array([SLOT])
	var none: PackedInt32Array = PackedInt32Array()
	var _n: int = codec.encode(store, t, one if tier == T.A else none, one if tier == T.B else none,
			one if tier == T.C else none, null, out)
	for pk: PackedByteArray in out:
		assert_int(dec.decode(pk)).is_equal(SnapshotDecoder.Status.OK)
	store.ack(dec.store.complete_tick)
	assert_bool(dec.current().same_state(store.frame_at(t))).is_true()


## A DYING entity hovering in tier C: FULL at tick 1, then C ticks until the stored blip is known. Returns that tick.
func _until_known_blip(ctx: Array, p: Vector3) -> int:
	var store: BaselineStore = ctx[1]
	_tick(ctx, 1, p, Vector3.ZERO, Codec.FLAG_DYING, T.C)
	for t: int in range(2, 400):
		_tick(ctx, t, p, Vector3.ZERO, Codec.FLAG_DYING, T.C)
		if store.frame_at(t).blip[SLOT] != DeadReckon.BLIP_UNKNOWN:
			return t
	return -1


func test_dying_known_blip_rests_300_ticks_then_promoted_encodes_bucket_residual() -> void:
	for tier: int in [T.A, T.B]:
		var ctx: Array = _setup()
		var codec: SnapshotCodec = ctx[0]
		var store: BaselineStore = ctx[1]
		var dec: SnapshotDecoder = ctx[2]
		var p: Vector3 = _p0()
		var tb: int = _until_known_blip(ctx, p)
		assert_int(tb).is_greater(1)
		var bucket: Vector3i = _levels(store.frame_at(tb).pos[SLOT])
		var recs: int = codec.n_full + codec.n_delta + codec.n_blip
		for t: int in range(tb + 1, tb + 1 + REST_TICKS):
			_tick(ctx, t, p, Vector3.ZERO, Codec.FLAG_DYING, T.C)
		assert_int(codec.n_full + codec.n_delta + codec.n_blip).is_equal(recs)     # rests: nothing sent
		var e: BaselineFrame = store.frame_at(tb + REST_TICKS)
		assert_int(e.blip[SLOT]).is_not_equal(DeadReckon.BLIP_UNKNOWN)
		assert_that(_levels(e.pos[SLOT])).is_equal(bucket)
		assert_int(e.vel[SLOT]).is_equal(0)
		# Promotion: one DELTA against the stored bucket, residual = truth - bucket, never POS_LARGE or FULL.
		var tp: int = tb + 1 + REST_TICKS
		var full0: int = codec.n_full
		var delta0: int = codec.n_delta
		var large0: int = codec.n_pos_large
		_tick(ctx, tp, p, Vector3.ZERO, Codec.FLAG_DYING, tier)
		assert_int(codec.n_full).is_equal(full0)
		assert_int(codec.n_delta).is_equal(delta0 + 1)
		assert_int(codec.n_pos_large).is_equal(large0)
		var truth: Vector3i = _levels(codec.c_pos[SLOT])
		var res: Vector3i = truth - bucket
		var mask: int = SnapshotCodec.pos_mask(res)
		assert_int(mask).is_not_equal(SnapshotCodec.MASK_POS_LARGE)
		assert_int(mask).is_not_equal(-1)
		var got: BaselineFrame = dec.current()
		assert_that(_levels(got.pos[SLOT])).is_equal(bucket + SnapshotCodec.applied_residual(mask, res))
		assert_int(got.vel[SLOT]).is_equal(0)                                       # no velocity advance
		assert_int(got.blip[SLOT]).is_equal(DeadReckon.BLIP_UNKNOWN)
		# After the DELTA the entry is A/B again: the DYING gravity branch resumes on both ends.
		for t: int in range(tp + 1, tp + 31):
			_tick(ctx, t, p, Vector3.ZERO, Codec.FLAG_DYING, tier)


func test_known_blip_delta_base_is_shown_levels_on_both_ends() -> void:
	var ctx: Array = _setup()
	var store: BaselineStore = ctx[1]
	var dec: SnapshotDecoder = ctx[2]
	var p: Vector3 = _p0()
	var tb: int = _until_known_blip(ctx, p)
	var base: BaselineFrame = store.frame_at(tb)
	for dtk: int in [1, 30, 300]:
		var stored: Vector3i = _levels(base.pos[SLOT])
		assert_that(base.shown_levels(SLOT, tb + dtk, true, G, DT)).is_equal(stored)
		assert_bool(base.base_grav(SLOT, true)).is_false()
		assert_bool(dec.current().base_grav(SLOT, false)).is_false()
	# Unknown blip with DYING: gravity, as before; def gravity alone too.
	var f: BaselineFrame = BaselineFrame.new()
	f.set_full_cached(SLOT, 1, base.pos[SLOT], 0, 0, 0, 255, Codec.FLAG_DYING, -1)
	assert_bool(f.base_grav(SLOT, false)).is_true()
	f.flags[SLOT] = 0
	assert_bool(f.base_grav(SLOT, true)).is_true()
	assert_bool(f.base_grav(SLOT, false)).is_false()


func test_falling_dying_known_blip_gets_a_new_blip_when_the_bucket_changes() -> void:
	var ctx: Array = _setup()
	var codec: SnapshotCodec = ctx[0]
	var store: BaselineStore = ctx[1]
	var p: Vector3 = _p0()
	var tb: int = _until_known_blip(ctx, p)
	var b0: int = store.frame_at(tb).blip[SLOT]
	var blips0: int = codec.n_blip
	for k: int in 60:
		var fall: float = 0.5 * G * pow(float(k + 1) * DT, 2.0)
		_tick(ctx, tb + 1 + k, p.normalized() * (p.length() - fall), Vector3.ZERO, Codec.FLAG_DYING, T.C)
	var lower: Vector3 = p.normalized() * (p.length() - 120.0)
	_tick(ctx, tb + 61, lower, Vector3.ZERO, Codec.FLAG_DYING, T.C)
	assert_int(codec.n_blip).is_greater(blips0)
	var b1: int = store.frame_at(tb + 61).blip[SLOT]
	assert_int(b1).is_not_equal(b0)
	assert_int(DeadReckon.blip_state(b1)).is_equal(DeadReckon.BlipState.DYING)
	assert_int((b1 >> 16) & 0x3F).is_less((b0 >> 16) & 0x3F)
