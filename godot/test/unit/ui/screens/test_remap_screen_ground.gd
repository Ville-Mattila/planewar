extends GdUnitTestSuite
## UX-48 remap screen: the ground actions sit under their own heading, the defaults show no conflict cue, a conflict
## inside the ground set does (R0 B.31 A-154).

const TMP: String = "user://test_remap_ui/input_map_ground.cfg"


func before() -> void:
	assert_bool(ContentDB.load_all().ok).is_true()
	var _n: int = LocaleSelect.register_translations("res://content/locale")
	var _l: String = LocaleSelect.apply("en")


func after_test() -> void:
	if FileAccess.file_exists(TMP):
		var _e: Error = DirAccess.remove_absolute(TMP)


func _screen() -> RemapScreen:
	var s: RemapScreen = (load("res://scenes/ui/screens/remap.tscn") as PackedScene).instantiate() as RemapScreen
	s.model = RemapModel.new(BindingStore.new(TMP))
	add_child(s)
	return s


func _headings(s: RemapScreen) -> Array[String]:
	var out: Array[String] = []
	for c: Node in s._rows_box.get_children():
		if c is Label:
			out.append((c as Label).text)
	return out


func _warn_count(s: RemapScreen) -> int:
	var n: int = 0
	for c: Node in s._rows_box.get_children():
		for g: Node in c.get_children():
			if g is Label:
				n += 1
	return n


func test_each_device_lists_the_ground_actions_under_their_own_heading() -> void:
	var s: RemapScreen = _screen()
	for d: StringName in [BindingStore.KBM, BindingStore.PAD]:
		s._show_device(d)
		assert_array(_headings(s)).is_equal([tr(&"ui.remap.set.flight"), tr(&"ui.remap.set.ground")])
		assert_str(tr(&"ui.remap.set.ground")).is_not_equal("ui.remap.set.ground")   # a real string, not the key
	s.free()


func test_ground_actions_have_slot_buttons_with_the_default_labels() -> void:
	var s: RemapScreen = _screen()
	assert_str(s.slot_button(&"steer_left", 0).text).is_equal("A")
	assert_str(s.slot_button(&"steer_right", 0).text).is_equal("D")
	assert_str(s.slot_button(&"barrel_up", 0).text).is_equal("E")
	assert_str(s.slot_button(&"barrel_down", 0).text).is_equal("Q")
	s._show_device(BindingStore.PAD)
	s.set_glyph_set(&"xbox")
	assert_str(s.slot_button(&"barrel_up", 0).text).is_equal(Glyphs.pad_label(&"xbox", JOY_BUTTON_RIGHT_SHOULDER))
	assert_str(s.slot_button(&"barrel_down", 0).text).is_equal(Glyphs.pad_label(&"xbox", JOY_BUTTON_LEFT_SHOULDER))
	s.free()


func test_the_defaults_show_no_conflict_cue_on_either_device() -> void:
	var s: RemapScreen = _screen()
	for d: StringName in [BindingStore.KBM, BindingStore.PAD]:
		s._show_device(d)
		assert_int(_warn_count(s)).is_equal(0)
		assert_str(s.prompt_text()).is_equal(tr(&"ui.remap.hint"))
	s.free()


func test_a_conflict_inside_the_ground_set_shows_a_cue() -> void:
	var s: RemapScreen = _screen()
	var other: StringName = s.model.store.bind(BindingStore.KBM, &"barrel_up", 0, KEY_A)
	s.refresh()
	assert_str(String(other)).is_equal("steer_left")
	assert_int(_warn_count(s)).is_greater(0)
	assert_str(s.prompt_text()).is_equal(tr(&"ui.remap.has_conflicts"))
	s.free()


func test_ground_rows_are_pad_focusable_at_the_text_floor() -> void:
	var s: RemapScreen = _screen()
	for b: Button in s._slot_buttons:
		assert_int(b.focus_mode).is_equal(Control.FOCUS_ALL)
		assert_int(b.get_theme_font_size(&"font_size")).is_greater_equal(int(HudMath.param("font_du_min")))
	s.free()
