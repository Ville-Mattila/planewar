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
