extends GdUnitTestSuite
## UX-24: ScreenFlow transitions, back stack, focus (06 s8).


class Stub extends FlowScreen:
	var consume_back: bool = false
	var entered_args: Dictionary = {}
	var btn: Button = null

	func _init() -> void:
		btn = Button.new()
		add_child(btn)

	func enter(args: Dictionary) -> void:
		entered_args = args

	func handle_back() -> bool:
		return consume_back

	func initial_focus() -> Control:
		return btn


class NoFocusHint extends FlowScreen:
	var btn: Button = null

	func _init() -> void:
		btn = Button.new()
		add_child(btn)


var _flow: ScreenFlow
var _host: Control


func before_test() -> void:
	_host = auto_free(Control.new()) as Control
	add_child(_host)
	_flow = auto_free(ScreenFlow.new()) as ScreenFlow
	add_child(_flow)
	_flow.setup(_host)
	for id: StringName in ScreenId.all_ids():
		_flow.register(id, func() -> FlowScreen: return Stub.new())


func after_test() -> void:
	_host.queue_free()


func test_start_and_edge_rules() -> void:
	assert_bool(_flow.start(ScreenId.MAIN_MENU)).is_true()
	assert_bool(_flow.go(ScreenId.MATCH)).is_false()
	assert_str(String(_flow.current_id)).is_equal("main_menu")
	assert_bool(_flow.go(ScreenId.ONLINE, {"k": 1})).is_true()
	assert_int((_flow.current as Stub).entered_args["k"] as int).is_equal(1)


func test_back_pops_to_previous() -> void:
	_flow.start(ScreenId.MAIN_MENU)
	_flow.go(ScreenId.ONLINE)
	_flow.go(ScreenId.ACCOUNT)
	assert_int(_flow.stack_depth()).is_equal(2)
	assert_bool(_flow.back()).is_true()
	assert_str(String(_flow.current_id)).is_equal("online")
	assert_bool(_flow.back()).is_true()
	assert_str(String(_flow.current_id)).is_equal("main_menu")


func test_handle_back_consumes() -> void:
	_flow.start(ScreenId.MAIN_MENU)
	_flow.go(ScreenId.SETTINGS)
	(_flow.current as Stub).consume_back = true
	assert_bool(_flow.back()).is_true()
	assert_str(String(_flow.current_id)).is_equal("settings")


func test_main_menu_back_requests_quit_native() -> void:
	var seen: Array[bool] = [false]
	_flow.quit_requested.connect(func() -> void: seen[0] = true)
	_flow.start(ScreenId.MAIN_MENU)
	var handled: bool = _flow.back()
	assert_bool(handled).is_equal(not OS.has_feature("web"))
	assert_bool(seen[0]).is_equal(not OS.has_feature("web"))


func test_pause_returns_to_match_via_stack() -> void:
	_flow.start(ScreenId.LOADING)
	_flow.go(ScreenId.MATCH)
	assert_int(_flow.stack_depth()).is_equal(0)  # loading is transient
	_flow.go(ScreenId.PAUSE)
	assert_bool(_flow.go(ScreenId.MATCH)).is_true()
	assert_int(_flow.stack_depth()).is_equal(0)
	_flow.go(ScreenId.PAUSE)
	assert_bool(_flow.back()).is_true()
	assert_str(String(_flow.current_id)).is_equal("match")


func test_results_and_menu_clear_stack() -> void:
	_flow.start(ScreenId.LOADING)
	_flow.go(ScreenId.MATCH)
	_flow.go(ScreenId.RESULTS)
	assert_int(_flow.stack_depth()).is_equal(0)
	_flow.go(ScreenId.LOBBY)
	assert_int(_flow.stack_depth()).is_equal(1)
	_flow.go(ScreenId.LOADING)
	_flow.go(ScreenId.MATCH)
	assert_int(_flow.stack_depth()).is_equal(2)  # results, lobby; loading is transient
	_flow.go(ScreenId.RESULTS)
	assert_int(_flow.stack_depth()).is_equal(0)


func test_back_intent_and_go_back_notification() -> void:
	_flow.start(ScreenId.MAIN_MENU)
	_flow.go(ScreenId.PROFILE)
	_flow.on_intent(Intents.BACK, {})
	assert_str(String(_flow.current_id)).is_equal("main_menu")
	_flow.go(ScreenId.REPLAYS)
	_flow.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	assert_str(String(_flow.current_id)).is_equal("main_menu")


func test_esc_ui_cancel_pops() -> void:
	_flow.start(ScreenId.MAIN_MENU)
	_flow.go(ScreenId.SETTINGS)
	var ev := InputEventAction.new()
	ev.action = &"ui_cancel"
	ev.pressed = true
	_flow._unhandled_input(ev)
	assert_str(String(_flow.current_id)).is_equal("main_menu")


func test_every_screen_has_initial_focus() -> void:
	for id: StringName in ScreenId.all_ids():
		assert_bool(_flow.start(id)).is_true()
		var owner_ctl: Control = _host.get_viewport().gui_get_focus_owner()
		assert_object(owner_ctl).is_not_null()
		assert_bool(_flow.current.is_ancestor_of(owner_ctl)).is_true()


func test_focus_falls_back_to_first_focusable() -> void:
	_flow.register(ScreenId.PROFILE, func() -> FlowScreen: return NoFocusHint.new())
	_flow.start(ScreenId.PROFILE)
	var owner_ctl: Control = _host.get_viewport().gui_get_focus_owner()
	assert_object(owner_ctl).is_equal((_flow.current as NoFocusHint).btn)


func test_every_target_is_a_known_screen() -> void:
	var ids: Array[StringName] = ScreenId.all_ids()
	for id: StringName in ids:
		for t: StringName in ScreenId.targets(id):
			assert_bool(ids.has(t)).is_true()
