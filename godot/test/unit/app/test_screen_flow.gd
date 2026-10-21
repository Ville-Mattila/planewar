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


func test_results_menu_and_loading_clear_stack() -> void:
	_flow.start(ScreenId.MAIN_MENU)
	_flow.go(ScreenId.SETUP_SKIRMISH)
	_flow.go(ScreenId.LOBBY)
	assert_int(_flow.stack_depth()).is_equal(2)
	_flow.go(ScreenId.LOADING)
	assert_int(_flow.stack_depth()).is_equal(0)
	_flow.go(ScreenId.MATCH)
	_flow.go(ScreenId.RESULTS)
	assert_int(_flow.stack_depth()).is_equal(0)
	_flow.go(ScreenId.LOBBY)
	assert_int(_flow.stack_depth()).is_equal(0)  # results is transient


func test_back_from_match_never_reaches_lobby_or_briefing() -> void:
	_flow.start(ScreenId.MAIN_MENU)
	_flow.go(ScreenId.CAMPAIGN)
	_flow.go(ScreenId.BRIEFING)
	_flow.go(ScreenId.LOADING)
	_flow.go(ScreenId.MATCH)
	_flow.back()
	assert_str(String(_flow.current_id)).is_equal("match")
	_flow.go(ScreenId.PAUSE)
	_flow.back()
	assert_str(String(_flow.current_id)).is_equal("match")


func test_stack_bounded_across_save_load_cycles() -> void:
	_flow.start(ScreenId.LOADING)
	_flow.go(ScreenId.MATCH)
	for i in 5:
		_flow.go(ScreenId.PAUSE)
		_flow.go(ScreenId.SAVE_LOAD)
		_flow.go(ScreenId.LOADING)
		_flow.go(ScreenId.MATCH)
		assert_int(_flow.stack_depth()).is_equal(0)


func test_every_pop_follows_an_allowed_reverse_edge() -> void:
	# Walk every edge, then back(): the landing screen must be a source of an edge into where we were.
	for from: StringName in ScreenId.all_ids():
		for to: StringName in ScreenId.targets(from):
			_flow.start(from)
			if not _flow.go(to):
				continue
			var before: StringName = _flow.current_id
			if _flow.stack_depth() > 0 and _flow.back():
				assert_bool(ScreenId.targets(_flow.current_id).has(before)).is_true()


func test_edge_table_pinned_to_06_s8() -> void:
	var want: Dictionary = {
		"boot": ["start_gate", "age_gate", "main_menu"],
		"start_gate": ["age_gate", "main_menu"],
		"age_gate": ["loading"],
		"main_menu": ["online", "setup_skirmish", "setup_coop", "campaign", "replays", "settings", "profile"],
		"online": ["account", "queue", "setup_custom"],
		"account": ["online"],
		"queue": ["lobby"], "setup_custom": ["lobby"], "setup_skirmish": ["lobby"], "setup_coop": ["lobby"],
		"campaign": ["briefing"], "briefing": ["loading"], "replays": ["replay_viewer"],
		"replay_viewer": [], "settings": [], "profile": [],
		"lobby": ["loading"], "loading": ["match"],
		"match": ["pause", "reconnecting", "results"],
		"pause": ["match", "save_load", "settings", "main_menu"],
		"save_load": ["pause", "loading"],
		"reconnecting": ["match"],
		"results": ["lobby", "main_menu"],
	}
	assert_int(ScreenId.all_ids().size()).is_equal(23)
	for id: StringName in ScreenId.all_ids():
		var got: Array = []
		for t: StringName in ScreenId.targets(id):
			got.append(String(t))
		assert_array(got).contains_exactly_in_any_order(want[String(id)] as Array)


func test_joypad_b_pops_exactly_once() -> void:
	_flow.start(ScreenId.MAIN_MENU)
	_flow.go(ScreenId.ONLINE)
	_flow.go(ScreenId.ACCOUNT)
	# One gamepad B press: Godot's ui_cancel joypad event plus the input lane's BACK intent.
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_B
	pad.pressed = true
	_flow._unhandled_input(pad)
	_flow.on_intent(Intents.BACK, {})
	assert_str(String(_flow.current_id)).is_equal("online")


func test_failed_show_leaves_stack_untouched() -> void:
	_flow.start(ScreenId.MAIN_MENU)
	_flow.register(ScreenId.ONLINE, func() -> FlowScreen: return null)
	assert_bool(_flow.go(ScreenId.ONLINE)).is_false()
	assert_int(_flow.stack_depth()).is_equal(0)
	assert_str(String(_flow.current_id)).is_equal("main_menu")


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
	var ev := InputEventKey.new()
	ev.keycode = KEY_ESCAPE
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
