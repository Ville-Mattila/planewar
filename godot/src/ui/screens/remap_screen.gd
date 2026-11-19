class_name RemapScreen extends ScreenBase
## Remapping screen (06 s2.5, A11Y-06, UX-09): a tab per device (Keyboard / Gamepad), one row per action with a button
## per slot, a per-row conflict flag, Reset and Done. Thin: RemapModel decides. Navigable by pad and keyboard alone.
## Glyph labels follow the active set; the host calls `set_glyph_set` on `glyph_set_changed`. scenes/ui/screens/remap.tscn.

signal done_requested

var model: RemapModel
var glyph_set: StringName = &"kbm"

var _box: VBoxContainer
var _rows_box: VBoxContainer
var _prompt: Label
var _tab_buttons: Dictionary[StringName, Button] = {}
var _slot_buttons: Array[Button] = []
var _reset: Button
var _done: Button


func _ready() -> void:
	if model == null:
		model = RemapModel.new(BindingStore.new())
		var _e: Error = model.store.load_file()
	_box = ScreenKit.shell(self, 520.0)
	_box.add_child(ScreenKit.label(tr(&"ui.remap.title"), int(ScreenParams.param("title_font_du"))))
	var tabs: HBoxContainer = HBoxContainer.new()
	_box.add_child(tabs)
	for d: StringName in [BindingStore.KBM, BindingStore.PAD]:
		var t: Button = ScreenKit.button(tr(StringName("ui.remap.device." + String(d))))
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ScreenKit.on(t.pressed, func() -> void: _show_device(d))
		tabs.add_child(t)
		_tab_buttons[d] = t
	_prompt = ScreenKit.label("")
	_box.add_child(_prompt)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0.0, ScreenParams.param("remap_list_h_du"))
	scroll.follow_focus = true
	_box.add_child(scroll)
	_rows_box = VBoxContainer.new()
	_rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_rows_box)
	var foot: HBoxContainer = HBoxContainer.new()
	_box.add_child(foot)
	_reset = ScreenKit.button(tr(&"ui.remap.reset"))
	ScreenKit.on(_reset.pressed, func() -> void:
		model.reset_device()
		refresh())
	_done = ScreenKit.button(tr(&"ui.remap.done"))
	ScreenKit.on(_done.pressed, func() -> void: done_requested.emit())
	foot.add_child(_reset)
	foot.add_child(_done)
	refresh()


func enter(args: Dictionary) -> void:
	var s: Variant = args.get("store", null)
	if s is BindingStore:
		var store: BindingStore = s
		model = RemapModel.new(store)
	var g: Variant = args.get("glyph_set", null)
	if g is StringName:
		glyph_set = g
	if _box != null:
		refresh()


## Swaps every label to `p_set` at once (06 s2.4: glyphs switch on the first qualifying event).
func set_glyph_set(p_set: StringName) -> void:
	glyph_set = p_set
	if _box != null:
		refresh()


func initial_focus() -> Control:
	return _slot_buttons[0] if not _slot_buttons.is_empty() else _done


func handle_back() -> bool:
	if model.is_listening():
		model.cancel()
		refresh()
		return true
	done_requested.emit()
	return true


func _input(event: InputEvent) -> void:
	if model != null and model.is_listening() and model.capture(event):
		get_viewport().set_input_as_handled()
		refresh()


func slot_button(action: StringName, slot: int) -> Button:
	var i: int = model.actions().find(action)
	return _slot_buttons[i * model.slot_count() + slot] if i >= 0 else null


func prompt_text() -> String:
	return _prompt.text


func refresh() -> void:
	for c: Node in _rows_box.get_children():
		c.queue_free()
		_rows_box.remove_child(c)
	_slot_buttons.clear()
	for a: StringName in model.actions():
		_rows_box.add_child(_row(a))
	for d: StringName in _tab_buttons:
		_tab_buttons[d].disabled = d == model.device
	_prompt.text = _prompt_text()


func _row(action: StringName) -> Control:
	var outer: VBoxContainer = VBoxContainer.new()
	var row: HBoxContainer = HBoxContainer.new()
	outer.add_child(row)
	var name_l: Label = ScreenKit.label(tr(StringName("ui.remap.action." + String(action))))
	name_l.custom_minimum_size = Vector2(ScreenParams.param("name_col_du"), 0.0)
	row.add_child(name_l)
	var flag: String = ""
	for s: int in model.slot_count():
		var listening: bool = model.is_listening() and model.listening_action() == action and model.listening_slot() == s
		var b: Button = ScreenKit.button("..." if listening else model.label(action, s, glyph_set))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ScreenKit.on(b.pressed, func() -> void:
			model.begin_listen(action, s)
			refresh()
			var nb: Button = slot_button(action, s)
			if nb != null:
				nb.grab_focus())
		row.add_child(b)
		_slot_buttons.append(b)
		var other: StringName = model.conflict_of(action, s)
		if other != &"":
			flag = tr(&"ui.remap.conflict").format({"action": tr(StringName("ui.remap.action." + String(other)))})
	if flag != "":
		var warn: Label = ScreenKit.label(flag, 0, UiTokens.UI_WARN)
		warn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		outer.add_child(warn)
	return outer


func _prompt_text() -> String:
	if model.is_listening():
		return tr(StringName("ui.remap.listen." + String(model.device)))
	if model.has_conflicts():
		return tr(&"ui.remap.has_conflicts")
	return tr(&"ui.remap.hint")


func _show_device(d: StringName) -> void:
	model.set_device(d)
	refresh()
	initial_focus().grab_focus()
