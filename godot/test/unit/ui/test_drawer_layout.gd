extends GdUnitTestSuite
## DrawerLayout (UX-22; docs/06 s4.4, s4.5, s7.5): 18 tiles fit without scrolling at 800x360 (COMPACT, tiles of 44)
## and 1280x720 (REGULAR, tiles of 64); touch targets >= 44 du and >= 8 du apart is the HUD rule, tiles keep gap 4.

const C := UiScale.Profile.COMPACT
const R := UiScale.Profile.REGULAR


func test_grid_is_three_by_six_and_holds_18_tiles() -> void:
	assert_int(DrawerLayout.cols()).is_equal(3)
	assert_int(DrawerLayout.rows()).is_equal(6)
	assert_int(DrawerLayout.capacity()).is_equal(18)
	var cat_max: int = maxi(DrawerCatalog.structure_ids().size(), DrawerCatalog.unit_ids().size())
	assert_int(cat_max).is_less_equal(DrawerLayout.capacity())


func test_compact_matches_the_spec_rectangle() -> void:
	assert_float(DrawerLayout.tile_du(C)).is_equal(44.0)
	assert_vector(DrawerLayout.grid_size(C)).is_equal(Vector2(140.0, 284.0))
	assert_vector(DrawerLayout.size_du(C)).is_equal(Vector2(188.0, 284.0))      # 06 s4.4: 188 x 284 at (-188, 52)
	assert_float(DrawerLayout.top_du(C)).is_equal(52.0)


func test_regular_uses_64_tiles_48_tabs_and_a_64_strip() -> void:
	assert_float(DrawerLayout.tile_du(R)).is_equal(64.0)
	assert_float(DrawerLayout.tab_w_du(R)).is_equal(48.0)
	assert_vector(DrawerLayout.grid_size(R)).is_equal(Vector2(200.0, 404.0))
	assert_vector(DrawerLayout.size_du(R)).is_equal(Vector2(252.0, 472.0))      # grid + gap + 64 strip under it


func test_fits_without_scrolling_at_800x360_and_1280x720() -> void:
	assert_bool(DrawerLayout.fits(C, Vector2(800.0, 360.0))).is_true()
	assert_bool(DrawerLayout.fits(R, Vector2(1280.0, 720.0))).is_true()
	assert_bool(DrawerLayout.fits(C, Vector2(800.0, 320.0))).is_false()        # too short: would need a scroll
	assert_bool(DrawerLayout.fits(R, Vector2(1280.0, 480.0))).is_false()


func test_profile_selection_puts_800x360_in_compact_and_1280x720_in_regular() -> void:
	assert_int(UiScale.select_profile(Vector2i(800, 360), 1.0, true, 1.0)).is_equal(C)
	assert_int(UiScale.select_profile(Vector2i(1280, 720), 1.0, false, 1.0)).is_equal(R)
	assert_int(UiScale.select_profile(Vector2i(1280, 800), 1.0, false, 1.0)).is_equal(R)


func test_tile_rects_are_inside_the_grid_non_overlapping_and_gapped() -> void:
	for p: UiScale.Profile in [C, R]:
		var grid: Rect2 = Rect2(Vector2.ZERO, DrawerLayout.grid_size(p))
		for i: int in DrawerLayout.capacity():
			var a: Rect2 = DrawerLayout.tile_rect(p, i)
			assert_bool(grid.encloses(a)).is_true()
			assert_float(a.size.x).is_equal(DrawerLayout.tile_du(p))
			for j: int in range(i + 1, DrawerLayout.capacity()):
				assert_bool(a.grow(DrawerLayout.gap_du() * 0.5 - 0.01).intersects(DrawerLayout.tile_rect(p, j).grow(DrawerLayout.gap_du() * 0.5 - 0.01))).is_false()
	assert_vector(DrawerLayout.tile_rect(C, 0).position).is_equal(Vector2.ZERO)
	assert_vector(DrawerLayout.tile_rect(C, 4).position).is_equal(Vector2(48.0, 48.0))   # row 1, column 1
	assert_vector(DrawerLayout.tile_rect(C, 17).position).is_equal(Vector2(96.0, 240.0))


func test_touch_targets_are_at_least_44_du() -> void:
	assert_float(DrawerLayout.tile_du(C)).is_greater_equal(44.0)
	assert_float(DrawerLayout.tab_w_du(C)).is_greater_equal(44.0)
	assert_float(DrawerLayout.tab_h_du(C)).is_greater_equal(44.0)
	assert_float(2.0 * DrawerLayout.tab_h_du(C)).is_less_equal(DrawerLayout.grid_size(C).y)   # two tabs fit beside the grid
