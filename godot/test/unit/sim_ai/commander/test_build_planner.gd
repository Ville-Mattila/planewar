extends GdUnitTestSuite
## AI-23 contract: `BuildPlanner.resolve_site` (05 s7.3): token -> anchor on the map's features and the slot layout, then the
## k-th placement candidate that passes the pre-check of 02 s6.2. Every structure: the ADR-05 radius rule (the centre inside
## a finished friendly build radius, outside every enemy one, clear of own footprints). Outposts: 02 AR-1 instead (no
## radius; >= 800 m from friendly and >= 1,500 m from enemy Cores / Outposts; outside enemy build radii).

var _p: BuildPlanner
var _m: MapSites
var _core0: Vector3


func before_test() -> void:
	_p = Ai23Kit.planner()
	_m = Ai23Kit.sites()
	_core0 = _m.slot_dir(0)
	_p.clear_view()
	_p.add_own(Ai23Kit.def(&"core"), _core0, true)
	_p.enemy_hint = _m.slot_dir(2)


func _gc(a: Vector3, b: Vector3) -> float:
	return a.angle_to(b) * Sphere.PLANET_RADIUS


func _site(def: StringName, tok: String, k: int = 0, issued: int = 0) -> Vector3:
	return _p.resolve_site(Ai23Kit.def(def), SiteToken.parse(tok), 0, k, issued)


func test_core_site_is_inside_the_core_radius_and_clear_of_it() -> void:
	var s: Vector3 = _site(&"solar_array", "core")
	assert_int(_p.status).is_equal(BuildPlanner.Status.OK)
	assert_float(s.length()).is_equal_approx(1.0, 1e-4)
	assert_float(_gc(s, _core0)).is_less_equal(600.0)
	assert_float(_gc(s, _core0)).is_greater(60.0)


func test_candidates_advance_with_k() -> void:
	var a: Vector3 = _site(&"solar_array", "core", 0)
	var k0: int = _p.last_k
	var b: Vector3 = _site(&"solar_array", "core", k0 + 1)
	assert_bool(a != b).is_true()
	assert_int(_p.last_k).is_greater(k0)


func test_resolution_is_deterministic() -> void:
	var a: Vector3 = _site(&"autocannon_turret", "approach:nearest_enemy")
	var b: Vector3 = _site(&"autocannon_turret", "approach:nearest_enemy")
	assert_vector(a).is_equal(b)


func test_own_footprints_are_avoided() -> void:
	var first: Vector3 = _site(&"solar_array", "core")
	_p.add_own(Ai23Kit.def(&"solar_array"), first, false)
	var second: Vector3 = _site(&"solar_array", "core")
	assert_bool(second != Vector3.ZERO).is_true()
	assert_float(_gc(first, second)).is_greater(2.0 * 4.0 * 9.2 * 0.5)   # two 4 x 4 cell footprints do not overlap


func test_approach_tower_sits_toward_the_enemy() -> void:
	var s: Vector3 = _site(&"autocannon_turret", "approach:nearest_enemy")
	assert_bool(s != Vector3.ZERO).is_true()
	assert_float(s.angle_to(_m.slot_dir(2))).is_less(_core0.angle_to(_m.slot_dir(2)))   # nearer the enemy than the Core is


func test_an_anchor_outside_every_radius_is_pulled_inside_the_nearest_one() -> void:
	# Home field 2 is ~1.3 km from the Core, outside its 600 m radius: the Refinery goes to the edge toward it.
	var f: Vector3 = _m.home_field(0, 2)
	var s: Vector3 = _site(&"refinery", "ore_field:home_2")
	assert_int(_p.status).is_equal(BuildPlanner.Status.OK)
	assert_float(_gc(s, _core0)).is_less_equal(600.0)
	assert_float(_gc(s, f)).is_less(_gc(_core0, f))


func test_a_node_structure_is_never_moved_off_its_node() -> void:
	# The Extractor must sit on the Cold Trap (ADR-05): out of radius it waits (BLOCKED), it is not projected.
	var s: Vector3 = _site(&"ice_extractor", "cold_trap:home")
	assert_vector(s).is_equal(Vector3.ZERO)
	assert_int(_p.status).is_equal(BuildPlanner.Status.BLOCKED)
	# the home-trap Outpost site covers the trap with its 400 m radius: then the Extractor goes on the trap's own cell
	var op: Vector3 = _p.anchor(SiteToken.parse("outpost_site:home_trap"), 0, 0)
	_p.add_own(Ai23Kit.def(&"outpost"), op, true)
	var s2: Vector3 = _site(&"ice_extractor", "cold_trap:home")
	assert_int(_p.status).is_equal(BuildPlanner.Status.OK)
	assert_int(Sphere.cell_of(s2, Sphere.GRID_BUILD)).is_equal(Sphere.cell_of(_m.home_trap(0), Sphere.GRID_BUILD))


func test_pylon_chain_stays_inside_the_supply_of_the_previous_one() -> void:
	var first: Vector3 = _site(&"relay_pylon", "toward:cold_trap:home", 0, 0)
	assert_bool(first != Vector3.ZERO).is_true()
	assert_float(_gc(first, _core0)).is_less_equal(600.0)
	_p.add_own(Ai23Kit.def(&"relay_pylon"), first, true)
	var second: Vector3 = _site(&"relay_pylon", "toward:cold_trap:home", 0, 1)
	assert_bool(second != Vector3.ZERO).is_true()
	assert_float(_gc(second, _core0)).is_greater(_gc(first, _core0))
	# no radius covers a fifth step: BLOCKED, never a site outside every friendly radius
	var far: Vector3 = _site(&"relay_pylon", "toward:cold_trap:home", 0, 5)
	assert_vector(far).is_equal(Vector3.ZERO)
	assert_int(_p.status).is_equal(BuildPlanner.Status.BLOCKED)


func test_unresolvable_tokens_are_unresolved_not_blocked() -> void:
	var tiny: BuildPlanner = Ai23Kit.planner(&"tiny_test")
	tiny.clear_view()
	tiny.add_own(Ai23Kit.def(&"core"), Ai23Kit.sites(&"tiny_test").slot_dir(0), true)
	var s: Vector3 = tiny.resolve_site(Ai23Kit.def(&"refinery"), SiteToken.parse("ore_field:home_2"), 0, 0, 0)
	assert_vector(s).is_equal(Vector3.ZERO)
	assert_int(tiny.status).is_equal(BuildPlanner.Status.UNRESOLVED)
	var c: Vector3 = tiny.resolve_site(Ai23Kit.def(&"outpost"), SiteToken.parse("contested_field"), 0, 0, 0)
	assert_vector(c).is_equal(Vector3.ZERO)
	assert_int(tiny.status).is_equal(BuildPlanner.Status.UNRESOLVED)


func test_enemy_build_radius_is_refused() -> void:
	var foe: Vector3 = Sphere.slerp_dir(_core0, _m.slot_dir(2), 700.0 / Sphere.PLANET_RADIUS / _core0.angle_to(_m.slot_dir(2)))
	_p.add_foe(Ai23Kit.def(&"core"), foe)
	var k: int = 0
	var seen: int = 0
	while k < 60:
		var s: Vector3 = _site(&"solar_array", "core", k)
		if s == Vector3.ZERO:
			break
		assert_float(_gc(s, foe)).is_greater(600.0)
		seen += 1
		k = _p.last_k + 1
	assert_int(seen).is_greater(0)


func test_outpost_site_honours_the_800_m_spacing() -> void:
	var s: Vector3 = _site(&"outpost", "outpost_site:home_trap")
	assert_int(_p.status).is_equal(BuildPlanner.Status.OK)
	assert_float(_gc(s, _core0)).is_greater_equal(800.0)
	assert_float(_gc(s, _m.home_trap(0))).is_less(400.0)   # the Cold Trap sits inside the new Outpost's build radius
	# a friendly Outpost within 800 m of the anchor leaves no candidate
	_p.add_own(Ai23Kit.def(&"outpost"), s, false)
	assert_vector(_site(&"outpost", "outpost_site:home_trap")).is_equal(Vector3.ZERO)
	assert_int(_p.status).is_equal(BuildPlanner.Status.BLOCKED)


func test_outpost_needs_no_build_radius() -> void:
	var s: Vector3 = _site(&"outpost", "contested_field")
	assert_int(_p.status).is_equal(BuildPlanner.Status.OK)
	assert_float(_gc(s, _core0)).is_greater(1000.0)   # far outside the Core's 600 m radius


func test_outpost_keeps_1500_m_from_enemy_cores_and_outposts() -> void:
	var anchor: Vector3 = _site(&"outpost", "contested_field")
	_p.add_foe(Ai23Kit.def(&"outpost"), Sphere.slerp_dir(anchor, _m.slot_dir(2), 1000.0 / Sphere.PLANET_RADIUS / anchor.angle_to(_m.slot_dir(2))))
	assert_vector(_site(&"outpost", "contested_field")).is_equal(Vector3.ZERO)
	assert_int(_p.status).is_equal(BuildPlanner.Status.BLOCKED)


func test_outpost_candidates_stay_inside_the_presence_radius_of_the_anchor() -> void:
	var anchor: Vector3 = _p.anchor(SiteToken.parse("outpost_site:home_trap"), 0, 0)
	var k: int = 0
	var seen: int = 0
	while k < 30:
		var s: Vector3 = _site(&"outpost", "outpost_site:home_trap", k)
		if s == Vector3.ZERO:
			break
		assert_float(_gc(s, anchor)).is_less(200.0)
		seen += 1
		k = _p.last_k + 1
	assert_int(seen).is_greater(3)
