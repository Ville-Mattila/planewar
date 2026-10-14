extends GdUnitTestSuite
## 05 s11.2 scenarios of AI-08 through SimWorld.step() with an AiDriver hook (OverlayKit): SC-11 (SAFETY pull-up
## after a release in a dive), SC-12 (SAFETY low-fuel RETURN request), SC-22 (hand-over LINK_BRIDGE), SC-23 (hard
## ceiling release and RECOVER_CEILING), SC-25 (silent pilot: 10 decayed ticks, then Assist.link_bridge). Flat datum
## (the scenario map recipe is tiny_test, not built yet); the cradle bridge window is test_assist.gd. "Survives" =
## alive, no hull damage, the centre never closer to the terrain than the bounding radius (no contact).


func _st(d: AiDriver, id: int) -> int:
	return EntityId.slot(id)


## Possesses `id` for slot 0 and flies `ticks` of scripted pilot inputs (thrust, pitch); returns the events.
func _fly(w: SimWorld, ticks: int, thrust: float, pitch: float) -> Array[SimEvent]:
	var out: Array[SimEvent] = []
	for _k: int in ticks:
		OverlayKit.pilot(w, 0, thrust, pitch)
		w.step()
		out.append_array(w.drain_events())
	return out


# SC-11 release_terrain_imminent: possessed Dart, scripted inputs dive at 190 m/s (30 degrees); release at 150 m AGL.
# Pass: PULL_UP within 1 tick of the release; survives; the overlay ends with TTI >= 4 s.
func test_sc11_release_terrain_imminent() -> void:
	var w: SimWorld = OverlayKit.world(11)
	var d: AiDriver = OverlayKit.driver(w)
	var p0: Vector3 = OverlayKit.at(700.0)
	var fwd: Vector3 = OverlayKit.dive_dir(p0, 30.0)
	var id: int = OverlayKit.spawn(w, &"dart", p0, fwd * 190.0, fwd)
	assert_bool(d.register(id, OverlayKit.CLS_DART)).is_true()
	OverlayKit.ok(w, Command.possess(0, id))
	w.step()
	var guard: int = 0
	while OverlayKit.agl(w, id) > 150.0 and guard < 300:
		var _e: Array[SimEvent] = _fly(w, 1, 0.0, 0.0)
		guard += 1
	OverlayKit.ok(w, Command.release(0))
	w.step()
	var t_rel: int = w.tick()
	assert_int(OverlayKit.of_kind(w.drain_events(), SimEvent.Kind.RELEASED).size()).is_equal(1)
	var s: int = EntityId.slot(id)
	var pull_tick: int = t_rel if (d.state.ov_flags[s] & AiState.OV_PULL_UP) != 0 else -1
	var min_agl: float = OverlayKit.agl(w, id)
	var ticks: int = 0
	while d.state.overlay[s] != Overlays.NONE and ticks < 600:
		w.step()
		var _ev: Array[SimEvent] = w.drain_events()
		ticks += 1
		min_agl = minf(min_agl, OverlayKit.agl(w, id))
		if pull_tick < 0 and (d.state.ov_flags[s] & AiState.OV_PULL_UP) != 0:
			pull_tick = w.tick()
	var what: String = "SC-11: pull-up at +%d ticks, overlay %d ticks, min AGL %.1f m, end TTI %.2f s, hp %.2f" % [
		pull_tick - t_rel, ticks, min_agl, d.state.tti[s], w.view().hp01(id)]
	print(what)
	assert_int(pull_tick).override_failure_message(what).is_between(t_rel, t_rel + 1)
	assert_int(d.state.overlay[s]).override_failure_message(what).is_equal(Overlays.NONE)
	assert_float(d.state.tti[s]).override_failure_message(what).is_greater_equal(4.0)
	assert_bool(w.view().alive(id)).override_failure_message(what).is_true()
	assert_float(w.view().hp01(id)).override_failure_message(what).is_equal(1.0)
	assert_float(min_agl).override_failure_message(what).is_greater(OverlayKit.ship(&"dart").bounding_radius)


# SC-12 release_low_fuel_forces_return: possessed Dart at 15 % fuel with a saved PATROL; on release SAFETY asks for a
# system RETURN in front of the resumed queue, once. Pass here: exactly one ORDER RETURN with FLAG_PREPEND for that
# Dart, from the SAFETY overlay of the release tick, and PATROL still the resumed head. The sim verdict and the
# queue after it are reported: SimSink.submit validates as a client (OrderRules from_client, issuer = cmd.player),
# so FLAG_PREPEND / issuer -1 is refused (MODULE.md open item, needs sim); "docks" needs AI-09 / AI-13.
func test_sc12_release_low_fuel_forces_return() -> void:
	var w: SimWorld = OverlayKit.world(12)
	var d: AiDriver = OverlayKit.driver(w)
	var rec: RecordingHook = RecordingHook.new(d)
	w.set_ai_hook(rec)
	var p0: Vector3 = OverlayKit.at(600.0)
	var fwd: Vector3 = OverlayKit.dive_dir(p0, 0.0)
	var id: int = OverlayKit.spawn(w, &"dart", p0, fwd * 110.0, fwd)
	assert_bool(d.register(id, OverlayKit.CLS_DART)).is_true()
	var patrol: OrderSpec = OrderSpec.make(OrderSpec.Kind.PATROL)
	patrol.points = PackedVector3Array([OverlayKit.at(600.0, 800.0), OverlayKit.at(600.0, -800.0)])
	OverlayKit.ok(w, Command.order(0, PackedInt32Array([id]), patrol))
	OverlayKit.ok(w, CommandPayload.debug_set(0, id, CommandPayload.SET_FUEL, 0.15 * OverlayKit.ship(&"dart").fuel_s))
	w.step()
	OverlayKit.ok(w, Command.possess(0, id))
	w.step()
	var _e: Array[SimEvent] = _fly(w, 15, 0.5, 0.0)
	rec.clear()
	OverlayKit.ok(w, Command.release(0))
	w.step()
	var t_rel: int = w.tick()
	assert_int(w.view().order_head(id).kind).is_equal(OrderSpec.Kind.PATROL)
	assert_int(d.state.overlay[EntityId.slot(id)]).is_equal(Overlays.SAFETY)
	for _k: int in 90:
		w.step()
	var orders: Array[Command] = rec.orders()
	assert_int(orders.size()).is_equal(1)
	assert_int(rec.order_ticks[0]).is_equal(t_rel)
	var spec: OrderSpec = OrderSpec.new()
	var ids: PackedInt32Array = PackedInt32Array()
	assert_bool(CommandPayload.read_order(orders[0], spec, ids)).is_true()
	assert_int(spec.kind).is_equal(OrderSpec.Kind.RETURN)
	assert_int(spec.flags).is_equal(OrderSpec.FLAG_PREPEND)
	assert_array(Array(ids)).is_equal([id])
	assert_int(orders[0].player).is_equal(0)
	print("SC-12: RETURN request verdict %d (needs sim: a system path for FLAG_PREPEND / issuer -1), head now %d" % [
		rec.codes[0], w.view().order_head(id).kind])


# SC-22 handover_during_dive: p (0) possesses a Dart in a 30 degree dive at 400 m AGL; q (3) requests, p hands over;
# q's first input arrives 9 ticks later. Pass: LINK_BRIDGE on for <= 9 ticks and flown by Assist.link_bridge (the
# entity input is the bridge's, not neutral); no terrain contact; possessor = q throughout.
func test_sc22_handover_during_dive() -> void:
	var w: SimWorld = OverlayKit.world(22)
	var _d: AiDriver = OverlayKit.driver(w)
	var p0: Vector3 = OverlayKit.at(400.0)
	var fwd: Vector3 = OverlayKit.dive_dir(p0, 30.0)
	var dart: ShipDef = OverlayKit.ship(&"dart")
	var id: int = OverlayKit.spawn(w, &"dart", p0, fwd * dart.v_cruise, fwd)
	OverlayKit.ok(w, Command.possess(0, id))
	w.step()
	OverlayKit.ok(w, CommandPayload.simple(OverlayKit.MATE, Command.Kind.REQUEST_POSSESS, id))
	var _a: Array[SimEvent] = _fly(w, 1, 0.5, 0.0)
	OverlayKit.ok(w, CommandPayload.handover(0, id, OverlayKit.MATE))
	w.step()
	var ev: Array[SimEvent] = w.drain_events()
	assert_int(OverlayKit.of_kind(ev, SimEvent.Kind.HANDOVER).size()).is_equal(1)
	var bridge_ticks: int = 1 if OverlayKit.overlay(w, id) == ControlMachine.Overlay.LINK_BRIDGE else 0
	var min_agl: float = OverlayKit.agl(w, id)
	var min_thrust: float = OverlayKit.entity_input(w, id).thrust
	var g: FlightGains = OverlayKit.overlay_params(&"dart").bridge.gains
	var q_in: PilotInput = PilotInput.new()
	var integ: Vector2 = Vector2.ZERO
	for k: int in 300:
		if k >= 8:   # q's first input lands 9 ticks after the hand-over tick; q pulls out to level flight at cruise
			var v: SimView = w.view()
			var up: Vector3 = v.pos(id).normalized()
			var level: Vector3 = (v.vel(id) - up * v.vel(id).dot(up)).normalized() * dart.v_cruise
			integ = FlightController.track_velocity(v.basis(id), v.vel(id), level, up, g, integ, q_in)
			OverlayKit.ok(w, Command.pilot(OverlayKit.MATE, w.tick() + 1, q_in))
		w.step()
		var _ev: Array[SimEvent] = w.drain_events()
		min_agl = minf(min_agl, OverlayKit.agl(w, id))
		assert_int(w.view().possessor(id)).is_equal(OverlayKit.MATE)
		if OverlayKit.overlay(w, id) == ControlMachine.Overlay.LINK_BRIDGE:
			bridge_ticks += 1
			min_thrust = minf(min_thrust, OverlayKit.entity_input(w, id).thrust)
	var what: String = "SC-22: bridge %d ticks, min thrust under the bridge %.2f, min AGL %.1f m" % [bridge_ticks,
		min_thrust, min_agl]
	print(what)
	assert_int(bridge_ticks).override_failure_message(what).is_between(1, 9)
	assert_float(min_thrust).override_failure_message(what).is_greater(0.0)
	assert_float(min_agl).override_failure_message(what).is_greater(dart.bounding_radius)
	assert_float(w.view().hp01(id)).override_failure_message(what).is_equal(1.0)


# SC-23 hard_ceiling_release: a possessed Dart with a saved MOVE zooms through 2,000 m. Pass: RELEASED(CEILING) and
# CEILING_RELEASE on the first control check at >= 2,000 m; POSSESS at ~1,960 m returns REJECTED_UPLINK;
# RECOVER_CEILING descends to <= 1,400 m and ends; the saved MOVE is the head again (ORDERED) and the brain is woken.
func test_sc23_hard_ceiling_release() -> void:
	var w: SimWorld = OverlayKit.world(23)
	var d: AiDriver = OverlayKit.driver(w)
	var p0: Vector3 = OverlayKit.at(1880.0)
	var fwd: Vector3 = OverlayKit.dive_dir(p0, -60.0)
	var id: int = OverlayKit.spawn(w, &"dart", p0, fwd * 160.0, fwd)
	assert_bool(d.register(id, OverlayKit.CLS_DART)).is_true()
	var move: OrderSpec = OrderSpec.make(OrderSpec.Kind.MOVE, 0, OverlayKit.at(600.0, 3000.0))
	OverlayKit.ok(w, Command.order(0, PackedInt32Array([id]), move))
	OverlayKit.ok(w, Command.possess(0, id))
	w.step()
	assert_int(w.view().control_state(id)).is_equal(ControlMachine.State.POSSESSED)
	var crossed: int = -1
	var released: int = -1
	var guard: int = 0
	while released < 0 and guard < 300:
		if crossed < 0 and w.view().pos(id).length() - Sphere.PLANET_RADIUS >= 2000.0:
			crossed = w.tick()
		var ev: Array[SimEvent] = _fly(w, 1, 1.0, 0.0)
		for e: SimEvent in OverlayKit.of_kind(ev, SimEvent.Kind.RELEASED):
			assert_int(e.extra[0]).is_equal(ControlMachine.ReleaseReason.CEILING)
			released = e.tick
			assert_int(OverlayKit.of_kind(ev, SimEvent.Kind.CEILING_RELEASE).size()).is_equal(1)
		guard += 1
	assert_int(released).is_equal(crossed + 1)        # the first step whose control check sees >= 2,000 m
	var s: int = EntityId.slot(id)
	assert_int(d.state.overlay[s]).is_equal(Overlays.RECOVER_CEILING)
	var refused: bool = false
	var ticks: int = 0
	var max_alt: float = 0.0
	while d.state.overlay[s] != Overlays.NONE and ticks < 3000:
		var alt: float = w.view().pos(id).length() - Sphere.PLANET_RADIUS
		max_alt = maxf(max_alt, alt)
		if not refused and alt <= 1970.0 and alt >= 1950.0:
			assert_int(w.apply_command(Command.possess(0, id)).code).is_equal(CommandResult.Code.REJECTED_UPLINK)
			refused = true
		w.step()
		var _ev: Array[SimEvent] = w.drain_events()
		ticks += 1
	var end_alt: float = w.view().pos(id).length() - Sphere.PLANET_RADIUS
	var what: String = "SC-23: released t=%d (crossed %d), peak %.0f m, recovered in %.1f s to %.0f m" % [released,
		crossed, max_alt, float(ticks) / 30.0, end_alt]
	print(what)
	assert_bool(refused).override_failure_message(what).is_true()
	assert_int(d.state.overlay[s]).override_failure_message(what).is_equal(Overlays.NONE)
	assert_float(end_alt).override_failure_message(what).is_less_equal(1400.0)
	assert_int(w.view().control_state(id)).is_equal(ControlMachine.State.ORDERED)
	assert_int(w.view().order_head(id).kind).is_equal(OrderSpec.Kind.MOVE)
	assert_int(d.state.wake_pending[s]).is_equal(1)


# SC-25 input_starvation_bridge: a possessed Dart's inputs stop for 70 ticks (still connected). Pass: silent ticks
# 1-10 fly the last input with the axes halved per tick, thrust and BOOST held, FIRE cleared (A-44); LINK_BRIDGE from
# silent tick 11 with one ALERT(LINK_WEAK), flown by Assist.link_bridge (the entity input equals the pure function
# on the pre-step state); inputs resume -> overlay cleared the same tick; POSSESSED throughout.
func test_sc25_input_starvation_bridge() -> void:
	var w: SimWorld = OverlayKit.world(25)
	var _d: AiDriver = OverlayKit.driver(w)
	var p0: Vector3 = OverlayKit.at(500.0)
	var fwd: Vector3 = OverlayKit.dive_dir(p0, 0.0)
	var id: int = OverlayKit.spawn(w, &"dart", p0, fwd * 110.0, fwd)
	OverlayKit.ok(w, Command.possess(0, id))
	w.step()
	var last: PilotInput = PilotInput.new()
	last.thrust = 0.8
	last.pitch = 0.4
	last.yaw = -0.2
	last.roll = 0.6
	last.buttons = PilotInput.BOOST | PilotInput.FIRE1
	for _k: int in 5:
		OverlayKit.ok(w, Command.pilot(0, w.tick() + 1, last))
		w.step()
	var _e: Array[SimEvent] = w.drain_events()
	var c: ContentSet = OverlayKit.content()
	var bp: BridgeParams = BridgeParams.table(c, c.rules, c.rules.tick_hz)[0]
	var probe: ProbeResult = ProbeResult.new()
	var want: PilotInput = PilotInput.new()
	var alerts: int = 0
	var min_agl: float = INF
	for k: int in range(1, 71):
		var v: SimView = w.view()
		Assist.link_bridge(v.basis(id), v.pos(id), v.vel(id), w.terrain(), bp, probe, want)
		w.step()
		alerts += OverlayKit.of_kind(w.drain_events(), SimEvent.Kind.ALERT).size()
		min_agl = minf(min_agl, OverlayKit.agl(w, id))
		var got: PilotInput = OverlayKit.entity_input(w, id)
		var tag: String = "silent tick %d" % k
		assert_int(w.view().control_state(id)).override_failure_message(tag).is_equal(ControlMachine.State.POSSESSED)
		if k <= ControlMachine.DECAY_TICKS:
			assert_int(OverlayKit.overlay(w, id)).override_failure_message(tag).is_equal(ControlMachine.Overlay.NONE)
			assert_float(got.pitch).override_failure_message(tag).is_equal_approx(0.4 * pow(0.5, k), 1e-9)
			assert_float(got.thrust).override_failure_message(tag).is_equal_approx(0.8, 1e-9)
			assert_int(got.buttons).override_failure_message(tag).is_equal(PilotInput.BOOST)
		else:
			assert_int(OverlayKit.overlay(w, id)).override_failure_message(tag).is_equal(ControlMachine.Overlay.LINK_BRIDGE)
			assert_float(got.thrust).override_failure_message(tag).is_equal(want.thrust)
			assert_float(got.pitch).override_failure_message(tag).is_equal(want.pitch)
			assert_float(got.yaw).override_failure_message(tag).is_equal(want.yaw)
			assert_float(got.roll).override_failure_message(tag).is_equal(want.roll)
			assert_int(got.buttons).override_failure_message(tag).is_equal(want.buttons)
	assert_int(alerts).is_equal(1)
	assert_float(min_agl).is_greater(OverlayKit.ship(&"dart").bounding_radius)
	OverlayKit.pilot(w, 0, 0.5, 0.0)
	w.step()
	assert_int(OverlayKit.overlay(w, id)).is_equal(ControlMachine.Overlay.NONE)
	assert_int(w.view().control_state(id)).is_equal(ControlMachine.State.POSSESSED)
	assert_float(OverlayKit.entity_input(w, id).thrust).is_equal_approx(0.5, 1e-9)


# Step 4 beyond ships in flight (AssistStep): a silent pilot's Harvester under LINK_BRIDGE stops (thrust 0, no BRAKE
# so it never reverses); a DOCKED Dart under LINK_BRIDGE keeps the decayed input (no pull-up off the pad).
func test_step4_ground_unit_stops_and_docked_ship_keeps_its_input() -> void:
	var w: SimWorld = OverlayKit.world(4)
	var _d: AiDriver = OverlayKit.driver(w)
	var p0: Vector3 = OverlayKit.at(0.0)
	var g: int = OverlayKit.spawn(w, &"harvester", p0, Vector3.ZERO, OverlayKit.dive_dir(p0, 0.0))
	var p1: Vector3 = OverlayKit.at(8.0, 300.0)
	var dart: int = OverlayKit.spawn(w, &"dart", p1, Vector3.ZERO, p1.normalized())
	w.store().flags[EntityId.slot(dart)] |= EntityStore.F_DOCKED
	OverlayKit.ok(w, Command.possess(0, g))
	OverlayKit.ok(w, Command.possess(OverlayKit.MATE, dart))
	w.step()
	OverlayKit.pilot(w, 0, 0.8, 0.0)
	OverlayKit.pilot(w, OverlayKit.MATE, 0.4, 0.0)
	w.step()
	for _k: int in ControlMachine.DECAY_TICKS + 1:
		w.step()
	var _e: Array[SimEvent] = w.drain_events()
	assert_int(OverlayKit.overlay(w, g)).is_equal(ControlMachine.Overlay.LINK_BRIDGE)
	assert_int(OverlayKit.overlay(w, dart)).is_equal(ControlMachine.Overlay.LINK_BRIDGE)
	var gi: PilotInput = OverlayKit.entity_input(w, g)
	assert_float(gi.thrust).is_equal(0.0)
	assert_int(gi.buttons).is_equal(0)
	assert_float(OverlayKit.entity_input(w, dart).thrust).is_equal_approx(0.4, 1e-9)


# Determinism and S4: a world with one Dart in SAFETY (released in a dive) and one under LINK_BRIDGE (its pilot
# silent) is run twice from scratch -> identical bytes; serialized mid-overlay and mid-bridge, restored into a fresh
# world with a freshly configured AiDriver, both continue 120 ticks -> identical bytes (03 S4, the hook's AiState
# blob included).
func test_overlays_deterministic_and_s4() -> void:
	var a: Array = _overlay_world(31)
	var b: Array = _overlay_world(31)
	var wa: SimWorld = a[0]
	var wb: SimWorld = b[0]
	assert_bool(wa.serialize() == wb.serialize()).is_true()
	var da: AiDriver = a[1]
	var safety: int = a[2]
	var bridged: int = a[3]
	assert_int(da.state.overlay[EntityId.slot(safety)]).is_equal(Overlays.SAFETY)
	assert_int(OverlayKit.overlay(wa, bridged)).is_equal(ControlMachine.Overlay.LINK_BRIDGE)
	var bytes: PackedByteArray = wa.serialize()
	var d2: AiDriver = AiDriver.new(Rng.new(99))
	d2.set_overlay_params(OverlayKit.CLS_DART, OverlayKit.overlay_params(&"dart"))
	var w2: SimWorld = SimWorld.deserialize(bytes, OverlayKit.content(), d2)
	assert_object(w2).is_not_null()
	d2.set_terrain(w2.terrain())
	assert_bool(w2.serialize() == bytes).is_true()
	for _k: int in 120:
		wa.step()
		w2.step()
		var _x: Array[SimEvent] = wa.drain_events()
		var _y: Array[SimEvent] = w2.drain_events()
	assert_bool(w2.serialize() == wa.serialize()).is_true()
	assert_int(d2.state.overlay[EntityId.slot(safety)]).is_equal(da.state.overlay[EntityId.slot(safety)])


# [world, driver, released Dart, bridged Dart] at the tick where both overlays run.
func _overlay_world(seed_value: int) -> Array:
	var w: SimWorld = OverlayKit.world(seed_value)
	var d: AiDriver = OverlayKit.driver(w)
	var p0: Vector3 = OverlayKit.at(500.0)
	var fwd: Vector3 = OverlayKit.dive_dir(p0, 30.0)
	var a: int = OverlayKit.spawn(w, &"dart", p0, fwd * 150.0, fwd)
	var p1: Vector3 = OverlayKit.at(700.0, 900.0)
	var level: Vector3 = OverlayKit.dive_dir(p1, 0.0)
	var b: int = OverlayKit.spawn(w, &"dart", p1, level * 110.0, level)
	var _r1: bool = d.register(a, OverlayKit.CLS_DART)
	var _r2: bool = d.register(b, OverlayKit.CLS_DART)
	OverlayKit.ok(w, Command.possess(0, a))
	OverlayKit.ok(w, Command.possess(OverlayKit.MATE, b))
	w.step()
	OverlayKit.pilot(w, OverlayKit.MATE, 0.7, 0.2)
	var _e: Array[SimEvent] = _fly(w, 30, 0.0, 0.0)
	OverlayKit.ok(w, Command.release(0))
	w.step()
	var _f: Array[SimEvent] = w.drain_events()
	return [w, d, a, b]


## Wraps the AiDriver and hands it a sink that records every submitted command, its tick and the sim's verdict.
class RecordingHook extends SimAiHook:
	var inner: AiDriver
	var sink: RecordingSink = RecordingSink.new()
	var order_ticks: PackedInt32Array = PackedInt32Array()
	var codes: PackedInt32Array = PackedInt32Array()

	func _init(d: AiDriver) -> void:
		inner = d

	func on_tick(tick: int, view: SimView, s: CommandSinkBase) -> void:
		sink.inner = s
		sink.tick = tick
		inner.on_tick(tick, view, sink)

	func serialize() -> PackedByteArray:
		return inner.serialize()

	func deserialize(bytes: PackedByteArray) -> void:
		inner.deserialize(bytes)

	func clear() -> void:
		sink.cmds.clear()
		sink.ticks.clear()
		sink.codes.clear()

	func orders() -> Array[Command]:
		order_ticks = sink.ticks
		codes = sink.codes
		return sink.cmds


class RecordingSink extends CommandSinkBase:
	var inner: CommandSinkBase = null
	var tick: int = 0
	var cmds: Array[Command] = []
	var ticks: PackedInt32Array = PackedInt32Array()
	var codes: PackedInt32Array = PackedInt32Array()

	func submit(cmd: Command) -> CommandResult:
		var r: CommandResult = inner.submit(cmd)
		cmds.append(cmd)
		var _a: bool = ticks.push_back(tick)
		var _b: bool = codes.push_back(r.code)
		return r

	func drive(id: int, input: PilotInput) -> bool:
		return inner.drive(id, input)

	func set_ai_tag(id: int, tag: int) -> void:
		inner.set_ai_tag(id, tag)

	func pathing() -> Pathing:
		return inner.pathing()
