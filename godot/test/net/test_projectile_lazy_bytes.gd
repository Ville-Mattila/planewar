extends GdUnitTestSuite
## NET-60 round 2: pins the lazy projectile c_ori / c_fine path (SnapshotCodec.ensure_full) end to end. (1) A KEYFRAME
## encoded before any SNAPSHOT of its tick carries each projectile's quantised orientation. (2) The SHA-256 of every
## ENTITY_META / ROSTER_REMOVE / SNAPSHOT packet for 3 clients plus KEYFRAMEs (encoded first in their tick) over a scene
## with live projectiles equals the value measured on main before NET-60 (the wreck test's NON_WRECK_SHA covers no projectile).

const PROJECTILE_SHA: String = "4270a8e0e8a36b03e4894adbdd06b1ee52bfbb29aa3ae42b3f19201e0b71183e"
const TICKS: int = 120


func _rig() -> ProjectileRig:
	var rig: ProjectileRig = ProjectileRig.new()
	rig.build(3, Vector3i(40, 200, 700), Vector3i(24, 70, 300), 6, 17)
	return rig


func test_keyframe_before_any_snapshot_carries_projectile_orientation() -> void:
	var rig: ProjectileRig = _rig()
	for _t: int in 90:
		rig.step_scene()
	var live: PackedInt32Array = rig.live_replicated()
	assert_int(live.size()).is_greater(10)
	var kc: KeyframeCodec = KeyframeCodec.new()
	var msg: PackedByteArray = kc.encode(rig.snap.codec, BaselineStore.new(0), rig.snap.tick, 1, Protocol.KeyframeScope.ALL, live)
	var dec: SnapshotDecoder = rig.new_projectile_decoder(0, rig.snap.roster)
	assert_int(kc.decode(msg, dec)).is_equal(KeyframeCodec.Status.OK)
	var frame: SnapshotFrame = rig.snap.frame
	var nonzero: int = 0
	for i: int in frame.count:
		var s: int = frame.index_of_row(i)
		if s < Roster.PROJECTILE_INDEX_MIN or not live.has(s):
			continue
		var r4: Vector4 = frame.rot[i]
		var want: int = Codec.quantize_quat(Quaternion(r4.x, r4.y, r4.z, r4.w))
		assert_int(dec.current().ori[s]).is_equal(want)
		nonzero += 1 if want != 0 else 0
	assert_int(nonzero).is_greater(0)


func _bytes() -> String:
	var rig: ProjectileRig = _rig()
	var kc: KeyframeCodec = KeyframeCodec.new()
	var kstore: BaselineStore = BaselineStore.new(0)
	var ctx: HashingContext = HashingContext.new()
	var _st: int = ctx.start(HashingContext.HASH_SHA256)
	var seq: int = 0
	for t: int in TICKS:
		rig.step_scene()
		rig.run_interest()
		if t % 20 == 19:                                         # first reader of this tick's projectile orientation
			var idx: PackedInt32Array = rig.clients[0].a.duplicate()
			idx.append_array(rig.clients[0].b)
			idx.append_array(rig.clients[0].c)
			seq += 1
			var _k: int = ctx.update(kc.encode(rig.snap.codec, kstore, rig.snap.tick, seq, Protocol.KeyframeScope.ALL, idx))
		for k: int in 3:
			var out: Array[PackedByteArray] = []
			rig.roster_packets(k, out)
			var _n: int = rig.encode(k, out)
			for pkt: PackedByteArray in out:
				var _u: int = ctx.update(pkt)
			rig.stores[k].ack(rig.snap.tick - 2)
	return ctx.finish().hex_encode()


func test_projectile_scene_bytes_unchanged() -> void:
	var sha: String = _bytes()
	print("PROJECTILE_SHA=", sha)
	assert_str(sha).is_equal(PROJECTILE_SHA)
