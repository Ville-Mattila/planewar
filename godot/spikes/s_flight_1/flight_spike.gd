class_name SfFlightSpike extends Node3D
## S-FLIGHT-1 (TA-30) root: steps `SfWorld` at the physics tick (= rules.tick_hz, 30 Hz), renders at up to
## 60 fps with render-time interpolation between the last two ticks (03 s10.1), Chase camera stub, HUD, touch
## layer, tuning panel and CSV telemetry. User args (after `--`): `--autofly` (demo autopilot laps),
## `--frames=N` (print frame-time and interpolation stats after N frames, then quit).

var defs: SfDefs
var world: SfWorld
var view: SfView
var cam: SfChaseCamera
var hud: SfHud
var touch: SfTouchLayer
var panel: SfTuningPanel
var inp: SfInput
var tele: SfTelemetry
var _ready_state: int             # 0 = show loading, 1 = build next frame, 2 = running
var _loading: Label
var _autofly: bool
var _frames_target: int
var _ap: SfAutopilot
var _ap_bearing: float
var _ap_out: bool = true
var _ap_in: PilotInput = PilotInput.new()
var _ft: PackedFloat32Array = PackedFloat32Array()     # frame times (ms)
var _disp: PackedFloat32Array = PackedFloat32Array()   # per-frame ship displacement while cruising (m)
var _last_rp: Vector3
var _frames: int
var _shot_path: String = ""
var _shot_every: int = 600
var _smoke: SfInputSmoke
var _smoke_kind: String = ""


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a == "--autofly":
			_autofly = true
		elif a.begins_with("--frames="):
			_frames_target = a.substr("--frames=".length()).to_int()
		elif a.begins_with("--shot="):
			_shot_path = a.substr("--shot=".length())
		elif a.begins_with("--smoke="):
			_smoke_kind = a.substr("--smoke=".length())
		elif a.begins_with("--shot-every="):
			_shot_every = a.substr("--shot-every=".length()).to_int()
	var layer: CanvasLayer = CanvasLayer.new()
	add_child(layer)
	_loading = Label.new()
	_loading.text = "S-FLIGHT-1: building the moon..."
	_loading.position = Vector2(40, 40)
	layer.add_child(_loading)
	touch = SfTouchLayer.new()
	hud = SfHud.new()
	panel = SfTuningPanel.new()
	layer.add_child(hud)
	layer.add_child(touch)
	layer.add_child(panel)
	panel.visible = false
	touch.visible = false


func _build() -> void:
	var t0: int = Time.get_ticks_msec()
	defs = SfDefs.load_all()
	Engine.max_fps = int(SfDefs.num(defs.render, "max_fps"))
	assert(Engine.physics_ticks_per_second == defs.rules.tick_hz, "physics tick must equal rules.tick_hz")
	world = SfWorld.new(defs, 1)
	view = SfView.new()
	add_child(view)
	view.build(defs, world)
	cam = SfChaseCamera.new()
	add_child(cam)
	cam.setup(defs.camera, defs.ship)
	cam.current = true
	touch.setup(defs.input)
	inp = SfInput.new()
	add_child(inp)
	inp.setup(defs, touch)
	tele = SfTelemetry.new(defs.telemetry)
	hud.world = world
	hud.view = view
	hud.cam = cam
	hud.inp = inp
	hud.defs = defs
	panel.build(defs, inp)
	panel.on_change = func(k: String, v: String) -> void: tele.row(world, "tuning", "%s=%s" % [k, v])
	panel.on_respawn = _respawn
	panel.on_save_log = _save_log
	_ap = SfAutopilot.new(defs)
	tele.row(null, "session_start", "platform=%s web=%s sources=%s" % [OS.get_name(), OS.has_feature("web"),
		";".join(defs.sources)])
	_loading.visible = false
	print("MEAS build_ms %d" % (Time.get_ticks_msec() - t0))
	hud.toast("Docked on the pad. Thrust to launch.  F1: tuning / help", SfHud.WHITE, 6.0)


func _process(delta: float) -> void:
	if _ready_state < 2:
		_ready_state += 1
		if _ready_state == 2:
			_build()
		return
	var alpha: float = Engine.get_physics_interpolation_fraction()
	view.sync(world, alpha, delta)
	var aim: Vector3 = inp.aim if inp.input_class == SfInput.InputClass.POINTER else Vector3.ZERO
	cam.follow(view.render_p, view.render_fwd, view.render_up, world.s.v, aim, world.s.boost_time > 0.0, delta)
	_frame_stats(delta)
	hud.hint = _hint()


func _physics_process(_delta: float) -> void:
	if _ready_state < 2:
		return
	if _smoke_kind != "" and _smoke == null:
		_smoke = SfInputSmoke.new(_smoke_kind, touch.size, get_viewport().get_final_transform())
	if _smoke != null:
		_smoke_step()
	var p: PilotInput = inp.sample(world, defs.dt())
	if _autofly:
		p = _autofly_input()
	if inp.class_changed:
		inp.class_changed = false
	tele.set_context(SfInput.CLASS_NAMES[inp.input_class], "FULL" if inp.current_tier() == SfInput.Tier.FULL else "RAW",
		str(defs.rules.lift_model))
	world.step(p)
	var evs: Array[SfEvent] = world.drain_events()
	for e: SfEvent in evs:
		_on_event(e)
	tele.on_tick(world, evs, defs.dt())


# --smoke: inject device events, then report what the device path produced (REPORT s3 "all three input classes").
func _smoke_step() -> void:
	if _smoke.done():
		print("MEAS smoke %s class=%s state=%s alt=%.0f speed=%.0f pitch_deg=%.0f shots=%d bombs_left=%d slider=%.2f" % [
			_smoke.kind, SfInput.CLASS_NAMES[inp.input_class], SfWorld.State.keys()[world.state], world.altitude(),
			world.s.v.length(), rad_to_deg(asin(clampf(world.s.fwd.dot(world.s.p.normalized()), -1.0, 1.0))),
			world.arena.shots, world.bombs, touch.slider_h])
		get_tree().quit(0)
		_smoke = null
		_smoke_kind = ""
		return
	_smoke.step(defs.dt())


func _on_event(e: SfEvent) -> void:
	match e.kind:
		SfEvent.Kind.TOUCHDOWN:
			var td: SfTouchdown = e.touchdown
			if td.outcome == SfTouchdown.Outcome.LANDED:
				hud.toast("LANDED  %s  q %.2f" % [td.grade_name(), td.q], SfHud.GREEN, 4.0)
			elif td.outcome == SfTouchdown.Outcome.HARD:
				hud.toast("HARD LANDING (BENT)  -%d HP" % int(td.damage_hp), SfHud.AMBER, 4.0)
			elif td.outcome == SfTouchdown.Outcome.DAMAGED or td.outcome == SfTouchdown.Outcome.SCRAPE:
				hud.toast("Ground contact  -%d HP" % int(td.damage_hp), SfHud.AMBER, 2.0)
			inp.reset_aim(world.s)
		SfEvent.Kind.CRASH:
			var why: String = e.reason
			if world.last_touchdown != null and e.reason == "crash":
				var td2: SfTouchdown = world.last_touchdown
				why = "sink %.1f  drift %.1f  nose %.0f deg" % [td2.v_vert, td2.v_hor, td2.tilt_deg]
			hud.toast("CRASH  (%s)" % why, SfHud.RED, 4.0)
			view.explode(e.pos, 12.0)
		SfEvent.Kind.TARGET_DESTROYED:
			view.explode(e.pos, 14.0)
			hud.toast("Target destroyed", SfHud.GREEN, 1.5)
		SfEvent.Kind.BOMB_IMPACT:
			view.explode(e.pos, defs.blast_radius_m if e.value > 0.0 else 3.0)
		SfEvent.Kind.RESPAWN, SfEvent.Kind.LAUNCHED:
			inp.reset_aim(world.s)
		_:
			pass


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		match (event as InputEventKey).physical_keycode:
			KEY_F1:
				_toggle_panel()
			KEY_F2:
				panel.toggle_lift()
			KEY_F3:
				inp.toggle_tier()
			KEY_F4:
				inp.mouse_mode = SfInput.MouseMode.DIRECT if inp.mouse_mode == SfInput.MouseMode.MOUSE_AIM \
					else SfInput.MouseMode.MOUSE_AIM
			KEY_F5:
				inp.thrust_mode = SfInput.ThrustMode.LEVER if inp.thrust_mode == SfInput.ThrustMode.POWER \
					else SfInput.ThrustMode.POWER
			KEY_F6:
				inp.invert_pitch = not inp.invert_pitch
			KEY_BACKSPACE, KEY_HOME:
				_respawn()
			KEY_ESCAPE:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if panel != null:
			panel.refresh()
	elif event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed:
		match (event as InputEventJoypadButton).button_index:
			JOY_BUTTON_BACK:
				inp.toggle_tier()
				panel.refresh()
			JOY_BUTTON_START:
				_respawn()
			JOY_BUTTON_DPAD_UP:
				_toggle_panel()


func _toggle_panel() -> void:
	panel.visible = not panel.visible
	inp.capture_allowed = not panel.visible
	if panel.visible:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	panel.refresh()


func _respawn() -> void:
	world.respawn_docked()
	inp.reset_aim(world.s)
	tele.row(world, "respawn_request", "")


func _save_log() -> String:
	tele.flush()
	var msg: String = "Saved %s\n%s" % [ProjectSettings.globalize_path(tele.path), tele.summary()]
	if OS.has_feature("web"):
		JavaScriptBridge.download_buffer(tele.text().to_utf8_buffer(), tele.path.get_file(), "text/csv")
		msg += "\n(downloaded by the browser)"
	return msg


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		if tele != null:
			tele.flush()


func _hint() -> String:
	match inp.input_class:
		SfInput.InputClass.GAMEPAD:
			return "RT thrust  LS pitch/roll  LB/RB yaw  LT brake  L3 boost  A gun  B bomb  Y flip  X dock (hold)  Back: FULL/RAW  Start: respawn  D-pad up: panel"
		SfInput.InputClass.TOUCH:
			return "Left: slider (thrust/speed) + stick (flick up = flip).  Right: FIRE BOMB BOOST BRAKE DOCK"
	var mouse: String = "click to capture mouse (aim)" if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED else "mouse aim (Esc frees)"
	return "W thrust  S brake  %s  arrows pitch/roll  A/D roll  Q/E yaw  Shift boost  Space flip  LMB/Ctrl gun  RMB/V bomb  F dock  F1 panel  F2 lift  F3 FULL/RAW  Backspace respawn" % mouse


# Frame time and per-frame displacement while cruising (03 s10.1 test: variance < 10 % of the mean).
func _frame_stats(delta: float) -> void:
	_frames += 1
	var _a: bool = _ft.push_back(delta * 1000.0)
	if world.state == SfWorld.State.FLYING and world.s.v.length() > 0.5 * defs.ship.v_cruise and _frames > 30:
		var _b: bool = _disp.push_back(view.render_p.distance_to(_last_rp))
	_last_rp = view.render_p
	if _ft.size() >= 600:
		var st: Vector3 = _stats(_ft)
		var ds: Vector3 = Vector3(_stats(_disp).x, 0.0, _local_cv(_disp, 10)) if _disp.size() > 10 else Vector3.ZERO
		hud.fps_text = "frame p50 %.1f ms  p95 %.1f ms  disp cv %.1f%%" % [st.x, st.y, ds.z]
		tele.row(world, "frame_stats", "p50_ms=%.2f p95_ms=%.2f disp_mean_m=%.3f disp_cv_pct=%.2f" % [st.x, st.y,
			ds.x, ds.z])
		if _frames_target > 0:
			print("MEAS frame p50_ms=%.2f p95_ms=%.2f p99_ms=%.2f disp_mean_m=%.3f disp_cv_pct=%.2f n_disp=%d" % [
				st.x, st.y, _pct(_ft, 0.99), ds.x, ds.z, _disp.size()])
		_ft.clear()
		_disp.clear()
	if _shot_path != "" and _frames % _shot_every == 0:
		var img: Image = get_viewport().get_texture().get_image()
		if img != null:
			var _e: Error = img.save_png(_shot_path.replace(".png", "_%05d.png" % _frames))
	if _frames_target > 0 and _frames >= _frames_target:
		tele.flush()
		print("MEAS telemetry %s %s" % [ProjectSettings.globalize_path(tele.path), tele.summary()])
		get_tree().quit(0)


## Mean over windows of `n` frames of std/mean (%): frame-to-frame jitter without the slow speed changes.
static func _local_cv(a: PackedFloat32Array, n: int) -> float:
	var acc: float = 0.0
	var k: int = 0
	var i: int = 0
	while i + n <= a.size():
		var st: Vector3 = _stats(a.slice(i, i + n))
		var m: float = 0.0
		for x: float in a.slice(i, i + n):
			m += x
		if m > 0.0:
			acc += st.z
			k += 1
		i += n
	return acc / maxf(float(k), 1.0)


static func _pct(a: PackedFloat32Array, q: float) -> float:
	var c: PackedFloat32Array = a.duplicate()
	c.sort()
	return c[clampi(int(q * float(c.size() - 1)), 0, c.size() - 1)]


static func _stats(a: PackedFloat32Array) -> Vector3:
	var m: float = 0.0
	for x: float in a:
		m += x
	m /= float(a.size())
	var v: float = 0.0
	for x: float in a:
		v += (x - m) * (x - m)
	var sd: float = sqrt(v / float(a.size()))
	return Vector3(_pct(a, 0.5), _pct(a, 0.95), 100.0 * sd / maxf(m, 1e-6))


# Demo autopilot laps for --autofly: out along a bearing at 150 m, back with the harness approach, land, relaunch.
func _autofly_input() -> PilotInput:
	var w: SfWorld = world
	_ap_in.buttons = 0
	if w.state == SfWorld.State.DOCKED:
		_ap_in.thrust = 1.0
		_ap_out = true
		_ap_bearing += 97.0
		_ap.reset(SfAutopilot.Phase.TRANSIT)
		return _ap_in
	if _ap_out:
		var goal: Vector3 = SfArena.place(w.pad_p, _ap_bearing, 1600.0, 0.0)
		var n: Vector3 = w.s.p.normalized()
		var to: Vector3 = goal - w.s.p
		_ap.hold(w.s, defs.ship, 150.0, defs.ship.v_cruise, (to - n * to.dot(n)).normalized(), _ap_in)
		if w.altitude() < 60.0 and w.s.fwd.dot(n) > 0.7:
			_ap_in.pitch = 0.0
			_ap_in.yaw = 0.0
			_ap_in.thrust = 1.0
		if Sphere.great_circle(w.s.p, w.pad_p) > 1300.0:
			_ap_out = false
		if floori(float(w.tick) / 15.0) % 4 == 0:
			_ap_in.buttons |= PilotInput.FIRE1
	else:
		_ap.approach_step(w.s, defs.ship, w.pad_p, w.pad_n, _ap_in)
		_ap_in.buttons &= ~PilotInput.DOCK
	return _ap_in
