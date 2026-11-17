class_name EliminatedOverlay extends Control
## ELIMINATED_COMMANDER banner of the Match screen (06 s8; GD-20): the Core is gone, teammates order the units, the
## structures self-destruct after `eliminated_selfdestruct_s`. Does not block input (no dim). Built once, shown on demand.

var _title: Label
var _hint: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_TOP_WIDE)
	var box: VBoxContainer = VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(box)
	_title = ScreenKit.label(tr(&"ui.eliminated.title"), int(ScreenParams.param("title_font_du")), UiTokens.UI_DANGER)
	_hint = ScreenKit.label("")
	box.add_child(_title)
	box.add_child(_hint)
	visible = false


## `selfdestruct_left_s` < 0 = unknown (no countdown line).
func show_for(selfdestruct_left_s: float) -> void:
	visible = true
	if selfdestruct_left_s >= 0.0:
		_hint.text = tr(&"ui.eliminated.countdown").format({"t": Fmt.duration(int(ceilf(selfdestruct_left_s)))})
	else:
		_hint.text = tr(&"ui.eliminated.hint")


func hide_overlay() -> void:
	visible = false


func hint_text() -> String:
	return _hint.text if _hint != null else ""
