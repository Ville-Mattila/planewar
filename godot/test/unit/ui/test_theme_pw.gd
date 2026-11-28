extends GdUnitTestSuite
## theme_pw.tres (ART-21, docs/07 s7): loads, colours equal UiTokens, fonts shape Finnish text, size floor.

const THEME_PATH: String = "res://assets/ui/theme_pw.tres"
const FINNISH: String = "Äänestä ölyä åsiat"
const MIN_PX: int = 9


func _theme() -> Theme:
	var t: Theme = load(THEME_PATH) as Theme
	assert_object(t).is_not_null()
	return t


func test_default_font_and_size() -> void:
	var t: Theme = _theme()
	assert_object(t.default_font).is_not_null()
	assert_int(t.default_font_size).is_greater_equal(MIN_PX)


func test_colours_come_from_tokens() -> void:
	var t: Theme = _theme()
	assert_bool(t.get_color("font_color", "Label").is_equal_approx(UiTokens.UI_TEXT)).is_true()
	assert_bool(t.get_color("font_color", "DimLabel").is_equal_approx(UiTokens.UI_TEXT_DIM)).is_true()
	assert_bool(t.get_color("font_hover_color", "Button").is_equal_approx(UiTokens.UI_ACCENT)).is_true()
	var panel: StyleBoxFlat = t.get_stylebox("panel", "PanelContainer") as StyleBoxFlat
	assert_bool(panel.border_color.is_equal_approx(UiTokens.UI_LINE)).is_true()
	var focus: StyleBoxFlat = t.get_stylebox("focus", "Button") as StyleBoxFlat
	assert_bool(focus.border_color.is_equal_approx(UiTokens.UI_FOCUS)).is_true()


func test_finnish_has_glyphs_in_both_fonts() -> void:
	var t: Theme = _theme()
	var heading: Font = t.get_font("font", "HeadingLabel")
	for font: Font in [t.default_font, heading]:
		for ch: String in "äöåÄÖÅ":
			assert_bool(font.has_char(ch.unicode_at(0))).override_failure_message("missing " + ch).is_true()
		assert_float(font.get_string_size(FINNISH, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x).is_greater(10.0)


func test_font_sizes_at_or_above_floor() -> void:
	var t: Theme = _theme()
	for type_name: String in ["Label", "HeadingLabel", "DimLabel", "Button", "ProgressBar"]:
		assert_int(t.get_font_size("font_size", type_name)).is_greater_equal(MIN_PX)


func test_tabular_digits_equal_width() -> void:
	var font: Font = _theme().default_font
	var w0: float = font.get_string_size("0", HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	for d: String in "123456789":
		assert_float(font.get_string_size(d, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x).is_equal_approx(w0, 0.01)


const MIN_CONTRAST: float = 3.0


func _lum(c: Color) -> float:
	var ch: Array[float] = []
	for v: float in [c.r, c.g, c.b]:
		ch.append(v / 12.92 if v <= 0.04045 else pow((v + 0.055) / 1.055, 2.4))
	return 0.2126 * ch[0] + 0.7152 * ch[1] + 0.0722 * ch[2]


func _contrast(a: Color, b: Color) -> float:
	var la: float = _lum(a)
	var lb: float = _lum(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


func test_project_theme_is_theme_pw() -> void:
	var t: Theme = ThemeDB.get_project_theme()
	assert_object(t).is_not_null()
	assert_str(t.resource_path).is_equal(THEME_PATH)


func test_selected_toggle_contrasts_unselected() -> void:
	var t: Theme = _theme()
	var sel: StyleBoxFlat = t.get_stylebox("pressed", "Button") as StyleBoxFlat
	var hov_sel: StyleBoxFlat = t.get_stylebox("hover_pressed", "Button") as StyleBoxFlat
	var unsel: StyleBoxFlat = t.get_stylebox("normal", "Button") as StyleBoxFlat
	assert_bool(sel.bg_color.is_equal_approx(UiTokens.UI_ACCENT)).is_true()
	assert_float(_contrast(sel.bg_color, unsel.bg_color)).is_greater_equal(MIN_CONTRAST)
	assert_float(_contrast(hov_sel.bg_color, unsel.bg_color)).is_greater_equal(MIN_CONTRAST)
	var sel_font: Color = t.get_color("font_pressed_color", "Button")
	assert_float(_contrast(sel_font, sel.bg_color)).is_greater_equal(MIN_CONTRAST)


## Mirrors GAP in tools/art/build_theme.py (A11Y-13): background strip between button edge and ring.
const FOCUS_GAP: int = 2


func test_focus_ring_sits_outside_fill() -> void:
	var focus: StyleBoxFlat = _theme().get_stylebox("focus", "Button") as StyleBoxFlat
	var need: int = int(focus.border_width_left) + FOCUS_GAP
	assert_int(int(focus.expand_margin_left)).is_greater_equal(need)
	assert_int(int(focus.expand_margin_top)).is_greater_equal(need)
	assert_int(int(focus.expand_margin_right)).is_greater_equal(need)
	assert_int(int(focus.expand_margin_bottom)).is_greater_equal(need)


func test_focus_ring_contrasts_every_dark_background() -> void:
	var focus: StyleBoxFlat = _theme().get_stylebox("focus", "Button") as StyleBoxFlat
	# Ring is separated from the accent fill by the gap, so the 1.4.11 check is against the backdrop.
	# White vs ui_accent is 1.88:1 and is documented here only, not asserted.
	assert_float(_contrast(focus.border_color, UiTokens.UI_BG_0)).override_failure_message("focus vs ui_bg_0").is_greater_equal(MIN_CONTRAST)
	assert_float(_contrast(focus.border_color, UiTokens.UI_BG_1)).override_failure_message("focus vs ui_bg_1").is_greater_equal(MIN_CONTRAST)
	assert_float(_contrast(focus.border_color, UiTokens.UI_BG_2)).override_failure_message("focus vs ui_bg_2").is_greater_equal(MIN_CONTRAST)


func test_tabbar_selected_contrasts_unselected() -> void:
	var t: Theme = _theme()
	var sel: StyleBoxFlat = t.get_stylebox("tab_selected", "TabBar") as StyleBoxFlat
	var unsel: StyleBoxFlat = t.get_stylebox("tab_unselected", "TabBar") as StyleBoxFlat
	assert_float(_contrast(sel.bg_color, unsel.bg_color)).is_greater_equal(MIN_CONTRAST)
