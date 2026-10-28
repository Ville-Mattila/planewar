extends GdUnitTestSuite
## Unit tests for the UX-18 landing guide, grade stamp, service panel, shield timer and cooldown maths
## (docs/06 s6.4; ui/hud/landing_math.gd, landing_stamp.gd, status_math.gd, landing_hud_data.gd).

const EPS: float = 0.0001
const Z := LandingMath.Zone


class FakeView extends SimView:
	var p_ship: Vector3 = Vector3(0, 6100, 0)
	var p_pad: Vector3 = Vector3(0, 6000, 0)
	var v_ship: Vector3 = Vector3(0, -5, 3)
	var occupant: int = 0

	func alive(_id: int) -> bool:
		return true

	func pos(id: int) -> Vector3:
		return p_ship if id == 1 else p_pad

	func vel(_id: int) -> Vector3:
		return v_ship

	func basis(_id: int) -> Basis:
		return Basis.looking_at(Vector3(0, 1, 0), Vector3(1, 0, 0))   # forward = -z -> +y: nose up

	func fuel01(_id: int) -> float:
		return 0.5

	func nearest_friendly_pad(_id: int) -> int:
		return 2

	func pad_occupant(_pad: int) -> int:
		return occupant

	func rockets(_id: int) -> int:
		return 2

	func service_progress(_id: int) -> Vector3:
		return Vector3(0.2, 0.5, 1.0)


func test_vertical_gauge_switches_at_8_and_15() -> void:
	assert_int(LandingMath.zone_vert(8.0)).is_equal(Z.SAFE)
	assert_int(LandingMath.zone_vert(8.01)).is_equal(Z.DAMAGE)
	assert_int(LandingMath.zone_vert(15.0)).is_equal(Z.DAMAGE)
	assert_int(LandingMath.zone_vert(15.01)).is_equal(Z.DESTROY)


func test_horizontal_gauge_switches_at_15_and_25() -> void:
	assert_int(LandingMath.zone_horiz(15.0)).is_equal(Z.SAFE)
	assert_int(LandingMath.zone_horiz(15.01)).is_equal(Z.DAMAGE)
	assert_int(LandingMath.zone_horiz(25.0)).is_equal(Z.DAMAGE)
	assert_int(LandingMath.zone_horiz(25.01)).is_equal(Z.DESTROY)


func test_nose_gauge_switches_at_25_and_45() -> void:
	assert_int(LandingMath.zone_nose(25.0)).is_equal(Z.SAFE)
	assert_int(LandingMath.zone_nose(25.01)).is_equal(Z.DAMAGE)
	assert_int(LandingMath.zone_nose(45.0)).is_equal(Z.DAMAGE)
	assert_int(LandingMath.zone_nose(45.01)).is_equal(Z.DESTROY)


func test_zone_colours_are_ok_warn_danger() -> void:
	assert_object(LandingMath.zone_color(Z.SAFE)).is_equal(UiTokens.UI_OK)
	assert_object(LandingMath.zone_color(Z.DAMAGE)).is_equal(UiTokens.UI_WARN)
	assert_object(LandingMath.zone_color(Z.DESTROY)).is_equal(UiTokens.UI_DANGER)


func test_hud_bands_match_the_sim_flight_common() -> void:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://content/defs/ships.json"))
	var common: Dictionary = (raw as Dictionary)["flight_common"]
	assert_float(HudMath.param("gauge_vert_safe_mps")).is_equal(float(common["landing_safe_v_vert"]))
	assert_float(HudMath.param("gauge_vert_damage_mps")).is_equal(float(common["landing_damage_v_vert"]))
	assert_float(HudMath.param("gauge_horiz_safe_mps")).is_equal(float(common["landing_safe_v_hor"]))
	assert_float(HudMath.param("gauge_horiz_damage_mps")).is_equal(float(common["landing_damage_v_hor"]))
	assert_float(HudMath.param("gauge_nose_safe_deg")).is_equal(float(common["landing_safe_pitch_deg"]))
	assert_float(HudMath.param("gauge_nose_damage_deg")).is_equal(float(common["landing_damage_tilt_deg"]))


func test_speeds_and_nose_from_vertical() -> void:
	var up: Vector3 = Vector3(0, 1, 0)
	assert_float(LandingMath.vert_speed(Vector3(4, -6, 0), up)).is_equal_approx(6.0, EPS)
	assert_float(LandingMath.vert_speed(Vector3(0, 3, 0), up)).is_equal_approx(0.0, EPS)
	assert_float(LandingMath.horiz_speed(Vector3(3, -6, 4), up)).is_equal_approx(5.0, EPS)
	assert_float(LandingMath.nose_from_vertical_deg(up, up)).is_equal_approx(0.0, EPS)
	assert_float(LandingMath.nose_from_vertical_deg(Vector3(1, 0, 0), up)).is_equal_approx(90.0, 0.001)
	var f: Vector3 = Vector3(sin(deg_to_rad(30.0)), cos(deg_to_rad(30.0)), 0.0)
	assert_float(LandingMath.nose_from_vertical_deg(f, up)).is_equal_approx(30.0, 0.001)


func test_guide_visibility_rule() -> void:
	assert_bool(LandingMath.guide_visible(1500.0, 300.0, 1.0)).is_true()
	assert_bool(LandingMath.guide_visible(1500.1, 300.0, 1.0)).is_false()
	assert_bool(LandingMath.guide_visible(800.0, 500.0, 1.0)).is_false()
	assert_bool(LandingMath.guide_visible(800.0, 500.0, 0.2)).is_true()
	assert_bool(LandingMath.guide_visible(-1.0, 10.0, 0.0)).is_false()


func test_phase_flare_then_hover() -> void:
	assert_int(LandingMath.phase(400.0, 300.0)).is_equal(LandingMath.Phase.APPROACH)
	assert_int(LandingMath.phase(150.0, 130.0)).is_equal(LandingMath.Phase.FLARE)
	assert_int(LandingMath.phase(150.0, 100.0)).is_equal(LandingMath.Phase.HOVER)
	assert_int(LandingMath.phase(40.0, 50.0)).is_equal(LandingMath.Phase.HOVER)


func test_gauge_fill_and_safe_tick() -> void:
	assert_float(LandingMath.fill01(0.0, 15.0)).is_equal_approx(0.0, EPS)
	assert_float(LandingMath.fill01(1000.0, 15.0)).is_equal_approx(1.0, EPS)
	assert_float(LandingMath.fill01(15.0, 15.0)).is_equal_approx(1.0 / 1.5, EPS)
	assert_bool(LandingMath.safe_tick01(8.0, 15.0) < LandingMath.fill01(15.0, 15.0)).is_true()


func test_drift_arrow_points_at_the_pad_and_is_capped() -> void:
	assert_object(LandingMath.drift_arrow(Vector2.ZERO, 10.0)).is_equal(Vector2.ZERO)
	var a: Vector2 = LandingMath.drift_arrow(Vector2(5.0, 0.0), 10.0)
	assert_bool(a.x < 0.0 and absf(a.y) < EPS).is_true()
	var cap: float = HudMath.param("drift_arrow_du")
	assert_float(LandingMath.drift_arrow(Vector2(0.0, 500.0), 10.0).length()).is_equal_approx(cap, EPS)
	assert_bool(LandingMath.drift_arrow(Vector2(0.0, 500.0), 10.0).y < 0.0).is_true()


func test_pad_offset_is_in_the_pad_plane() -> void:
	var up: Vector3 = Vector3(0, 1, 0)
	var o: Vector2 = LandingMath.pad_offset(Vector3(3, 90, 4), Vector3.ZERO, up, Vector3(1, 0, 0), Vector3(0, 0, 1))
	assert_float(o.x).is_equal_approx(3.0, EPS)
	assert_float(o.y).is_equal_approx(4.0, EPS)


func test_first_free_pad_skips_occupied() -> void:
	var pads: PackedInt32Array = PackedInt32Array([5, 6, 7])
	assert_int(LandingMath.first_free(pads, PackedInt32Array([9, 0, 0]))).is_equal(1)
	assert_int(LandingMath.first_free(pads, PackedInt32Array([9, 8, 7]))).is_equal(-1)


# --- grade stamp ---

func _landing(grade: int, flags: int) -> SimEvent:
	var e: SimEvent = SimEvent.new()
	e.kind = SimEvent.Kind.LANDING
	e.a = 1
	e.b = 2
	e.value = 0.7
	e.extra = PackedByteArray([grade, 178, flags, 52, 91])
	return e


func test_stamp_shows_every_landing_grade() -> void:
	var seen: Dictionary = {}
	for g: int in LandingGrade.Grade.values():
		var s: LandingStamp = LandingStamp.from_event(_landing(g, 1))
		assert_object(s).is_not_null()
		assert_int(s.grade).is_equal(g)
		assert_str(tr(s.label_key())).is_not_empty()
		assert_str(String(s.label_key())).is_equal("hud.grade." + String(LandingGrade.Grade.keys()[g]).to_lower())
		seen[g] = true
	assert_int(seen.size()).is_equal(LandingGrade.Grade.size())


func test_stamp_view_shows_each_grade_and_hides_after_hold() -> void:
	var view: GradeStampView = auto_free(load("res://scenes/ui/grade_stamp.tscn").instantiate())
	add_child(view)
	for g: int in LandingGrade.Grade.values():
		assert_bool(view.show_event(_landing(g, 1))).is_true()
		assert_bool(view.visible).is_true()
		assert_str(view.lines()[0]).is_equal(tr(LandingStamp.GRADE_KEYS[g]))
	view._process(HudMath.param("stamp_hold_s") + 0.1)
	assert_bool(view.visible).is_false()


func test_stamp_view_ignores_other_events() -> void:
	var view: GradeStampView = auto_free(load("res://scenes/ui/grade_stamp.tscn").instantiate())
	add_child(view)
	var e: SimEvent = SimEvent.new()
	e.kind = SimEvent.Kind.DOCKED
	assert_bool(view.show_event(e)).is_false()
	var bad: SimEvent = _landing(0, 0)
	bad.extra = PackedByteArray([200, 0, 0, 0, 0])
	assert_bool(view.show_event(bad)).is_false()


func test_stamp_points_hot_and_dead_stick() -> void:
	var ace: LandingStamp = LandingStamp.from_event(_landing(LandingGrade.Grade.ACE, 1))
	assert_int(ace.base_points).is_equal(50)
	assert_int(ace.total_points()).is_equal(50)
	var hot: LandingStamp = LandingStamp.from_event(_landing(LandingGrade.Grade.ACE, 1 | 2))
	assert_float(hot.hot_mult).is_equal_approx(1.5, EPS)
	assert_int(hot.total_points()).is_equal(75)
	var dead: LandingStamp = LandingStamp.from_event(_landing(LandingGrade.Grade.FAIR, 1 | 2 | 4))
	assert_bool(dead.dead_stick).is_true()
	assert_int(dead.bonus_points).is_equal(20)
	assert_int(dead.total_points()).is_equal(int(roundf(15.0 * 1.5)) + 20)
	var auto: LandingStamp = LandingStamp.from_event(_landing(LandingGrade.Grade.AUTO, 0))
	assert_bool(auto.manual).is_false()
	assert_int(auto.total_points()).is_equal(0)
	var crash: LandingStamp = LandingStamp.from_event(_landing(LandingGrade.Grade.CRASH, 4))
	assert_int(crash.total_points()).is_equal(0)


func test_dead_stick_bonus_only_on_manual_grades() -> void:
	for g: int in [LandingGrade.Grade.AUTO, LandingGrade.Grade.BENT, LandingGrade.Grade.CRASH]:
		var s: LandingStamp = LandingStamp.from_event(_landing(g, 4))
		assert_bool(s.dead_stick).is_true()
		assert_int(s.bonus_points).is_equal(0)
		assert_int(s.total_points()).is_equal(0)
	for g: int in [LandingGrade.Grade.HARD, LandingGrade.Grade.CLEAN, LandingGrade.Grade.ACE]:
		var s: LandingStamp = LandingStamp.from_event(_landing(g, 1 | 4))
		assert_int(s.bonus_points).is_equal(20)
		assert_int(s.total_points()).is_equal(s.base_points + 20)


func test_stamp_decodes_speeds() -> void:
	var s: LandingStamp = LandingStamp.from_event(_landing(LandingGrade.Grade.CLEAN, 1))
	assert_float(s.v_vert).is_equal_approx(5.2, EPS)
	assert_float(s.v_horiz).is_equal_approx(9.1, EPS)
	assert_float(s.q).is_equal_approx(0.7, EPS)


# --- shield timer, cooldowns, consumables ---

func test_shield_timer() -> void:
	assert_float(StatusMath.shield_remaining_s(480.0, 100.0)).is_equal_approx(380.0, EPS)
	assert_float(StatusMath.shield_remaining_s(480.0, 500.0)).is_equal_approx(0.0, EPS)
	assert_int(StatusMath.CORE_SHIELD_UP).is_equal(TeamStateView.CORE_SHIELD_UP)
	assert_float(StatusMath.shield_ring01(480.0, 0.0)).is_equal_approx(1.0, EPS)
	assert_float(StatusMath.shield_ring01(480.0, 240.0)).is_equal_approx(0.5, EPS)
	assert_bool(StatusMath.shield_visible(TeamStateView.CORE_SHIELD_UP, 480.0, 100.0)).is_true()
	assert_bool(StatusMath.shield_visible(TeamStateView.LOW_POWER, 480.0, 100.0)).is_false()
	assert_bool(StatusMath.shield_visible(TeamStateView.CORE_SHIELD_UP, 480.0, 480.0)).is_false()


func test_cooldown_rings_and_shares() -> void:
	assert_float(StatusMath.ring_fill(1.0)).is_equal_approx(0.0, EPS)
	assert_float(StatusMath.ring_fill(0.25)).is_equal_approx(0.75, EPS)
	assert_bool(StatusMath.ring_ready(0.0)).is_true()
	assert_bool(StatusMath.ring_ready(0.1)).is_false()
	assert_float(StatusMath.boost_fill(StatusMath.Boost.COOLING)).is_equal_approx(0.0, EPS)
	assert_float(StatusMath.boost_fill(StatusMath.Boost.READY)).is_equal_approx(1.0, EPS)
	assert_float(StatusMath.share01(3, 6)).is_equal_approx(0.5, EPS)
	assert_float(StatusMath.share01(3, 0)).is_equal_approx(0.0, EPS)


func test_status_cluster_rows_and_shield() -> void:
	var view: StatusClusterView = auto_free(load("res://scenes/ui/status_cluster.tscn").instantiate())
	add_child(view)
	var d: LandingHudData = LandingHudData.new()
	d.ammo = 40
	d.rockets = 2
	view.set_data(d)
	assert_int(view.rows().size()).is_equal(4)
	assert_str(view.rows()[1][1]).is_equal("40")
	view.set_shield(TeamStateView.CORE_SHIELD_UP, 480.0, 60.0)
	assert_bool(view.shield_shown).is_true()
	assert_float(view.shield_left_s).is_equal_approx(420.0, EPS)


# --- reading through SimView ---

func test_hud_data_reads_simview() -> void:
	var v: FakeView = FakeView.new()
	var d: LandingHudData = LandingHudData.from_view(v, 1, 100.0, 12.0)
	assert_int(d.pad).is_equal(2)
	assert_float(d.pad_dist_m).is_equal_approx(100.0, EPS)
	assert_float(d.v_vert).is_equal_approx(5.0, EPS)
	assert_float(d.v_horiz).is_equal_approx(3.0, EPS)
	assert_float(d.nose_deg).is_equal_approx(0.0, 0.01)
	assert_int(d.rockets).is_equal(2)
	assert_bool(d.visible).is_true()
	assert_int(d.phase).is_equal(LandingMath.Phase.HOVER)
	assert_bool(d.pad_occupied).is_false()
	v.occupant = 9
	assert_bool(LandingHudData.from_view(v, 1, 100.0, 12.0).pad_occupied).is_true()
	assert_float(d.service.x).is_equal_approx(0.2, EPS)


func test_views_instantiate_and_draw_each_state() -> void:
	var v: FakeView = FakeView.new()
	var d: LandingHudData = LandingHudData.from_view(v, 1, 100.0, 12.0)
	var guide: LandingGuideView = auto_free(load("res://scenes/ui/landing_guide.tscn").instantiate())
	add_child(guide)
	guide.set_data(d)
	assert_bool(guide.visible).is_true()
	var panel: ServicePanelView = auto_free(load("res://scenes/ui/service_panel.tscn").instantiate())
	add_child(panel)
	d.docked = true
	panel.set_data(d)
	assert_bool(panel.visible).is_true()
	assert_float(panel.fills()[1]).is_equal_approx(0.5, EPS)
	guide.set_data(d)
	assert_bool(guide.visible).is_false()


func test_text_never_below_the_minimum() -> void:
	assert_bool(HudText.font_size(UiScale.Profile.REGULAR) >= int(HudMath.param("font_du_min"))).is_true()
	assert_bool(HudText.font_size(UiScale.Profile.COMPACT) >= HudText.font_size(UiScale.Profile.REGULAR)).is_true()
