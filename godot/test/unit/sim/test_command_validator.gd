extends GdUnitTestSuite
## CommandValidator (TA-18): S10 (rate token bucket 10/s burst 30, ownership, rights, caps, cost, phase, shape;
## a rejected command has no effect) and S12 (cancel only by the placer / queuer, or a teammate when that player is
## disconnected, eliminated or a bot). Placement legality is Build.can_place's (TA-19).

const C := CommandResult.Code


func _code(w: SimWorld, cmd: Command) -> int:
	return w.apply_command(cmd).code


func _structure(w: SimWorld, def: StringName, owner: int, team: int, building: bool) -> int:
	var id: int = WorldTestKit.spawn(w, def, owner, team, WorldTestKit.at(0.0, 400.0 * float(owner + 1)))
	if building:
		w.store().flags[EntityId.slot(id)] |= EntityStore.F_BUILDING
	return id


func test_rate_bucket_burst_then_sustained_rate() -> void:
	var w: SimWorld = WorldTestKit.world()
	var hz: int = WorldTestKit.content().rules.tick_hz
	for k: int in CommandValidator.BURST:
		assert_int(_code(w, Command.release(0))).is_not_equal(C.REJECTED_RATE)
	assert_int(_code(w, Command.release(0))).is_equal(C.REJECTED_RATE)
	assert_int(_code(w, Command.release(1))).is_not_equal(C.REJECTED_RATE)      # per player
	var per_token: int = hz / CommandValidator.RATE_PER_S
	for _i: int in per_token - 1:
		w.step()
	assert_int(_code(w, Command.release(0))).is_equal(C.REJECTED_RATE)
	w.step()
	assert_int(_code(w, Command.release(0))).is_not_equal(C.REJECTED_RATE)
	assert_int(_code(w, Command.release(0))).is_equal(C.REJECTED_RATE)


func test_pilot_input_is_not_rate_limited() -> void:
	var w: SimWorld = WorldTestKit.world()
	var inp: PilotInput = PilotInput.new()
	for k: int in CommandValidator.BURST * 3:
		assert_int(_code(w, Command.pilot(0, 1, inp))).is_equal(C.ACCEPTED)


func test_unknown_or_inactive_player_is_malformed() -> void:
	var w: SimWorld = WorldTestKit.world()
	assert_int(_code(w, Command.release(9))).is_equal(C.REJECTED_MALFORMED)
	assert_int(_code(w, Command.release(5))).is_equal(C.REJECTED_MALFORMED)


func test_possess_guards_in_05_c6r_order() -> void:
	var w: SimWorld = WorldTestKit.world()
	var own: int = WorldTestKit.spawn(w, &"dart", 0, 0, WorldTestKit.at(500.0))
	var enemy: int = WorldTestKit.spawn(w, &"dart", 1, 1, WorldTestKit.at(500.0, 100.0))
	var core: int = WorldTestKit.spawn(w, &"core", 0, 0, WorldTestKit.at(0.0, 900.0))
	assert_int(_code(w, Command.possess(0, EntityId.make(77, 1)))).is_equal(C.REJECTED_DEAD)
	assert_int(_code(w, Command.possess(0, enemy))).is_equal(C.REJECTED_NOT_OWNER)
	assert_int(_code(w, Command.possess(0, core))).is_equal(C.REJECTED_NOT_POSSESSABLE)
	assert_int(_code(w, Command.possess(0, own))).is_equal(C.ACCEPTED)
	assert_int(_code(w, Command.possess(2, own))).is_equal(C.REJECTED_ALREADY_POSSESSED)   # same-tick claim
	w.step()
	assert_int(_code(w, Command.possess(2, own))).is_equal(C.REJECTED_ALREADY_POSSESSED)
	var high: int = WorldTestKit.spawn(w, &"dart", 2, 0,
		WorldTestKit.at(WorldTestKit.content().rules.ceiling_hard_m - 10.0, 300.0))
	assert_int(_code(w, Command.possess(2, high))).is_equal(C.REJECTED_UPLINK)


func test_debug_commands_need_the_rule() -> void:
	var r: MatchRules = WorldTestKit.rules()
	r.debug_commands = false
	var w: SimWorld = WorldTestKit.world(7, r)
	assert_int(WorldTestKit.queue_spawn(w, &"dart", 0, 0, WorldTestKit.at(500.0))).is_equal(C.REJECTED_NO_RIGHTS)


func test_ended_match_rejects_with_phase() -> void:
	var w: SimWorld = WorldTestKit.world(7, WorldTestKit.rules(-1.0, 0.01))
	w.step()
	assert_int(_code(w, Command.release(0))).is_equal(C.REJECTED_PHASE)


func test_produce_checks_owner_shape_cap_and_cost() -> void:
	var r: MatchRules = WorldTestKit.rules()
	var w: SimWorld = WorldTestKit.world(7, r)
	var yard: int = _structure(w, &"shipyard", 0, 0, false)
	var enemy_yard: int = _structure(w, &"shipyard", 1, 1, false)
	var dart: int = WorldTestKit.def_id(&"dart")
	var bomber: int = WorldTestKit.def_id(&"bomber")
	assert_int(_code(w, Command.produce(0, yard, dart, 1))).is_equal(C.ACCEPTED)
	assert_int(_code(w, Command.produce(2, yard, dart, 1))).is_equal(C.ACCEPTED)            # queues are team-shared (02 s6.4)
	assert_int(_code(w, Command.produce(0, enemy_yard, dart, 1))).is_equal(C.REJECTED_NOT_OWNER)
	assert_int(_code(w, Command.produce(0, yard, bomber, 1))).is_equal(C.REJECTED_PREREQ)     # needs a Hangar
	assert_int(_code(w, Command.produce(0, yard, dart, 0))).is_equal(C.REJECTED_MALFORMED)
	assert_int(_code(w, Command.produce(0, yard, WorldTestKit.def_id(&"pad"), 1))).is_equal(C.REJECTED_MALFORMED)
	var pool: Vector2i = w.economy().economy.stockpile(0)
	assert_bool(w.economy().economy.try_spend(0, pool.x, 0)).is_true()
	assert_int(_code(w, Command.produce(0, yard, dart, 1))).is_equal(C.REJECTED_COST)
	w.economy().economy.credit(0, pool.x, 0)
	r.caps.units = 1
	WorldTestKit.spawn(w, &"dart", 0, 0, WorldTestKit.at(500.0))
	assert_int(_code(w, Command.produce(0, yard, dart, 1))).is_equal(C.REJECTED_CAP)


func test_build_checks_shape_cap_and_cost() -> void:
	var r: MatchRules = WorldTestKit.rules()
	var w: SimWorld = WorldTestKit.world(7, r)
	var pad: int = WorldTestKit.def_id(&"pad")
	var res: CommandResult = w.apply_command(Command.build(0, pad, 1234, 1))
	assert_int(res.code).is_equal(C.REJECTED_PLACEMENT)                    # Build.can_place's verdict travels in `reject`
	assert_int(res.reject).is_equal(Build.Reject.PREREQ)
	assert_int(_code(w, Command.build(0, pad, 1234, 4))).is_equal(C.REJECTED_MALFORMED)
	assert_int(_code(w, Command.build(0, WorldTestKit.def_id(&"dart"), 1234, 0))).is_equal(C.REJECTED_MALFORMED)
	r.caps.structures = 0
	assert_int(_code(w, Command.build(0, pad, 1234, 0))).is_equal(C.REJECTED_CAP)


func test_order_validation() -> void:
	var w: SimWorld = WorldTestKit.world()
	var own: int = WorldTestKit.spawn(w, &"dart", 0, 0, WorldTestKit.at(500.0))
	var mate: int = WorldTestKit.spawn(w, &"dart", 2, 0, WorldTestKit.at(500.0, 50.0))
	var enemy: int = WorldTestKit.spawn(w, &"dart", 1, 1, WorldTestKit.at(500.0, 100.0))
	var move: OrderSpec = OrderSpec.make(OrderSpec.Kind.MOVE, 0, WorldTestKit.at(600.0, 900.0))
	assert_int(_code(w, Command.order(0, PackedInt32Array([own, mate]), move))).is_equal(C.ACCEPTED)
	assert_int(_code(w, Command.order(0, PackedInt32Array([enemy]), move))).is_equal(C.REJECTED_NOT_OWNER)
	assert_int(_code(w, Command.order(0, PackedInt32Array([EntityId.make(99, 3)]), move))).is_equal(C.REJECTED_DEAD)
	assert_int(_code(w, Command.order(0, PackedInt32Array(), move))).is_equal(C.REJECTED_MALFORMED)
	var bad: OrderSpec = OrderSpec.make(OrderSpec.Kind.PATROL_ROUTE)
	assert_int(_code(w, Command.order(0, PackedInt32Array([own]), bad))).is_equal(C.REJECTED_INVALID_ORDER)
	var flags: OrderSpec = OrderSpec.make(OrderSpec.Kind.MOVE, 0, WorldTestKit.at(600.0), OrderSpec.FLAG_PREPEND)
	assert_int(_code(w, Command.order(0, PackedInt32Array([own]), flags))).is_equal(C.REJECTED_MALFORMED)
	var dead_target: OrderSpec = OrderSpec.make(OrderSpec.Kind.ATTACK, EntityId.make(98, 2))
	assert_int(_code(w, Command.order(0, PackedInt32Array([own]), dead_target))).is_equal(C.REJECTED_INVALID_ORDER)
	w.step()
	assert_int(w.view().order_head(mate).kind).is_equal(OrderSpec.Kind.MOVE)
	assert_int(w.view().order_issuer(mate)).is_equal(0)


func test_set_adjutant_rights() -> void:
	var r: MatchRules = WorldTestKit.rules()
	var w: SimWorld = WorldTestKit.world(7, r)
	assert_int(_code(w, Command.set_adjutant(0, true, 1, 3))).is_equal(C.ACCEPTED)
	w.step()
	assert_int(w.view().player_state(0).adjutant_profile).is_equal(1)
	assert_int(w.view().player_state(0).adjutant_toggles).is_equal(3)
	r.adjutant_allowed = &"economy"
	assert_int(_code(w, Command.set_adjutant(0, true, 1, 0))).is_equal(C.REJECTED_NO_RIGHTS)
	assert_int(_code(w, Command.set_adjutant(0, true, 2, 1))).is_equal(C.ACCEPTED)
	r.ranked = true
	assert_int(_code(w, Command.set_adjutant(0, true, 2, 1))).is_equal(C.REJECTED_NO_RIGHTS)
	assert_int(_code(w, Command.set_adjutant(0, false, 0, 0))).is_equal(C.ACCEPTED)


func test_rejected_commands_have_no_effect() -> void:
	var w: SimWorld = WorldTestKit.world()
	var twin: SimWorld = WorldTestKit.world()
	var enemy: int = WorldTestKit.spawn(w, &"core", 1, 1, WorldTestKit.at(0.0, 600.0))
	var _e2: int = WorldTestKit.spawn(twin, &"core", 1, 1, WorldTestKit.at(0.0, 600.0))
	var rejected: Array[Command] = [Command.possess(0, enemy), Command.produce(0, enemy, WorldTestKit.def_id(&"dart"), 1),
		CommandPayload.cancel_build(0, enemy), Command.order(0, PackedInt32Array([enemy]), OrderSpec.make(OrderSpec.Kind.HOLD)),
		CommandPayload.debug_set(0, EntityId.make(3, 9), CommandPayload.SET_KILL, 0.0)]
	for c: Command in rejected:
		assert_int(_code(w, c)).is_not_equal(C.ACCEPTED)
	for _i: int in 3:
		w.step()
		twin.step()
	assert_bool(WorldTestKit.store_bytes(w) == WorldTestKit.store_bytes(twin)).is_true()
	assert_int(w.drain_events().size()).is_equal(0)


func test_s12_cancel_build_owner_or_delegable_teammate() -> void:
	var w: SimWorld = WorldTestKit.world()
	var site: int = _structure(w, &"pad", 0, 0, true)
	var done: int = _structure(w, &"pad", 0, 0, false)
	assert_int(_code(w, CommandPayload.cancel_build(0, site))).is_equal(C.ACCEPTED)       # the placer
	assert_int(_code(w, CommandPayload.cancel_build(1, site))).is_equal(C.REJECTED_NOT_OWNER)   # enemy
	assert_int(_code(w, CommandPayload.cancel_build(0, done))).is_equal(C.REJECTED_MALFORMED)   # nothing to cancel
	var bot_site: int = _structure(w, &"pad", 2, 0, true)
	assert_int(_code(w, CommandPayload.cancel_build(0, bot_site))).is_equal(C.ACCEPTED)  # placer is a bot
	w.add_player(3, 0, &"", PlayerTable.KIND_HUMAN)
	var human_site: int = _structure(w, &"pad", 3, 0, true)
	assert_int(_code(w, CommandPayload.cancel_build(0, human_site))).is_equal(C.REJECTED_NOT_OWNER)  # connected human
	w.remove_player(3)
	assert_int(_code(w, CommandPayload.cancel_build(0, human_site))).is_equal(C.ACCEPTED)  # disconnected


func test_s12_cancel_produce_owner_or_delegable_teammate() -> void:
	var w: SimWorld = WorldTestKit.world()
	w.add_player(3, 0, &"", PlayerTable.KIND_HUMAN)
	var yard: int = _structure(w, &"shipyard", 3, 0, false)
	assert_int(_code(w, CommandPayload.cancel_produce(3, yard, 0))).is_equal(C.REJECTED_DEAD)   # empty queue
	assert_int(_code(w, Command.produce(3, yard, WorldTestKit.def_id(&"dart"), 2))).is_equal(C.ACCEPTED)
	w.step()
	assert_int(_code(w, CommandPayload.cancel_produce(3, yard, 1))).is_equal(C.ACCEPTED)       # the queuer
	assert_int(_code(w, CommandPayload.cancel_produce(0, yard, 0))).is_equal(C.REJECTED_NOT_OWNER)
	assert_int(_code(w, CommandPayload.cancel_produce(1, yard, 0))).is_equal(C.REJECTED_NOT_OWNER)
	w.remove_player(3)
	assert_int(_code(w, CommandPayload.cancel_produce(0, yard, 0))).is_equal(C.ACCEPTED)


func test_s12_delegation_rule_of_the_player_table() -> void:
	var t: PlayerTable = PlayerTable.new()
	t.active[4] = 1
	t.connected[4] = 1
	t.kind[4] = PlayerTable.KIND_HUMAN
	assert_bool(t.cancel_delegable(4)).is_false()
	t.eliminated[4] = 1
	assert_bool(t.cancel_delegable(4)).is_true()
	t.eliminated[4] = 0
	t.kind[4] = PlayerTable.KIND_BOT
	assert_bool(t.cancel_delegable(4)).is_true()
	t.kind[4] = PlayerTable.KIND_HUMAN
	t.connected[4] = 0
	assert_bool(t.cancel_delegable(4)).is_true()
