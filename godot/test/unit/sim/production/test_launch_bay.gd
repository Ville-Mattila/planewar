extends GdUnitTestSuite
## GD-17 (02 s6.4, s2.3, R0 A-82): a produced ship spawns DOCKED on its Shipyard launch pad and leaves on the next tick by
## the LAUNCHED rule; a Dart is above 20 m AGL about 3 s after completion (23 s after its start) at full power; SET_RALLY gives
## the produced unit an ORDERED move to the rally point (ground units at once, ships when they launch).

const K := preload("res://test/unit/sim/economy_test_kit.gd")
const C := CommandResult.Code
const EPS: Vector3 = Vector3(0.001, 0.001, 0.001)


# The Shipyard / Vehicle Bay kit with its start-kit SPAWN events drained (they come with the first step).
func _world() -> SimWorld:
	var w: SimWorld = K.solo_world()
	var _kit: Array[SimEvent] = K.run(w, 1)
	return w


func _yard_id(w: SimWorld) -> int:
	return w.store().id_of(K.find(w, &"shipyard"))


func _pending(w: SimWorld) -> int:
	return w.economy().production.launch.pending()


func _first(events: Array[SimEvent], kind: SimEvent.Kind) -> SimEvent:
	for e: SimEvent in events:
		if e.kind == kind:
			return e
	return null


# Steps until an event of `kind` is seen (at most `limit` ticks); returns it or null.
func _until(w: SimWorld, kind: SimEvent.Kind, limit: int = 4000) -> SimEvent:
	for _i: int in limit:
		var e: SimEvent = _first(K.run(w, 1), kind)
		if e != null:
			return e
	return null


# Holds full thrust on one ship every tick from step 3, like the launch assist will (AI-10).
class ThrustHook extends SimAiHook:
	var target: int = 0
	var input: PilotInput = PilotInput.new()

	func on_tick(_t: int, _v: SimView, sink: CommandSinkBase) -> void:
		input.thrust = 1.0
		if target != 0:
			var _ok: bool = sink.drive(target, input)

	func serialize() -> PackedByteArray:
		return PackedByteArray()

	func deserialize(_bytes: PackedByteArray) -> void:
		pass


func _agl(w: SimWorld, ship: int) -> float:
	var p: Vector3 = w.store().pos[ship]
	return p.length() - Sphere.PLANET_RADIUS - w.view().terrain_height(p.normalized())


func test_dart_is_airborne_23_s_after_its_start_at_full_power() -> void:
	var w: SimWorld = _world()
	var hook: ThrustHook = ThrustHook.new()
	w.set_ai_hook(hook)
	var yard: int = _yard_id(w)
	var hz: int = WorldTestKit.content().rules.tick_hz
	var dart: ShipDef = WorldTestKit.content().ships[K.def(&"dart") - DefRanges.SHIP_BASE]
	assert_float(w.economy().economy.power_ratio(0)).is_equal_approx(1.0, 0.001)
	assert_int(K.code(w, Command.produce(0, yard, K.def(&"dart"), 1))).is_equal(C.ACCEPTED)
	var _first_step: Array[SimEvent] = K.run(w, 1)
	var start: int = w.tick()                                           # the head was paid in this tick
	var spawned: int = -1
	var airborne: int = -1
	var ship: int = -1
	var launched: int = 0
	var parked_alt: float = 0.0
	for _i: int in 26 * hz:
		for e: SimEvent in K.run(w, 1):
			if e.kind == SimEvent.Kind.LAUNCHED:
				launched += 1
			if e.kind == SimEvent.Kind.SPAWN and spawned < 0:
				spawned = w.tick()
				ship = EntityId.slot(e.a)
				hook.target = e.a
		if ship >= 0 and parked_alt == 0.0:
			parked_alt = _agl(w, ship)                                  # the tick it appears, DOCKED on the pad
		if ship >= 0 and airborne < 0:
			if _agl(w, ship) > 20.0:
				airborne = w.tick()
			else:
				assert_float(w.store().hp[ship]).is_equal(float(dart.hp))       # the launch costs no damage (no ram, no terrain hit)
	# Tolerance: +-3 ticks (0.1 s) on the 20 s build, the same slack as test_production's build-time test (float32 progress sum).
	assert_int(spawned - start).is_between(int(dart.build_time_s) * hz - 3, int(dart.build_time_s) * hz + 3)
	# 02 s2.3 / A-82: "airborne (> 20 m AGL) about 3 s after completion"; the window is [completion + 1 tick, completion + 4 s]
	# (about 3 s plus 1 s slack). The measured climb goes into the PR perf note.
	assert_int(airborne - spawned).is_between(1, 4 * hz)
	assert_int(launched).is_equal(1)                                    # exactly one LAUNCHED
	assert_float(parked_alt).is_less_equal(w.store().radius[ship] + 0.5)         # B.5 landing band while DOCKED


func test_ship_waits_on_the_pad_then_leaves_along_the_normal() -> void:
	var w: SimWorld = _world()
	var yard: int = _yard_id(w)
	var ys: int = EntityId.slot(yard)
	var common: FlightCommonDef = WorldTestKit.content().flight_common
	assert_int(K.code(w, Command.produce(0, yard, K.def(&"scout"), 1))).is_equal(C.ACCEPTED)
	assert_object(_until(w, SimEvent.Kind.SPAWN)).is_not_null()
	var ship: int = w.store().ships[0]
	assert_int(w.store().flags[ship] & EntityStore.F_DOCKED).is_equal(EntityStore.F_DOCKED)
	assert_int(w.store().link[ship]).is_equal(yard)
	assert_vector(w.store().fwd[ship]).is_equal_approx(w.store().up[ys], EPS)   # tail-down: nose along the pad normal
	var rel: Vector3 = w.store().pos[ship] - w.store().pos[ys]
	assert_float(rel.dot(w.store().up[ys])).is_equal_approx(w.store().radius[ship], 0.001)   # on the pad plane, resting on it
	assert_float(rel.slide(w.store().up[ys]).length()).is_less(0.001)                        # over the pad centre
	assert_float(w.store().vel[ship].length()).is_equal(0.0)
	assert_int(_pending(w)).is_equal(1)
	var l: SimEvent = _until(w, SimEvent.Kind.LAUNCHED)
	assert_object(l).is_not_null()
	assert_int(l.a).is_equal(w.store().id_of(ship))
	assert_int(l.b).is_equal(yard)
	assert_int(w.store().flags[ship] & EntityStore.F_DOCKED).is_equal(0)
	assert_float(w.store().vel[ship].length()).is_equal_approx(common.launch_speed_mps, 0.5)   # the launch step itself
	assert_float(w.store().vel[ship].normalized().dot(w.store().up[ys])).is_greater(0.99)
	assert_int(w.store().link[ship]).is_equal(0)                        # A-87: a flying ship never carries link
	assert_int(_pending(w)).is_equal(0)                                 # forgotten at LAUNCHED
	var after: Array[SimEvent] = K.run(w, 3)
	assert_int(K.count_kind(after, SimEvent.Kind.DEATH)).is_equal(0)    # not rammed by its own Shipyard


func test_a_shipyard_is_never_a_service_pad() -> void:
	var w: SimWorld = _world()
	var yard: int = _yard_id(w)
	assert_int(K.code(w, Command.produce(0, yard, K.def(&"scout"), 1))).is_equal(C.ACCEPTED)
	assert_object(_until(w, SimEvent.Kind.SPAWN)).is_not_null()
	assert_int(w.store().flags[w.store().ships[0]] & EntityStore.F_DOCKED).is_equal(EntityStore.F_DOCKED)
	assert_int(w.view().pad_occupant(yard)).is_equal(0)                 # A-19: launch only


func test_ship_killed_while_parked_never_launches() -> void:
	var w: SimWorld = _world()
	var yard: int = _yard_id(w)
	assert_int(K.code(w, Command.produce(0, yard, K.def(&"scout"), 1))).is_equal(C.ACCEPTED)
	assert_object(_until(w, SimEvent.Kind.SPAWN)).is_not_null()
	var id: int = w.store().id_of(w.store().ships[0])
	assert_int(K.code(w, CommandPayload.debug_set(0, id, CommandPayload.SET_KILL, 0.0))).is_equal(C.ACCEPTED)
	var after: Array[SimEvent] = K.run(w, 120)
	assert_int(K.count_kind(after, SimEvent.Kind.LAUNCHED)).is_equal(0)
	assert_int(_pending(w)).is_equal(0)


func test_a_possessed_parked_ship_is_not_launched_for_the_pilot() -> void:
	var w: SimWorld = _world()
	var yard: int = _yard_id(w)
	assert_int(K.code(w, Command.produce(0, yard, K.def(&"scout"), 1))).is_equal(C.ACCEPTED)
	var sp: SimEvent = _until(w, SimEvent.Kind.SPAWN)
	assert_int(K.code(w, Command.possess(0, sp.a))).is_equal(C.ACCEPTED)
	var ev: Array[SimEvent] = K.run(w, 5)
	assert_int(K.count_kind(ev, SimEvent.Kind.LAUNCHED)).is_equal(0)
	var s: int = EntityId.slot(sp.a)
	assert_int(w.store().flags[s] & EntityStore.F_DOCKED).is_equal(EntityStore.F_DOCKED)   # the pilot's own launch (GD-15)
	assert_float(w.store().vel[s].length()).is_equal(0.0)
	assert_int(_pending(w)).is_equal(0)


func test_set_rally_orders_a_launched_ship_to_move_there() -> void:
	var w: SimWorld = _world()
	var yard: int = _yard_id(w)
	var rally: Vector3 = WorldTestKit.at(300.0, 900.0)
	assert_int(K.code(w, Command.set_rally(0, yard, rally))).is_equal(C.ACCEPTED)
	assert_int(K.code(w, Command.produce(0, yard, K.def(&"scout"), 1))).is_equal(C.ACCEPTED)
	var l: SimEvent = _until(w, SimEvent.Kind.LAUNCHED)
	assert_object(l).is_not_null()
	var head: OrderSpec = w.view().order_head(l.a)
	assert_int(head.kind).is_equal(OrderSpec.Kind.MOVE)
	assert_vector(head.point).is_equal_approx(rally, EPS)
	assert_int(head.issuer).is_equal(0)


func test_set_rally_sends_a_ground_unit_at_once() -> void:
	var w: SimWorld = _world()
	var bay: int = w.store().id_of(K.find(w, &"vehicle_bay"))
	var rally: Vector3 = WorldTestKit.at(0.0, 700.0)
	assert_int(K.code(w, Command.set_rally(0, bay, rally))).is_equal(C.ACCEPTED)
	assert_int(K.code(w, Command.produce(0, bay, K.def(&"harvester"), 1))).is_equal(C.ACCEPTED)
	var sp: SimEvent = _until(w, SimEvent.Kind.SPAWN)
	assert_object(sp).is_not_null()
	var head: OrderSpec = w.view().order_head(sp.a)
	assert_int(head.kind).is_equal(OrderSpec.Kind.MOVE)
	assert_vector(head.point).is_equal_approx(rally, EPS)


func test_no_rally_means_no_order() -> void:
	var w: SimWorld = _world()
	var bay: int = w.store().id_of(K.find(w, &"vehicle_bay"))
	assert_bool(w.economy().production.launch.has_rally(EntityId.slot(bay))).is_false()
	assert_int(K.code(w, Command.produce(0, bay, K.def(&"harvester"), 1))).is_equal(C.ACCEPTED)
	var sp: SimEvent = _until(w, SimEvent.Kind.SPAWN)
	assert_object(sp).is_not_null()
	assert_object(w.view().order_head(sp.a)).is_null()


func test_set_rally_validation() -> void:
	var w: SimWorld = WorldTestKit.world()                              # players 0 and 2 share team 0
	var yard: int = WorldTestKit.spawn(w, &"shipyard", 0, 0, WorldTestKit.at(0.0, 400.0))
	var core: int = WorldTestKit.spawn(w, &"core", 0, 0, WorldTestKit.at(0.0, 900.0))
	var p: Vector3 = WorldTestKit.at(100.0, 50.0)
	assert_int(K.code(w, Command.set_rally(2, yard, p))).is_equal(C.ACCEPTED)                # team-shared (A-81): a teammate may
	assert_int(K.code(w, Command.set_rally(1, yard, p))).is_equal(C.REJECTED_NOT_OWNER)      # a foreign team may not
	assert_int(K.code(w, Command.set_rally(0, yard, Vector3.ZERO))).is_equal(C.REJECTED_MALFORMED)
	assert_int(K.code(w, Command.set_rally(0, yard, Vector3(NAN, 0.0, 1.0)))).is_equal(C.REJECTED_MALFORMED)
	assert_int(K.code(w, Command.set_rally(0, core, p))).is_equal(C.REJECTED_MALFORMED)       # a Core makes nothing
	assert_int(K.code(w, Command.set_rally(0, 0, p))).is_equal(C.REJECTED_DEAD)
	assert_int(K.code(w, Command.set_rally(0, yard, p))).is_equal(C.ACCEPTED)


func test_launch_bay_state_round_trips() -> void:
	var w: SimWorld = _world()
	var yard: int = _yard_id(w)
	assert_int(K.code(w, Command.set_rally(0, yard, WorldTestKit.at(0.0, 800.0)))).is_equal(C.ACCEPTED)
	assert_int(K.code(w, Command.produce(0, yard, K.def(&"scout"), 1))).is_equal(C.ACCEPTED)
	assert_object(_until(w, SimEvent.Kind.SPAWN)).is_not_null()
	assert_int(_pending(w)).is_equal(1)                                 # parked, launches next step
	var copy: SimWorld = SimWorld.deserialize(w.serialize(), WorldTestKit.content(), null)
	assert_int(copy.economy().production.launch.pending()).is_equal(1)
	assert_bool(copy.economy().production.launch.has_rally(EntityId.slot(yard))).is_true()
	for _i: int in 120:
		w.step()
		copy.step()
	assert_bool(w.serialize() == copy.serialize()).is_true()


func test_format_9_snapshots_are_refused() -> void:
	var bytes: PackedByteArray = _world().serialize()
	assert_int(SimSerialize.FORMAT).is_equal(10)                        # GD-17: Production state gained the launch bay and targets
	bytes.encode_u32(4, 9)
	assert_int(SimSerialize.check(bytes)).is_equal(SimSerialize.Status.OLD_FORMAT)
