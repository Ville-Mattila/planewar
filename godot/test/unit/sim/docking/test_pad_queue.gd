extends GdUnitTestSuite
## GD-15 pad queues (03 s3.2 `pad_queues`, 03 s6.4 "pad free"): ships with a RETURN head order (or a pilot holding DOCK)
## within `economy.pad_queue_radius_m` (horizontal in the pad frame, no altitude term; R0 B.24 A-125) of a busy pad
## wait in arrival order (<= 8 per pad); only the head may land when the pad
## frees; leaving the radius, losing the wish, docking or dying drops a ship. SimView.pad_queue reads it.

var _w: SimWorld
var _pad: int


func before_test() -> void:
	_w = WorldTestKit.world()
	_pad = DockingTestKit.pad(_w)
	var _e: Array[SimEvent] = _w.drain_events()


func _slot(id: int) -> int:
	return EntityId.slot(id)


func _return(id: int) -> void:
	var spec: OrderSpec = OrderSpec.make(OrderSpec.Kind.RETURN)
	var r: CommandResult = _w.apply_command(Command.order(_w.view().owner(id), PackedInt32Array([id]), spec))
	assert_int(r.code).is_equal(CommandResult.Code.ACCEPTED)


# A ship hovering `off` metres east of the pad, 80 m up, with a RETURN order (applied by the next step). It takes the
# order parked on the far side of the moon: the queue zone has no altitude term (A-125), so not above the pad.
func _waiting(off: float, owner: int = 0) -> int:
	var id: int = WorldTestKit.spawn(_w, &"dart", owner, 0, DockingTestKit.far(_w))
	_return(id)
	_w.step()
	DockingTestKit.pose(_w, id, _pad, 80.0, off, Vector3.ZERO)
	return id


func _occupy() -> int:
	var a: int = DockingTestKit.ship_over(_w, &"dart", 0, 0, _pad, DockingTestKit.HIGH)
	DockingTestKit.dock(_w, a, _pad)
	return a


func test_arrivals_at_a_busy_pad_queue_in_order_and_only_the_head_lands() -> void:
	var a: int = _occupy()
	var b: int = _waiting(50.0)
	var c: int = _waiting(-60.0, 2)
	DockingTestKit.pose(_w, b, _pad, 80.0, 50.0, Vector3.ZERO)
	_w.step()
	assert_array(Array(_w.view().pad_queue(_pad))).is_equal([b, c])
	assert_int(_w.economy().docking.queue.head(_pad)).is_equal(b)
	DockingTestKit.clear(_w, a)                                            # the pad frees; the queue stays
	DockingTestKit.pose(_w, c, _pad, 6.0, 1.0, Vector3.ZERO)
	var _d: Array[SimEvent] = _w.drain_events()
	var _x: int = DockingTestKit.contact(_w, c, _pad, 1.0, 0.0, 0.0, 1.0)
	assert_int(DockingTestKit.of_kind(_w.drain_events(), SimEvent.Kind.LANDING).size()).is_equal(0)   # not the head: holds
	DockingTestKit.pose(_w, c, _pad, 80.0, -60.0, Vector3.ZERO)
	DockingTestKit.pose(_w, b, _pad, 6.0, 1.0, Vector3.ZERO)
	var _y: int = DockingTestKit.contact(_w, b, _pad, 1.0, 0.0, 0.0, 1.0)
	var l: Array[SimEvent] = DockingTestKit.of_kind(_w.drain_events(), SimEvent.Kind.LANDING)
	assert_int(l.size()).is_equal(1)
	assert_int(l[0].a).is_equal(b)
	assert_array(Array(_w.view().pad_queue(_pad))).is_equal([c])               # b docked and left the queue
	_w.step()
	assert_array(Array(_w.view().pad_queue(_pad))).is_equal([c])               # b now occupies: c still waits


func test_a_free_pad_without_a_queue_takes_no_waiters() -> void:
	var _b: int = _waiting(50.0)
	_w.step()
	assert_bool(_w.view().pad_queue(_pad).is_empty()).is_true()


func test_leaving_the_radius_losing_the_order_or_dying_drops_out() -> void:
	var _a: int = _occupy()
	var r: float = DockingTestKit.queue_radius()
	var b: int = _waiting(0.0)
	var c: int = _waiting(-30.0)
	var d: int = _waiting(20.0, 2)
	_w.step()
	assert_array(Array(_w.view().pad_queue(_pad))).is_equal([b, c, d])
	DockingTestKit.pose(_w, b, _pad, 20.0, r + 1.0, Vector3.ZERO)               # just out of the zone (horizontal)
	var stop: OrderSpec = OrderSpec.make(OrderSpec.Kind.MOVE, 0, WorldTestKit.at(300.0, 900.0))
	assert_int(_w.apply_command(Command.order(0, PackedInt32Array([c]), stop)).code).is_equal(CommandResult.Code.ACCEPTED)
	_w.step()
	assert_array(Array(_w.view().pad_queue(_pad))).is_equal([d])
	assert_int(_w.apply_command(CommandPayload.debug_set(0, d, CommandPayload.SET_KILL, 0.0)).code).is_equal(CommandResult.Code.ACCEPTED)
	_w.step()
	_w.step()
	assert_bool(_w.view().pad_queue(_pad).is_empty()).is_true()


func test_a_possessed_pilot_holding_dock_queues() -> void:
	var _a: int = _occupy()
	var id: int = DockingTestKit.ship_over(_w, &"dart", 0, 0, _pad, DockingTestKit.HIGH)
	DockingTestKit.pose(_w, id, _pad, 80.0, DockingTestKit.queue_radius() + 100.0, Vector3.ZERO)
	assert_bool(DockingTestKit.possess(_w, id)).is_true()
	DockingTestKit.pose(_w, id, _pad, 80.0, 40.0, Vector3.ZERO)
	DockingTestKit.step_piloted(_w, 0, 0)
	assert_bool(_w.view().pad_queue(_pad).is_empty()).is_true()                # no DOCK, no wish
	DockingTestKit.pose(_w, id, _pad, 80.0, 40.0, Vector3.ZERO)
	DockingTestKit.step_piloted(_w, 0, PilotInput.DOCK)
	assert_array(Array(_w.view().pad_queue(_pad))).is_equal([id])


func test_same_tick_waiters_join_in_ascending_slot_whatever_their_wish() -> void:
	var _a: int = _occupy()
	var pilot: int = DockingTestKit.ship_over(_w, &"dart", 0, 0, _pad, DockingTestKit.HIGH)
	var out: float = DockingTestKit.queue_radius() + 100.0
	DockingTestKit.pose(_w, pilot, _pad, 80.0, out, Vector3.ZERO)
	assert_bool(DockingTestKit.possess(_w, pilot)).is_true()
	var ret: int = _waiting(-out)                                           # RETURN, still outside the radius
	assert_int(_slot(pilot)).is_less(_slot(ret))
	assert_bool(_w.view().pad_queue(_pad).is_empty()).is_true()
	DockingTestKit.pose(_w, pilot, _pad, 80.0, 40.0, Vector3.ZERO)
	DockingTestKit.pose(_w, ret, _pad, 80.0, -40.0, Vector3.ZERO)
	DockingTestKit.step_piloted(_w, 0, PilotInput.DOCK)
	assert_array(Array(_w.view().pad_queue(_pad))).is_equal([pilot, ret])   # D6: ascending ship slot, DOCK or RETURN


# R0 B.24 A-125 (05 s5.5 L2b holds at a 400 m orbit, 150 m AGL): the zone is pad_queue_radius_m (500) horizontally
# in the pad frame with no altitude term.
func test_the_queue_zone_is_horizontal_500_m_with_no_altitude_term() -> void:
	var _a: int = _occupy()
	assert_float(DockingTestKit.queue_radius()).is_equal(500.0)                 # the A-125 value
	var hold: int = _waiting(-400.0)                                         # the L2b hold: 400 m out, 150 m AGL
	var wide: int = _waiting(520.0)
	var above: int = _waiting(60.0)
	for _t: int in 2:
		DockingTestKit.pose(_w, hold, _pad, 150.0, -400.0, Vector3.ZERO)
		DockingTestKit.pose(_w, wide, _pad, 150.0, 520.0, Vector3.ZERO)
		DockingTestKit.pose(_w, above, _pad, 450.0, 0.0, Vector3.ZERO)     # straight above: no altitude term
		_w.step()
	var q: PackedInt32Array = _w.view().pad_queue(_pad)
	assert_bool(q.has(hold)).is_true()
	assert_bool(q.has(above)).is_true()
	assert_bool(q.has(wide)).is_false()
	assert_int(q.size()).is_equal(2)


func test_at_most_eight_wait_per_pad_and_other_teams_never_queue() -> void:
	var _a: int = _occupy()
	var ids: Array[int] = []
	for k: int in PadQueue.PER_PAD + 2:
		ids.append(_waiting(-90.0 + 18.0 * float(k)))
	for k: int in ids.size():
		DockingTestKit.pose(_w, ids[k], _pad, 80.0 + 3.0 * float(k), -90.0 + 18.0 * float(k), Vector3.ZERO)
	var enemy: int = DockingTestKit.ship_over(_w, &"dart", 1, 1, _pad, DockingTestKit.HIGH)
	_return(enemy)
	_w.step()
	DockingTestKit.pose(_w, enemy, _pad, 120.0, 0.0, Vector3.ZERO)
	_w.step()
	var q: PackedInt32Array = _w.view().pad_queue(_pad)
	assert_int(q.size()).is_equal(PadQueue.PER_PAD)
	assert_bool(q.has(enemy)).is_false()
	assert_int(_w.economy().docking.queue.count(_pad)).is_equal(PadQueue.PER_PAD)


func test_queue_state_round_trips_and_refuses_bad_bytes() -> void:
	var q: PadQueue = PadQueue.new()
	var ships: PackedInt32Array = PackedInt32Array([EntityId.make(10, 1), EntityId.make(11, 1), EntityId.make(12, 1)])
	var pads: PackedInt32Array = PackedInt32Array([EntityId.make(3, 1), EntityId.make(3, 1), EntityId.make(4, 1)])
	q.update(ships, pads, 3)
	assert_array(Array(q.of(EntityId.make(3, 1)))).is_equal([ships[0], ships[1]])
	assert_int(q.pad_of(ships[2])).is_equal(pads[2])
	q.update(PackedInt32Array([ships[1], ships[0]]), PackedInt32Array([pads[1], pads[0]]), 2)   # arrival order kept
	assert_array(Array(q.of(EntityId.make(3, 1)))).is_equal([ships[0], ships[1]])
	assert_int(q.pad_of(ships[2])).is_equal(0)
	var buf: StreamPeerBuffer = StreamPeerBuffer.new()
	q.write_state(buf)
	var r: PadQueue = PadQueue.new()
	buf.seek(0)
	assert_bool(r.read_state(buf)).is_true()
	assert_array(Array(r.q_ship)).is_equal(Array(q.q_ship))
	q.q_ship[1] = q.q_ship[0]                                                    # a ship twice: refused
	var bad: StreamPeerBuffer = StreamPeerBuffer.new()
	q.write_state(bad)
	bad.seek(0)
	assert_bool(PadQueue.new().read_state(bad)).is_false()
	assert_int(_w.view().pad_queue(0).size()).is_equal(0)
