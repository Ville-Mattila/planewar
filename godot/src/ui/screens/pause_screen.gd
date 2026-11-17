class_name PauseScreen extends ScreenBase
## Pause menu (06 s8 Pause): one button per PauseItem; unavailable items stay in the focus order, disabled, with the
## reason in the label. Thin: PauseModel decides. scenes/ui/screens/pause.tscn.

signal item_chosen(id: StringName)

var items: Array[PauseItem] = []
var _box: VBoxContainer
var _buttons: Dictionary[StringName, Button] = {}


func _ready() -> void:
	_box = ScreenKit.shell(self, 360.0)
	_box.add_child(ScreenKit.label(tr(&"ui.pause.title"), int(ScreenParams.param("title_font_du"))))
	configure(items)


func configure(p_items: Array[PauseItem]) -> void:
	items = p_items
	if _box == null:
		return
	for b: Button in _buttons.values():
		b.free()
	_buttons.clear()
	for it: PauseItem in items:
		var text: String = tr(StringName("ui.pause.item." + String(it.id)))
		if not it.enabled:
			text += " - " + tr(it.reason_key)
		var b: Button = ScreenKit.button(text)
		b.disabled = not it.enabled
		ScreenKit.on(b.pressed, func() -> void: item_chosen.emit(it.id))
		_box.add_child(b)
		_buttons[it.id] = b


func initial_focus() -> Control:
	return _buttons.get(&"resume")


func handle_back() -> bool:
	item_chosen.emit(&"resume")   # B / Esc resumes
	return true


func button_of(id: StringName) -> Button:
	return _buttons.get(id)
