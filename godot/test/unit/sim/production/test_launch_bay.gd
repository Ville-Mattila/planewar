extends GdUnitTestSuite
## GD-17 (02 s6.4, s2.3): a produced ship is parked DOCKED on its Shipyard launch pad and leaves 3 s after completion
## (`economy.launch_delay_s`, LAUNCHED event); a Dart is airborne 23 s after its start at full power; SET_RALLY gives
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


func test_dart_is_airborne_23_s_after_its_start_at_full_power() -> void:
	var w: SimWorld = _world()
	var yard: int = _yard_id(w)
	var hz: int = WorldTestKit.content().rules.tick_hz
	var dart: ShipDef = WorldTestKit.content().ships[K.def(&"dart") - DefRanges.SHIP_BASE]
	assert_float(w.economy().economy.power_ratio(0)).is_equal_approx(1.0, 0.001)
	assert_int(K.code(w, Command.produce(0, yard, K.def(&"dart"), 1))).is_equal(C.ACCEPTED)
	var _first_step: Array[SimEvent] = K.run(w, 1)
	var start: int = w.tick()                                           # the head was paid in this tick
	var spawned: int = -1
	var launched: int = -1
	for _i: int in 26 * hz:
		for e: SimEvent in K.run(w, 1):
			if e.kind == SimEvent.Kind.SPAWN and spawned < 0:
				spawned = w.tick()
			if e.kind == SimEvent.Kind.LAUNCHED and launched < 0:
				launched = w.tick()
	var delay: float = WorldTestKit.content().economy.launch_delay_s
	assert_float(delay).is_equal(3.0)
	assert_int(spawned - start).is_between(int(dart.build_time_s) * hz - 3, int(dart.build_time_s) * hz + 3)
	assert_int(launched - start).is_between(int(dart.build_time_s + delay) * hz - 3, int(dart.build_time_s + delay) * hz + 3)
	assert_int(launched - spawned).is_equal(int(delay * float(hz)))     # exactly launch_delay_s after completion


func test_ship_waits_docked_on_the_pad_then_leaves_along_the_normal() -> void:
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
	assert_float(w.store().vel[ship].length()).is_equal(0.0)
	assert_int(_pending(w)).is_equal(1)
	var l: SimEvent = null
	while l == null:
		assert_int(w.store().flags[ship] & EntityStore.F_DOCKED).is_equal(EntityStore.F_DOCKED)
		l = _first(K.run(w, 1), SimEvent.Kind.LAUNCHED)
	assert_int(l.a).is_equal(w.store().id_of(ship))
	assert_int(l.b).is_equal(yard)
	assert_int(w.store().flags[ship] & EntityStore.F_DOCKED).is_equal(0)
	assert_int(w.store().link[ship]).is_equal(0)
	assert_float(w.store().vel[ship].length()).is_equal_approx(common.launch_speed_mps, 0.001)
	assert_float(w.store().vel[ship].normalized().dot(w.store().up[ys])).is_greater(0.999)
	assert_int(_pending(w)).is_equal(0)


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
	assert_int(K.code(w, Command.set_rally(2, yard, p))).is_equal(C.REJECTED_NOT_OWNER)      # the factory's owner only
	assert_int(K.code(w, Command.set_rally(1, yard, p))).is_equal(C.REJECTED_NOT_OWNER)
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
	assert_int(_pending(w)).is_equal(1)
	var copy: SimWorld = SimWorld.deserialize(w.serialize(), WorldTestKit.content(), null)
	assert_int(copy.economy().production.launch.pending()).is_equal(1)
	for _i: int in 120:
		w.step()
		copy.step()
	assert_bool(w.serialize() == copy.serialize()).is_true()
	assert_int(_pending(w)).is_equal(0)
