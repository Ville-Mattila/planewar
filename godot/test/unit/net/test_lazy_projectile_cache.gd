extends GdUnitTestSuite
## NET-60: a projectile row's c_ori / c_fine are quantised on first use (SnapshotCodec.ensure_full); the values equal the
## eager quantisation of the same row, so no wire byte changes (NON_WRECK_SHA and the bench hash pin that end to end).


func test_ensure_full_matches_eager_quantisation() -> void:
	var rig: ProjectileRig = ProjectileRig.new()
	rig.build(2, Vector3i(40, 200, 700), Vector3i(24, 70, 300), 6, 5)
	for _t: int in 90:
		rig.snap.frame.count = rig.n_entities
		rig.snap.tick += 1
		rig.snap.frame.tick = rig.snap.tick
		rig.snap.step_motion()
		rig.step_projectiles()
	var codec: SnapshotCodec = rig.snap.codec
	var frame: SnapshotFrame = rig.snap.frame
	codec.prepare_tick(frame)
	var checked: int = 0
	for i: int in frame.count:
		var s: int = frame.index_of_row(i)
		if s < Roster.PROJECTILE_INDEX_MIN:
			continue
		var r4: Vector4 = frame.rot[i]
		var want_ori: int = Codec.quantize_quat(Quaternion(r4.x, r4.y, r4.z, r4.w))
		codec.ensure_full(s)
		codec.ensure_full(s)                                   # idempotent
		assert_int(codec.c_ori[s]).is_equal(want_ori)
		assert_int(codec.c_fine[s]).is_equal(DeadReckon.fine_from_bits(codec.c_vel[s]))
		checked += 1
	assert_int(checked).is_greater(10)
