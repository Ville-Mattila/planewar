extends GdUnitTestSuite
## UX-09 Glyphs: glyphs.json joypad-name table, per-set labels, and the swap within one frame of a device change.


func test_joy_names_map_to_sets() -> void:
	assert_str(String(Glyphs.set_for_joy_name("Steam Deck Controller"))).is_equal("deck")
	assert_str(String(Glyphs.set_for_joy_name("Xbox Series Controller"))).is_equal("xbox")
	assert_str(String(Glyphs.set_for_joy_name("PS5 Controller"))).is_equal("ps")
	assert_str(String(Glyphs.set_for_joy_name("DualSense Wireless Controller"))).is_equal("ps")
	assert_str(String(Glyphs.set_for_joy_name("Nintendo Switch Pro Controller"))).is_equal("nintendo")
	assert_str(String(Glyphs.set_for_joy_name("Mystery Pad"))).is_equal("generic")
	assert_str(String(Glyphs.set_for_joy_name(""))).is_equal("generic")


func test_device_monitor_delegates_to_the_table() -> void:
	for n: String in ["Xbox 360 Controller", "PS4 Controller", "Joy-Con", "Steam Deck", "foo"]:
		assert_str(String(DeviceMonitor.glyphs_for_joy_name(n))).is_equal(String(Glyphs.set_for_joy_name(n)))


func test_every_set_labels_every_remappable_button() -> void:
	var sets: Array[StringName] = Glyphs.set_ids()
	assert_int(sets.size()).is_equal(5)
	for gs: StringName in sets:
		for id: StringName in Glyphs.BUTTON_IDS:
			var label: String = Glyphs.pad_label(gs, Glyphs.BUTTON_IDS[id])
			assert_bool(label.begins_with("#")).override_failure_message("%s/%s unlabelled" % [gs, id]).is_false()


func test_labels_differ_by_family() -> void:
	assert_str(Glyphs.pad_label(&"xbox", JOY_BUTTON_A)).is_equal("A")
	assert_str(Glyphs.pad_label(&"ps", JOY_BUTTON_A)).is_equal("Cross")
	assert_str(Glyphs.pad_label(&"nintendo", JOY_BUTTON_A)).is_equal("B")
	assert_str(Glyphs.pad_label(&"deck", JOY_BUTTON_LEFT_SHOULDER)).is_equal("L1")
	assert_str(Glyphs.pad_label(&"unknown_set", JOY_BUTTON_X)).is_equal("X")   # falls back to generic


func test_unbound_and_key_labels() -> void:
	assert_str(Glyphs.pad_label(&"xbox", -1)).is_equal("-")
	assert_str(Glyphs.key_label(BindingStore.UNBOUND)).is_equal("-")
	assert_str(Glyphs.key_label(KEY_W)).is_equal("W")
	assert_int(Glyphs.key_from_name("Space")).is_equal(KEY_SPACE)
	assert_int(Glyphs.key_from_name("")).is_equal(BindingStore.UNBOUND)
	assert_str(Glyphs.binding_label(&"ps", &"kbm", KEY_W)).is_equal("W")
	assert_str(Glyphs.binding_label(&"ps", &"pad", JOY_BUTTON_Y)).is_equal("Triangle")


func test_no_kbm_glyphs_while_a_gamepad_is_active() -> void:
	assert_str(String(Glyphs.set_for_class(InputClass.Kind.GAMEPAD, &"kbm"))).is_equal("generic")
	assert_str(String(Glyphs.set_for_class(InputClass.Kind.GAMEPAD, &"ps"))).is_equal("ps")
	assert_str(String(Glyphs.set_for_class(InputClass.Kind.POINTER, &"ps"))).is_equal("kbm")


func test_glyph_set_swaps_in_the_same_call_as_the_device_change() -> void:
	var m: DeviceMonitor = DeviceMonitor.new(InputClass.Kind.POINTER)
	assert_str(String(m.glyph_set)).is_equal("kbm")
	var b: InputEventJoypadButton = InputEventJoypadButton.new()
	b.pressed = true
	b.button_index = JOY_BUTTON_A
	assert_bool(m.feed(b, 0)).is_true()   # one event -> changed -> router emits glyph_set_changed this frame
	assert_str(String(m.glyph_set)).is_not_equal("kbm")
	var k: InputEventKey = InputEventKey.new()
	k.pressed = true
	k.keycode = KEY_W
	m.key_bound = func(_e: InputEvent) -> bool: return true
	assert_bool(m.feed(k, 1)).is_true()
	assert_str(String(m.glyph_set)).is_equal("kbm")
