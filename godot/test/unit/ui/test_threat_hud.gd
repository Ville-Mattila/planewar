extends GdUnitTestSuite
## UX-19 threat ring and tower hints from scripted SimView states (docs/06 s6.1; ui/hud/threat_*.gd, tower_hint.gd).

const EPS: float = 0.0001
const SHIP: int = 1
const R: float = Sphere.PLANET_RADIUS

var _v: HudScenarioView


func before_test() -> void:
	var r: Result = ContentDB.load_all()
	assert_bool(r.ok).is_true()
	_v = HudScenarioView.new()
	_v.add(SHIP, &"dart", 0, Vector3(0.0, R + 300.0, 0.0))


func test_angle_zero_is_up_and_clockwise_positive() -> void:
	var b: Basis = Basis.IDENTITY
	assert_float(ThreatMath.angle(Vector3(0, 10, 0), b)).is_equal_approx(0.0, EPS)
	assert_float(ThreatMath.angle(Vector3(10, 0, 0), b)).is_equal_approx(PI / 2.0, EPS)
	assert_float(ThreatMath.angle(Vector3(0, -10, 0), b)).is_equal_approx(PI, EPS)
	assert_float(ThreatMath.angle(Vector3(-10, 0, 0), b)).is_equal_approx(-PI / 2.0, EPS)


func test_angle_follows_the_ship_basis() -> void:
	var rolled: Basis = Basis(Vector3(0, 0, -1), PI / 2.0)   # bank 90 deg about the nose
	var a: float = ThreatMath.angle(Vector3(0, 10, 0), rolled)
	assert_float(absf(a)).is_equal_approx(PI / 2.0, EPS)


func test_ring_pos_and_intensity_and_ahead() -> void:
	assert_vector(ThreatMath.ring_pos(0.0, 140.0)).is_equal_approx(Vector2(0, -140), Vector2(EPS, EPS))
	assert_vector(ThreatMath.ring_pos(PI / 2.0, 140.0)).is_equal_approx(Vector2(140, 0), Vector2(EPS, EPS))
	assert_float(ThreatMath.intensity(0.0, 2000.0)).is_equal_approx(1.0, EPS)
	assert_float(ThreatMath.intensity(1000.0, 2000.0)).is_equal_approx(0.5, EPS)
	assert_float(ThreatMath.intensity(5000.0, 2000.0)).is_equal_approx(0.0, EPS)
	assert_bool(ThreatMath.ahead(Vector3(0, 0, -5), Basis.IDENTITY)).is_true()
	assert_bool(ThreatMath.ahead(Vector3(0, 0, 5), Basis.IDENTITY)).is_false()


func test_only_visible_hostiles_inside_2000_m_make_arrows_sorted_near_first() -> void:
	_v.add(2, &"dart", 1, Vector3(500.0, R + 300.0, 0.0))        # hostile, 500 m right
	_v.add(3, &"lancer", 1, Vector3(0.0, R + 300.0, -1500.0))    # hostile, 1,500 m ahead
	_v.add(4, &"dart", 0, Vector3(100.0, R + 300.0, 0.0))        # friendly
	_v.add(5, &"dart", 1, Vector3(0.0, R + 300.0, 2500.0))       # hostile, out of range
	_v.add(6, &"dart", 1, Vector3(0.0, R + 800.0, 0.0))          # hostile but not visible
	_v.hidden[6] = true
	var t: ThreatData = ThreatData.from_view(_v, SHIP, 0)
	assert_int(t.arrows.size()).is_equal(2)
	assert_int(t.arrows[0].id).is_equal(2)
	assert_int(t.arrows[1].id).is_equal(3)
	assert_float(t.arrows[0].angle).is_equal_approx(PI / 2.0, EPS)
	assert_bool(t.arrows[1].ahead).is_true()
	assert_bool(t.rocket_lock).is_false()


func test_arrows_are_capped_at_the_json_maximum() -> void:
	for i: int in 12:
		_v.add(10 + i, &"dart", 1, Vector3(100.0 + 50.0 * i, R + 300.0, 0.0))
	var t: ThreatData = ThreatData.from_view(_v, SHIP, 0)
	assert_int(t.arrows.size()).is_equal(int(HudMath.param("threat_max_arrows")))
	assert_int(t.arrows[0].id).is_equal(10)


func test_incoming_rocket_sets_the_lock() -> void:
	_v.rockets_at[SHIP] = 2
	var t: ThreatData = ThreatData.from_view(_v, SHIP, 0)
	assert_bool(t.rocket_lock).is_true()
	assert_int(t.rockets).is_equal(2)
	assert_int(t.arrows.size()).is_equal(0)


func test_tower_rule_per_envelope() -> void:
	var flak: Dictionary = {"h_rel_min": 150, "h_rel_max": 1500}
	var cannon: Dictionary = {"h_rel_min": -200, "h_rel_max": 400, "target_agl_min": 0}
	var missile: Dictionary = {"h_rel_min": -300, "h_rel_max": 1500, "target_agl_min": 40}
	assert_int(TowerHint.rule_for(flak)).is_equal(TowerHint.Rule.BELOW)
	assert_float(TowerHint.limit_for(flak)).is_equal_approx(150.0, EPS)
	assert_int(TowerHint.rule_for(cannon)).is_equal(TowerHint.Rule.ABOVE)
	assert_float(TowerHint.limit_for(cannon)).is_equal_approx(400.0, EPS)
	assert_int(TowerHint.rule_for(missile)).is_equal(TowerHint.Rule.BELOW)
	assert_float(TowerHint.limit_for(missile)).is_equal_approx(40.0, EPS)


func test_tower_inside_uses_relative_height_and_agl_floor() -> void:
	var flak: Dictionary = {"h_rel_min": 150, "h_rel_max": 1500}
	assert_bool(TowerHint.in_envelope(flak, 100.0, 100.0)).is_false()
	assert_bool(TowerHint.in_envelope(flak, 800.0, 800.0)).is_true()
	assert_bool(TowerHint.in_envelope(flak, 1600.0, 800.0)).is_false()
	var missile: Dictionary = {"h_rel_min": -300, "h_rel_max": 1500, "target_agl_min": 40}
	assert_bool(TowerHint.in_envelope(missile, 0.0, 30.0)).is_false()
	assert_bool(TowerHint.in_envelope(missile, 0.0, 50.0)).is_true()


func test_hints_for_hostile_towers_in_sensor_range_one_per_type_nearest_first() -> void:
	_v.add(20, &"flak_battery", 1, Vector3(0.0, R, -800.0))
	_v.add(21, &"flak_battery", 1, Vector3(0.0, R, -1200.0))       # same type, farther: no second hint
	_v.add(22, &"autocannon_turret", 1, Vector3(0.0, R, -1000.0))
	_v.add(23, &"flak_battery", 0, Vector3(0.0, R, -100.0))        # friendly
	_v.add(24, &"rail_lance", 1, Vector3(0.0, R, -3000.0))         # out of range
	var hints: Array[TowerHint] = TowerHint.from_view(_v, SHIP, 0, 300.0)
	assert_int(hints.size()).is_equal(2)
	assert_str(String(hints[0].def)).is_equal("flak_battery")
	assert_int(hints[0].tower).is_equal(20)
	assert_int(hints[0].rule).is_equal(TowerHint.Rule.BELOW)
	assert_bool(hints[0].inside).is_true()
	assert_str(String(hints[1].def)).is_equal("autocannon_turret")
	assert_int(hints[1].rule).is_equal(TowerHint.Rule.ABOVE)
	assert_bool(hints[1].inside).is_true()


func test_hint_keys_exist_in_the_locale() -> void:
	for k: StringName in [TowerHint.key(TowerHint.Rule.BELOW), TowerHint.key(TowerHint.Rule.ABOVE), &"hud.tower.flak_battery",
			&"hud.threat.lock", &"hud.threat.arrow"]:
		assert_str(tr(k)).is_not_equal(String(k))
