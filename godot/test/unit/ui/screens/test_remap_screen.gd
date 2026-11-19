extends GdUnitTestSuite
## UX-09 remapping screen: RemapModel capture/conflict/persist, glyph swap, pad-only navigation, 9 du floor.

const TMP: String = "user://test_remap_ui/input_map.cfg"


func before() -> void:
	assert_bool(ContentDB.load_all().ok).is_true()
	var _n: int = LocaleSelect.register_translations("res://content/locale")
	var _l: String = LocaleSelect.apply("en")


func after_test() -> void:
	if FileAccess.file_exists(TMP):
		var _e: Error = DirAccess.remove_absolute(TMP)


func _key(code: Key) -> InputEventKey:
	var e: InputEventKey = InputEventKey.new()
	e.pressed = true
	e.physical_keycode = code
	return e


func _btn(i: JoyButton) -> InputEventJoypadButton:
	var e: InputEventJoypadButton = InputEventJoypadButton.new()
	e.pressed = true
	e.button_index = i
	return e


func _screen() -> RemapScreen:
	var s: RemapScreen = (load("res://scenes/ui/screens/remap.tscn") as PackedScene).instantiate() as RemapScreen
	s.model = RemapModel.new(BindingStore.new(TMP))
	add_child(s)
	return s


func test_capture_binds_persists_and_flags_a_conflict() -> void:
	var m: RemapModel = RemapModel.new(BindingStore.new(TMP))
	assert_bool(m.capture(_key(KEY_G))).is_false()   # not listening: untouched
	m.begin_listen(&"flip", 0)
	assert_bool(m.capture(_key(KEY_W))).is_true()
	assert_str(String(m.last_conflict)).is_equal("throttle_up")
	assert_bool(m.has_conflicts()).is_true()
	assert_bool(m.is_listening()).is_false()
	var reloaded: BindingStore = BindingStore.new(TMP)
	assert_int(reloaded.load_file()).is_equal(OK)
	assert_int(reloaded.code(BindingStore.KBM, &"flip", 0)).is_equal(KEY_W)


func test_escape_cancels_delete_clears_and_wrong_device_is_ignored() -> void:
	var m: RemapModel = RemapModel.new(BindingStore.new(TMP))
	m.begin_listen(&"flip", 0)
	assert_bool(m.capture(_btn(JOY_BUTTON_A))).is_false()   # pad event on the keyboard tab
	assert_bool(m.is_listening()).is_true()
	assert_bool(m.capture(_key(KEY_ESCAPE))).is_true()
	assert_int(m.store.code(BindingStore.KBM, &"flip", 0)).is_equal(KEY_SPACE)
	m.begin_listen(&"flip", 0)
	assert_bool(m.capture(_key(KEY_DELETE))).is_true()
	assert_int(m.store.code(BindingStore.KBM, &"flip", 0)).is_equal(BindingStore.UNBOUND)


func test_pad_tab_capture_cancel_and_clear() -> void:
	var m: RemapModel = RemapModel.new(BindingStore.new(TMP))
	m.set_device(BindingStore.PAD)
	assert_int(m.slot_count()).is_equal(1)
	m.begin_listen(&"flip", 0)
	assert_bool(m.capture(_btn(JOY_BUTTON_START))).is_true()
	assert_int(m.store.code(BindingStore.PAD, &"flip")).is_equal(JOY_BUTTON_Y)
	m.begin_listen(&"flip", 0)
	assert_bool(m.capture(_btn(JOY_BUTTON_LEFT_SHOULDER))).is_true()
	assert_str(String(m.last_conflict)).is_equal("yaw_left")
	m.begin_listen(&"flip", 0)
	assert_bool(m.capture(_btn(JOY_BUTTON_BACK))).is_true()
	assert_int(m.store.code(BindingStore.PAD, &"flip")).is_equal(BindingStore.UNBOUND)


func test_model_labels_follow_the_glyph_set() -> void:
	var m: RemapModel = RemapModel.new(BindingStore.new(TMP))
	m.set_device(BindingStore.PAD)
	assert_str(m.label(&"fire1", 0, &"xbox")).is_equal("A")
	assert_str(m.label(&"fire1", 0, &"ps")).is_equal("Cross")


func test_screen_labels_swap_at_once_on_a_glyph_set_change() -> void:
	var s: RemapScreen = _screen()
	s._show_device(BindingStore.PAD)
	s.set_glyph_set(&"xbox")
	assert_str(s.slot_button(&"fire1", 0).text).is_equal("A")
	s.set_glyph_set(&"ps")
	assert_str(s.slot_button(&"fire1", 0).text).is_equal("Cross")
	s.free()


func test_screen_listens_flags_conflict_and_back_cancels() -> void:
	var s: RemapScreen = _screen()
	assert_object(s.initial_focus()).is_same(s.slot_button(&"throttle_up", 0))
	assert_str(s.slot_button(&"throttle_up", 0).text).is_equal("W")
	s.slot_button(&"flip", 0).pressed.emit()
	assert_bool(s.model.is_listening()).is_true()
	assert_str(s.prompt_text()).contains("Esc")
	assert_bool(s.handle_back()).is_true()   # B / Esc cancels listening first
	assert_bool(s.model.is_listening()).is_false()
	s.model.begin_listen(&"flip", 0)
	assert_bool(s.model.capture(_key(KEY_W))).is_true()
	s.refresh()
	assert_str(s.prompt_text()).contains("share")
	s.free()


func test_done_and_reset_are_pad_reachable_buttons() -> void:
	var s: RemapScreen = _screen()
	var got: Array[int] = [0]
	s.done_requested.connect(func() -> void: got[0] += 1)
	assert_bool(s.handle_back()).is_true()
	assert_int(got[0]).is_equal(1)
	assert_int(s._done.focus_mode).is_equal(Control.FOCUS_ALL)
	assert_int(s._reset.focus_mode).is_equal(Control.FOCUS_ALL)
	for b: Button in s._slot_buttons:
		assert_int(b.focus_mode).is_equal(Control.FOCUS_ALL)
		assert_float(b.custom_minimum_size.y).is_greater_equal(44.0)
		assert_int(b.get_theme_font_size(&"font_size")).is_greater_equal(int(HudMath.param("font_du_min")))
	s.free()


func test_reset_button_restores_defaults() -> void:
	var s: RemapScreen = _screen()
	var _c: StringName = s.model.store.bind(BindingStore.KBM, &"flip", 0, KEY_G)
	s.refresh()
	s._reset.pressed.emit()
	assert_str(s.slot_button(&"flip", 0).text).is_equal("Space")
	s.free()


func test_selected_tab_is_the_listed_device_for_both_devices() -> void:
	var s: RemapScreen = _screen()
	for d: StringName in [BindingStore.PAD, BindingStore.KBM]:
		s._show_device(d)
		var other: StringName = BindingStore.KBM if d == BindingStore.PAD else BindingStore.PAD
		assert_bool(s.tab_pressed(d)).is_true()
		assert_bool(s.tab_pressed(other)).is_false()
		assert_bool(s._tab_buttons[d].disabled).is_false()   # selected is highlighted, never dimmed
		assert_bool(s._tab_buttons[other].disabled).is_false()
		var acts: Array[StringName] = s.model.store.actions(d)
		assert_int(s._slot_buttons.size()).is_equal(acts.size() * s.model.slot_count())
		for a: StringName in acts:
			for slot: int in s.model.slot_count():
				assert_str(s.slot_button(a, slot).text).is_equal(
						Glyphs.binding_label(s.glyph_set, d, s.model.store.code(d, a, slot)))
	s.free()


func test_lb_rb_and_page_keys_switch_tabs() -> void:
	var s: RemapScreen = _screen()
	assert_int(RemapScreen.tab_step(_btn(JOY_BUTTON_RIGHT_SHOULDER))).is_equal(1)
	assert_int(RemapScreen.tab_step(_btn(JOY_BUTTON_LEFT_SHOULDER))).is_equal(-1)
	assert_int(RemapScreen.tab_step(_key(KEY_PAGEDOWN))).is_equal(1)
	assert_int(RemapScreen.tab_step(_key(KEY_PAGEUP))).is_equal(-1)
	assert_int(RemapScreen.tab_step(_key(KEY_A))).is_equal(0)
	assert_str(String(s.model.device)).is_equal("kbm")
	s._input(_btn(JOY_BUTTON_RIGHT_SHOULDER))
	assert_str(String(s.model.device)).is_equal("pad")
	assert_bool(s.tab_pressed(BindingStore.PAD)).is_true()
	s._input(_key(KEY_PAGEUP))
	assert_str(String(s.model.device)).is_equal("kbm")
	s._input(_btn(JOY_BUTTON_LEFT_SHOULDER))
	assert_str(String(s.model.device)).is_equal("pad")   # wraps
	s.free()


func test_tab_keys_are_bindable_while_listening_not_tab_switches() -> void:
	var s: RemapScreen = _screen()
	s._show_device(BindingStore.PAD)
	s.model.begin_listen(&"flip", 0)
	s._input(_btn(JOY_BUTTON_RIGHT_SHOULDER))
	assert_str(String(s.model.device)).is_equal("pad")
	assert_int(s.model.store.code(BindingStore.PAD, &"flip")).is_equal(JOY_BUTTON_RIGHT_SHOULDER)
	s.free()
