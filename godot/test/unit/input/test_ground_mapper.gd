extends GdUnitTestSuite
## UX-48 GroundMapper (06 s3.2, R0 B.31 A-154): drive, steer, BRAKE, FIRE1 and the barrel holds for the three input
## classes; stick Y and mouse Y never reach pitch; no roll, BOOST, FLIP, DOCK, FIRE2; yaw + = left; orbit intent.

const TMP: String = "user://test_ground_mapper/input_map.cfg"

const ILLEGAL: int = PilotInput.BOOST | PilotInput.FLIP | PilotInput.DOCK | PilotInput.FIRE2


func after_test() -> void:
	if FileAccess.file_exists(TMP):
		var _e: Error = DirAccess.remove_absolute(TMP)


# --- gamepad ---------------------------------------------------------------------------------------------------

func test_pad_ls_forward_is_thrust_and_back_is_brake() -> void:
	var m: GroundMapper = GroundMapper.new()
	var st: PadState = PadState.new()
	st.left_stick = Vector2(0.0, -1.0)
	var fwd: PilotInput = m.map_pad(st)
	assert_float(fwd.thrust).is_equal(1.0)
	assert_int(fwd.buttons & PilotInput.BRAKE).is_equal(0)
	st.left_stick = Vector2(0.0, 1.0)
	var back: PilotInput = m.map_pad(st)
	assert_float(back.thrust).is_equal(0.0)
	assert_int(back.buttons & PilotInput.BRAKE).is_equal(PilotInput.BRAKE)


func test_pad_ls_x_steers_with_plus_left() -> void:
	var m: GroundMapper = GroundMapper.new()
	var st: PadState = PadState.new()
	st.left_stick = Vector2(-1.0, 0.0)
	assert_float(m.map_pad(st).yaw).is_equal(1.0)
	st.left_stick = Vector2(1.0, 0.0)
	assert_float(m.map_pad(st).yaw).is_equal(-1.0)


func test_pad_rt_fires_and_rb_lb_hold_the_barrel() -> void:
	var m: GroundMapper = GroundMapper.new()
	var st: PadState = PadState.new()
	st.right_trigger = 1.0
	assert_int(m.map_pad(st).buttons & PilotInput.FIRE1).is_equal(PilotInput.FIRE1)
	st.right_trigger = 0.0
	var s: BindingStore = BindingStore.new(TMP)
	var held: PackedInt32Array = PackedInt32Array([JOY_BUTTON_RIGHT_SHOULDER])
	var up: PadState = PadState.with_buttons(PadState.new(), held, s)
	assert_float(m.map_pad(up).pitch).is_equal(1.0)
	held = PackedInt32Array([JOY_BUTTON_LEFT_SHOULDER])
	assert_float(m.map_pad(PadState.with_buttons(PadState.new(), held, s)).pitch).is_equal(-1.0)
	held = PackedInt32Array([JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER])
	assert_float(m.map_pad(PadState.with_buttons(PadState.new(), held, s)).pitch).is_equal(0.0)
	assert_float(m.map_pad(PadState.new()).pitch).is_equal(0.0)   # released: the barrel holds


func test_pad_ground_barrel_follows_a_remap_and_ignores_yaw_buttons() -> void:
	var s: BindingStore = BindingStore.new(TMP)
	var _c: StringName = s.bind(BindingStore.PAD, &"barrel_up", 0, JOY_BUTTON_X)
	var m: GroundMapper = GroundMapper.new()
	var x: PadState = PadState.with_buttons(PadState.new(), PackedInt32Array([JOY_BUTTON_X]), s)
	assert_float(m.map_pad(x).pitch).is_equal(1.0)
	# RB is still yaw_right (the default) but is no longer barrel_up: the flight mapper would yaw on it, ground must not.
	var rb: PadState = PadState.with_buttons(PadState.new(), PackedInt32Array([JOY_BUTTON_RIGHT_SHOULDER]), s)
	assert_bool(rb.rb).is_true()
	assert_float(GamepadFlightMapper.new().map(rb, 1.0).yaw).is_less(0.0)   # the premise: yaw WOULD be non-zero
	var out: PilotInput = m.map_pad(rb)
	assert_float(out.yaw).is_equal(0.0)
	assert_float(out.pitch).is_equal(0.0)


func test_pad_right_stick_is_the_orbit_not_pitch() -> void:
	var m: GroundMapper = GroundMapper.new()
	var st: PadState = PadState.new()
	st.right_stick = Vector2(1.0, -1.0)
	var out: PilotInput = m.map_pad(st)
	assert_float(out.pitch).is_equal(0.0)
	assert_float(out.yaw).is_equal(0.0)
	assert_float(m.orbit.x).is_greater(0.5)
	assert_float(m.orbit.y).is_less(-0.5)


# --- KBM -------------------------------------------------------------------------------------------------------

func test_kbm_w_s_drive_and_a_d_steer_through_the_steer_actions() -> void:
	var s: BindingStore = BindingStore.new(TMP)
	var m: GroundMapper = GroundMapper.new()
	var w: PilotInput = m.map_kbm(KbmState.from_held(PackedInt32Array([KEY_W]), Vector2.ZERO, s))
	assert_float(w.thrust).is_equal(1.0)
	var back: PilotInput = m.map_kbm(KbmState.from_held(PackedInt32Array([KEY_S]), Vector2.ZERO, s))
	assert_int(back.buttons & PilotInput.BRAKE).is_equal(PilotInput.BRAKE)
	assert_float(back.thrust).is_equal(0.0)
	assert_float(m.map_kbm(KbmState.from_held(PackedInt32Array([KEY_A]), Vector2.ZERO, s)).yaw).is_equal(1.0)
	assert_float(m.map_kbm(KbmState.from_held(PackedInt32Array([KEY_D]), Vector2.ZERO, s)).yaw).is_equal(-1.0)
	# A steer comes from steer_left, not yaw_left: rebinding steer_left moves it, and the old A no longer steers.
	var _c: StringName = s.bind(BindingStore.KBM, &"steer_left", 0, KEY_J)
	assert_float(m.map_kbm(KbmState.from_held(PackedInt32Array([KEY_J]), Vector2.ZERO, s)).yaw).is_equal(1.0)
	assert_float(m.map_kbm(KbmState.from_held(PackedInt32Array([KEY_A]), Vector2.ZERO, s)).yaw).is_equal(0.0)


func test_kbm_e_q_hold_the_barrel_and_lmb_fires() -> void:
	var s: BindingStore = BindingStore.new(TMP)
	var m: GroundMapper = GroundMapper.new()
	assert_float(m.map_kbm(KbmState.from_held(PackedInt32Array([KEY_E]), Vector2.ZERO, s)).pitch).is_equal(1.0)
	assert_float(m.map_kbm(KbmState.from_held(PackedInt32Array([KEY_Q]), Vector2.ZERO, s)).pitch).is_equal(-1.0)
	assert_float(m.map_kbm(KbmState.from_held(PackedInt32Array([KEY_Q, KEY_E]), Vector2.ZERO, s)).pitch).is_equal(0.0)
	var st: KbmState = KbmState.from_held(PackedInt32Array(), Vector2.ZERO, s)
	st.lmb = true
	st.rmb = true
	var out: PilotInput = m.map_kbm(st)
	assert_int(out.buttons & PilotInput.FIRE1).is_equal(PilotInput.FIRE1)
	assert_int(out.buttons & PilotInput.FIRE2).is_equal(0)


func test_kbm_mouse_motion_never_reaches_pilot_input() -> void:
	var m: GroundMapper = GroundMapper.new()
	var st: KbmState = KbmState.new()
	st.mouse_delta = Vector2(40.0, -90.0)
	var out: PilotInput = m.map_kbm(st)
	assert_float(out.pitch).is_equal(0.0)
	assert_float(out.roll).is_equal(0.0)
	assert_float(out.yaw).is_equal(0.0)
	assert_vector(m.orbit).is_equal(Vector2(40.0, -90.0))


# --- touch -----------------------------------------------------------------------------------------------------

func test_touch_stick_drives_and_steers_and_buttons_map() -> void:
	var m: GroundMapper = GroundMapper.new()
	var st: TouchState = TouchState.new()
	st.stick = Vector2(0.0, 1.0)
	assert_float(m.map_touch(st).thrust).is_equal(1.0)
	st.stick = Vector2(0.0, -1.0)
	var back: PilotInput = m.map_touch(st)
	assert_float(back.thrust).is_equal(0.0)
	assert_int(back.buttons & PilotInput.BRAKE).is_equal(PilotInput.BRAKE)
	st.stick = Vector2(1.0, 0.0)
	assert_float(m.map_touch(st).yaw).is_equal(-1.0)   # right = - (+ is left)
	st.stick = Vector2.ZERO
	st.fire1 = true
	assert_int(m.map_touch(st).buttons & PilotInput.FIRE1).is_equal(PilotInput.FIRE1)
	st.fire1 = false
	st.barrel_up = true
	assert_float(m.map_touch(st).pitch).is_equal(1.0)
	st.barrel_up = false
	st.barrel_down = true
	assert_float(m.map_touch(st).pitch).is_equal(-1.0)


func test_touch_state_polls_the_barrel_actions() -> void:
	if not InputMap.has_action(TouchState.A_BARREL_UP):
		InputMap.add_action(TouchState.A_BARREL_UP)
	Input.action_press(TouchState.A_BARREL_UP, 1.0)
	assert_bool(TouchState.poll().barrel_up).is_true()
	assert_bool(TouchState.poll().barrel_down).is_false()
	Input.action_release(TouchState.A_BARREL_UP)
	InputMap.erase_action(TouchState.A_BARREL_UP)


func test_three_simultaneous_touches_stick_fire_and_barrel() -> void:
	var m: GroundMapper = GroundMapper.new()
	var st: TouchState = TouchState.new()
	st.stick = Vector2(-1.0, 1.0)
	st.fire1 = true
	st.barrel_up = true
	var out: PilotInput = m.map_touch(st)
	assert_float(out.thrust).is_greater(0.5)
	assert_float(out.yaw).is_greater(0.5)
	assert_float(out.pitch).is_equal(1.0)
	assert_int(out.buttons & PilotInput.FIRE1).is_equal(PilotInput.FIRE1)


# --- always ----------------------------------------------------------------------------------------------------

func test_every_class_sends_no_roll_and_no_flight_only_bits() -> void:
	var m: GroundMapper = GroundMapper.new()
	var pad: PadState = PadState.new()
	pad.left_stick = Vector2(1.0, -1.0)
	pad.right_stick = Vector2(1.0, 1.0)
	pad.a = true
	pad.b = true
	pad.x = true
	pad.y = true
	pad.l3 = true
	var kbm: KbmState = KbmState.new()
	kbm.shift = true
	kbm.space = true
	kbm.f = true
	kbm.rmb = true
	kbm.mouse_delta = Vector2(30.0, 30.0)
	var touch: TouchState = TouchState.new()
	touch.stick = Vector2(1.0, 1.0)
	touch.boost = true
	touch.flip = true
	touch.dock = true
	touch.fire2 = true
	for out: PilotInput in [m.map_pad(pad), m.map_kbm(kbm), m.map_touch(touch)]:
		assert_float(out.roll).is_equal(0.0)
		assert_int(out.buttons & ILLEGAL).is_equal(0)


func test_invert_pitch_is_not_applied() -> void:
	var m: GroundMapper = GroundMapper.new()
	assert_bool("invert_pitch" in m).is_false()
	var s: BindingStore = BindingStore.new(TMP)
	var out: PilotInput = m.map_kbm(KbmState.from_held(PackedInt32Array([KEY_E]), Vector2.ZERO, s))
	assert_float(out.pitch).is_equal(1.0)


func test_stick_y_and_mouse_y_leave_pitch_at_zero() -> void:
	var m: GroundMapper = GroundMapper.new()
	var pad: PadState = PadState.new()
	pad.left_stick = Vector2(0.0, -1.0)
	pad.right_stick = Vector2(0.0, -1.0)
	assert_float(m.map_pad(pad).pitch).is_equal(0.0)
	var kbm: KbmState = KbmState.new()
	kbm.mouse_delta = Vector2(0.0, -500.0)
	assert_float(m.map_kbm(kbm).pitch).is_equal(0.0)
	var touch: TouchState = TouchState.new()
	touch.stick = Vector2(0.0, 1.0)
	assert_float(m.map_touch(touch).pitch).is_equal(0.0)


func test_release_is_one_tick_per_press_on_every_class() -> void:
	var m: GroundMapper = GroundMapper.new()
	var pad: PadState = PadState.new()
	pad.dpad_down = true
	assert_int(m.map_pad(pad).buttons & PilotInput.RELEASE).is_equal(PilotInput.RELEASE)
	assert_int(m.map_pad(pad).buttons & PilotInput.RELEASE).is_equal(0)
	m = GroundMapper.new()   # the edge memory is per press, not per class
	var kbm: KbmState = KbmState.new()
	kbm.r = true
	assert_int(m.map_kbm(kbm).buttons & PilotInput.RELEASE).is_equal(PilotInput.RELEASE)
	assert_int(m.map_kbm(kbm).buttons & PilotInput.RELEASE).is_equal(0)
	m = GroundMapper.new()
	var touch: TouchState = TouchState.new()
	touch.release = true
	assert_int(m.map_touch(touch).buttons & PilotInput.RELEASE).is_equal(PilotInput.RELEASE)
	assert_int(m.map_touch(touch).buttons & PilotInput.RELEASE).is_equal(0)


func test_sample_for_uses_the_poller_of_the_class() -> void:
	var m: GroundMapper = GroundMapper.new()
	var pad: PadState = PadState.new()
	pad.right_trigger = 1.0
	m.pad_poller = func() -> PadState: return pad
	assert_int(m.sample_for(InputClass.Kind.GAMEPAD).buttons & PilotInput.FIRE1).is_equal(PilotInput.FIRE1)
	var touch: TouchState = TouchState.new()
	touch.barrel_down = true
	m.touch_poller = func() -> TouchState: return touch
	assert_float(m.sample_for(InputClass.Kind.TOUCH).pitch).is_equal(-1.0)
	var kbm: KbmState = KbmState.new()
	kbm.barrel_up = true
	m.kbm_poller = func() -> KbmState: return kbm
	assert_float(m.sample_for(InputClass.Kind.POINTER).pitch).is_equal(1.0)
