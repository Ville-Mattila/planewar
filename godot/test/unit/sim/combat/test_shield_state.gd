extends GdUnitTestSuite
## GD-10 S4 (save / restore / continue) and determinism for the shield domes: a world saved mid-recharge and mid-collapse
## continues byte-exact, a format-11 save is refused, malformed shield bytes are refused. Contract SH15-SH17.

const K: GDScript = preload("res://test/unit/sim/combat/shield_test_kit.gd")
const HZ: int = 30


# Two Projectors (one covering the Core) and the Core; a fixed bomb schedule: A takes hits until it collapses (tick 40+),
# B takes one early hit and recharges. Returns the world after `ticks`.
func _scene(ticks: int) -> SimWorld:
	var w: SimWorld = K.world(true, WorldTestKit.rules(60.0))
	var a: int = K.projector(w, 150.0)
	var _o: int = K.put(w, &"outpost", WorldTestKit.at(0.0, 900.0))
	var b: int = K.projector(w, 1000.0)
	w.shields()._charge[a] = 1200.0
	w.shields()._charge[b] = 1200.0
	while w.tick() < ticks:
		_schedule(w, a, b)
		w.step()
		var _e: Array[SimEvent] = w.drain_events()
	return w


func _schedule(w: SimWorld, a: int, b: int) -> void:
	var t: int = w.tick()
	if t >= 40 and t < 100 and (t - 40) % 15 == 0:
		var _x: int = K.shot(w, a)
		var _n: int = K.absorb(w)
	if t == 50:
		var _y: int = K.shot(w, b, &"rocket", &"rocket_lancer")
		var _m: int = K.absorb(w)


func _same_future(w: SimWorld, ticks: int) -> void:
	var copy: SimWorld = SimWorld.deserialize(w.serialize(), WorldTestKit.content(), null)
	assert_object(copy).is_not_null()
	assert_bool(copy.serialize() == w.serialize()).is_true()
	var a: int = EconomyTestKit.find(w, &"shield_projector")
	var log_w: PackedStringArray = PackedStringArray()
	var log_c: PackedStringArray = PackedStringArray()
	for _t: int in ticks:
		for x: SimWorld in [w, copy]:
			if x.tick() % 17 == 0:
				var _id: int = K.shot(x, a)
				var _n: int = K.absorb(x)
			x.step()
		for e: SimEvent in w.drain_events():
			log_w.append("%d:%d:%d:%d" % [e.tick, e.kind, e.a, e.b])
		for e: SimEvent in copy.drain_events():
			log_c.append("%d:%d:%d:%d" % [e.tick, e.kind, e.a, e.b])
	assert_array(log_c).is_equal(log_w)
	assert_bool(copy.serialize() == w.serialize()).is_true()
	assert_float(copy.shields().charge_of(a)).is_equal(w.shields().charge_of(a))


func test_save_mid_collapse_continues_byte_exact() -> void:
	var w: SimWorld = _scene(130)
	var a: int = EconomyTestKit.find(w, &"shield_projector")
	assert_int(w.shields().collapse_left(a, w.tick())).is_greater(0)                  # the scene is mid-collapse
	_same_future(w, 400)


func test_save_mid_recharge_continues_byte_exact() -> void:
	var w: SimWorld = _scene(130)
	var a: int = EconomyTestKit.find(w, &"shield_projector")
	var _e: Array[SimEvent] = EconomyTestKit.run(w, w.shields().collapse_left(a, w.tick()) + 200)
	assert_int(w.shields().collapse_left(a, w.tick())).is_equal(0)
	assert_float(w.shields().charge_of(a)).is_greater(0.0)                            # charging again
	assert_float(w.shields()._credit[a]).is_greater(-1.0)
	_same_future(w, 400)


func test_save_before_the_core_shield_ends_removes_it_at_the_same_tick_after_restore() -> void:
	var w: SimWorld = K.world(true, WorldTestKit.rules(20.0))
	var _a: Array[SimEvent] = EconomyTestKit.run(w, 580 - w.tick())
	var copy: SimWorld = SimWorld.deserialize(w.serialize(), WorldTestKit.content(), null)
	assert_bool(copy.shields().core_up(0)).is_true()                                  # derived list rebuilt on load
	for x: SimWorld in [w, copy]:
		var ev: Array[SimEvent] = EconomyTestKit.run(x, 30)
		assert_int(EconomyTestKit.count_alert(ev, AlertKind.Kind.CORE_SHIELD_DOWN)).is_equal(1)
		assert_bool(x.shields().core_up(0)).is_false()
	assert_bool(copy.serialize() == w.serialize()).is_true()


func test_two_runs_of_the_same_scene_are_identical() -> void:
	var a: SimWorld = _scene(300)
	var b: SimWorld = _scene(300)
	assert_bool(a.serialize() == b.serialize()).is_true()
	assert_int(a.shields().absorbed_total).is_equal(b.shields().absorbed_total)
	assert_int(a.shields().absorbed_total).is_greater(2)


func test_a_format_11_save_is_refused() -> void:
	var w: SimWorld = K.world()
	var bytes: PackedByteArray = w.serialize()
	assert_int(SimSerialize.FORMAT).is_greater_equal(12)                              # GD-10 appended the shield state
	var old: PackedByteArray = bytes.duplicate()
	old.encode_u32(4, 11)
	assert_int(SimSerialize.check(old)).is_equal(SimSerialize.Status.OLD_FORMAT)
	assert_object(SimWorld.deserialize(old, WorldTestKit.content(), null)).is_null()
	assert_object(SimWorld.deserialize(bytes, WorldTestKit.content(), null)).is_not_null()


func test_malformed_shield_bytes_are_refused() -> void:
	var w: SimWorld = K.world()
	var good: StreamPeerBuffer = StreamPeerBuffer.new()
	w.shields().write_state(good)
	var sd: ShieldDomes = w.shields()
	var buf: StreamPeerBuffer = StreamPeerBuffer.new()
	buf.data_array = good.data_array.slice(0, good.data_array.size() / 2)             # truncated
	assert_bool(sd.read_state(buf)).is_false()
	var short: StreamPeerBuffer = StreamPeerBuffer.new()
	short.put_var(PackedFloat64Array([1.0, 2.0]))                                     # wrong element count
	for _k: int in 4:
		short.put_var(PackedInt32Array([0]))
	assert_bool(sd.read_state(short)).is_false()
	var neg: ShieldDomes = w.shields()
	neg._charge[3] = -5.0
	var bad: StreamPeerBuffer = StreamPeerBuffer.new()
	neg.write_state(bad)
	neg._charge[3] = 0.0
	var rd: StreamPeerBuffer = StreamPeerBuffer.new()
	rd.data_array = bad.data_array
	assert_bool(neg.read_state(rd)).is_false()                                        # a negative charge
	var ok: StreamPeerBuffer = StreamPeerBuffer.new()
	ok.data_array = good.data_array
	assert_bool(sd.read_state(ok)).is_true()


func test_shield_collapse_and_core_shield_down_survive_the_wire() -> void:
	var w: SimWorld = K.world()
	var core: int = K.core_slot(w)
	w.shields()._charge[core] = 100.0
	var _id: int = K.shot(w, core)
	var _n: int = K.absorb(w)
	var events: Array[SimEvent] = w.drain_events()
	var aud: EventAudience = EventAudience.new(Roster.new())
	aud.unfiltered = true
	var router: EventRouter = EventRouter.new()
	var auds: Array[EventAudience] = [aud]
	router.route(w.tick(), events, auds)
	var out: Array[WireEvent] = []
	for p: PackedByteArray in aud.outbox:
		assert_int(EventCodec.decode(p, out)).is_greater_equal(0)
	var collapse: int = -1
	var alert_subject: int = -1
	for we: WireEvent in out:
		if we.kind == SimEvent.Kind.SHIELD_COLLAPSE:
			collapse = we.v[0]
		elif we.kind == SimEvent.Kind.ALERT and we.v[0] == AlertKind.Kind.CORE_SHIELD_DOWN:
			alert_subject = we.v[1]
	assert_int(collapse).is_equal(core)                                               # 04 s3.6: structure u16
	assert_int(alert_subject).is_equal(core)                                          # subject = the Core
