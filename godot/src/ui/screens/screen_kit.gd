class_name ScreenKit extends RefCounted
## Builders shared by the match overlays (UX-27): labels and buttons at the screens.json sizes, and the dimmed centred
## panel. Text comes from the caller (`tr(key)`); nothing literal lives here.


static func font_px() -> int:
	return maxi(int(ScreenParams.param("font_du")), int(HudMath.param("font_du_min")))


## Connects without leaking the Error (warnings are errors).
static func on(sig: Signal, cb: Callable) -> void:
	var _e: int = sig.connect(cb)


static func label(text: String, size_du: int = 0, color: Color = UiTokens.UI_TEXT) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.add_theme_font_size_override(&"font_size", size_du if size_du > 0 else font_px())
	l.add_theme_color_override(&"font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func button(text: String) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size = Vector2(0.0, ScreenParams.param("button_h_du"))
	b.add_theme_font_size_override(&"font_size", font_px())
	return b


## Dim backdrop plus a centred panel; returns the VBox the screen fills.
static func shell(root: Control, min_width_du: float) -> VBoxContainer:
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	var dim: ColorRect = ColorRect.new()
	dim.color = Color(UiTokens.UI_BG_0, ScreenParams.param("dim_alpha"))
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var centre: CenterContainer = CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(centre)
	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = Vector2(min_width_du, 0.0)
	centre.add_child(panel)
	var margin: MarginContainer = MarginContainer.new()
	for side: StringName in [&"margin_left", &"margin_right", &"margin_top", &"margin_bottom"]:
		margin.add_theme_constant_override(side, 16)
	panel.add_child(margin)
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 8)
	margin.add_child(box)
	return box
