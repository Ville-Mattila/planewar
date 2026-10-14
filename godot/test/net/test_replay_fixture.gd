extends GdUnitTestSuite
## NET-25: the committed fixture godot/test/fixtures/replay/net25_small.pwr (20 entities incl. 2 falling bombs, 150
## ticks, events, chat, one input summary) decodes to the summary pinned in net25_small.json. The same JSON is
## checked by tools/tests/test_replay_inspect.py against tools/replay_inspect.py, so the GDScript and Python decoders
## agree on every quantised field. Regenerate with PW_UPDATE_FIXTURES=1 (then commit both files).

const PWR: String = "res://test/fixtures/replay/net25_small.pwr"
const JSON_PATH: String = "res://test/fixtures/replay/net25_small.json"
const TICKS: int = 150
const GRAVITY_DEF: int = 3


func _build() -> ReplayRig:
	var rig: ReplayRig = ReplayRig.new()
	rig.build(Vector3i(3, 6, 11), Vector3i(2, 3, 4), 2, 99)
	var evs: Array[SimEvent] = [EventRig.ev(SimEvent.Kind.DEATH, EntityId.make(3, 1), EntityId.make(4, 1), 0.0, -1,
			PackedByteArray([2]))]
	rig.add_events(40, evs)
	rig.run(TICKS, 30, 60, 90)
	return rig


## Summary of a whole read, in the shape tools/replay_inspect.py decode_all() returns.
func summarize(r: ReplayReader) -> Dictionary:
	var counts: Dictionary = {"KEYFRAME": 0, "DELTA": 0, "EVENTS": 0, "CHAT": 0, "INPUT_SUMMARY": 0}
	var names: Array = ["", "KEYFRAME", "DELTA", "EVENTS", "CHAT", "INPUT_SUMMARY"]
	var events: int = 0
	var chat: Array[String] = []
	var inputs: int = 0
	var last: int = 0
	while not r.at_end():
		var type: int = r.next_frame()
		if type == ReplayReader.NO_FRAME:
			break
		counts[names[type]] = int(counts[names[type]]) + 1
		events += r.events.size()
		chat.append_array(r.chat_text)
		inputs += r.input_slot.size()
		last = r.tick
	var state: Array = []
	var f: BaselineFrame = r.current()
	for s: int in Roster.CAPACITY:
		if r.roster.has(s) and f.present[s] != 0:
			state.append([s, Codec.pos_cell(f.pos[s]), Codec.pos_e(f.pos[s]), Codec.pos_n(f.pos[s]), Codec.pos_u(f.pos[s]),
					f.ori[s], str(f.vel[s]), f.hp[s], f.flags[s], f.etick[s]])
	var keys: Array = []
	for t: int in r.index_tick:
		keys.append(t)
	return {"map_id": r.header.map_id, "tick_rate": r.header.tick_rate, "seed": r.header.seed_value,
		"players": Array(r.header.player_name), "frames": counts, "keyframe_ticks": keys, "ended_tick": r.ended_tick,
		"last_tick": last, "roster_count": r.roster.count(), "events": events, "chat": chat, "input_players": inputs,
		"state": state}


func test_fixture_matches_pinned_summary() -> void:
	if OS.get_environment("PW_UPDATE_FIXTURES") == "1":
		_regenerate()
	var r: ReplayReader = ReplayReader.new(SnapRig.G, SnapRig.HZ)
	var _x: int = r.decoder.gravity_def.resize(4)
	r.decoder.gravity_def[GRAVITY_DEF] = 1
	assert_int(r.open(PWR)).is_equal(ReplayFormat.Status.OK)
	var got: Dictionary = summarize(r)
	var want: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(JSON_PATH))
	for key: String in ["map_id", "tick_rate", "seed", "keyframe_ticks", "ended_tick", "last_tick", "roster_count",
			"events", "input_players", "frames", "players", "chat"]:
		assert_str(JSON.stringify(_norm(got[key]), "", true)).is_equal(JSON.stringify(_norm(want[key]), "", true))
	var gs: Array = got["state"]
	var ws: Array = want["state"]
	assert_int(gs.size()).is_equal(ws.size())
	assert_int(gs.size()).is_equal(20)
	for i: int in gs.size():
		assert_str(JSON.stringify(_norm(gs[i]))).is_equal(JSON.stringify(_norm(ws[i])))


## JSON numbers come back as floats; integers print the same after rounding.
func _norm(v: Variant) -> Variant:
	if v is float:
		return int(v)
	if v is Array:
		var out: Array = []
		for e: Variant in v:
			out.append(_norm(e))
		return out
	if v is Dictionary:
		var d: Dictionary = {}
		for k: Variant in (v as Dictionary).keys():
			d[k] = _norm(v[k])
		return d
	return v


func _regenerate() -> void:
	var rig: ReplayRig = _build()
	var dir: String = ProjectSettings.globalize_path("res://test/fixtures/replay")
	var _m: Error = DirAccess.make_dir_recursive_absolute(dir)
	var f: FileAccess = FileAccess.open(PWR, FileAccess.WRITE)
	var _s: bool = f.store_buffer(rig.file)
	f.close()
	var r: ReplayReader = rig.new_reader()
	var _o: int = r.open_bytes(rig.file)
	var g: FileAccess = FileAccess.open(JSON_PATH, FileAccess.WRITE)
	g.store_string(JSON.stringify(summarize(r), "", true))
	g.close()
