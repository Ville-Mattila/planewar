class_name BombSightView extends Control
## Draws the bomb impact ring (green on a predicted hit), time to impact, and lead pips.
## Thin: callers project world points to local screen coordinates and push state.

var ring_visible: bool = false
var ring_pos: Vector2
var ring_hit: bool = false
var tti_s: float
var pips: PackedVector2Array = PackedVector2Array()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_ring(pos: Vector2, hit: bool, tti: float) -> void:
	ring_visible = true
	ring_pos = pos
	ring_hit = hit
	tti_s = tti
	queue_redraw()


func hide_ring() -> void:
	ring_visible = false
	queue_redraw()


func set_pips(p: PackedVector2Array) -> void:
	pips = p
	queue_redraw()


func _draw() -> void:
	var lw: float = HudMath.param("line_du")
	if ring_visible:
		var col: Color = UiTokens.UI_OK if ring_hit else UiTokens.UI_WARN
		var r: float = HudMath.param("sight_ring_du")
		draw_arc(ring_pos, r, 0.0, TAU, 32, col, lw)
		draw_line(ring_pos - Vector2(r * 0.4, 0.0), ring_pos + Vector2(r * 0.4, 0.0), col, lw)
		draw_line(ring_pos - Vector2(0.0, r * 0.4), ring_pos + Vector2(0.0, r * 0.4), col, lw)
		var fs: int = int(HudMath.param("font_du"))
		draw_string(ThemeDB.fallback_font, ring_pos + Vector2(r + 4.0, fs * 0.4),
				tr(&"hud.bomb.tti") + " " + String.num(tti_s, 1), HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs, col)
	for p: Vector2 in pips:
		draw_arc(p, HudMath.param("sight_pip_du"), 0.0, TAU, 16, UiTokens.RELATION_ENEMY, lw)
