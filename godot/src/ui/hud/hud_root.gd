class_name HudRoot extends Control
## Safe-area HUD root: children anchor to this node, which sits at the safe rect + margin.
## Thin scene script; maths is in UiScale.

signal profile_changed(profile: UiScale.Profile)

var profile: UiScale.Profile = UiScale.Profile.REGULAR


## Lays out the root for a window; an empty safe_px means no cut-outs.
func layout(win_px: Vector2i, factor: float, safe_px: Rect2i) -> void:
	var rect: Rect2 = UiScale.safe_rect_du(win_px, factor, safe_px)
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = rect.position
	size = rect.size
	var p: UiScale.Profile = UiScale.profile_for_height(UiScale.canvas_size_du(win_px, factor).y)
	if p != profile:
		profile = p
		profile_changed.emit(p)


## Reads the live window and display; call from the screen on boot and size_changed.
func refresh(win: Window) -> void:
	var is_touch: bool = DisplayServer.is_touchscreen_available()
	var f: float = UiScale.apply(win, DisplayServer.screen_get_scale(), is_touch, 1.0)
	layout(win.size, f, DisplayServer.get_display_safe_area())
