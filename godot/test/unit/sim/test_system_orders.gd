extends GdUnitTestSuite
## TA-59: SimSink's system path for AI orders (FLAG_PREPEND, issuer -1), `SimView.overlay`, `CommandSinkBase.end_overlay`.


class Capture extends SimAiHook:
	var sink: CommandSinkBase = null

	func on_tick(_tick: int, _view: SimView, s: CommandSinkBase) -> void:
		sink = s


var _cap: Capture = null


func _sink() -> CommandSinkBase:
	return _cap.sink


func _world() -> SimWorld:
	var w: SimWorld = SimWorld.new(WorldTestKit.content())
	_cap = Capture.new()
	w.set_ai_hook(_cap)
	var res: Result = w.load_map(MapDef.new(), 7, WorldTestKit.rules())
	assert(res.ok, res.message)
	w.add_player(0, 0, &"", PlayerTable.KIND_HUMAN)
	w.add_player(1, 1, &"vanguard", PlayerTable.KIND_HUMAN)
	return w


func _dart(w: SimWorld) -> int:
	var p: Vector3 = Vector3(0.0, Sphere.PLANET_RADIUS + 300.0, 0.0)
	var r: CommandResult = w.apply_command(CommandPayload.debug_spawn(0, WorldTestKit.def_id(&"dart"), 0, 0, p, Vector3.ZERO, Vector3.ZERO))
	assert(r.code == CommandResult.Code.ACCEPTED)
	w.step()
	for e: SimEvent in w.drain_events():
		if e.kind == SimEvent.Kind.SPAWN:
			return e.a
	return 0


func _prepend_return(id: int, player: int) -> Command:
	return Command.order(player, PackedInt32Array([id]), OrderSpec.make(OrderSpec.Kind.RETURN, 0, Vector3.ZERO, OrderSpec.FLAG_PREPEND))


func test_client_prepend_stays_refused() -> void:
	var w: SimWorld = _world()
	var id: int = _dart(w)
	assert_int(w.apply_command(_prepend_return(id, 0)).code).is_not_equal(CommandResult.Code.ACCEPTED)


func test_sink_prepend_is_accepted_with_issuer_minus_one() -> void:
	var w: SimWorld = _world()
	var id: int = _dart(w)
	var r: CommandResult = _sink().submit(_prepend_return(id, 0))
	assert_int(r.code).is_equal(CommandResult.Code.ACCEPTED)
	w.step()
	assert_int(w.view().order_head(id).kind).is_equal(OrderSpec.Kind.RETURN)
	assert_int(w.view().order_issuer(id)).is_equal(-1)


func test_system_order_takes_no_rate_token_from_the_owner() -> void:
	var w: SimWorld = _world()
	var id: int = _dart(w)
	for _k: int in 100:                                  # more than the burst of 30, same tick
		assert_int(_sink().submit(_prepend_return(id, 0)).code).is_equal(CommandResult.Code.ACCEPTED)
	assert_int(w.apply_command(Command.release(0)).code).is_not_equal(CommandResult.Code.REJECTED_RATE)


func test_system_path_accepts_only_return() -> void:
	var w: SimWorld = _world()
	var id: int = _dart(w)
	var far: Vector3 = Vector3(0.0, Sphere.PLANET_RADIUS + 300.0, 500.0)
	var mv: OrderSpec = OrderSpec.make(OrderSpec.Kind.MOVE, 0, far, OrderSpec.FLAG_PREPEND)
	assert_int(_sink().submit(Command.order(0, PackedInt32Array([id]), mv)).code).is_equal(CommandResult.Code.REJECTED_INVALID_ORDER)
	var at: OrderSpec = OrderSpec.make(OrderSpec.Kind.ATTACK, id, Vector3.ZERO, OrderSpec.FLAG_PREPEND)
	assert_int(_sink().submit(Command.order(0, PackedInt32Array([id]), at)).code).is_equal(CommandResult.Code.REJECTED_INVALID_ORDER)


func test_system_return_on_enemy_unit_rejected() -> void:
	var w: SimWorld = _world()
	var id: int = _dart(w)                                 # team 0
	assert_int(_sink().submit(_prepend_return(id, 1)).code).is_equal(CommandResult.Code.REJECTED_NOT_OWNER)
	w.step()
	assert_object(w.view().order_head(id)).is_null()


func test_client_cannot_forge_the_system_marker() -> void:
	var w: SimWorld = _world()
	var id: int = _dart(w)
	var c: Command = Command.order(0, PackedInt32Array([id]), OrderSpec.make(OrderSpec.Kind.RETURN))
	c.target = CommandValidator.SYSTEM
	assert_int(w.apply_command(c).code).is_not_equal(CommandResult.Code.ACCEPTED)


func test_system_order_dead_target_rejected() -> void:
	var w: SimWorld = _world()
	var _id: int = _dart(w)
	assert_int(_sink().submit(_prepend_return(EntityId.make(90, 1), 0)).code).is_equal(CommandResult.Code.REJECTED_DEAD)


func test_pending_system_order_round_trips_s4_and_is_deterministic() -> void:
	var a: SimWorld = _world()
	var id: int = _dart(a)
	assert_int(_sink().submit(_prepend_return(id, 0)).code).is_equal(CommandResult.Code.ACCEPTED)
	var bytes: PackedByteArray = a.serialize()
	var b: SimWorld = SimWorld.deserialize(bytes, WorldTestKit.content(), Capture.new())
	assert_object(b).is_not_null()
	assert_array(Array(b.serialize())).is_equal(Array(bytes))
	a.step()
	b.step()
	assert_int(b.view().order_head(id).kind).is_equal(OrderSpec.Kind.RETURN)
	assert_int(b.view().order_issuer(id)).is_equal(-1)
	assert_array(Array(a.serialize())).is_equal(Array(b.serialize()))


func test_end_overlay_clears_ai_overlays_only() -> void:
	var w: SimWorld = _world()
	var id: int = _dart(w)
	var s: int = EntityId.slot(id)
	w.store().overlay[s] = ControlMachine.Overlay.SAFETY
	assert_int(w.view().overlay(id)).is_equal(ControlMachine.Overlay.SAFETY)
	_sink().end_overlay(id)
	assert_int(w.view().overlay(id)).is_equal(ControlMachine.Overlay.NONE)
	w.store().overlay[s] = ControlMachine.Overlay.LINK_BRIDGE
	_sink().end_overlay(id)
	assert_int(w.view().overlay(id)).is_equal(ControlMachine.Overlay.LINK_BRIDGE)
	assert_int(w.view().overlay(EntityId.make(91, 1))).is_equal(0)
