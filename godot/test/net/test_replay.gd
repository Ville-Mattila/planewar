extends GdUnitTestSuite
## NET-25 replay_test: a 2-minute scene (3,600 ticks, 120 entities incl. falling bombs) is written and read back.
## Covers the write/read round trip within quantisation, header / footer / index, keyframe cadence, index seek
## (forward and back), events, chat and input summary frames, redaction in place, truncated files, determinism,
## ReplayTransport delivery and the 20-file cap.

const TICKS: int = 3600
const TOL_M: float = 0.5

static var _rig: ReplayRig = null


func _make() -> ReplayRig:
	var rig: ReplayRig = ReplayRig.new()
	rig.build(Vector3i(10, 30, 80), Vector3i(8, 15, 20), 3, 5)
	var evs: Array[SimEvent] = [EventRig.ev(SimEvent.Kind.DEATH, EntityId.make(3, 1), EntityId.make(4, 1), 0.0, -1,
			PackedByteArray([2]))]
	rig.add_events(100, evs)
	rig.add_events(2000, evs)
	rig.run(TICKS, 30, 500)
	return rig


func _shared() -> ReplayRig:
	if _rig == null:
		_rig = _make()
	return _rig


func test_round_trip_two_minutes() -> void:
	var rig: ReplayRig = _shared()
	var r: ReplayReader = rig.new_reader()
	assert_int(r.open_bytes(rig.file)).is_equal(ReplayFormat.Status.OK)
	assert_bool(r.has_footer).is_true()
	assert_int(r.ended_tick).is_equal(TICKS)
	assert_int(r.header.player_count()).is_equal(2)
	assert_str(r.header.player_name[1]).is_equal("Bobby Tables")
	assert_str(r.header.map_id).is_equal("test-map")
	var checked: int = 0
	var worst: float = 0.0
	var k: int = 0
	var keys: int = 0
	while not r.at_end():
		var t: int = r.peek_tick()
		var type: int = r.next_frame()
		assert_int(type).is_not_equal(ReplayReader.NO_FRAME)
		keys += 1 if type == ReplayFormat.FrameType.KEYFRAME else 0
		if type != ReplayFormat.FrameType.DELTA and type != ReplayFormat.FrameType.KEYFRAME:
			continue
		if k < rig.saved_ticks.size() and rig.saved_ticks[k] == t:
			worst = maxf(worst, rig.max_error(r, k))
			checked += 1
			k += 1
	assert_int(checked).is_equal(rig.saved_ticks.size())
	assert_float(worst).is_less(TOL_M)
	assert_int(keys).is_equal(12)
	assert_int(r.index_tick.size()).is_equal(12)
	assert_int(r.index_tick[0]).is_equal(1)
	assert_int(r.index_tick[1]).is_equal(301)
	assert_int(rig.writer.deferred).is_equal(0)
	assert_int(r.roster.count()).is_equal(rig.snap.frame.count)


func test_events_chat_and_hp() -> void:
	var rig: ReplayRig = _shared()
	var r: ReplayReader = rig.new_reader()
	var _s: int = r.open_bytes(rig.file)
	var deaths: int = 0
	var chats: PackedStringArray = PackedStringArray()
	while not r.at_end():
		var type: int = r.next_frame()
		if type == ReplayFormat.FrameType.EVENTS:
			deaths += r.events.size()
		chats.append_array(r.chat_text)
	assert_int(deaths).is_equal(2)
	assert_array(chats).contains_exactly(["hello secret"])


func test_index_seek() -> void:
	var rig: ReplayRig = _shared()
	var r: ReplayReader = rig.new_reader()
	var _s: int = r.open_bytes(rig.file)
	for k: int in [60, 20, 100, 5, 119]:
		var t: int = rig.saved_ticks[k]
		assert_bool(r.seek(t)).is_true()
		assert_int(r.tick).is_equal(t)
		assert_float(rig.max_error(r, k)).is_less(TOL_M)
	assert_int(r.seek_keyframe(1799)).is_equal(1501)
	assert_int(r.seek_keyframe(0)).is_equal(-1)
	assert_bool(r.seek(1)).is_true()
	assert_int(r.tick).is_equal(1)


func test_input_summary_frame() -> void:
	var rig: ReplayRig = ReplayRig.new()
	rig.build(Vector3i(2, 2, 2), Vector3i(1, 1, 1), 0, 3)
	var inputs: PackedByteArray = PackedByteArray()
	var _x: int = inputs.resize(ReplayFormat.INPUT_ENTRY_BYTES - 5)
	for i: int in inputs.size():
		inputs[i] = i & 0xFF
	var w: ReplayWriter = rig.writer
	var _e: int = w.open_memory(rig.header)
	rig.snap.step()
	var none: Array[SimEvent] = []
	w.record_tick(rig.snap.codec, 1, rig.slots, rig.snap.roster, none)
	w.record_input_summary(30, PackedInt32Array([1]), PackedInt32Array([1234]), inputs)
	w.record_input_summary(31, PackedInt32Array([1]), PackedInt32Array([1234]), PackedByteArray([1]))   # wrong size: ignored
	var r: ReplayReader = rig.new_reader()
	var _o: int = r.open_bytes(w.finish(PackedByteArray(), 31))
	var _f: int = r.next_frame()
	assert_int(r.next_frame()).is_equal(ReplayFormat.FrameType.INPUT_SUMMARY)
	assert_int(r.input_entity[0]).is_equal(1234)
	assert_array(r.input_bytes).is_equal(inputs)
	assert_bool(r.at_end()).is_true()


func test_redaction_in_place_keeps_file_valid() -> void:
	var rig: ReplayRig = _shared()
	var ok: PackedByteArray = PackedByteArray([1])
	var raw: PackedByteArray = ReplayFormat.gunzip(rig.file, ok)
	assert_int(ok[0]).is_equal(1)
	var red: PackedByteArray = ReplayRedactor.redact_raw(raw)
	assert_int(red.size()).is_equal(raw.size())
	assert_bool(red == raw).is_false()
	var r: ReplayReader = rig.new_reader()
	assert_int(r.open_raw(red)).is_equal(ReplayFormat.Status.OK)
	assert_str(r.header.player_name[0]).is_equal("*****")
	assert_str(r.header.player_name[1]).is_equal("************")
	assert_int(r.header.user_id[0][0]).is_equal(0)
	assert_int(r.index_tick.size()).is_equal(12)
	var chats: PackedStringArray = PackedStringArray()
	var k: int = 0
	while not r.at_end():
		var type: int = r.next_frame()
		assert_int(type).is_not_equal(ReplayReader.NO_FRAME)
		chats.append_array(r.chat_text)
		if type == ReplayFormat.FrameType.DELTA and k < rig.saved_ticks.size() and r.tick == rig.saved_ticks[k]:
			assert_float(rig.max_error(r, k)).is_less(TOL_M)
			k += 1
	assert_array(chats).contains_exactly(["************"])
	# everything outside names, ids and chat text is byte-identical
	var diff: int = 0
	for i: int in raw.size():
		diff += 1 if raw[i] != red[i] else 0
	assert_int(diff).is_less(80)
	assert_bool(r.result_hash == rig.file.slice(0, 0)).is_false()


func test_redact_file_round_trip() -> void:
	var rig: ReplayRig = _shared()
	var path: String = "user://net25_redact.pwr"
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	var _s: bool = f.store_buffer(rig.file)
	f.close()
	assert_int(ReplayRedactor.redact_file(path)).is_equal(OK)
	var r: ReplayReader = rig.new_reader()
	assert_int(r.open(path)).is_equal(ReplayFormat.Status.OK)
	assert_str(r.header.player_name[0]).is_equal("*****")
	var _d: Error = DirAccess.remove_absolute(path)


func test_truncated_gzip_recovers_frames() -> void:
	var rig: ReplayRig = _shared()
	var cut: PackedByteArray = rig.file.slice(0, rig.file.size() * 6 / 10)
	var r: ReplayReader = rig.new_reader()
	assert_int(r.open_bytes(cut)).is_equal(ReplayFormat.Status.RECOVERED)
	assert_bool(r.has_footer).is_false()
	assert_int(r.index_tick.size()).is_greater(2)
	var n: int = 0
	var last: int = 0
	while r.next_frame() != ReplayReader.NO_FRAME:
		n += 1
		last = r.tick
	assert_int(n).is_greater(500)
	assert_int(last).is_less(TICKS)
	assert_int(r.status).is_equal(ReplayFormat.Status.RECOVERED)
	assert_bool(r.seek(r.index_tick[1] + 5)).is_true()


func test_truncated_raw_and_missing_footer() -> void:
	var rig: ReplayRig = _shared()
	var ok: PackedByteArray = PackedByteArray([1])
	var raw: PackedByteArray = ReplayFormat.gunzip(rig.file, ok)
	var r: ReplayReader = rig.new_reader()
	assert_int(r.open_raw(raw.slice(0, raw.size() - 10))).is_equal(ReplayFormat.Status.RECOVERED)
	var frames: int = 0
	while r.next_frame() != ReplayReader.NO_FRAME:
		frames += 1
	assert_int(frames).is_equal(rig.writer.frames_written)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 4
	for _i: int in 40:
		var n: int = rng.randi_range(0, raw.size() - 1)
		var r2: ReplayReader = rig.new_reader()
		var st: int = r2.open_raw(raw.slice(0, n))
		assert_bool(st == ReplayFormat.Status.RECOVERED or st == ReplayFormat.Status.CORRUPT or st == ReplayFormat.Status.BAD_MAGIC).is_true()
		var guard: int = 0
		while r2.next_frame() != ReplayReader.NO_FRAME and guard < 100000:
			guard += 1
	assert_int(rig.new_reader().open_bytes(PackedByteArray([1, 2, 3]))).is_not_equal(ReplayFormat.Status.OK)
	assert_int(rig.new_reader().open_raw(PackedByteArray())).is_equal(ReplayFormat.Status.BAD_MAGIC)


func test_version_mismatch_is_reported() -> void:
	var rig: ReplayRig = _shared()
	var ok: PackedByteArray = PackedByteArray([1])
	var raw: PackedByteArray = ReplayFormat.gunzip(rig.file, ok)
	raw.encode_u16(4, Protocol.PROTOCOL_VERSION + 1)
	assert_int(rig.new_reader().open_raw(raw)).is_equal(ReplayFormat.Status.UNSUPPORTED_VERSION)
	raw[0] = 0
	assert_int(rig.new_reader().open_raw(raw)).is_equal(ReplayFormat.Status.BAD_MAGIC)


func test_mutated_file_never_throws() -> void:
	var rig: ReplayRig = ReplayRig.new()
	rig.build(Vector3i(3, 5, 12), Vector3i(2, 3, 4), 1, 8)
	rig.run(240, 30, 50)
	var ok: PackedByteArray = PackedByteArray([1])
	var raw: PackedByteArray = ReplayFormat.gunzip(rig.file, ok)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 11
	for _i: int in 1500:
		var m: PackedByteArray = raw.duplicate()
		for _k: int in rng.randi_range(1, 6):
			m[rng.randi_range(0, m.size() - 1)] = rng.randi() & 0xFF
		var r: ReplayReader = rig.new_reader()
		var _st: int = r.open_raw(m)
		var guard: int = 0
		while r.next_frame() != ReplayReader.NO_FRAME and guard < 5000:
			guard += 1
		var _sk: bool = r.seek(rng.randi_range(0, 240))
	assert_int(ReplayReader.NO_FRAME).is_equal(0)


func test_determinism() -> void:
	var a: ReplayRig = ReplayRig.new()
	a.build(Vector3i(5, 10, 30), Vector3i(4, 6, 8), 2, 21)
	a.run(400)
	var b: ReplayRig = ReplayRig.new()
	b.build(Vector3i(5, 10, 30), Vector3i(4, 6, 8), 2, 21)
	b.run(400)
	assert_bool(a.file == b.file).is_true()
	assert_int(a.file.size()).is_greater(1000)


func test_transport_delivers_frames_at_playback_speed() -> void:
	var rig: ReplayRig = _shared()
	var r: ReplayReader = rig.new_reader()
	var _s: int = r.open_bytes(rig.file)
	var t: ReplayTransport = ReplayTransport.new(r)
	var counts: PackedInt32Array = PackedInt32Array([0, 0, 0])   # packets, keyframes, finished
	var client: ReplayReader = rig.new_reader()
	t.packet.connect(func(_c: int, _ch: int, b: PackedByteArray) -> void:
		counts[0] += 1
		if b[0] == Protocol.ENTITY_META:
			var tmp: PackedInt32Array = PackedInt32Array()
			var _n: int = RosterCodec.decode_meta(b, client.roster, tmp))
	t.keyframe_started.connect(func(_tk: int) -> void: counts[1] += 1)
	t.finished.connect(func() -> void: counts[2] += 1)
	t.speed = 10.0
	for _i: int in 29:
		t.poll()
	assert_float(t.playhead).is_between(289.0, 292.0)
	assert_int(counts[1]).is_equal(1)
	assert_int(counts[0]).is_greater(10)
	assert_int(client.roster.count()).is_equal(rig.snap.frame.count)
	assert_int(t.seek(1800)).is_equal(1501)
	t.speed = 100.0
	for _i: int in 40:
		t.poll()
	assert_int(counts[2]).is_equal(1)
	assert_str(String(t.kind())).is_equal("replay")


func test_store_keeps_twenty_oldest_first() -> void:
	var dir: String = "user://net25_replays"
	var _m: Error = DirAccess.make_dir_recursive_absolute(dir)
	var d: DirAccess = DirAccess.open(dir)
	for f: String in d.get_files():
		var _x: Error = d.remove(f)
	for i: int in 22:
		var name: String = ReplayStore.file_name(1000 + i, "skirmish", "moon one")
		var f: FileAccess = FileAccess.open(dir.path_join(name), FileAccess.WRITE)
		f.store_8(1)
		f.close()
		var _r: int = ReplayStore.prune(dir)
	var names: PackedStringArray = ReplayStore.list(dir)
	assert_int(names.size()).is_equal(20)
	assert_str(names[0]).is_equal("1002_skirmish_moon-one.pwr")
	assert_int(ReplayStore.make_room(dir)).is_equal(1)
	assert_int(ReplayStore.list(dir).size()).is_equal(19)
	for f: String in d.get_files():
		var _x: Error = d.remove(f)
