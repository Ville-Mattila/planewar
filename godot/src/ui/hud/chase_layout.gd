class_name ChaseLayout extends RefCounted
## Pure anchors of the Chase HUD widgets (06 s3.2 layout table; UX-51). Numbers from content/ui/hud.json.
## The status cluster takes the "Consumables" row (bottom-centre, 8 du above the bottom edge); the barrel readout
## has no row of its own and sits centred directly above it, clear of the touch stick zone and the right-half buttons.


## Top-left of a bottom-centre block of `size` du whose bottom edge is `lift` du above the margin.
static func bottom_centre(canvas_du: Vector2, size: Vector2, lift: float = 0.0) -> Vector2:
	return Vector2((canvas_du.x - size.x) * 0.5, canvas_du.y - HudMath.param("chase_margin_du") - lift - size.y)


static func status_pos(canvas_du: Vector2, status_size: Vector2) -> Vector2:
	return bottom_centre(canvas_du, status_size)


static func barrel_pos(canvas_du: Vector2, status_size: Vector2, barrel_size: Vector2) -> Vector2:
	return bottom_centre(canvas_du, barrel_size, status_size.y + HudMath.param("chase_gap_du"))
