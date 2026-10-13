class_name SfTuningPanel extends PanelContainer
## Live tuning panel (03 s14.6): gravity, k_side, k_up, k_up_flight, lift_model, a_thrust, turn rates,
## rate_accel_dps2, eff_fade_start; edits the loaded defs in place (the next tick uses them). Each row shows the
## 01 / 02 anchor band (g 5-8, speeds and rates +-15 %, a_thrust >= 2 g, k_up_flight 0.6-1.5). "Export patch"
## writes the changed values as a rules.json + ships.json patch proposal to user://s_flight_1/.

var defs: SfDefs
var on_change: Callable           # (key: String, value: String) -> void
var on_respawn: Callable          # () -> void
var on_save_log: Callable         # () -> String
var inp: SfInput
var _rows: Dictionary[String, Label] = {}
var _sliders: Dictionary[String, HSlider] = {}
var _defaults: Dictionary[String, float] = {}
var _out: Label
var _lift_btn: Button
var _opts: Label


func build(d: SfDefs, input_node: SfInput) -> void:
	defs = d
	inp = input_node
	set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	custom_minimum_size = Vector2(360, 0)
	var scroll: ScrollContainer = ScrollContainer.new()
	add_child(scroll)
	var box: VBoxContainer = VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	var title: Label = Label.new()
	title.text = "S-FLIGHT-1 tuning (F1 / Select hides)"
	box.add_child(title)
	_lift_btn = Button.new()
	var _cn: int = _lift_btn.pressed.connect(_toggle_lift)
	box.add_child(_lift_btn)
	_opts = Label.new()
	box.add_child(_opts)
	var sh: ShipDef = defs.ship
	_slider(box, "gravity", defs.rules.gravity, 3.0, 10.0)
	_slider(box, "k_side", sh.k_side, 0.1, 1.5)
	_slider(box, "k_up", sh.k_up, 0.02, 0.5)
	_slider(box, "k_up_flight", sh.k_up_flight, 0.3, 2.0)
	_slider(box, "a_thrust", sh.a_thrust, 8.0, 40.0)
	_slider(box, "pitch_rate_dps", sh.pitch_rate_dps, 40.0, 200.0)
	_slider(box, "yaw_rate_dps", sh.yaw_rate_dps, 20.0, 120.0)
	_slider(box, "roll_rate_dps", sh.roll_rate_dps, 60.0, 300.0)
	_slider(box, "rate_accel_dps2", sh.rate_accel_dps2, 200.0, 1500.0)
	_slider(box, "eff_fade_start", defs.common.eff_fade_start, 0.5, 0.98)
	_button(box, "Assist tier FULL/RAW (F3)", _toggle_tier)
	_button(box, "Mouse MOUSE_AIM/DIRECT (F4)", _toggle_mouse)
	_button(box, "KBM thrust POWER/LEVER (F5)", _toggle_thrust)
	_button(box, "Invert pitch (F6)", _toggle_invert)
	_button(box, "Respawn on pad (Backspace)", _respawn)
	_button(box, "Reset to defs", _reset)
	_button(box, "Export patch", _export)
	_button(box, "Save telemetry CSV", _save)
	_out = Label.new()
	_out.autowrap_mode = TextServer.AUTOWRAP_WORD
	_out.custom_minimum_size = Vector2(330, 0)
	box.add_child(_out)
	_refresh()


func _button(box: VBoxContainer, text: String, cb: Callable) -> void:
	var btn: Button = Button.new()
	btn.text = text
	btn.focus_mode = Control.FOCUS_NONE
	var _cn: int = btn.pressed.connect(cb)
	box.add_child(btn)


func _slider(box: VBoxContainer, key: String, v: float, lo: float, hi: float) -> void:
	_defaults[key] = v
	var l: Label = Label.new()
	box.add_child(l)
	_rows[key] = l
	var sl: HSlider = HSlider.new()
	sl.min_value = lo
	sl.max_value = hi
	sl.step = (hi - lo) / 200.0
	sl.value = v
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.focus_mode = Control.FOCUS_NONE
	var _cn: int = sl.value_changed.connect(func(x: float) -> void: _apply(key, x))
	_sliders[key] = sl
	box.add_child(sl)


func value(key: String) -> float:
	var s: ShipDef = defs.ship
	match key:
		"gravity": return defs.rules.gravity
		"k_side": return s.k_side
		"k_up": return s.k_up
		"k_up_flight": return s.k_up_flight
		"a_thrust": return s.a_thrust
		"pitch_rate_dps": return s.pitch_rate_dps
		"yaw_rate_dps": return s.yaw_rate_dps
		"roll_rate_dps": return s.roll_rate_dps
		"rate_accel_dps2": return s.rate_accel_dps2
		_: return defs.common.eff_fade_start


func _apply(key: String, x: float) -> void:
	var s: ShipDef = defs.ship
	match key:
		"gravity": defs.rules.gravity = x
		"k_side": s.k_side = x
		"k_up": s.k_up = x
		"k_up_flight": s.k_up_flight = x
		"a_thrust": s.a_thrust = x
		"pitch_rate_dps": s.pitch_rate_dps = x
		"yaw_rate_dps": s.yaw_rate_dps = x
		"roll_rate_dps": s.roll_rate_dps = x
		"rate_accel_dps2": s.rate_accel_dps2 = x
		_: defs.common.eff_fade_start = x
	if on_change.is_valid():
		on_change.call(key, "%.3f" % x)
	_refresh()


## Anchor band check (01 s3.1.1 / s5.2, 02 s2.2): "" when inside, else the violated band.
func anchor_issue(key: String) -> String:
	var x: float = value(key)
	var d0: float = _defaults[key]
	match key:
		"gravity":
			return "" if x >= 5.0 and x <= 8.0 else "g anchor 5-8"
		"k_up_flight":
			return "" if x >= 0.6 and x <= 1.5 else "k_up_flight anchor 0.6-1.5"
		"a_thrust":
			return "" if x >= 2.0 * defs.rules.gravity else "a_thrust >= 2 g (%.1f)" % (2.0 * defs.rules.gravity)
		"pitch_rate_dps", "yaw_rate_dps", "roll_rate_dps":
			return "" if absf(x - d0) <= 0.15 * d0 else "rates +-15 %"
	return ""


func _refresh() -> void:
	_lift_btn.text = "lift_model: %s (F2 toggles)" % defs.rules.lift_model
	for key: String in _rows:
		var issue: String = anchor_issue(key)
		var changed: String = " *" if absf(value(key) - _defaults[key]) > 1e-6 else ""
		_rows[key].text = "%s = %.3f%s%s" % [key, value(key), changed, ("   OUT: " + issue) if issue != "" else ""]
		_rows[key].modulate = Color(1, 0.5, 0.4) if issue != "" else Color(1, 1, 1)
	if inp != null:
		_opts.text = "assist %s | mouse %s | thrust %s | invert %s" % [
			"FULL" if inp.current_tier() == SfInput.Tier.FULL else "RAW",
			"MOUSE_AIM" if inp.mouse_mode == SfInput.MouseMode.MOUSE_AIM else "DIRECT",
			"POWER" if inp.thrust_mode == SfInput.ThrustMode.POWER else "LEVER", inp.invert_pitch]


func refresh() -> void:
	_refresh()


func _toggle_lift() -> void:
	var r: RulesDef = defs.rules
	r.lift_model = RulesDef.LIFT_DAMPING_ONLY if r.lift_model == RulesDef.LIFT_SPEED_SCALED \
		else RulesDef.LIFT_SPEED_SCALED
	if on_change.is_valid():
		on_change.call("lift_model", str(r.lift_model))
	_refresh()


func toggle_lift() -> void:
	_toggle_lift()


func _toggle_tier() -> void:
	inp.toggle_tier()
	_refresh()


func _toggle_mouse() -> void:
	inp.mouse_mode = SfInput.MouseMode.DIRECT if inp.mouse_mode == SfInput.MouseMode.MOUSE_AIM else SfInput.MouseMode.MOUSE_AIM
	_refresh()


func _toggle_thrust() -> void:
	inp.thrust_mode = SfInput.ThrustMode.LEVER if inp.thrust_mode == SfInput.ThrustMode.POWER else SfInput.ThrustMode.POWER
	_refresh()


func _toggle_invert() -> void:
	inp.invert_pitch = not inp.invert_pitch
	_refresh()


func _respawn() -> void:
	if on_respawn.is_valid():
		on_respawn.call()


func _reset() -> void:
	for key: String in _defaults:
		_apply(key, _defaults[key])
	for key: String in _sliders:
		_sliders[key].set_value_no_signal(_defaults[key])
	_out.text = "Reset to the loaded defs."


func patch_json() -> String:
	var ship_patch: Dictionary = {}
	var common_patch: Dictionary = {}
	var rules_patch: Dictionary = {}
	for key: String in _defaults:
		if absf(value(key) - _defaults[key]) <= 1e-6:
			continue
		if key == "gravity":
			rules_patch[key] = value(key)
		elif key == "eff_fade_start":
			common_patch[key] = value(key)
		else:
			ship_patch[key] = value(key)
	rules_patch["lift_model"] = str(defs.rules.lift_model)
	var issues: PackedStringArray = PackedStringArray()
	for key: String in _defaults:
		var i: String = anchor_issue(key)
		if i != "":
			var _a: bool = issues.push_back("%s: %s" % [key, i])
	var doc: Dictionary = {"_doc": "S-FLIGHT-1 (TA-30) tuning patch proposal to 02 (rules.json + ships.json). Values outside the 01 anchors need an anchor refinement filed to 02.",
		"rules.json": rules_patch, "ships.json": {"flight_common": common_patch, "ships": {str(defs.ship.id): ship_patch}},
		"outside_anchors": issues}
	return JSON.stringify(doc, "  ")


func _export() -> void:
	var text: String = patch_json()
	var _e: Error = DirAccess.make_dir_recursive_absolute(SfTelemetry.DIR)
	var p: String = SfTelemetry.DIR + "/tuning_patch.json"
	var f: FileAccess = FileAccess.open(p, FileAccess.WRITE)
	if f != null:
		var _ok: bool = f.store_string(text)
		f.close()
	if OS.has_feature("web"):
		JavaScriptBridge.download_buffer(text.to_utf8_buffer(), "s_flight_1_tuning_patch.json", "application/json")
	if on_change.is_valid():
		on_change.call("export_patch", text.replace("\n", " "))
	_out.text = "Saved %s\n%s" % [ProjectSettings.globalize_path(p), text]


func _save() -> void:
	if on_save_log.is_valid():
		_out.text = str(on_save_log.call())
