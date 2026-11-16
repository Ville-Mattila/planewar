extends GdUnitTestSuite
## PlacementController (UX-21; docs/06 s7.3): the machine driven through an injected validator, the BUILD command, the
## pending outline, toasts, the haptic flip, and agreement with the real Build.can_place / apply_command.

const K := preload("res://test/unit/sim/economy_test_kit.gd")
const S := PlacementMachine.State

var _c: PlacementController
var _verdict: int = 0
var _asked: Array[Vector3i] = []
var _cmds: Array[Command] = []
var _toasts: Array[StringName] = []
var _flips: Array[bool] = []


func before_test() -> void:
	var r: Result = ContentDB.load_all()
	assert_bool(r.ok).is_true()
	_verdict = PlacementRules.OK
	_asked.clear()
	_cmds.clear()
	_toasts.clear()
	_flips.clear()
	_c = PlacementController.new()
	_c.setup(3, _validate)
	_c.command_ready.connect(func(cmd: Command) -> void: _cmds.append(cmd))
	_c.toast.connect(func(k: StringName, _a: Dictionary) -> void: _toasts.append(k))
	_c.validity_flipped.connect(func(v: bool) -> void: _flips.append(v))


func _validate(def_index: int, cell: int, rotation: int) -> int:
	_asked.append(Vector3i(def_index, cell, rotation))
	return _verdict


func _ctx() -> DrawerContext:
	var ctx: DrawerContext = DrawerContext.new()
	ctx.ore = 2000
	ctx.ice = 1000
	ctx.commander_rights = true
	ctx.lock_left_ore = -1
	return ctx


func _positioning() -> void:
	_c.arm(&"relay_pylon", _ctx())
	_c.set_camera(900.0, 42)


func test_arm_waits_for_altitude_then_positions_at_the_focus() -> void:
	_c.arm(&"relay_pylon", _ctx())
	assert_int(_c.machine.state).is_equal(S.ARMED)
	assert_int(_asked.size()).is_equal(0)
	_c.set_camera(3000.0, 42)
	assert_int(_c.machine.state).is_equal(S.ARMED)
	_c.set_camera(1100.0, 42)
	assert_int(_c.machine.state).is_equal(S.POSITIONING)
	assert_int(_c.machine.cell).is_equal(42)
	assert_object(_asked.back()).is_equal(Vector3i(ContentDB.def_index(&"relay_pylon"), 42, 0))   # validity computed on entry
	assert_bool(_c.is_valid()).is_true()


func test_move_and_rotate_revalidate_and_flips_emit_once_per_change() -> void:
	_positioning()
	assert_int(_flips.size()).is_equal(0)                  # the first evaluation is not a flip
	_verdict = PlacementRules.NO_RADIUS
	_c.move_to(50)
	assert_bool(_c.is_valid()).is_false()
	assert_array(_flips).is_equal([false])
	_c.rotate_by(1)
	assert_object(_asked.back()).is_equal(Vector3i(ContentDB.def_index(&"relay_pylon"), 50, 1))
	assert_array(_flips).is_equal([false])                  # still invalid: no second pulse
	_verdict = PlacementRules.OK
	_c.move_to(51)
	assert_array(_flips).is_equal([false, true])


func test_reason_line_is_the_highest_priority_of_sim_and_client() -> void:
	var ctx: DrawerContext = _ctx()
	ctx.ore = 10
	_c.arm(&"relay_pylon", ctx)
	_c.set_camera(500.0, 1)
	assert_int(_c.reject).is_equal(PlacementRules.FUNDS)    # the validator said OK; the client knows the Ore is short
	_verdict = PlacementRules.CAP
	_c.move_to(2)
	assert_int(_c.reject).is_equal(PlacementRules.FUNDS)    # FUNDS outranks CAP
	_verdict = PlacementRules.NO_RADIUS
	_c.move_to(3)
	assert_int(_c.reject).is_equal(PlacementRules.NO_RADIUS)
	assert_str(String(_c.reason_key())).is_equal("ui.place.reject.no_radius")
	_c.revalidate(_ctx())
	_verdict = PlacementRules.OK
	_c.move_to(4)
	assert_bool(_c.is_valid()).is_true()
	assert_str(String(_c.reason_key())).is_empty()


func test_confirm_invalid_sends_nothing() -> void:
	_positioning()
	_verdict = PlacementRules.OCCUPIED
	_c.move_to(9)
	assert_bool(_c.confirm()).is_false()
	assert_int(_cmds.size()).is_equal(0)
	assert_int(_c.machine.state).is_equal(S.POSITIONING)


func test_confirm_builds_the_command_and_holds_a_pending_outline_until_the_result() -> void:
	_positioning()
	_c.move_to(77)
	_c.rotate_by(2)
	assert_bool(_c.show_pending()).is_false()
	assert_bool(_c.confirm()).is_true()
	assert_int(_cmds.size()).is_equal(1)
	var cmd: Command = _cmds[0]
	assert_int(cmd.kind).is_equal(Command.Kind.BUILD)
	assert_int(cmd.player).is_equal(3)
	assert_int(cmd.payload.decode_u16(0)).is_equal(ContentDB.def_index(&"relay_pylon"))
	assert_int(cmd.payload.decode_u32(2)).is_equal(77)
	assert_int(cmd.payload.decode_u8(6)).is_equal(2)
	assert_bool(_c.show_pending()).is_true()                # the outline hides the round trip
	assert_int(_c.machine.cell).is_equal(77)
	assert_bool(_c.confirm()).is_false()                    # no second command in flight
	assert_int(_cmds.size()).is_equal(1)
	var ok: CommandResult = CommandResult.new()
	_c.on_result(ok)
	assert_bool(_c.show_pending()).is_false()
	assert_int(_c.machine.state).is_equal(S.IDLE)
	assert_int(_toasts.size()).is_equal(0)


func test_accepted_with_repeat_keeps_positioning() -> void:
	_positioning()
	_c.set_repeat(true)
	var _ok: bool = _c.confirm()
	_c.on_result(CommandResult.new())
	assert_int(_c.machine.state).is_equal(S.POSITIONING)
	assert_bool(_c.show_pending()).is_false()


func test_rejection_toasts_the_mapped_reason_and_returns_to_positioning() -> void:
	_positioning()
	var _ok: bool = _c.confirm()
	var rej: CommandResult = CommandResult.new()
	rej.code = CommandResult.Code.REJECTED_PLACEMENT
	rej.reject = Build.Reject.SLOPE
	_c.on_result(rej)
	assert_int(_c.machine.state).is_equal(S.POSITIONING)
	assert_bool(_c.show_pending()).is_false()
	assert_array(_toasts).is_equal([&"ui.place.reject.slope"])
	var _ok2: bool = _c.confirm()
	var locked: CommandResult = CommandResult.new()
	locked.code = CommandResult.Code.REJECTED_LOCKED
	_c.on_result(locked)
	assert_array(_toasts).is_equal([&"ui.place.reject.slope", &"ui.place.reject.spend_locked"])


func test_results_outside_sent_are_ignored() -> void:
	_positioning()
	var rej: CommandResult = CommandResult.new()
	rej.code = CommandResult.Code.REJECTED_COST
	_c.on_result(rej)
	assert_int(_toasts.size()).is_equal(0)
	assert_int(_c.machine.state).is_equal(S.POSITIONING)


func test_cancel_goes_idle_and_a_cancel_in_flight_is_ignored() -> void:
	_positioning()
	_c.cancel()
	assert_int(_c.machine.state).is_equal(S.IDLE)
	_positioning()
	var _ok: bool = _c.confirm()
	_c.cancel()
	assert_int(_c.machine.state).is_equal(S.SENT)


func test_eliminated_commander_cannot_arm() -> void:
	var ctx: DrawerContext = _ctx()
	ctx.eliminated = true
	_c.arm(&"relay_pylon", ctx)
	assert_int(_c.machine.state).is_equal(S.IDLE)
	assert_array(_toasts).is_equal([&"ui.place.reject.eliminated"])


func test_state_changed_signal_fires_per_transition() -> void:
	var seen: Array[int] = []
	_c.state_changed.connect(func(s: int) -> void: seen.append(s))
	_positioning()
	var _ok: bool = _c.confirm()
	_c.on_result(CommandResult.new())
	assert_array(seen).is_equal([S.ARMED, S.POSITIONING, S.SENT, S.IDLE])


func test_agrees_with_the_real_build_validator() -> void:
	var w: SimWorld = K.solo_world()
	var b: Build = w.economy().build
	var d: int = K.def(&"relay_pylon")
	var vc: PlacementController = PlacementController.new()
	vc.setup(0, func(def_index: int, cell: int, rot: int) -> int: return b.can_place(0, def_index, cell, rot))
	var dctx: DrawerContext = DrawerContextKit.from_view(w.view(), 0, -1)
	var cells: Array[int] = [K.cell_west(150.0), K.cell_west(3000.0), K.cell_west(300.0)]
	var seen_ok: bool = false
	var seen_bad: bool = false
	for cell: int in cells:
		vc.arm(&"relay_pylon", dctx)
		vc.set_camera(100.0, cell)
		var expect: int = b.can_place(0, d, cell, 0)
		assert_bool(vc.is_valid()).is_equal(expect == Build.Reject.OK)
		if expect != Build.Reject.OK:
			assert_int(vc.reject).is_equal(expect)
			seen_bad = true
		var got: CommandResult = w.apply_command(Command.build(0, d, cell, 0))
		if expect == Build.Reject.OK:
			seen_ok = true
			assert_int(got.code).is_equal(CommandResult.Code.ACCEPTED)
		else:
			assert_int(got.code).is_equal(CommandResult.Code.REJECTED_PLACEMENT)
			assert_int(PlacementRules.from_result(got.code, got.reject)).is_equal(expect)
		vc.cancel()
	assert_bool(seen_ok).is_true()
	assert_bool(seen_bad).is_true()
