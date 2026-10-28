class_name HudText extends RefCounted
## Shared HUD text and bar drawing for the UX-18 views (font size from hud.json, never below font_du_min).


static func font_size(profile: UiScale.Profile) -> int:
	var base: float = HudMath.param("font_du")
	if profile == UiScale.Profile.COMPACT:
		base += 2.0
	return int(maxf(base, HudMath.param("font_du_min")))


static func text(ci: CanvasItem, pos: Vector2, s: String, col: Color, fs: int,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, w: float = -1.0) -> void:
	ci.draw_string(ThemeDB.fallback_font, pos, s, align, w, fs, col)


## Horizontal bar: outline, fill 0..1 and an optional tick at tick01 (< 0 = none).
static func bar(ci: CanvasItem, r: Rect2, fill01: float, col: Color, tick01: float = -1.0) -> void:
	ci.draw_rect(r, UiTokens.UI_BG_1)
	ci.draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(fill01, 0.0, 1.0), r.size.y)), col)
	ci.draw_rect(r, UiTokens.UI_LINE, false, 1.0)
	if tick01 >= 0.0:
		var x: float = r.position.x + r.size.x * tick01
		ci.draw_line(Vector2(x, r.position.y - 2.0), Vector2(x, r.end.y + 2.0), UiTokens.UI_TEXT, 1.0)


## Ring arc of fill 0..1 starting at 12 o'clock.
static func ring(ci: CanvasItem, c: Vector2, radius: float, fill01: float, col: Color) -> void:
	var lw: float = HudMath.param("line_du")
	ci.draw_arc(c, radius, 0.0, TAU, 32, UiTokens.UI_LINE, lw)
	if fill01 > 0.0:
		ci.draw_arc(c, radius, -PI * 0.5, -PI * 0.5 + TAU * clampf(fill01, 0.0, 1.0), 32, col, lw + 1.0)
