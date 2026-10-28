extends GdUnitTestSuite
## GD-15 S4 (sim/MODULE.md S4, format 13+; sim/docking/MODULE.md D11): the Docking state (pad queue, per-ship service
## record, landing log, pilot track) is in the economy section. The original world is run straight through once as the
## reference (the combat/test_fire_s4_exact.gd pattern): its per-tick event bytes and, every CHECK_EVERY ticks, its raw
## state bytes plus the Docking reads of SimView. At each save point the save is reloaded (same bytes again on
## re-serialize) and the reloaded world is continued and compared with the reference, not with a second reload, so
## state left out of the save shows up as a divergence. The scene makes each part matter after a reload:
##   service  - Lancer A, docked by a real landing, mid-service with the Ice pool running dry (a pause + ALERT);
##   queue    - two RETURN Darts hovering at A's busy pad, the higher slot queued first (arrival order != slot order);
##   landings - A's AUTO grade, read back through SimView.landing_grade_last at every checkpoint;
##   pilots   - Dart C possessed far from pad 2, then flown (scripted poses, live PILOT_INPUT) inside 150 m of pad 2 and
##              landed there at LAND_AT: manual only if its last non-human tick is remembered across the reload.
## A format-12 file and a corrupt Docking section are refused. Mutation check (GD-15 PR): leaving any one of queue,
## service, landings or pilots out of Docking.write_state / read_state fails test_reload_continues_like_the_original.

const SAVE_TICKS: PackedInt32Array = [3, 11, 29, 47, 90]
const CONTINUE: int = 240
const CHECK_EVERY: int = 10
const LAND_AT: int = 200           ## relative tick C is put on pad 2 (inside every save's CONTINUE window)
const HOVER_ALT: float = 60.0
const HOVER_OFF: float = 100.0     ## C's hover offset from pad 2 (inside the 150 m manual window)
const FAR_OFF: float = 600.0


class Scene:
	var w: SimWorld
	var pad: int
	var pad2: int
	var a: int
	var waiters: PackedInt32Array = PackedInt32Array()
	var c: int
	var t0: int


class Ref:
	var events: Dictionary = {}     ## tick -> event bytes of that tick
	var checks: Dictionary = {}     ## tick -> raw state bytes + Docking reads
	var saves: Array[PackedByteArray] = []
	var paused: bool = false
	var queued_out_of_slot_order: int = 0
	var manual_landing_tick: int = -1


func _scene() -> Scene:
	var sc: Scene = Scene.new()
	var w: SimWorld = WorldTestKit.world(31)
	sc.w = w
	sc.pad = DockingTestKit.pad(w)
	sc.pad2 = DockingTestKit.pad(w, &"pad", 0, 0, 900.0)
	var sd: ShipDef = DockingTestKit.ship_def(&"lancer")
	var up: Vector3 = w.store().up[EntityId.slot(sc.pad)]
	sc.a = DockingTestKit.ship_over(w, &"lancer", 0, 0, sc.pad, sd.bounding_radius, 0.0, -up * 3.0)
	var s: int = EntityId.slot(sc.a)
	w.store().fuel[s] = 0.0
	w.store().ammo[s] = 0
	w.store().rockets[s] = 0
	w.store().hp[s] = float(sd.hp) * 0.3
	w.step()                                                   # lands for real: LANDING AUTO, DOCKED
	assert_int(w.view().dock_state(sc.a)).is_equal(2)
	for k: int in 2:
		var b: int = DockingTestKit.ship_over(w, &"dart", 0, 0, sc.pad, DockingTestKit.HIGH, FAR_OFF + 100.0 * float(k))
		var spec: OrderSpec = OrderSpec.make(OrderSpec.Kind.RETURN)
		assert_int(w.apply_command(Command.order(0, PackedInt32Array([b]), spec)).code).is_equal(CommandResult.Code.ACCEPTED)
		var _x: bool = sc.waiters.push_back(b)
	w.step()                                                   # the orders apply; both still far above
	_hover_waiter(w, sc.pad, sc.waiters[1], 1)                 # the higher slot arrives first
	w.step()
	_hover_waiter(w, sc.pad, sc.waiters[0], 0)
	w.step()
	sc.c = DockingTestKit.ship_over(w, &"dart", 2, 0, sc.pad2, HOVER_ALT, FAR_OFF)
	w._players.team_ice[0] = 8                                 # the first Ice pays, then the pool runs dry: a pause
	w._players.kind[2] = PlayerTable.KIND_HUMAN
	assert_bool(DockingTestKit.possess(w, sc.c, 2)).is_true()  # the autopilot's last tick: 600 m from pad 2
	var _e: Array[SimEvent] = w.drain_events()
	sc.t0 = w.tick()
	return sc


func _hover_waiter(w: SimWorld, pad: int, id: int, k: int) -> void:
	DockingTestKit.pose(w, id, pad, 120.0, 40.0 - 80.0 * float(k), Vector3.ZERO)


# The scripted inputs of the tick about to run (identical in the reference and in every reloaded world, keyed on the
# absolute tick): the waiters hover in the queue zone, C's pilot sends live input and hovers C 100 m from pad 2 until
# LAND_AT, where C is set down tail-down at 2 m/s.
func _script(sc: Scene, w: SimWorld) -> void:
	var rel: int = w.tick() + 1 - sc.t0
	for k: int in sc.waiters.size():
		if w.view().alive(sc.waiters[k]) and w.view().dock_state(sc.waiters[k]) == 0:
			_hover_waiter(w, sc.pad, sc.waiters[k], k)
	var inp: PilotInput = PilotInput.new()
	var _r: CommandResult = w.apply_command(Command.pilot(2, w.tick() + 1, inp))
	if w.view().dock_state(sc.c) != 0:
		return
	if rel < LAND_AT:
		DockingTestKit.pose(w, sc.c, sc.pad2, HOVER_ALT, HOVER_OFF, Vector3.ZERO)
	elif rel == LAND_AT:
		var sd: ShipDef = DockingTestKit.ship_def(&"dart")
		DockingTestKit.pose(w, sc.c, sc.pad2, sd.bounding_radius, 0.0, -w.store().up[EntityId.slot(sc.pad2)] * 2.0)


static func _event_bytes(events: Array[SimEvent]) -> PackedByteArray:
	var b: StreamPeerBuffer = StreamPeerBuffer.new()
	for e: SimEvent in events:
		b.put_var([e.kind, e.tick, e.a, e.b, e.pos, e.value, e.team, e.extra])
	return b.data_array


# Raw state plus what SimView reads from Docking (the landing log and the queue are only visible this way).
func _check_bytes(sc: Scene, w: SimWorld) -> PackedByteArray:
	var b: StreamPeerBuffer = StreamPeerBuffer.new()
	b.put_var(SimSerialize.write_raw(w))
	var v: SimView = w.view()
	for id: int in PackedInt32Array([sc.a, sc.c, sc.waiters[0], sc.waiters[1]]):
		b.put_var([v.landing_grade_last(id), v.service_progress(id)])
	b.put_var(v.pad_queue(sc.pad))
	b.put_var(v.pad_queue(sc.pad2))
	return b.data_array


func _step(sc: Scene, w: SimWorld) -> PackedByteArray:
	_script(sc, w)
	w.step()
	return _event_bytes(w.drain_events())


func _reference(sc: Scene) -> Ref:
	var ref: Ref = Ref.new()
	var w: SimWorld = sc.w
	var last: int = sc.t0 + SAVE_TICKS[SAVE_TICKS.size() - 1] + CONTINUE
	var k: int = 0
	while w.tick() < last:
		_script(sc, w)
		w.step()
		var ev: Array[SimEvent] = w.drain_events()
		ref.events[w.tick()] = _event_bytes(ev)
		for e: SimEvent in ev:
			ref.paused = ref.paused or (e.kind == SimEvent.Kind.ALERT and e.a == AlertKind.Kind.WAITING_FOR_ICE)
			if e.kind == SimEvent.Kind.LANDING and e.a == sc.c and (e.extra[2] & 1) != 0:
				ref.manual_landing_tick = w.tick()
		if (w.tick() - sc.t0) % CHECK_EVERY == 0:
			ref.checks[w.tick()] = _check_bytes(sc, w)
		if k < SAVE_TICKS.size() and w.tick() == sc.t0 + SAVE_TICKS[k]:
			ref.saves.append(w.serialize())
			var q: PackedInt32Array = w.view().pad_queue(sc.pad)
			if q.size() == 2 and EntityId.slot(q[0]) > EntityId.slot(q[1]):
				ref.queued_out_of_slot_order += 1
			k += 1
	return ref


func test_reload_continues_like_the_original() -> void:
	var sc: Scene = _scene()
	var ref: Ref = _reference(sc)
	assert_bool(ref.paused).override_failure_message("no service pause happened in the scene").is_true()
	assert_int(ref.queued_out_of_slot_order).override_failure_message("the queue was not out of slot order at every save") \
			.is_equal(SAVE_TICKS.size())
	assert_int(ref.manual_landing_tick).override_failure_message("C never landed manually").is_equal(sc.t0 + LAND_AT)
	var c: ContentSet = WorldTestKit.content()
	for k: int in SAVE_TICKS.size():
		var bytes: PackedByteArray = ref.saves[k]
		var r: SimWorld = SimWorld.deserialize(bytes, c, null)
		assert_object(r).is_not_null()
		assert_bool(r.serialize() == bytes).override_failure_message("reload at +%d differs" % SAVE_TICKS[k]).is_true()
		for t: int in CONTINUE:
			var got: PackedByteArray = _step(sc, r)
			var tick: int = r.tick()
			var want: PackedByteArray = ref.events[tick]
			if got != want:
				fail("save +%d: events differ from the original at +%d" % [SAVE_TICKS[k], tick - sc.t0])
				return
			var want_check: PackedByteArray = ref.checks.get(tick, PackedByteArray())
			if not want_check.is_empty() and _check_bytes(sc, r) != want_check:
				fail("save +%d: state or Docking reads differ from the original at +%d" % [SAVE_TICKS[k], tick - sc.t0])
				return


func test_the_format_has_the_docking_section_and_the_previous_format_is_refused() -> void:
	assert_int(SimSerialize.FORMAT).is_greater_equal(13)                      # 13 added Docking; GD-27 made it 14
	var w: SimWorld = _scene().w
	var bytes: PackedByteArray = w.serialize()
	assert_int(SimSerialize.check(bytes)).is_equal(SimSerialize.Status.OK)
	var old: PackedByteArray = bytes.duplicate()
	old.encode_u32(4, SimSerialize.FORMAT - 1)
	assert_int(SimSerialize.check(old)).is_equal(SimSerialize.Status.OLD_FORMAT)
	assert_object(SimWorld.deserialize(old, WorldTestKit.content(), null)).is_null()


func test_a_corrupt_docking_section_is_refused() -> void:
	var w: SimWorld = _scene().w
	assert_int(w.economy().docking.queue.q_ship.size()).is_greater(0)
	w.economy().docking.queue.q_ship[0] = 0                     # a queue entry naming no ship
	var bytes: PackedByteArray = w.serialize()
	assert_object(SimWorld.deserialize(bytes, WorldTestKit.content(), null)).is_null()

