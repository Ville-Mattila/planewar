class_name SfInput extends Node
## Device layer of the spike: keyboard + mouse (MOUSE_AIM default, DIRECT option), gamepad (DIRECT) and touch
## (ARCADE) all produce one `PilotInput` per tick (06 s3.1, s3.5). Input class switches on the first qualifying
## event (06 s2.4). Assist tiers FULL and RAW (06 s3.6): FULL adds auto-level, aim assist, auto-dock and, on
## touch, auto-throttle on the sticky slider; RAW is the bare mapping (auto-dock off).

enum InputClass { POINTER, GAMEPAD, TOUCH }
enum Tier { FULL, RAW }
enum MouseMode { MOUSE_AIM, DIRECT }
enum ThrustMode { POWER, LEVER }
const CLASS_NAMES: PackedStringArray = ["KBM", "GAMEPAD", "TOUCH"]

var input_class: InputClass = InputClass.POINTER
var tier: PackedInt32Array = PackedInt32Array([Tier.RAW, Tier.FULL, Tier.FULL])   # per class (06 defaults)
var mouse_mode: MouseMode = MouseMode.MOUSE_AIM
var thrust_mode: ThrustMode = ThrustMode.POWER
var invert_pitch: bool
var aim: Vector3 = Vector3.ZERO   # MOUSE_AIM world vector (unit), ZERO when unused
var touch: SfTouchLayer
var class_changed: bool
var capture_allowed: bool = true
var _p: Dictionary
var _a: Dictionary
var _out: PilotInput = PilotInput.new()
var _thr: float
var _kp: float                    # keyboard pitch / roll ramps (arrow keys)
var _kr: float
var _yaw_ramp: float
var _mouse_acc: Vector2 = Vector2.ZERO
var _neutral_t: float
var _fire_t: float
var _lever_prev: int
var _last_n: Vector3 = Vector3.ZERO


func setup(d: SfDefs, touch_layer: SfTouchLayer) -> void:
	_p = d.input
	_a = d.assist
	touch = touch_layer
	if OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios"):
		_set_class(InputClass.TOUCH)
	else:
		_set_class(InputClass.POINTER)


func current_tier() -> Tier:
	return tier[input_class] as Tier


func toggle_tier() -> void:
	tier[input_class] = Tier.RAW if current_tier() == Tier.FULL else Tier.FULL


func _set_class(c: InputClass) -> void:
	if c != input_class:
		class_changed = true
	input_class = c
	touch.visible = c == InputClass.TOUCH


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		_set_class(InputClass.TOUCH)
	elif event is InputEventJoypadButton:
		if (event as InputEventJoypadButton).pressed:
			_set_class(InputClass.GAMEPAD)
	elif event is InputEventJoypadMotion:
		if absf((event as InputEventJoypadMotion).axis_value) > SfDefs.num(_p, "axis_threshold"):
			_set_class(InputClass.GAMEPAD)
	elif event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event as InputEventMouseMotion
		if mm.device != InputEvent.DEVICE_ID_EMULATION:
			if mm.relative.length() > SfDefs.num(_p, "class_mouse_du"):
				_set_class(InputClass.POINTER)
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
				_mouse_acc += mm.relative
	elif event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.pressed and mb.device != InputEvent.DEVICE_ID_EMULATION:
			_set_class(InputClass.POINTER)
			if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and touch.active_touches == 0 and capture_allowed:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventKey:
		if (event as InputEventKey).pressed:
			_set_class(InputClass.POINTER)


## One tick of input for `w`'s ship. Returns a reused PilotInput.
func sample(w: SfWorld, dt: float) -> PilotInput:
	var s: ShipState = w.s
	_track_aim(s)
	_out.buttons = 0
	match input_class:
		InputClass.GAMEPAD:
			_gamepad(dt)
		InputClass.TOUCH:
			_touch(s, w.d)
		_:
			_kbm(s, dt)
	var stick_neutral: bool = absf(_out.pitch) < 0.05 and absf(_out.roll) < 0.05 and absf(_out.yaw) < 0.05
	if current_tier() == Tier.FULL:
		_auto_level(s, stick_neutral, dt)
		_aim_assist(w, dt)
	w.dock_allowed = current_tier() == Tier.FULL
	return _out


func _kbm(s: ShipState, dt: float) -> void:
	var ramp: float = SfDefs.num(_p, "kbm_thrust_ramp") * dt
	var w_key: bool = Input.is_physical_key_pressed(KEY_W)
	var s_key: bool = Input.is_physical_key_pressed(KEY_S)
	if thrust_mode == ThrustMode.POWER:
		_thr = move_toward(_thr, 1.0 if w_key else 0.0, ramp)
		if s_key:
			_out.buttons |= PilotInput.BRAKE
	else:
		var lever: int = (1 if w_key else 0) - (1 if s_key else 0)
		if lever != _lever_prev and lever != 0:
			_thr = clampf(_thr + float(lever) * SfDefs.num(_p, "lever_step"), 0.0, 1.0)
		_lever_prev = lever
		if s_key and _thr <= 0.0:
			_out.buttons |= PilotInput.BRAKE
	_out.thrust = _thr
	var kr: float = SfDefs.num(_p, "key_axis_ramp") * dt
	_kp = move_toward(_kp, _axis(KEY_UP, KEY_DOWN), kr)
	_kr = move_toward(_kr, _axis(KEY_RIGHT, KEY_LEFT), kr)
	var mouse: Vector2 = _mouse_acc
	_mouse_acc = Vector2.ZERO
	if mouse_mode == MouseMode.MOUSE_AIM and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_mouse_aim(s, mouse)
	else:
		aim = Vector3.ZERO
		_out.pitch = -_kp if invert_pitch else _kp
		_out.roll = _kr
		_out.yaw = 0.0
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:   # DIRECT: mouse is a virtual stick
			var k: float = SfDefs.num(_p, "mouse_deg_per_px") / SfDefs.num(_p, "mouse_pitch_full_deg")
			_out.pitch = clampf(_out.pitch - mouse.y * k * (-1.0 if invert_pitch else 1.0), -1.0, 1.0)
			_out.roll = clampf(_out.roll + mouse.x * k, -1.0, 1.0)
	if Input.is_physical_key_pressed(KEY_A):
		_out.roll = -1.0
	if Input.is_physical_key_pressed(KEY_D):
		_out.roll = 1.0
	_out.yaw += _axis(KEY_Q, KEY_E)
	if absf(_kp) > 0.0 and aim != Vector3.ZERO:
		_out.pitch = -_kp if invert_pitch else _kp
	_btn(Input.is_physical_key_pressed(KEY_SHIFT), PilotInput.BOOST)
	_btn(Input.is_physical_key_pressed(KEY_SPACE), PilotInput.FLIP)
	_btn(Input.is_physical_key_pressed(KEY_F), PilotInput.DOCK)
	_btn(Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_physical_key_pressed(KEY_CTRL), PilotInput.FIRE1)
	_btn(Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or Input.is_physical_key_pressed(KEY_V),
		PilotInput.FIRE2)


# 06 s3.5 MOUSE_AIM: the mouse turns the aim vector; the ship chases it.
func _mouse_aim(s: ShipState, mouse: Vector2) -> void:
	var n: Vector3 = s.p.normalized()
	if aim == Vector3.ZERO:
		aim = s.fwd
	var k: float = deg_to_rad(SfDefs.num(_p, "mouse_deg_per_px"))
	aim = aim.rotated(n, -mouse.x * k)
	var r: Vector3 = aim.cross(n)
	if r.length_squared() > 1e-8:
		var sgn: float = -1.0 if invert_pitch else 1.0
		var cand: Vector3 = aim.rotated(r.normalized(), -sgn * mouse.y * k)
		var lim: float = sin(deg_to_rad(SfDefs.num(_p, "aim_pitch_clamp_deg")))
		if absf(cand.dot(n)) <= lim:
			aim = cand
	aim = aim.normalized()
	var right: Vector3 = s.fwd.cross(s.up)
	var ax: float = aim.dot(right)
	var ay: float = aim.dot(s.up)
	var az: float = aim.dot(s.fwd)
	var alpha: float = rad_to_deg(s.fwd.angle_to(aim))
	_out.pitch = clampf(rad_to_deg(atan2(ay, az)) / SfDefs.num(_p, "mouse_pitch_full_deg"), -1.0, 1.0)
	_out.yaw = clampf(-rad_to_deg(atan2(ax, az)) / SfDefs.num(_p, "mouse_yaw_full_deg"), -1.0, 1.0)
	var full_r: float = SfDefs.num(_p, "mouse_roll_full_deg")
	if alpha > SfDefs.num(_p, "mouse_roll_engage_deg") and ay > 0.0:
		_out.roll = clampf(rad_to_deg(atan2(ax, ay)) / full_r, -1.0, 1.0)
	else:
		_out.roll = clampf(-rad_to_deg(SfChaseCamera.bank_angle(s.fwd, s.up, n)) / full_r, -1.0, 1.0)


# Keep the aim vector fixed relative to the local horizon as the ship moves over the sphere (CF transport).
func _track_aim(s: ShipState) -> void:
	var n: Vector3 = s.p.normalized()
	if aim != Vector3.ZERO and _last_n != Vector3.ZERO:
		aim = (Sphere.transport(_last_n, n) * aim).normalized()
	_last_n = n


## Reset the aim vector to the ship's nose (respawn, launch).
func reset_aim(s: ShipState) -> void:
	aim = s.fwd if aim != Vector3.ZERO else Vector3.ZERO
	_last_n = s.p.normalized()


func _gamepad(dt: float) -> void:
	var ls: Vector2 = _shape(Vector2(Input.get_joy_axis(0, JOY_AXIS_LEFT_X), -Input.get_joy_axis(0, JOY_AXIS_LEFT_Y)),
		SfDefs.num(_p, "dead_pad"), SfDefs.num(_p, "gamma_pad"))
	aim = Vector3.ZERO
	_out.roll = ls.x
	_out.pitch = -ls.y if invert_pitch else ls.y
	var yaw_t: float = (1.0 if Input.is_joy_button_pressed(0, JOY_BUTTON_LEFT_SHOULDER) else 0.0) \
		- (1.0 if Input.is_joy_button_pressed(0, JOY_BUTTON_RIGHT_SHOULDER) else 0.0)
	_yaw_ramp = move_toward(_yaw_ramp, yaw_t, dt / SfDefs.num(_p, "yaw_ramp_s"))
	_out.yaw = _yaw_ramp
	var rt: float = Input.get_joy_axis(0, JOY_AXIS_TRIGGER_RIGHT)
	_out.thrust = 0.0 if rt < SfDefs.num(_p, "trigger_dead") else rt
	_btn(Input.get_joy_axis(0, JOY_AXIS_TRIGGER_LEFT) > SfDefs.num(_p, "brake_trigger"), PilotInput.BRAKE)
	_btn(Input.is_joy_button_pressed(0, JOY_BUTTON_LEFT_STICK), PilotInput.BOOST)
	_btn(Input.is_joy_button_pressed(0, JOY_BUTTON_A), PilotInput.FIRE1)
	_btn(Input.is_joy_button_pressed(0, JOY_BUTTON_B), PilotInput.FIRE2)
	_btn(Input.is_joy_button_pressed(0, JOY_BUTTON_Y), PilotInput.FLIP)
	_btn(Input.is_joy_button_pressed(0, JOY_BUTTON_X), PilotInput.DOCK)


# 06 s3.5 ARCADE stick + sticky slider; FULL adds auto-throttle (06 s3.6).
func _touch(s: ShipState, d: SfDefs) -> void:
	aim = Vector3.ZERO
	var st: Vector2 = _shape(touch.stick, SfDefs.num(_p, "dead_touch"), SfDefs.num(_p, "gamma_touch"))
	var n: Vector3 = s.p.normalized()
	var phi: float = SfChaseCamera.bank_angle(s.fwd, s.up, n)
	var phi_t: float = st.x * deg_to_rad(SfDefs.num(_p, "arcade_bank_deg"))
	_out.roll = clampf((phi_t - phi) / deg_to_rad(SfDefs.num(_p, "arcade_roll_full_deg")), -1.0, 1.0)
	var pull: float = SfDefs.num(_p, "arcade_pull") * absf(st.x) \
		* clampf(absf(phi) / deg_to_rad(SfDefs.num(_p, "arcade_pull_bank_deg")), 0.0, 1.0)
	_out.pitch = clampf((-st.y if invert_pitch else st.y) + pull, -1.0, 1.0)
	_out.yaw = -SfDefs.num(_p, "arcade_yaw") * st.x
	var h: float = touch.slider_h
	if current_tier() == Tier.FULL:
		var v_fwd: float = s.v.dot(s.fwd)
		var v_star: float = h * d.ship.v_cruise
		_out.thrust = clampf((v_star - v_fwd) / SfDefs.num(_a, "auto_throttle_band_mps"), 0.0, 1.0)
		_btn(v_fwd - v_star > SfDefs.num(_a, "auto_throttle_brake_mps"), PilotInput.BRAKE)
	else:
		_out.thrust = h
	_btn(touch.held[SfTouchLayer.Btn.FIRE] == 1, PilotInput.FIRE1)
	_btn(touch.held[SfTouchLayer.Btn.BOMB] == 1, PilotInput.FIRE2)
	_btn(touch.held[SfTouchLayer.Btn.BRAKE] == 1, PilotInput.BRAKE)
	_btn(touch.held[SfTouchLayer.Btn.DOCK] == 1, PilotInput.DOCK)
	_btn(touch.boost_tap, PilotInput.BOOST)
	_btn(touch.flick, PilotInput.FLIP)
	touch.boost_tap = false
	touch.flick = false


# 06 s3.6 auto-level (FULL): after 0.25 s of neutral stick; off while the nose is in hover attitude (spike hook).
func _auto_level(s: ShipState, neutral: bool, dt: float) -> void:
	_neutral_t = _neutral_t + dt if neutral else 0.0
	if aim != Vector3.ZERO or _neutral_t < SfDefs.num(_a, "auto_level_delay_s"):
		return
	var n: Vector3 = s.p.normalized()
	var theta: float = asin(clampf(s.fwd.dot(n), -1.0, 1.0))
	if rad_to_deg(theta) > SfDefs.num(_a, "auto_level_max_pitch_deg"):
		return
	var phi: float = SfChaseCamera.bank_angle(s.fwd, s.up, n)
	_out.roll = clampf(-phi / deg_to_rad(SfDefs.num(_a, "auto_level_roll_deg")), -1.0, 1.0)
	var lim: float = SfDefs.num(_a, "auto_level_pitch_clamp")
	_out.pitch = clampf(-SfDefs.num(_a, "auto_level_vn_gain") * s.v.dot(n)
		- (theta - deg_to_rad(SfDefs.num(_a, "theta_trim_deg"))) / deg_to_rad(SfDefs.num(_a, "auto_level_pitch_deg")),
		-lim, lim)


# 06 s3.6 aim assist (FULL): nudge toward the lead point of the best target inside the cone while firing.
func _aim_assist(w: SfWorld, dt: float) -> void:
	_fire_t = SfDefs.num(_a, "aim_hold_s") if (_out.buttons & PilotInput.FIRE1) != 0 else maxf(_fire_t - dt, 0.0)
	if _fire_t <= 0.0:
		return
	var s: ShipState = w.s
	var cone: float = deg_to_rad(SfDefs.num(_a, "aim_cone_deg"))
	var best: Vector3 = Vector3.ZERO
	var best_e: float = cone
	for i: int in w.arena.t_pos.size():
		if not w.arena.alive(i) or s.p.distance_to(w.arena.t_pos[i]) > SfDefs.num(_a, "aim_range_m"):
			continue
		var l: Vector3 = SfArena.lead(s.p, s.v, w.arena.t_pos[i], w.d.slug.speed_mps)
		var e: float = s.fwd.angle_to(l - s.p)
		if e < best_e:
			best_e = e
			best = (l - s.p).normalized()
	if best == Vector3.ZERO:
		return
	var ev: Vector3 = s.fwd.cross(best)
	var k: float = SfDefs.num(_a, "aim_k")
	var dp: float = k * ev.dot(s.fwd.cross(s.up)) / cone
	var dy: float = k * ev.dot(s.up) / cone
	if not (absf(_out.pitch) > 0.5 and signf(_out.pitch) != signf(dp)):
		_out.pitch = clampf(_out.pitch + dp, -1.0, 1.0)
	if not (absf(_out.yaw) > 0.5 and signf(_out.yaw) != signf(dy)):
		_out.yaw = clampf(_out.yaw + dy, -1.0, 1.0)


func _btn(on: bool, bit: int) -> void:
	if on:
		_out.buttons |= bit


func _axis(pos_key: Key, neg_key: Key) -> float:
	return (1.0 if Input.is_physical_key_pressed(pos_key) else 0.0) - (1.0 if Input.is_physical_key_pressed(neg_key) else 0.0)


# Radial dead zone and response curve (06 s3.5).
static func _shape(v: Vector2, d0: float, gamma: float) -> Vector2:
	var m: float = v.length()
	if m <= d0:
		return Vector2.ZERO
	var s: float = clampf((m - d0) / (1.0 - d0), 0.0, 1.0)
	return v / m * pow(s, gamma)
