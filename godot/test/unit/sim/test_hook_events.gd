extends GdUnitTestSuite
## TA-57 / A-71: the events the caller drained after tick t reach SimAiHook.on_event once each, in SimEvents order,
## at the start of step 3 of tick t+1, before on_tick; the step-12 drain is unchanged; S4 holds with a queued batch.


class LogHook extends SimAiHook:
	var log: Array[String] = []        ## "E<kind>@<tick>" for on_event, "T<tick>" for on_tick, in call order
	var events: Array[SimEvent] = []
	var count: int = 0

	func on_event(ev: SimEvent) -> void:
		events.append(ev)
		log.append("E%d@%d" % [ev.kind, ev.tick])

	func on_tick(t: int, _v: SimView, _s: CommandSinkBase) -> void:
		log.append("T%d" % t)
		count += 1

	func serialize() -> PackedByteArray:
		var b: PackedByteArray = PackedByteArray()
		var _r: int = b.resize(8)
		b.encode_s64(0, count)
		return b

	func deserialize(bytes: PackedByteArray) -> void:
		count = bytes.decode_s64(0)


func _spawn(w: SimWorld, east: float) -> void:
	var code: int = WorldTestKit.queue_spawn(w, &"dart", 0, 0, WorldTestKit.at(300.0, east), Vector3(0, 50.0, 0))
	assert_int(code).is_equal(CommandResult.Code.ACCEPTED)


# Runs `ticks` steps, queuing a spawn before the 1st, 3rd and last; returns every drained event in order.
func _run(w: SimWorld, ticks: int) -> Array[SimEvent]:
	var drained: Array[SimEvent] = []
	for t: int in ticks:
		if t == 0 or t == 2 or t == ticks - 1:
			_spawn(w, 100.0 * t)
		w.step()
		drained.append_array(w.drain_events())
	return drained


func _kinds(events: Array[SimEvent]) -> PackedInt32Array:
	return WorldTestKit.kinds(events)


func test_events_forwarded_once_in_order_before_on_tick() -> void:
	var w: SimWorld = WorldTestKit.world()
	var hook: LogHook = LogHook.new()
	w.set_ai_hook(hook)
	var drained: Array[SimEvent] = _run(w, 5)
	var delivered: Array[SimEvent] = []
	for e: SimEvent in drained:
		if e.tick < 5:                       # tick 5's events were drained after the last step: still queued
			delivered.append(e)
	assert_int(delivered.size()).is_greater(1)
	assert_int(hook.events.size()).is_equal(delivered.size())
	for i: int in delivered.size():
		assert_object(hook.events[i]).is_same(delivered[i])
	for i: int in hook.log.size():           # an event of tick t is followed first by T(t+1), never by an earlier on_tick
		if hook.log[i].begins_with("E"):
			var et: int = int(hook.log[i].get_slice("@", 1))
			var j: int = i
			while not hook.log[j].begins_with("T"):
				j += 1
			assert_str(hook.log[j]).is_equal("T%d" % (et + 1))
	var n: int = hook.events.size()
	w.step()                                 # the queued batch arrives now
	assert_int(hook.events.size()).is_greater(n)


func test_step_12_drain_unchanged_and_hookless_world_queues_nothing() -> void:
	var a: SimWorld = WorldTestKit.world()
	var b: SimWorld = WorldTestKit.world()
	b.set_ai_hook(LogHook.new())
	var da: Array[SimEvent] = _run(a, 4)
	var db: Array[SimEvent] = _run(b, 4)
	assert_array(_kinds(da)).is_equal(_kinds(db))
	assert_int(a.drain_events().size()).is_equal(0)
	assert_int(SimSerialize.write_raw(a).size()).is_less(SimSerialize.write_raw(b).size())   # only b queued a batch


func test_base_hook_on_event_is_a_noop() -> void:
	var w: SimWorld = WorldTestKit.world()
	w.set_ai_hook(SimAiHook.new())
	var drained: Array[SimEvent] = _run(w, 3)
	assert_int(drained.size()).is_greater(0)
	SimAiHook.new().on_event(drained[0])


func test_determinism_same_inputs_same_delivery() -> void:
	var logs: Array[Array] = []
	for _k: int in 2:
		var w: SimWorld = WorldTestKit.world(11)
		var hook: LogHook = LogHook.new()
		w.set_ai_hook(hook)
		var _d: Array[SimEvent] = _run(w, 8)
		logs.append(hook.log)
	assert_array(logs[0]).is_equal(logs[1])


func test_s4_roundtrip_with_a_queued_batch() -> void:
	var a: SimWorld = WorldTestKit.world(5)
	var ha: LogHook = LogHook.new()
	a.set_ai_hook(ha)
	var _d: Array[SimEvent] = _run(a, 3)     # drained after tick 3, queued for tick 4
	var hb: LogHook = LogHook.new()
	var b: SimWorld = SimWorld.deserialize(a.serialize(), WorldTestKit.content(), hb)
	assert_object(b).is_not_null()
	var before: int = ha.events.size()
	for _t: int in 5:
		a.step()
		b.step()
		assert_array(_kinds(a.drain_events())).is_equal(_kinds(b.drain_events()))
	assert_int(hb.events.size()).is_equal(ha.events.size() - before)   # the restored hook got the queued batch and the rest
	assert_int(hb.events.size()).is_greater(0)
	assert_array(a.serialize()).is_equal(b.serialize())


func test_pending_queue_roundtrip_and_malformed_refusal() -> void:
	var ev: SimEvents = SimEvents.new()
	var e: SimEvent = ev.emit(SimEvent.Kind.SPAWN, 1, 2, Vector3(1, 2, 3), 4.0, 0, 3)
	assert_object(e).is_not_null()
	var _d: Array[SimEvent] = ev.drain(true)
	var buf: StreamPeerBuffer = StreamPeerBuffer.new()
	ev.write_pending(buf)
	var rd: SimEvents = SimEvents.new()
	var rb: StreamPeerBuffer = StreamPeerBuffer.new()
	rb.data_array = buf.data_array
	assert_bool(rd.read_pending(rb)).is_true()
	assert_int(rd.pending.size()).is_equal(1)
	assert_that(rd.pending[0].pos).is_equal(Vector3(1, 2, 3))
	var bad: PackedByteArray = buf.data_array
	bad[4] = 255                             # kind byte out of range
	rb.data_array = bad
	assert_bool(SimEvents.new().read_pending(rb)).is_false()


# The saved queue returns every field exactly: a HIT whose value is not float32-exact, every kind, extra bytes.
func test_pending_queue_roundtrips_every_field_exactly() -> void:
	var ev: SimEvents = SimEvents.new()
	ev.tick = 123456
	var _a: SimEvent = ev.emit(SimEvent.Kind.HIT, 7, 9, Vector3(0.1, -2.5, 3.0e3), 0.1, 2, 5)
	for k: int in SimEvent.Kind.size():
		var _e: SimEvent = ev.emit(k as SimEvent.Kind, k, -k, Vector3.ZERO, 1.0 / 3.0, k % 8)
	var _d: Array[SimEvent] = ev.drain(true)
	var buf: StreamPeerBuffer = StreamPeerBuffer.new()
	ev.write_pending(buf)
	var rb: StreamPeerBuffer = StreamPeerBuffer.new()
	rb.data_array = buf.data_array
	var rd: SimEvents = SimEvents.new()
	assert_bool(rd.read_pending(rb)).is_true()
	assert_int(rb.get_available_bytes()).is_equal(0)
	assert_int(rd.pending.size()).is_equal(ev.pending.size())
	for i: int in ev.pending.size():
		var x: SimEvent = ev.pending[i]
		var y: SimEvent = rd.pending[i]
		assert_int(y.kind).is_equal(x.kind)
		assert_int(y.tick).is_equal(x.tick)
		assert_int(y.a).is_equal(x.a)
		assert_int(y.b).is_equal(x.b)
		assert_int(y.team).is_equal(x.team)
		assert_that(y.pos).is_equal(x.pos)
		assert_float(y.value).is_equal(x.value)           # exact: 0.1 and 1/3 survive as doubles
		assert_array(y.extra).is_equal(x.extra)
