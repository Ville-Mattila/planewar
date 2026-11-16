extends GdUnitTestSuite
## NET-51 (R0 B.12 A-77): FrameType.PROJECTILES = 6 holds a tick's unfiltered PROJECTILE_BATCH packets (one copy, no
## next-tick re-send). A 2-minute recording with gunfire replays every item at its tick; a file without frame 6 opens
## OK; the writer stays correct with NET-60's lazy projectile orientation (replay bytes pinned over a scene with live
## projectiles where the writer is the first reader of every tick's c_ori / c_fine).

const TICKS: int = 3600
## SHA-256 of the inflated stream over the ProjectileRig scene (_projectile_raw). WITHOUT_SHOTS was measured on main
## before NET-51 (a null ShotBuffer must change no byte); WITH_SHOTS adds the PROJECTILES frames.
const SHA_WITHOUT_SHOTS: String = "73d658684c2c272d06cfaf2172ba75ff9a58bf2451d964ab3d95d0e8280ba380"
const SHA_WITH_SHOTS: String = "PIN"


func _shots_for(tick: int) -> ShotBuffer:
	var sb: ShotBuffer = ShotBuffer.new()
	sb.clear(tick)
	if tick % 7 == 0:
		sb.add_q(EntityId.make(3, 1), 0, tick & 0xFF, (tick % 40) - 20, (tick % 11) - 5)
		sb.add_q(EntityId.make(4, 1), 1, (tick + 1) & 0xFF, -7, 3, 45)            # flak: fuse byte
	if tick == 1001:
		for i: int in 200:                                                        # > COUNT_MAX: two packets
			sb.add_q(EntityId.make(5 + (i % 4), 1), i % 3, i & 0xFF, (i % 100) - 50, 0)
	return sb


func _gunfire_rig(ticks: int) -> ReplayRig:
	var rig: ReplayRig = ReplayRig.new()
	rig.build(Vector3i(10, 30, 80), Vector3i(8, 15, 20), 3, 5)
	for t: int in range(1, ticks + 1):
		var sb: ShotBuffer = _shots_for(t)
		if sb.count > 0:
			rig.add_shots(t, sb)
	rig.run(ticks, 30)
	return rig


func _fire_ticks(ticks: int) -> int:
	var n: int = 0
	for t: int in range(1, ticks + 1):
		n += 1 if _shots_for(t).count > 0 else 0
	return n


func test_two_minute_gunfire_replays_every_item_at_its_tick() -> void:
	var rig: ReplayRig = _gunfire_rig(TICKS)
	var r: ReplayReader = rig.new_reader()
	assert_int(r.open_bytes(rig.file)).is_equal(ReplayFormat.Status.OK)
	assert_int(ReplayFormat.FrameType.PROJECTILES).is_equal(6)
	var frames: int = 0
	var items: int = 0
	var want_items: int = 0
	for t: int in range(1, TICKS + 1):
		want_items += _shots_for(t).count
	var guard: int = 0
	while not r.at_end() and guard < 20000:
		guard += 1
		var type: int = r.next_frame()
		if type == ReplayReader.NO_FRAME:
			break
		if type != ReplayFormat.FrameType.PROJECTILES:
			assert_int(r.shots.count).is_equal(0)
			continue
		frames += 1
		var want: ShotBuffer = _shots_for(r.tick)
		assert_int(want.count).is_greater(0)
		assert_int(r.shots.count).is_equal(want.count)
		assert_int(r.shots.tick).is_equal(r.tick)
		for i: int in want.count:
			assert_int(r.shots.shooter[i]).is_equal(EntityId.slot(want.shooter[i]))   # unfiltered: roster index
			assert_int(r.shots.weapon_slot[i]).is_equal(want.weapon_slot[i])
			assert_int(r.shots.seed_byte[i]).is_equal(want.seed_byte[i])
			assert_int(r.shots.yaw_q[i]).is_equal(want.yaw_q[i])
			assert_int(r.shots.pitch_q[i]).is_equal(want.pitch_q[i])
			assert_int(r.shots.fuse[i]).is_equal(want.fuse[i])
		items += r.shots.count
	assert_int(r.status).is_equal(ReplayFormat.Status.OK)
	assert_int(items).is_equal(want_items)
	assert_int(frames).is_equal(_fire_ticks(TICKS))                                  # once per firing tick: no re-send


func test_file_without_projectile_frames_opens_ok() -> void:
	var rig: ReplayRig = ReplayRig.new()
	rig.build(Vector3i(3, 6, 11), Vector3i(2, 3, 4), 2, 99)
	rig.run(150)
	var r: ReplayReader = rig.new_reader()
	assert_int(r.open_bytes(rig.file)).is_equal(ReplayFormat.Status.OK)
	var seen: int = 0
	while r.next_frame() != ReplayReader.NO_FRAME:
		seen += 1 if r.frame_type == ReplayFormat.FrameType.PROJECTILES else 0
	assert_int(seen).is_equal(0)
	assert_int(r.status).is_equal(ReplayFormat.Status.OK)


func test_seek_and_transport_carry_projectile_packets() -> void:
	var rig: ReplayRig = _gunfire_rig(700)
	var r: ReplayReader = rig.new_reader()
	var _s: int = r.open_bytes(rig.file)
	assert_bool(r.seek(500)).is_true()
	assert_int(r.tick).is_less_equal(500)
	var t: ReplayTransport = ReplayTransport.new(r)
	var got: PackedInt32Array = PackedInt32Array([0, 0])                           # batches, items
	t.packet.connect(func(_c: int, ch: int, b: PackedByteArray) -> void:
		if b[0] == Protocol.PROJECTILE_BATCH:
			assert_int(ch).is_equal(Protocol.channel_of(Protocol.PROJECTILE_BATCH))
			var sb: ShotBuffer = ShotBuffer.new()
			var n: int = ProjectileBatch.decode(b, sb)
			assert_int(n).is_greater(0)
			got[0] += 1
			got[1] += n)
	var _k: int = t.seek(0)
	t.speed = 100.0
	for _i: int in 10:
		t.poll()
	var want: int = 0
	for tk: int in range(1, 701):
		want += _shots_for(tk).count
	assert_int(got[1]).is_equal(want)
	assert_int(got[0]).is_greater(50)


func test_mutated_file_with_projectile_frames_never_throws() -> void:
	var rig: ReplayRig = _gunfire_rig(240)
	var ok: PackedByteArray = PackedByteArray([1])
	var raw: PackedByteArray = ReplayFormat.gunzip(rig.file, ok)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 51
	for _i: int in 1500:
		var m: PackedByteArray = raw.duplicate()
		for _k: int in rng.randi_range(1, 6):
			m[rng.randi_range(0, m.size() - 1)] = rng.randi() & 0xFF
		var r: ReplayReader = rig.new_reader()
		var _st: int = r.open_raw(m)
		var guard: int = 0
		while r.next_frame() != ReplayReader.NO_FRAME and guard < 5000:
			guard += 1
	assert_int(ReplayReader.NO_FRAME).is_equal(0)


func test_wrong_packet_id_in_projectile_frame_is_corrupt() -> void:
	var rig: ReplayRig = _gunfire_rig(60)
	var ok: PackedByteArray = PackedByteArray([1])
	var raw: PackedByteArray = ReplayFormat.gunzip(rig.file, ok)
	var r: ReplayReader = rig.new_reader()
	var _s: int = r.open_raw(raw)
	var at: int = r.frames_begin()
	while at < r.frames_end() and raw[at] != ReplayFormat.FrameType.PROJECTILES:
		at += ReplayFormat.FRAME_HEADER_BYTES + raw.decode_u32(at + 5)
	assert_int(raw[at]).is_equal(ReplayFormat.FrameType.PROJECTILES)
	raw[at + ReplayFormat.FRAME_HEADER_BYTES + 2 + 2] = Protocol.SNAPSHOT          # container count, length, then the id
	var bad: ReplayReader = rig.new_reader()
	var _b: int = bad.open_raw(raw)
	var guard: int = 0
	while bad.next_frame() != ReplayReader.NO_FRAME and guard < 1000:
		guard += 1
	assert_int(bad.status).is_equal(ReplayFormat.Status.CORRUPT)


func _live_slots(rig: ProjectileRig) -> PackedInt32Array:
	var slots: PackedInt32Array = PackedInt32Array()
	for i: int in rig.n_entities:
		var _p: bool = slots.push_back(i)
	slots.append_array(rig.live_replicated())
	return slots


## ProjectileRig scene; the writer is the only reader of each tick's cache, hence the first reader of c_ori / c_fine.
func _projectile_raw(with_shots: bool) -> PackedByteArray:
	var rig: ProjectileRig = ProjectileRig.new()
	rig.build(1, Vector3i(40, 200, 700), Vector3i(24, 70, 300), 6, 17)
	var w: ReplayWriter = ReplayWriter.new()
	var h: ReplayHeader = ReplayHeader.new()
	h.map_id = "pin"
	h.started_unix = 1760000000
	var _o: int = w.open_memory(h)
	var none: Array[SimEvent] = []
	for t: int in 120:
		rig.step_scene()
		var sb: ShotBuffer = null
		if with_shots and t % 3 == 0:
			sb = _shots_for(t + 1)
			sb.add_q(EntityId.make(2, 1), 0, t & 0xFF, 1, -1)
		w.record_tick(rig.snap.codec, rig.snap.tick, _live_slots(rig), rig.snap.roster, none, sb)
	var file: PackedByteArray = w.finish(PackedByteArray([1]), rig.snap.tick)
	var ok: PackedByteArray = PackedByteArray([1])
	return ReplayFormat.gunzip(file, ok)


func _sha(raw: PackedByteArray) -> String:
	var ctx: HashingContext = HashingContext.new()
	var _st: int = ctx.start(HashingContext.HASH_SHA256)
	var _u: int = ctx.update(raw)
	return ctx.finish().hex_encode()


func test_replay_bytes_over_live_projectiles_pinned() -> void:
	var a: String = _sha(_projectile_raw(false))
	var b: String = _sha(_projectile_raw(true))
	print("SHA_WITHOUT_SHOTS=", a, " SHA_WITH_SHOTS=", b)
	assert_str(a).is_equal(SHA_WITHOUT_SHOTS)
	assert_str(b).is_equal(SHA_WITH_SHOTS)


func test_projectile_orientation_survives_replay_when_writer_reads_first() -> void:
	var rig: ProjectileRig = ProjectileRig.new()
	rig.build(1, Vector3i(40, 200, 700), Vector3i(24, 70, 300), 6, 17)
	var w: ReplayWriter = ReplayWriter.new()
	var _o: int = w.open_memory(ReplayHeader.new())
	var none: Array[SimEvent] = []
	for _t: int in 91:                                                              # written ticks are 1, 4 ... 91
		rig.step_scene()
		w.record_tick(rig.snap.codec, rig.snap.tick, _live_slots(rig), rig.snap.roster, none, null)
	var file: PackedByteArray = w.finish(PackedByteArray([1]), rig.snap.tick)
	var r: ReplayReader = ReplayReader.new(SnapRig.G, SnapRig.HZ)
	var _g: int = r.decoder.gravity_def.resize(16)
	assert_int(r.open_bytes(file)).is_equal(ReplayFormat.Status.OK)
	assert_bool(r.seek(91)).is_true()
	assert_int(r.tick).is_equal(91)
	var f: BaselineFrame = r.current()
	var checked: int = 0
	var frame: SnapshotFrame = rig.snap.frame
	for i: int in frame.count:
		var s: int = frame.index_of_row(i)
		if s < Roster.PROJECTILE_INDEX_MIN or not r.roster.has(s):
			continue
		var r4: Vector4 = frame.rot[i]
		assert_int(f.ori[s]).is_equal(Codec.quantize_quat(Quaternion(r4.x, r4.y, r4.z, r4.w)))
		checked += 1
	assert_int(checked).is_greater(5)
