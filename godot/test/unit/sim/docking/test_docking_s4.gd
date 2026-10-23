extends GdUnitTestSuite
## GD-15 S4 (sim/MODULE.md S4, format 13): the Docking state (pad queue, per-ship service record, landing log, pilot
## track) is in the economy section. A world mid-service (a ship docked by a real landing, refuel / rearm / repair
## running, Ice running short so a timer pauses), with a queue (two RETURN ships at the busy pad), a possessed ship
## tracked for the manual flag and a second ship about to land on another pad, is saved at several ticks; every save
## reloads to the same bytes and the reloaded world then steps byte-identically to the original, events included.
## A format-12 file is refused.

const SAVE_TICKS: PackedInt32Array = [3, 11, 29, 47, 90]
const CONTINUE: int = 240
const CHECK_EVERY: int = 20


func _scene() -> SimWorld:
	var w: SimWorld = WorldTestKit.world(31)
	var pad: int = DockingTestKit.pad(w)
	var pad2: int = DockingTestKit.pad(w, &"pad", 0, 0, 900.0)
	var sd: ShipDef = DockingTestKit.ship_def(&"lancer")
	var up: Vector3 = w.store().up[EntityId.slot(pad)]
	var a: int = DockingTestKit.ship_over(w, &"lancer", 0, 0, pad, sd.bounding_radius, 0.0, -up * 3.0)
	var s: int = EntityId.slot(a)
	w.store().fuel[s] = 0.0
	w.store().ammo[s] = 0
	w.store().rockets[s] = 0
	w.store().hp[s] = float(sd.hp) * 0.3
	w.step()                                                   # lands for real: LANDING AUTO, DOCKED
	assert_int(w.view().dock_state(a)).is_equal(2)
	for k: int in 2:
		var b: int = DockingTestKit.ship_over(w, &"dart", 0, 0, pad, DockingTestKit.HIGH)
		var spec: OrderSpec = OrderSpec.make(OrderSpec.Kind.RETURN)
		assert_int(w.apply_command(Command.order(0, PackedInt32Array([b]), spec)).code).is_equal(CommandResult.Code.ACCEPTED)
		w.step()
		DockingTestKit.pose(w, b, pad, 120.0, 40.0 - 80.0 * float(k), Vector3.ZERO)
	var c: int = DockingTestKit.ship_over(w, &"dart", 2, 0, pad, DockingTestKit.HIGH)
	DockingTestKit.pose(w, c, pad, 200.0, 600.0, Vector3.ZERO)
	var d: int = DockingTestKit.ship_over(w, &"scout", 0, 0, pad2, 40.0, 0.0, -up * 2.0)
	assert_int(d).is_not_equal(0)
	w._players.team_ice[0] = 8                                 # the first Ice pays, then the pool runs dry: a pause
	w._players.kind[2] = PlayerTable.KIND_HUMAN
	assert_bool(DockingTestKit.possess(w, c, 2)).is_true()
	var _e: Array[SimEvent] = w.drain_events()
	return w


static func _event_bytes(events: Array[SimEvent]) -> PackedByteArray:
	var b: StreamPeerBuffer = StreamPeerBuffer.new()
	for e: SimEvent in events:
		b.put_u8(e.kind)
		b.put_32(e.tick)
		b.put_32(e.a)
		b.put_32(e.b)
		b.put_double(e.value)
		b.put_32(e.team)
		b.put_var(e.extra)
	return b.data_array


func test_mid_service_saves_reload_byte_exact_and_continue_identically() -> void:
	var w: SimWorld = _scene()
	var c: ContentSet = WorldTestKit.content()
	var t0: int = w.tick()
	var paused: bool = false
	var queued: bool = false
	var landed_later: bool = false
	for k: int in SAVE_TICKS.size():
		while w.tick() < t0 + SAVE_TICKS[k]:
			w.step()
			var ev: Array[SimEvent] = w.drain_events()
			for e: SimEvent in ev:
				paused = paused or (e.kind == SimEvent.Kind.ALERT and e.a == AlertKind.Kind.WAITING_FOR_ICE)
		queued = queued or w.economy().docking.queue.q_ship.size() == 2
		var bytes: PackedByteArray = w.serialize()
		var r: SimWorld = SimWorld.deserialize(bytes, c, null)
		assert_object(r).is_not_null()
		assert_bool(r.serialize() == bytes).override_failure_message("reload at +%d differs" % SAVE_TICKS[k]).is_true()
		var copy: SimWorld = SimWorld.deserialize(bytes, c, null)
		for t: int in CONTINUE:
			copy.step()
			r.step()
			var e1: Array[SimEvent] = copy.drain_events()
			var e2: Array[SimEvent] = r.drain_events()
			assert_bool(_event_bytes(e1) == _event_bytes(e2)).override_failure_message("events at +%d/%d" % [SAVE_TICKS[k], t]).is_true()
			for e: SimEvent in e1:
				landed_later = landed_later or e.kind == SimEvent.Kind.LANDING
			if t % CHECK_EVERY == 0:
				assert_bool(SimSerialize.write_raw(copy) == SimSerialize.write_raw(r)).override_failure_message("raw at +%d/%d" % [SAVE_TICKS[k], t]).is_true()
		assert_bool(copy.serialize() == r.serialize()).is_true()
	assert_bool(paused).override_failure_message("no service pause happened in the scene").is_true()
	assert_bool(queued).override_failure_message("the queue never held both waiters").is_true()
	assert_bool(landed_later).override_failure_message("no landing happened after a reload").is_true()


func test_the_format_is_13_and_a_format_12_file_is_refused() -> void:
	assert_int(SimSerialize.FORMAT).is_equal(13)
	var w: SimWorld = _scene()
	var bytes: PackedByteArray = w.serialize()
	assert_int(SimSerialize.check(bytes)).is_equal(SimSerialize.Status.OK)
	var old: PackedByteArray = bytes.duplicate()
	old.encode_u32(4, 12)
	assert_int(SimSerialize.check(old)).is_equal(SimSerialize.Status.OLD_FORMAT)
	assert_object(SimWorld.deserialize(old, WorldTestKit.content(), null)).is_null()


func test_a_corrupt_docking_section_is_refused() -> void:
	var w: SimWorld = _scene()
	assert_int(w.economy().docking.queue.q_ship.size()).is_greater(0)
	w.economy().docking.queue.q_ship[0] = 0                     # a queue entry naming no ship
	var bytes: PackedByteArray = w.serialize()
	assert_object(SimWorld.deserialize(bytes, WorldTestKit.content(), null)).is_null()
