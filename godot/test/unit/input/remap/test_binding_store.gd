extends GdUnitTestSuite
## UX-09 BindingStore: defaults, conflicts flagged (never refused), persistence across a restart, feeding the flight states.

const TMP: String = "user://test_remap/input_map.cfg"


func after_test() -> void:
	if FileAccess.file_exists(TMP):
		var _e: Error = DirAccess.remove_absolute(TMP)


func test_defaults_match_the_s3_1_keys_and_pad_buttons() -> void:
	var s: BindingStore = BindingStore.new(TMP)
	assert_int(s.code(BindingStore.KBM, &"throttle_up", 0)).is_equal(KEY_W)
	assert_int(s.code(BindingStore.KBM, &"yaw_left", 0)).is_equal(KEY_A)
	assert_int(s.code(BindingStore.KBM, &"yaw_left", 1)).is_equal(KEY_Q)
	assert_int(s.code(BindingStore.KBM, &"boost", 0)).is_equal(KEY_SHIFT)
	assert_int(s.code(BindingStore.KBM, &"boost", 1)).is_equal(BindingStore.UNBOUND)
	assert_int(s.code(BindingStore.PAD, &"fire1")).is_equal(JOY_BUTTON_A)
	assert_int(s.code(BindingStore.PAD, &"release")).is_equal(JOY_BUTTON_DPAD_DOWN)
	assert_bool(s.conflicted(BindingStore.KBM).is_empty()).is_true()
	assert_bool(s.conflicted(BindingStore.PAD).is_empty()).is_true()


func test_conflict_is_flagged_not_refused() -> void:
	var s: BindingStore = BindingStore.new(TMP)
	var other: StringName = s.bind(BindingStore.KBM, &"flip", 0, KEY_W)
	assert_str(String(other)).is_equal("throttle_up")
	assert_int(s.code(BindingStore.KBM, &"flip", 0)).is_equal(KEY_W)
	var flagged: Array[StringName] = s.conflicted(BindingStore.KBM)
	assert_bool(flagged.has(&"flip")).is_true()
	assert_bool(flagged.has(&"throttle_up")).is_true()
	assert_bool(flagged.has(&"brake")).is_false()
	assert_str(String(s.bind(BindingStore.KBM, &"flip", 0, KEY_G))).is_equal("")
	assert_bool(s.conflicted(BindingStore.KBM).is_empty()).is_true()


func test_two_slots_of_one_action_are_not_a_conflict() -> void:
	var s: BindingStore = BindingStore.new(TMP)
	assert_str(String(s.bind(BindingStore.KBM, &"boost", 1, KEY_SHIFT))).is_equal("")


func test_pad_conflict_and_clear() -> void:
	var s: BindingStore = BindingStore.new(TMP)
	assert_str(String(s.bind(BindingStore.PAD, &"flip", 0, JOY_BUTTON_A))).is_equal("fire1")
	s.clear(BindingStore.PAD, &"flip")
	assert_int(s.code(BindingStore.PAD, &"flip")).is_equal(BindingStore.UNBOUND)
	assert_str(String(s.conflict_of(BindingStore.PAD, &"flip"))).is_equal("")


func test_remaps_persist_across_a_restart() -> void:
	var a: BindingStore = BindingStore.new(TMP)
	var _c: StringName = a.bind(BindingStore.KBM, &"dock", 0, KEY_G)
	_c = a.bind(BindingStore.KBM, &"dock", 1, KEY_H)
	_c = a.bind(BindingStore.PAD, &"dock", 0, JOY_BUTTON_RIGHT_SHOULDER)
	assert_int(a.save()).is_equal(OK)
	var b: BindingStore = BindingStore.new(TMP)
	assert_int(b.code(BindingStore.KBM, &"dock", 0)).is_equal(KEY_F)   # defaults before load
	assert_int(b.load_file()).is_equal(OK)
	assert_int(b.code(BindingStore.KBM, &"dock", 0)).is_equal(KEY_G)
	assert_int(b.code(BindingStore.KBM, &"dock", 1)).is_equal(KEY_H)
	assert_int(b.code(BindingStore.PAD, &"dock")).is_equal(JOY_BUTTON_RIGHT_SHOULDER)
	assert_int(b.code(BindingStore.KBM, &"throttle_up", 0)).is_equal(KEY_W)


func test_file_carries_a_version_and_a_newer_file_is_ignored() -> void:
	var a: BindingStore = BindingStore.new(TMP)
	var _c: StringName = a.bind(BindingStore.KBM, &"dock", 0, KEY_G)
	assert_int(a.save()).is_equal(OK)
	var cf: ConfigFile = ConfigFile.new()
	assert_int(cf.load(TMP)).is_equal(OK)
	assert_int(int(cf.get_value("meta", "version", 0))).is_equal(BindingStore.FILE_VERSION)
	cf.set_value("meta", "version", BindingStore.FILE_VERSION + 1)
	assert_int(cf.save(TMP)).is_equal(OK)
	var b: BindingStore = BindingStore.new(TMP)
	assert_int(b.load_file()).is_not_equal(OK)
	assert_int(b.code(BindingStore.KBM, &"dock", 0)).is_equal(KEY_F)


func test_missing_or_malformed_file_keeps_defaults() -> void:
	var s: BindingStore = BindingStore.new("user://test_remap/none.cfg")
	assert_int(s.load_file()).is_equal(OK)
	assert_int(s.code(BindingStore.KBM, &"flip", 0)).is_equal(KEY_SPACE)
	var cf: ConfigFile = ConfigFile.new()
	cf.set_value("kbm", "flip", "garbage")
	cf.set_value("kbm", "nonsense_action", [1, 2])
	cf.set_value("pad", "flip", "x")
	var _e: Error = DirAccess.make_dir_recursive_absolute("user://test_remap")
	assert_int(cf.save(TMP)).is_equal(OK)
	var t: BindingStore = BindingStore.new(TMP)
	assert_int(t.load_file()).is_equal(OK)
	assert_int(t.code(BindingStore.KBM, &"flip", 0)).is_equal(KEY_SPACE)
	assert_int(t.code(BindingStore.PAD, &"flip")).is_equal(JOY_BUTTON_Y)


func test_reset_restores_one_device_only() -> void:
	var s: BindingStore = BindingStore.new(TMP)
	var _c: StringName = s.bind(BindingStore.KBM, &"flip", 0, KEY_G)
	_c = s.bind(BindingStore.PAD, &"flip", 0, JOY_BUTTON_X)
	s.reset(BindingStore.KBM)
	assert_int(s.code(BindingStore.KBM, &"flip", 0)).is_equal(KEY_SPACE)
	assert_int(s.code(BindingStore.PAD, &"flip")).is_equal(JOY_BUTTON_X)


func test_kbm_state_follows_remapped_keys() -> void:
	var s: BindingStore = BindingStore.new(TMP)
	var held: PackedInt32Array = PackedInt32Array([KEY_W, KEY_Q])
	var d: KbmState = KbmState.from_held(held, Vector2.ZERO, s)
	assert_bool(d.w).is_true()
	assert_bool(d.q).is_true()
	assert_bool(d.a).is_false()
	var _c: StringName = s.bind(BindingStore.KBM, &"throttle_up", 0, KEY_UP)
	var m: KbmState = KbmState.from_held(held, Vector2.ZERO, s)
	assert_bool(m.w).is_false()
	assert_bool(KbmState.from_held(PackedInt32Array([KEY_UP]), Vector2.ZERO, s).w).is_true()
	_c = s.bind(BindingStore.KBM, &"flip", 1, KEY_V)
	assert_bool(KbmState.from_held(PackedInt32Array([KEY_V]), Vector2.ZERO, s).space).is_true()


func test_pad_state_follows_remapped_buttons() -> void:
	var s: BindingStore = BindingStore.new(TMP)
	var base: PadState = PadState.with_buttons(PadState.new(), PackedInt32Array([JOY_BUTTON_A]), s)
	assert_bool(base.a).is_true()
	assert_bool(base.y).is_false()
	var _c: StringName = s.bind(BindingStore.PAD, &"flip", 0, JOY_BUTTON_LEFT_SHOULDER)
	var st: PadState = PadState.with_buttons(PadState.new(), PackedInt32Array([JOY_BUTTON_LEFT_SHOULDER]), s)
	assert_bool(st.y).is_true()
	assert_bool(st.lb).is_true()   # the old yaw_left default now conflicts; both fire, which is what "flagged" means


func _press_physical(code: Key, pressed: bool) -> void:
	var e: InputEventKey = InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = pressed
	Input.parse_input_event(e)
	Input.flush_buffered_events()


## No poller: sample() must forward its `bindings` member to KbmState.poll. A mapper that ignored `bindings`
## would poll the defaults (Space = flip) and see no FLIP for G.
func test_mapper_forwards_its_bindings_member_to_poll() -> void:
	var s: BindingStore = BindingStore.new(TMP)
	var _c: StringName = s.bind(BindingStore.KBM, &"flip", 0, KEY_G)
	var m: KbmFlightMapper = KbmFlightMapper.new()
	m.bindings = s
	_press_physical(KEY_G, true)
	var got: int = m.sample(1.0 / 30.0).buttons
	_press_physical(KEY_G, false)
	assert_int(got & PilotInput.FLIP).is_equal(PilotInput.FLIP)
	var plain: KbmFlightMapper = KbmFlightMapper.new()   # defaults: G is not bound
	_press_physical(KEY_G, true)
	var none: int = plain.sample(1.0 / 30.0).buttons
	_press_physical(KEY_G, false)
	assert_int(none & PilotInput.FLIP).is_equal(0)
