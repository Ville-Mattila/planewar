class_name RemapModel extends RefCounted
## State of the remapping screen (06 s2.5, A11Y-06, UX-09): which device tab is shown, which slot is waiting for a
## press, and what the press did. Pure: events are passed in, labels come from Glyphs. Bindings persist on every change
## (`autosave`). Conflicts are flagged, never refused. While listening: Esc / Start cancels, Delete / View clears the slot.

var store: BindingStore
var device: StringName = BindingStore.KBM
var autosave: bool = true
## Last bind outcome: the other action that now shares the code, or &"" (UI shows a warning).
var last_conflict: StringName = &""

var _action: StringName = &""
var _slot: int = 0


func _init(p_store: BindingStore) -> void:
	store = p_store


func actions() -> Array[StringName]:
	return store.actions(device)


func slot_count() -> int:
	return 1 if device == BindingStore.PAD else store.slots()


func set_device(d: StringName) -> void:
	device = d
	cancel()
	last_conflict = &""


func is_listening() -> bool:
	return _action != &""


func listening_action() -> StringName:
	return _action


func listening_slot() -> int:
	return _slot


func begin_listen(action: StringName, slot: int) -> void:
	_action = action
	_slot = slot
	last_conflict = &""


func cancel() -> void:
	_action = &""


## Consumes a press while listening; returns true when the event was consumed (it ended or changed the listen state).
func capture(event: InputEvent) -> bool:
	if not is_listening():
		return false
	var code: int = BindingStore.UNBOUND
	if device == BindingStore.KBM:
		if not (event is InputEventKey):
			return false
		var k: InputEventKey = event as InputEventKey
		if not k.pressed or k.echo:
			return false
		var kc: Key = k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
		if kc == KEY_ESCAPE:
			cancel()
			return true
		code = BindingStore.UNBOUND if (kc == KEY_DELETE or kc == KEY_BACKSPACE) else int(kc)
	else:
		if not (event is InputEventJoypadButton):
			return false
		var b: InputEventJoypadButton = event as InputEventJoypadButton
		if not b.pressed:
			return false
		if b.button_index == JOY_BUTTON_START:
			cancel()
			return true
		code = BindingStore.UNBOUND if b.button_index == JOY_BUTTON_BACK else int(b.button_index)
	last_conflict = store.bind(device, _action, _slot, code)
	_action = &""
	_save()
	return true


func clear(action: StringName, slot: int) -> void:
	store.clear(device, action, slot)
	last_conflict = &""
	_save()


func reset_device() -> void:
	store.reset(device)
	last_conflict = &""
	_save()


func label(action: StringName, slot: int, glyph_set: StringName) -> String:
	return Glyphs.binding_label(glyph_set, device, store.code(device, action, slot))


## The other action sharing this slot's code, or &"" (drives the per-row conflict flag).
func conflict_of(action: StringName, slot: int) -> StringName:
	return store.conflict_of(device, action, slot)


func has_conflicts() -> bool:
	return not store.conflicted(device).is_empty()


func _save() -> void:
	if autosave:
		var _e: Error = store.save()
