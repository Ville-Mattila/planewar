extends GdUnitTestSuite
## Unit tests for ui/hud/hud_math.gd and flight_hud_data.gd (UX-16; docs/06 s6.2).

const EPS: float = 0.0001


func test_pitch_level_up_down() -> void:
	var n: Vector3 = Vector3(0, 0, 1)
	assert_float(HudMath.pitch(Vector3(1, 0, 0), n)).is_equal_approx(0.0, EPS)
	assert_float(HudMath.pitch(Vector3(0, 0, 1), n)).is_equal_approx(PI / 2.0, EPS)
	assert_float(HudMath.pitch(Vector3(0, 0, -1), n)).is_equal_approx(-PI / 2.0, EPS)
	var f: Vector3 = Vector3(cos(deg_to_rad(30.0)), 0.0, sin(deg_to_rad(30.0)))
	assert_float(rad_to_deg(HudMath.pitch(f, n))).is_equal_approx(30.0, 0.001)


func test_ladder_angles_are_multiples_of_step() -> void:
	var marks: PackedFloat32Array = HudMath.ladder_marks(deg_to_rad(23.0), 10.0, 40.0)
	assert_float(marks[0]).is_equal_approx(-10.0, EPS)
	assert_float(marks[marks.size() - 1]).is_equal_approx(60.0, EPS)
	assert_int(marks.size()).is_equal(8)
	for m: float in marks:
		assert_float(fmod(m, 10.0)).is_equal_approx(0.0, EPS)


func test_ladder_y_pitch_up_moves_rungs_down() -> void:
	var p: float = deg_to_rad(10.0)
	assert_float(HudMath.ladder_y(0.0, p, 4.0)).is_equal_approx(40.0, 0.001)
	assert_float(HudMath.ladder_y(10.0, p, 4.0)).is_equal_approx(0.0, 0.001)


func test_bank_angle_magnitude() -> void:
	var n: Vector3 = Vector3(0, 1, 0)
	var level: Basis = Basis.looking_at(Vector3(0, 0, -1), n)
	assert_float(CamMath.bank_angle(level, n)).is_equal_approx(0.0, EPS)
	var banked: Basis = level.rotated(level.z, deg_to_rad(25.0))
	var d: FlightHudData = FlightHudData.from_state(Vector3(0, 6100.0, 0), Vector3.ZERO, banked, 6000.0, Vector3.ZERO)
	assert_float(absf(rad_to_deg(d.bank_rad))).is_equal_approx(25.0, 0.01)
	var d2: FlightHudData = FlightHudData.from_state(Vector3(0, 6100.0, 0), Vector3.ZERO, level, 6000.0, Vector3.ZERO)
	assert_float(d2.bank_rad).is_equal_approx(0.0, EPS)


func test_limb_dip_matches_spec() -> void:
	assert_float(HudMath.limb_dip(0.0)).is_equal_approx(0.0, EPS)
	var expect: float = acos(Sphere.PLANET_RADIUS / (Sphere.PLANET_RADIUS + 100.0))
	assert_float(HudMath.limb_dip(100.0)).is_equal_approx(expect, EPS)
	assert_float(rad_to_deg(HudMath.limb_dip(100.0))).is_between(10.0, 10.8)
	assert_float(HudMath.limb_dip(-5.0)).is_equal_approx(0.0, EPS)
	assert_bool(HudMath.limb_dip(1500.0) > HudMath.limb_dip(400.0)).is_true()


func test_limb_y_lies_below_level_line() -> void:
	var y0: float = HudMath.ladder_y(0.0, 0.1, 4.0)
	assert_bool(HudMath.limb_y(0.1, 400.0, 4.0) > y0).is_true()
	assert_float(HudMath.limb_y(0.1, 0.0, 4.0)).is_equal_approx(y0, EPS)


func test_heading_cardinals() -> void:
	# Equator point on +X: north = +Z, east = N x n = Z x X = +Y.
	var n: Vector3 = Vector3(1, 0, 0)
	assert_float(HudMath.heading_deg(Vector3(0, 0, 1), n)).is_equal_approx(0.0, 0.001)
	assert_float(HudMath.heading_deg(Vector3(0, 1, 0), n)).is_equal_approx(90.0, 0.001)
	assert_float(HudMath.heading_deg(Vector3(0, 0, -1), n)).is_equal_approx(180.0, 0.001)
	assert_float(HudMath.heading_deg(Vector3(0, -1, 0), n)).is_equal_approx(270.0, 0.001)
	assert_float(HudMath.heading_deg(Vector3(0.5, 0, 1), n)).is_equal_approx(0.0, 0.001)


func test_heading_undefined_at_pole_and_straight_up() -> void:
	assert_bool(is_nan(HudMath.heading_deg(Vector3(1, 0, 0), Vector3(0, 0, 1)))).is_true()
	assert_bool(HudMath.is_pole(Vector3(0, sin(deg_to_rad(0.5)), cos(deg_to_rad(0.5))))).is_true()
	assert_bool(HudMath.is_pole(Vector3(0, sin(deg_to_rad(2.0)), cos(deg_to_rad(2.0))))).is_false()
	assert_bool(is_nan(HudMath.heading_deg(Vector3(1, 0, 0), Vector3(1, 0, 0)))).is_true()


func test_heading_wrap() -> void:
	assert_float(HudMath.wrap_deg(-10.0)).is_equal_approx(350.0, EPS)
	assert_float(HudMath.wrap_deg(360.0)).is_equal_approx(0.0, EPS)
	assert_float(HudMath.wrap_deg(725.0)).is_equal_approx(5.0, EPS)
	assert_float(HudMath.delta_deg(350.0, 10.0)).is_equal_approx(20.0, EPS)
	assert_float(HudMath.delta_deg(10.0, 350.0)).is_equal_approx(-20.0, EPS)
	assert_float(HudMath.delta_deg(0.0, 180.0)).is_equal_approx(180.0, EPS)
	assert_float(HudMath.tape_x(10.0, 350.0, 280.0, 90.0)).is_equal_approx(62.2222, 0.01)


func test_band_thresholds() -> void:
	assert_int(HudMath.band(149.9, 149.9)).is_equal(HudMath.Band.DECK)
	assert_int(HudMath.band(150.0, 150.0)).is_equal(HudMath.Band.LOW)
	assert_int(HudMath.band(500.0, 399.9)).is_equal(HudMath.Band.LOW)
	assert_int(HudMath.band(500.0, 400.0)).is_equal(HudMath.Band.HIGH)
	assert_int(HudMath.band(1500.0, 1499.9)).is_equal(HudMath.Band.HIGH)
	assert_int(HudMath.band(1500.0, 1500.0)).is_equal(HudMath.Band.FADE)
	assert_int(HudMath.band(2100.0, 2100.0)).is_equal(HudMath.Band.FADE)
	assert_int(HudMath.band(100.0, 600.0)).is_equal(HudMath.Band.DECK)


func test_uplink() -> void:
	assert_float(HudMath.uplink(1000.0)).is_equal_approx(1.0, EPS)
	assert_float(HudMath.uplink(1500.0)).is_equal_approx(1.0, EPS)
	assert_float(HudMath.uplink(1750.0)).is_equal_approx(0.5, EPS)
	assert_float(HudMath.uplink(2000.0)).is_equal_approx(0.0, EPS)
	assert_bool(HudMath.uplink_visible(1499.0)).is_false()
	assert_bool(HudMath.uplink_visible(1500.0)).is_true()
	assert_bool(HudMath.uplink_lost(1999.0)).is_false()
	assert_bool(HudMath.uplink_lost(2000.0)).is_true()


func test_uplink_pulse_two_hz_from_1800() -> void:
	assert_float(HudMath.uplink_pulse(1799.0, 0.125)).is_equal_approx(0.0, EPS)
	assert_float(HudMath.uplink_pulse(1800.0, 0.125)).is_equal_approx(1.0, EPS)
	assert_float(HudMath.uplink_pulse(1800.0, 0.625)).is_equal_approx(1.0, EPS)
	assert_float(HudMath.uplink_pulse(1800.0, 0.375)).is_equal_approx(0.0, EPS)


func test_from_state_altitude_from_sphere_radius() -> void:
	var pos: Vector3 = Vector3(Sphere.PLANET_RADIUS + 300.0, 0, 0)
	var b: Basis = Basis.looking_at(Vector3(0, 0, 1), Vector3(1, 0, 0))
	var d: FlightHudData = FlightHudData.from_state(pos, Vector3(5, 0, 0), b, Sphere.PLANET_RADIUS + 100.0, Vector3(0, 1, 0))
	assert_float(d.alt_m).is_equal_approx(300.0, 0.01)
	assert_float(d.agl_m).is_equal_approx(200.0, 0.01)
	assert_float(d.vs_mps).is_equal_approx(5.0, 0.001)
	assert_int(d.band).is_equal(HudMath.Band.LOW)
	assert_float(d.heading).is_equal_approx(0.0, 0.01)
	assert_float(d.home_bearing).is_equal_approx(90.0, 0.01)
	assert_bool(d.link_visible).is_false()


func test_instruments_scene_instantiates_and_font_min() -> void:
	var scene: PackedScene = load("res://scenes/ui/flight_instruments.tscn")
	var fi: FlightInstruments = auto_free(scene.instantiate())
	assert_int(fi.font_size()).is_greater_equal(9)
	fi.profile = UiScale.Profile.COMPACT
	assert_int(fi.font_size()).is_greater_equal(9)


func test_readouts_inside_hud_root_safe_rect() -> void:
	var wins: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(2400, 1080)]
	var scales: Array[float] = [1.0, 2.75]
	var touch: Array[bool] = [false, true]
	var scene: PackedScene = load("res://scenes/ui/flight_instruments.tscn")
	for i: int in 2:
		var root: HudRoot = auto_free(HudRoot.new())
		var f: float = UiScale.content_scale_factor(wins[i], scales[i], touch[i], 1.0)
		root.layout(wins[i], f, Rect2i())
		var fi: FlightInstruments = auto_free(scene.instantiate())
		root.add_child(fi)
		fi.profile = root.profile
		fi.size = root.size
		var safe: Rect2 = Rect2(Vector2.ZERO, root.size)
		for r: Rect2 in fi.readout_rects():
			assert_bool(safe.encloses(r)).is_true()
		var canvas: Vector2 = UiScale.canvas_size_du(wins[i], f)
		var inset: float = UiScale.param("safe_margin_du")
		assert_float(root.position.x + root.size.x).is_less_equal(canvas.x - inset + 0.001)
		assert_float(root.position.x).is_greater_equal(inset - 0.001)
	assert_int(UiScale.select_profile(wins[0], 1.0, false, 1.0)).is_equal(UiScale.Profile.REGULAR)
	assert_int(UiScale.select_profile(wins[1], 2.75, true, 1.0)).is_equal(UiScale.Profile.COMPACT)
