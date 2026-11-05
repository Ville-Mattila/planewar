extends GdUnitTestSuite
## DrawerModel, DrawerCommands, DrawerDetail (UX-22; docs/06 s7.5): tile states, badges, factory choice, commands and the
## detail slots, all from a mocked SimView.

const S := DrawerMath.State
const V := DrawerMath.Cancel

var _v: DrawerMockView


func before_test() -> void:
	var r: Result = ContentDB.load_all()
	assert_bool(r.ok).is_true()
	_v = DrawerMockView.new()
	var _p: PlayerStateView = _v.add_player(0, 0)
	_v.team_view.ore = 800
	_v.team_view.ice = 300
	_v.team_view.unit_cap = 20
	_v.team_view.structure_cap = 40
	_v.add_structure(1, &"core", 0, 0)
	_v.add_structure(2, &"refinery", 0, 0)
	_v.add_structure(3, &"shipyard", 0, 0, Vector3(0.0, 0.0, 100.0))
	_v.add_structure(4, &"vehicle_bay", 0, 0, Vector3(0.0, 0.0, 400.0))


func _d(id: StringName) -> int:
	return ContentDB.def_index(id)


func _c(lock: int = -1) -> DrawerContext:
	return DrawerContextKit.from_view(_v, 0, lock)


func _t(id: StringName, lock: int = -1) -> TileInfo:
	return DrawerModel.tile(_v, _c(lock), id)


func test_a_plain_tile_is_available_with_its_cost() -> void:
	var t: TileInfo = _t(&"dart")
	assert_int(t.state).is_equal(S.AVAILABLE)
	assert_vector(t.cost).is_equal(Vector2i(150, 0))
	assert_bool(t.is_unit).is_true()
	assert_int(t.def).is_equal(_d(&"dart"))
	assert_int(_t(&"solar_array").state).is_equal(S.AVAILABLE)
	assert_bool(_t(&"solar_array").is_unit).is_false()


func test_unaffordable_names_the_missing_resource() -> void:
	_v.team_view.ore = 100
	var t: TileInfo = _t(&"dart")
	assert_int(t.state).is_equal(S.UNAFFORDABLE)
	assert_vector(t.short).is_equal(Vector2i(50, 0))
	_v.team_view.ore = 800
	_v.team_view.ice = 20
	assert_vector(_t(&"bomber").short).is_equal(Vector2i(0, 30))                  # bomber 450 Ore + 50 Ice


func test_spend_locked_keeps_the_amount_and_the_left_share() -> void:
	var t: TileInfo = _t(&"dart", 100)
	assert_int(t.state).is_equal(S.SPEND_LOCKED)
	assert_int(t.lock_left_ore).is_equal(100)
	assert_vector(t.cost).is_equal(Vector2i(150, 0))                              # the greyed amount stays visible
	assert_int(_t(&"scout", 100).state).is_equal(S.AVAILABLE)                     # 60 Ore fits the left share
	assert_int(_t(&"dart", -1).state).is_equal(S.AVAILABLE)


func test_missing_tech_locks_and_names_the_prerequisite() -> void:
	_v.missing_tech[_d(&"bomber")] = true
	var t: TileInfo = _t(&"bomber")
	assert_int(t.state).is_equal(S.LOCKED)
	assert_str(String(t.need)).is_equal("hangar")
	_v.missing_tech[_d(&"hangar")] = true
	assert_str(String(_t(&"hangar").need)).is_equal("pad")                         # first missing of [pad, shipyard]: no pad yet


func test_a_unit_without_a_finished_factory_is_locked_even_if_tech_says_yes() -> void:
	_v.flags_of[3] = DrawerMockView.BUILDING
	var t: TileInfo = _t(&"dart")
	assert_int(t.state).is_equal(S.LOCKED)
	assert_str(String(t.need)).is_equal("shipyard")


func test_cap_reached_for_units_queues_and_structures() -> void:
	_v.units = 20
	assert_int(_t(&"dart").state).is_equal(S.CAP_REACHED)                         # unit cap
	_v.units = 3
	_v.queues[3] = PackedInt32Array([1, 1, 1, 1, 1])
	assert_int(_t(&"dart").state).is_equal(S.CAP_REACHED)                         # the only shipyard queue is full
	assert_int(_t(&"harvester").state).is_equal(S.AVAILABLE)                      # another factory
	_v.add_structure(5, &"shipyard", 0, 0)
	_v.add_structure(6, &"shipyard", 0, 0)
	assert_int(_t(&"shipyard").state).is_equal(S.CAP_REACHED)                     # max_per_player 3
	var o: DrawerMockView = DrawerMockView.new()
	var _p: PlayerStateView = o.add_player(0, 0)
	o.team_view.ore = 800
	o.team_view.structure_cap = 40
	o.add_structure(7, &"refinery", 0, 0)
	o.add_structure(8, &"shipyard", 1, 0)
	o.add_structure(9, &"shipyard", 1, 0)
	o.add_structure(10, &"shipyard", 1, 0)
	assert_int(DrawerModel.tile(o, DrawerContextKit.from_view(o, 0, -1), &"shipyard").state).is_equal(S.AVAILABLE)   # a teammate's structures do not count
	o.team_view.structure_cap = 1
	assert_int(DrawerModel.tile(o, DrawerContextKit.from_view(o, 0, -1), &"solar_array").state).is_equal(S.CAP_REACHED)


func test_queue_badges_progress_and_replenish() -> void:
	_v.queues[3] = PackedInt32Array([_d(&"dart"), _d(&"lancer"), _d(&"dart")])
	_v.progress[3] = 0.4
	_v.repl[_d(&"dart")] = 4
	var t: TileInfo = _t(&"dart")
	assert_int(t.queued).is_equal(2)
	assert_float(t.progress01).is_equal_approx(0.4, 0.0001)                       # the head is a dart
	assert_int(t.replenish).is_equal(4)
	assert_float(_t(&"lancer").progress01).is_equal(0.0)                          # lancer is queued behind the head
	assert_int(_t(&"lancer").queued).is_equal(1)


func test_structure_sites_count_as_building() -> void:
	_v.add_structure(20, &"solar_array", 0, 0, Vector3.ZERO, DrawerMockView.BUILDING)
	_v.hp_of[20] = 0.35
	_v.add_structure(21, &"solar_array", 1, 0, Vector3.ZERO, DrawerMockView.BUILDING)
	var t: TileInfo = _t(&"solar_array")
	assert_int(t.queued).is_equal(2)                                              # team sites; a teammate's counts for the badge
	assert_float(t.progress01).is_equal_approx(0.35, 0.0001)                      # own site


func test_tiles_lists_follow_the_tab() -> void:
	assert_int(DrawerModel.tiles(_v, _c(), false).size()).is_equal(16)
	assert_int(DrawerModel.tiles(_v, _c(), true).size()).is_equal(7)
	assert_str(String(DrawerModel.tiles(_v, _c(), true)[0].id)).is_equal("dart")


func test_disabled_reason_for_an_eliminated_commander() -> void:
	assert_str(String(DrawerModel.disabled_reason(_c()))).is_equal("")
	_v.players[0].eliminated = true
	_v.players[0].commander_rights = false
	assert_str(String(DrawerModel.disabled_reason(_c()))).is_equal("ui.prod.disabled.eliminated")
	assert_str(String(DrawerModel.disabled_reason(DrawerContextKit.from_view(_v, 5)))).is_equal("ui.prod.disabled.eliminated")   # unknown slot


func test_factories_finished_own_team_and_best_is_shortest_queue_then_nearest() -> void:
	_v.add_structure(30, &"shipyard", 1, 0, Vector3(0.0, 0.0, 900.0))
	_v.add_structure(31, &"shipyard", 2, 1, Vector3.ZERO)                          # enemy
	_v.add_structure(32, &"shipyard", 0, 0, Vector3.ZERO, DrawerMockView.BUILDING)  # unfinished
	assert_array(DrawerModel.factories(_v, 0, &"dart")).contains_exactly_in_any_order([3, 30])
	assert_int(DrawerModel.best_factory(_v, 0, &"dart", Vector3(0.0, 0.0, 800.0))).is_equal(30)   # tie: nearest the focus
	_v.queues[30] = PackedInt32Array([1])
	assert_int(DrawerModel.best_factory(_v, 0, &"dart", Vector3(0.0, 0.0, 800.0))).is_equal(3)    # shorter queue wins
	_v.queues[3] = PackedInt32Array([1, 1, 1, 1, 1])
	_v.queues[30] = PackedInt32Array([1, 1, 1, 1, 1])
	assert_int(DrawerModel.best_factory(_v, 0, &"dart", Vector3.ZERO)).is_equal(-1)
	assert_int(DrawerModel.best_factory(_v, 0, &"refinery", Vector3.ZERO)).is_equal(-1)


func test_queue_verdicts_follow_the_queuer() -> void:
	var _a: PlayerStateView = _v.add_player(1, 0)
	var _b: PlayerStateView = _v.add_player(2, 0, 1)                               # bot teammate
	var vs: PackedInt32Array = DrawerModel.queue_verdicts(_v, _c(), 3, PackedInt32Array([0, 1, 2]))
	assert_array(vs).contains_exactly([V.OWNER, V.DENIED_NOT_OWNER, V.DELEGATED])
	_v.players[1].connected = false
	assert_int(DrawerModel.queue_verdicts(_v, _c(), 3, PackedInt32Array([1]))[0]).is_equal(V.DELEGATED)
	_v.queues[3] = PackedInt32Array([1, 1])
	assert_array(DrawerModel.queue_verdicts(_v, _c(), 3, PackedInt32Array())).contains_exactly([V.UNKNOWN, V.UNKNOWN])   # needs sim: queuer read


func test_produce_commands_target_the_best_factory() -> void:
	var c: Command = DrawerCommands.produce_at_best(_v, _c(), &"dart", 1, Vector3.ZERO)
	assert_object(c).is_not_null()
	assert_int(c.kind).is_equal(Command.Kind.PRODUCE)
	assert_int(c.target).is_equal(3)
	assert_int(c.player).is_equal(0)
	assert_int(c.payload.decode_u16(0)).is_equal(_d(&"dart"))
	assert_int(c.payload.decode_u8(2)).is_equal(1)
	assert_int(DrawerCommands.produce_at_best(_v, _c(), &"dart", 5, Vector3.ZERO).payload.decode_u8(2)).is_equal(5)
	_v.queues[3] = PackedInt32Array([1, 1, 1])
	assert_int(DrawerCommands.produce_at_best(_v, _c(), &"dart", 5, Vector3.ZERO).payload.decode_u8(2)).is_equal(2)   # clipped to the free slots
	_v.queues[3] = PackedInt32Array([1, 1, 1, 1, 1])
	assert_object(DrawerCommands.produce_at_best(_v, _c(), &"dart", 1, Vector3.ZERO)).is_null()
	assert_object(DrawerCommands.produce_at_best(_v, _c(), &"dart", 0, Vector3.ZERO)).is_null()


func test_cancel_commands_match_the_sims_payloads() -> void:
	var c: Command = DrawerCommands.cancel_produce(0, 3, 2)
	var want: Command = CommandPayload.cancel_produce(0, 3, 2)
	assert_int(c.kind).is_equal(want.kind)
	assert_int(c.target).is_equal(want.target)
	assert_array(c.payload).is_equal(want.payload)
	var b: Command = DrawerCommands.cancel_build(0, 20)
	var wb: Command = CommandPayload.cancel_build(0, 20)
	assert_int(b.kind).is_equal(wb.kind)
	assert_int(b.target).is_equal(wb.target)
	assert_array(b.payload).is_equal(wb.payload)


func test_replenish_command_rewrites_the_roster() -> void:
	_v.repl[_d(&"dart")] = 2
	var c: Command = DrawerCommands.replenish(_v, _c(), 3, &"lancer", 3)
	assert_int(c.kind).is_equal(Command.Kind.TOGGLE_AUTO_REPLENISH)
	assert_int(c.target).is_equal(3)
	assert_int(c.payload.decode_u8(0)).is_equal(1)
	assert_int(c.payload.size()).is_equal(1 + 3 * 2)
	assert_int(c.payload.decode_u16(1)).is_equal(_d(&"dart"))
	assert_int(c.payload.decode_u8(3)).is_equal(2)
	assert_int(c.payload.decode_u16(4)).is_equal(_d(&"lancer"))
	assert_int(c.payload.decode_u8(6)).is_equal(3)
	var off: Command = DrawerCommands.replenish(_v, _c(), 3, &"dart", 0)
	assert_int(off.payload.decode_u8(0)).is_equal(0)                              # no target left: disabled
	assert_int(off.payload.size()).is_equal(1)


func test_detail_slots_enable_by_queue_and_rights() -> void:
	var info: TileInfo = _t(&"dart")
	var vs: PackedInt32Array = PackedInt32Array([V.OWNER, V.DENIED_NOT_OWNER])
	var slots: Array[DetailSlot] = DrawerDetail.slots(info, 2, vs)
	assert_int(slots[0].kind).is_equal(DetailSlot.Kind.BACK)
	assert_int(slots.size()).is_less_equal(DrawerLayout.capacity())
	var by: Dictionary = {}
	for s: DetailSlot in slots:
		by[s.kind * 100 + s.index] = s
	assert_bool(by[DetailSlot.Kind.BATCH * 100].enabled).is_true()
	assert_bool(by[DetailSlot.Kind.REPL_DEC * 100].enabled).is_false()             # target is 0
	assert_bool(by[DetailSlot.Kind.REPL_INC * 100].enabled).is_true()
	assert_bool(by[DetailSlot.Kind.QUEUE_ITEM * 100 + 0].enabled).is_true()
	var denied: DetailSlot = by[DetailSlot.Kind.QUEUE_ITEM * 100 + 1]
	assert_bool(denied.enabled).is_false()
	assert_str(String(denied.reason)).is_equal("ui.prod.cancel.not_owner")
	assert_bool(by[DetailSlot.Kind.CANCEL_LAST * 100].enabled).is_false()          # the last item is not ours
	assert_str(String(by[DetailSlot.Kind.CANCEL_LAST * 100].reason)).is_equal("ui.prod.cancel.not_owner")


func test_detail_batch_is_disabled_when_the_queue_is_full_or_the_tile_is_not_available() -> void:
	var full: Array[DetailSlot] = DrawerDetail.slots(_t(&"dart"), 5, PackedInt32Array([0, 0, 0, 0, 0]))
	for s: DetailSlot in full:
		if s.kind == DetailSlot.Kind.BATCH:
			assert_bool(s.enabled).is_false()
		if s.kind == DetailSlot.Kind.QUEUE_ITEM:
			assert_bool(s.enabled).is_true()
	_v.team_view.ore = 10
	for s: DetailSlot in DrawerDetail.slots(_t(&"dart"), 0, PackedInt32Array()):
		if s.kind == DetailSlot.Kind.BATCH:
			assert_bool(s.enabled).is_false()
