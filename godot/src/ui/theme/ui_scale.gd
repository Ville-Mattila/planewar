class_name UiScale extends RefCounted
## UI scale, COMPACT/REGULAR profile selection and safe-area maths (docs/06 s4.1).
## Pure statics; numbers come from res://content/ui/ui_scale.json.

enum Profile { COMPACT, REGULAR }

const PARAMS_PATH: String = "res://content/ui/ui_scale.json"

static var _params: Dictionary = {}


static func param(key: String) -> float:
	if _params.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PARAMS_PATH))
		var d: Dictionary = {}
		if parsed is Dictionary:
			d = parsed
		_params = d
	var v: Variant = _params.get(key, 0.0)
	return v if v is float or v is int else 0.0


## Window-pixel to du ratio before content_scale_factor (expand aspect).
static func base_scale(win_px: Vector2i) -> float:
	return minf(win_px.x / param("base_width"), win_px.y / param("base_height"))


static func content_scale_factor(win_px: Vector2i, screen_scale: float, is_touch: bool, user_scale: float) -> float:
	var user: float = clampf(user_scale, param("user_scale_min"), param("user_scale_max"))
	if not is_touch:
		return user
	var s0: float = maxf(base_scale(win_px), 0.0001)
	return clampf(screen_scale / s0, param("touch_factor_min"), param("touch_factor_max")) * user


## Visible canvas size in du for a window and content scale factor.
static func canvas_size_du(win_px: Vector2i, factor: float) -> Vector2:
	var d: float = maxf(base_scale(win_px) * factor, 0.0001)
	return Vector2(win_px) / d


static func profile_for_height(height_du: float) -> Profile:
	return Profile.COMPACT if height_du < param("compact_below_height_du") else Profile.REGULAR


## Profile for a window, display scale (density) and input class.
static func select_profile(win_px: Vector2i, screen_scale: float, is_touch: bool, user_scale: float) -> Profile:
	var f: float = content_scale_factor(win_px, screen_scale, is_touch, user_scale)
	return profile_for_height(canvas_size_du(win_px, f).y)


## HUD root rect in du: safe area (window pixels) converted to du, clipped to the canvas, then inset by
## safe_margin_du. An empty safe rect means "whole window".
static func safe_rect_du(win_px: Vector2i, factor: float, safe_px: Rect2i) -> Rect2:
	var canvas: Rect2 = Rect2(Vector2.ZERO, canvas_size_du(win_px, factor))
	var area: Rect2 = canvas
	if safe_px.size.x > 0 and safe_px.size.y > 0:
		var d: float = maxf(base_scale(win_px) * factor, 0.0001)
		area = Rect2(Vector2(safe_px.position) / d, Vector2(safe_px.size) / d).intersection(canvas)
	return area.grow(-param("safe_margin_du"))


## Applies the factor to a Window. Call on boot and on size_changed.
static func apply(win: Window, screen_scale: float, is_touch: bool, user_scale: float) -> float:
	var f: float = content_scale_factor(win.size, screen_scale, is_touch, user_scale)
	win.content_scale_factor = f
	return f
