extends GdUnitTestSuite
## AI-03: the sim_ai CommandSink forwards to the sim's sink at tick-order step 3. drive refuses POSSESSED and leaves the
## slot untouched, submit goes through the validator, ai_tag round-trips through SimView, the hook runs once per tick,
## the hook's S4 bytes round-trip, and two identical runs are byte-identical.

class SinkHook extends SimAiHook:
	var sink: CommandSink = CommandSink.new()
	var ticks: PackedInt32Array = PackedInt32Array()
	var drive_id: int = 0
	var input: PilotInput = PilotInput.new()
	var results: Array[bool] = []
	var tag_id: int = 0
	var tag: int = 0
	var cmd: Command = null
	var cmd_result: CommandResult = null
	var state: int = 0

	func on_tick(t: int, _v: SimView, base: CommandSinkBase) -> void:
		sink.bind(base)
		ticks.push_back(t)
		state += 1
		if drive_id != 0:
			results.append(sink.drive(drive_id, input))
		if tag_id != 0:
			sink.set_ai_tag(tag_id, tag)
		if cmd != null:
			cmd_result = sink.submit(cmd)
			cmd = null

	func serialize() -> PackedByteArray:
		var b: PackedByteArray = PackedByteArray()
		b.resize(8)
		b.encode_s64(0, state)
		return b

	func deserialize(bytes: PackedByteArray) -> void:
		state = bytes.decode_s64(0) if bytes.size() == 8 else -1


func _dart(w: SimWorld) -> int:
	return WorldTestKit.spawn(w, &"dart", 0, 0, WorldTestKit.at(300.0), Vector3(0.0, 50.0, 0.0))


func test_drive_on_possessed_id_returns_false_and_leaves_slot_untouched() -> void:
	var w: SimWorld = WorldTestKit.world()
	var id: int = _dart(w)
	var h: SinkHook = SinkHook.new()
	h.drive_id = id
	h.input.thrust = 0.75
	w.set_ai_hook(h)
	w.step()
	var s: int = EntityId.slot(id)
	assert_float(ControlTestKit.inputs(w).e_thrust[s]).is_equal(0.75)
	var _a: Array[SimEvent] = ControlTestKit.run(w, Command.possess(0, id))
	h.input.thrust = 0.1
	var before: float = ControlTestKit.inputs(w).e_thrust[s]
	var _b: Array[SimEvent] = ControlTestKit.step(w, 3)
	assert_bool(h.results[h.results.size() - 1]).is_false()
	assert_float(ControlTestKit.inputs(w).e_thrust[s]).is_equal(before)
	assert_int(h.sink.drives_refused).is_greater(0)


func test_drive_refuses_stale_ids() -> void:
	var w: SimWorld = WorldTestKit.world()
	var id: int = _dart(w)
	var h: SinkHook = SinkHook.new()
	h.drive_id = id + 0x100000
	w.set_ai_hook(h)
	w.step()
	assert_bool(h.results[0]).is_false()


func test_unbound_sink_refuses_everything() -> void:
	var s: CommandSink = CommandSink.new()
	assert_bool(s.drive(1, PilotInput.new())).is_false()
	assert_int(s.submit(Command.release(0)).code).is_equal(CommandResult.Code.REJECTED_NO_RIGHTS)
	assert_object(s.pathing()).is_null()
	s.set_ai_tag(1, 2)
	assert_int(s.tags).is_equal(1)


func test_submit_goes_through_validator() -> void:
	var w: SimWorld = WorldTestKit.world()
	var id: int = _dart(w)
	var h: SinkHook = SinkHook.new()
	w.set_ai_hook(h)
	h.cmd = Command.possess(1, id)          # player 1 is on the other team: validator must reject
	w.step()
	assert_int(h.cmd_result.code).is_not_equal(CommandResult.Code.ACCEPTED)
	h.cmd = Command.possess(0, id)
	w.step()
	assert_int(h.cmd_result.code).is_equal(CommandResult.Code.ACCEPTED)
	w.step()
	assert_int(w.view().control_state(id)).is_equal(ControlMachine.State.POSSESSED)
	assert_int(h.sink.submits).is_equal(2)


func test_ai_tag_write_read() -> void:
	var w: SimWorld = WorldTestKit.world()
	var id: int = _dart(w)
	var h: SinkHook = SinkHook.new()
	h.tag_id = id
	h.tag = 5
	w.set_ai_hook(h)
	assert_int(w.view().ai_tag(id)).is_equal(0)
	w.step()
	assert_int(w.view().ai_tag(id)).is_equal(5)
	h.tag = 0x1FF
	w.step()
	assert_int(w.view().ai_tag(id)).is_equal(0xFF)


func test_hook_called_once_per_tick_in_order() -> void:
	var w: SimWorld = WorldTestKit.world()
	var h: SinkHook = SinkHook.new()
	w.set_ai_hook(h)
	var _e: Array[SimEvent] = ControlTestKit.step(w, 10)
	assert_int(h.ticks.size()).is_equal(10)
	for i: int in range(1, h.ticks.size()):
		assert_int(h.ticks[i]).is_equal(h.ticks[i - 1] + 1)


func test_s4_hook_bytes_round_trip() -> void:
	var a: SimWorld = WorldTestKit.world(11)
	var ha: SinkHook = SinkHook.new()
	a.set_ai_hook(ha)
	var _e: Array[SimEvent] = ControlTestKit.step(a, 7)
	var hb: SinkHook = SinkHook.new()
	var b: SimWorld = SimWorld.deserialize(a.serialize(), WorldTestKit.content(), hb)
	assert_object(b).is_not_null()
	assert_int(hb.state).is_equal(7)
	a.step()
	b.step()
	assert_bool(a.serialize() == b.serialize()).is_true()


func test_determinism_two_runs_identical() -> void:
	var outs: Array[PackedByteArray] = []
	for _run: int in 2:
		var w: SimWorld = WorldTestKit.world(21)
		var id: int = _dart(w)
		var h: SinkHook = SinkHook.new()
		h.drive_id = id
		h.input.thrust = 0.6
		h.input.roll = -0.3
		h.tag_id = id
		h.tag = 3
		w.set_ai_hook(h)
		var _e: Array[SimEvent] = ControlTestKit.step(w, 60)
		outs.append(w.serialize())
	assert_bool(outs[0] == outs[1]).is_true()
