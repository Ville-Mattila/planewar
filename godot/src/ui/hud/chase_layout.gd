class_name ChaseLayout extends RefCounted
## Pure anchors of the Chase HUD widgets (06 s3.2 layout table; UX-51). Numbers from content/ui/hud.json.
## The status cluster takes the "Consumables" row (bottom-centre, 8 du above the bottom edge); the barrel readout
## has no row of its own and sits centred directly above it, clear of the touch stick zone and the right-half buttons.


## Top-left of a bottom-centre block of `size` du whose bottom edge is `lift` du above the margin.
static func bottom_centre(canvas_du: Vector2, size: Vector2, lift: float = 0.0) -> Vector2:
	return Vector2((canvas_du.x - size.x) * 0.5, canvas_du.y - HudMath.param("chase_margin_du") - lift - size.y)


## Top-left of the status cluster control so the DRAWN content (`content`, from StatusClusterView.content_rect) is centred.
static func status_pos(canvas_du: Vector2, content: Rect2) -> Vector2:
	var p: Vector2 = bottom_centre(canvas_du, content.size)
	return Vector2(p.x - content.position.x, p.y - content.position.y)


## Barrel readout centred above the drawn status content, `chase_gap_du` clear of its top.
static func barrel_pos(canvas_du: Vector2, content: Rect2, barrel_size: Vector2) -> Vector2:
	return bottom_centre(canvas_du, barrel_size, content.size.y + HudMath.param("chase_gap_du"))
