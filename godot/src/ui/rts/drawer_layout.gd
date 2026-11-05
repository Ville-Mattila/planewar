class_name DrawerLayout extends RefCounted
## Production drawer geometry (docs/06 s4.4 COMPACT, s4.5 REGULAR, s7.5): a 3 x 6 grid of square tiles beside two
## vertical tabs, REGULAR with a queue strip under the grid. All numbers are in du, from content/ui/rts.json.


static func cols() -> int:
	return int(RtsParams.param("drawer_cols"))


static func rows() -> int:
	return int(RtsParams.param("drawer_rows"))


static func capacity() -> int:
	return cols() * rows()


static func tile_du(profile: UiScale.Profile) -> float:
	return RtsParams.param("drawer_tile_compact_du" if profile == UiScale.Profile.COMPACT else "drawer_tile_regular_du")


static func gap_du() -> float:
	return RtsParams.param("drawer_gap_du")


static func tab_w_du(profile: UiScale.Profile) -> float:
	return RtsParams.param("drawer_tab_w_compact_du" if profile == UiScale.Profile.COMPACT else "drawer_tab_w_regular_du")


static func tab_h_du(_profile: UiScale.Profile) -> float:
	return RtsParams.param("drawer_tab_h_du")


static func top_du(profile: UiScale.Profile) -> float:
	return RtsParams.param("drawer_top_compact_du" if profile == UiScale.Profile.COMPACT else "drawer_top_regular_du")


static func strip_du(profile: UiScale.Profile) -> float:
	return 0.0 if profile == UiScale.Profile.COMPACT else RtsParams.param("drawer_strip_regular_du")


static func font_du(profile: UiScale.Profile) -> int:
	var f: float = RtsParams.param("drawer_font_compact_du" if profile == UiScale.Profile.COMPACT else "drawer_font_regular_du")
	return int(maxf(f, HudMath.param("font_du_min")))


static func grid_size(profile: UiScale.Profile) -> Vector2:
	var t: float = tile_du(profile)
	var g: float = gap_du()
	return Vector2(float(cols()) * t + float(cols() - 1) * g, float(rows()) * t + float(rows() - 1) * g)


## Grid origin inside the drawer: right of the tabs.
static func grid_origin(profile: UiScale.Profile) -> Vector2:
	return Vector2(tab_w_du(profile) + gap_du(), 0.0)


## Tabs + gap + grid; REGULAR adds the queue strip (and one gap) under the grid.
static func size_du(profile: UiScale.Profile) -> Vector2:
	var g: Vector2 = grid_size(profile)
	var s: float = strip_du(profile)
	return Vector2(grid_origin(profile).x + g.x, g.y + (gap_du() + s if s > 0.0 else 0.0))


## Tile `index` (row-major) relative to the grid origin.
static func tile_rect(profile: UiScale.Profile, index: int) -> Rect2:
	var t: float = tile_du(profile)
	var step: float = t + gap_du()
	var col: int = index % cols()
	var row: int = MathX.floori_div(index, cols())
	return Rect2(Vector2(float(col) * step, float(row) * step), Vector2(t, t))


## Tab `index` (0 BUILD, 1 UNITS) relative to the drawer origin.
static func tab_rect(profile: UiScale.Profile, index: int) -> Rect2:
	var h: float = tab_h_du(profile)
	return Rect2(Vector2(0.0, float(index) * (h + gap_du())), Vector2(tab_w_du(profile), h))


## Queue strip relative to the drawer origin (zero-size in COMPACT).
static func strip_rect(profile: UiScale.Profile) -> Rect2:
	var s: float = strip_du(profile)
	if s <= 0.0:
		return Rect2()
	return Rect2(Vector2(grid_origin(profile).x, grid_size(profile).y + gap_du()), Vector2(grid_size(profile).x, s))


## True when the drawer, placed `top_du` under the HUD root's top edge, lies inside the canvas minus `safe_margin_du` on
## every side, so nothing needs a scroll bar.
static func fits(profile: UiScale.Profile, canvas_du: Vector2) -> bool:
	var m: float = UiScale.param("safe_margin_du") * 2.0
	var sz: Vector2 = size_du(profile)
	return sz.x <= canvas_du.x - m and top_du(profile) + sz.y <= canvas_du.y - m
