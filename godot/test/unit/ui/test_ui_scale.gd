extends GdUnitTestSuite
## Unit tests for ui/theme/ui_scale.gd and ui/hud/hud_root.gd (UX-12; docs/06 s4.1).

const EPS: float = 0.001


func test_desktop_factor_is_user_scale() -> void:
	assert_float(UiScale.content_scale_factor(Vector2i(1280, 720), 1.0, false, 1.0)).is_equal_approx(1.0, EPS)
	assert_float(UiScale.content_scale_factor(Vector2i(2560, 1440), 2.0, false, 1.25)).is_equal_approx(1.25, EPS)


func test_user_scale_is_clamped() -> void:
	assert_float(UiScale.content_scale_factor(Vector2i(1280, 720), 1.0, false, 5.0)).is_equal_approx(1.5, EPS)
	assert_float(UiScale.content_scale_factor(Vector2i(1280, 720), 1.0, false, 0.1)).is_equal_approx(0.8, EPS)


func test_touch_one_du_is_one_dp() -> void:
	# 1 du = 1 dp: window px / (s0 * factor) == window px / density.
	var cases: Array[Vector3] = [Vector3(2400, 1080, 2.75), Vector3(1920, 1080, 2.0), Vector3(2560, 1600, 2.0), Vector3(1600, 720, 1.5)]
	for c: Vector3 in cases:
		var win: Vector2i = Vector2i(int(c.x), int(c.y))
		var f: float = UiScale.content_scale_factor(win, c.z, true, 1.0)
		var du: Vector2 = UiScale.canvas_size_du(win, f)
		assert_float(du.x).is_equal_approx(c.x / c.z, 0.01)
		assert_float(du.y).is_equal_approx(c.y / c.z, 0.01)


func test_profile_switches_at_500_du() -> void:
	assert_int(UiScale.profile_for_height(499.9)).is_equal(UiScale.Profile.COMPACT)
	assert_int(UiScale.profile_for_height(500.0)).is_equal(UiScale.Profile.REGULAR)


func test_profile_by_screen_size_and_density() -> void:
	# Landscape phone 2400x1080 at 2.75: 392 du high.
	assert_int(UiScale.select_profile(Vector2i(2400, 1080), 2.75, true, 1.0)).is_equal(UiScale.Profile.COMPACT)
	# Tablet 2560x1600 at 2.0: 800 du high.
	assert_int(UiScale.select_profile(Vector2i(2560, 1600), 2.0, true, 1.0)).is_equal(UiScale.Profile.REGULAR)
	# Same phone pixels at a lower density become REGULAR (more du).
	assert_int(UiScale.select_profile(Vector2i(2400, 1080), 1.5, true, 1.0)).is_equal(UiScale.Profile.REGULAR)
	# PC and Deck.
	assert_int(UiScale.select_profile(Vector2i(1280, 720), 1.0, false, 1.0)).is_equal(UiScale.Profile.REGULAR)
	assert_int(UiScale.select_profile(Vector2i(1280, 800), 1.0, false, 1.0)).is_equal(UiScale.Profile.REGULAR)


func test_safe_rect_without_cutout_is_canvas_minus_margin() -> void:
	var r: Rect2 = UiScale.safe_rect_du(Vector2i(1280, 720), 1.0, Rect2i())
	assert_vector(r.position).is_equal_approx(Vector2(8, 8), Vector2.ONE * EPS)
	assert_vector(r.size).is_equal_approx(Vector2(1264, 704), Vector2.ONE * EPS)


func test_safe_insets_applied_in_du() -> void:
	# 2400x1080 at density 3.0 -> 800x360 du; notch inset 120 px left, 60 px right, 30 px bottom.
	var win: Vector2i = Vector2i(2400, 1080)
	var f: float = UiScale.content_scale_factor(win, 3.0, true, 1.0)
	var r: Rect2 = UiScale.safe_rect_du(win, f, Rect2i(120, 0, 2400 - 180, 1080 - 30))
	assert_float(r.position.x).is_equal_approx(40.0 + 8.0, 0.01)
	assert_float(r.position.y).is_equal_approx(8.0, 0.01)
	assert_float(r.end.x).is_equal_approx(800.0 - 20.0 - 8.0, 0.01)
	assert_float(r.end.y).is_equal_approx(360.0 - 10.0 - 8.0, 0.01)


func test_hud_root_layout_and_profile_signal() -> void:
	var root: HudRoot = auto_free(load("res://scenes/ui/hud_root.tscn").instantiate()) as HudRoot
	assert_object(root).is_not_null()
	var phone: Vector2i = Vector2i(2400, 1080)
	root.layout(phone, UiScale.content_scale_factor(phone, 3.0, true, 1.0), Rect2i(120, 0, 2220, 1050))
	assert_int(root.profile).is_equal(UiScale.Profile.COMPACT)
	assert_float(root.position.x).is_equal_approx(48.0, 0.01)
	root.layout(Vector2i(1280, 720), 1.0, Rect2i())
	assert_int(root.profile).is_equal(UiScale.Profile.REGULAR)
	assert_vector(root.size).is_equal_approx(Vector2(1264, 704), Vector2.ONE * EPS)
