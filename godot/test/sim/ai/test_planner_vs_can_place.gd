extends GdUnitTestSuite
## AI-23: `BuildPlanner.resolve_site` agrees with the real `Build.can_place` (02 s6.2). On a real world with both start kits
## (cradle's slots 0 and 2, flat datum): every site the planner returns for the tokens and defs of the books is accepted by
## the sim's validator (the only other answers allowed are funds, prerequisites and caps: they are not geometry), and the
## sites it refuses for Outpost spacing and for an enemy build radius are refused by the sim for the same reason.

const R: float = Sphere.PLANET_RADIUS
const NOT_GEOMETRY: Array[int] = [Build.Reject.FUNDS, Build.Reject.SPEND_LOCKED, Build.Reject.PREREQ, Build.Reject.CAP]

var _w: SimWorld
var _p: BuildPlanner
var _m: MapSites
var _b: Build


func before_test() -> void:
	_w = Ai23Kit.world(9)
	_p = Ai23Kit.planner()
	_m = Ai23Kit.sites()
	_b = _w.economy().build
	_load()


func _load() -> void:
	_p.clear_view()
	var st: EntityStore = _w.store()
	for s: int in st.structures:
		var done: bool = (st.flags[s] & EntityStore.F_BUILDING) == 0
		if st.team[s] == 0:
			_p.add_own(st.def_id[s], st.pos[s].normalized(), done)
		else:
			_p.add_foe(st.def_id[s], st.pos[s].normalized())
	_p.enemy_hint = _m.slot_dir(2)


func _verdict(def: StringName, dir: Vector3) -> int:
	return _b.can_place(0, Ai23Kit.def(def), Sphere.cell_of(dir, Sphere.GRID_BUILD), 0)


func _dart_at(dir: Vector3) -> void:
	var _id: int = IntelKit.spawn(_w, &"dart", 0, 0, dir * (R + 120.0))
	_load()


# Walks up to `n` OK candidates of (def, token) and checks each against can_place.
func _agree(def: StringName, token: String, n: int, issued: int = 0, with_dart: bool = false) -> int:
	var tok: SiteToken = SiteToken.parse(token)
	var k: int = 0
	var seen: int = 0
	for _i: int in n:
		var d: Vector3 = _p.resolve_site(Ai23Kit.def(def), tok, 0, k, issued)
		if d == Vector3.ZERO:
			break
		if with_dart:
			_dart_at(d)
		var v: int = _verdict(def, d)
		assert_bool(v == Build.Reject.OK or NOT_GEOMETRY.has(v)).override_failure_message("%s @ %s candidate %d: can_place says %d" % [def, token, _p.last_k, v]).is_true()
		seen += 1
		k = _p.last_k + 1
	return seen


func test_core_and_approach_sites_are_accepted_by_the_sim() -> void:
	for def: StringName in [&"solar_array", &"pad", &"flak_battery", &"hangar", &"autocannon_turret", &"sensor_mast"]:
		assert_int(_agree(def, "core", 6)).override_failure_message("no candidates for %s" % def).is_greater(3)
	assert_int(_agree(&"autocannon_turret", "approach:nearest_enemy", 6)).is_greater(3)
	assert_int(_agree(&"sensor_mast", "approach:nearest_enemy", 6)).is_greater(3)


func test_a_refinery_pulled_inside_the_radius_is_accepted() -> void:
	assert_int(_agree(&"refinery", "ore_field:home_2", 6)).is_greater(2)


func test_the_pylon_chain_is_accepted_step_by_step() -> void:
	var tok: SiteToken = SiteToken.parse("toward:cold_trap:home")
	for issued: int in 3:
		var d: Vector3 = _p.resolve_site(Ai23Kit.def(&"relay_pylon"), tok, 0, 0, issued)
		assert_bool(d != Vector3.ZERO).override_failure_message("pylon %d has no site" % issued).is_true()
		assert_int(_verdict(&"relay_pylon", d)).is_equal(Build.Reject.OK)
		var id: int = _b.stamp(0, Ai23Kit.def(&"relay_pylon"), Sphere.cell_of(d, Sphere.GRID_BUILD), 0, true)
		assert_int(id).is_greater(0)
		_load()


func test_outpost_sites_and_the_extractor_on_the_trap_are_accepted() -> void:
	assert_int(_agree(&"outpost", "outpost_site:home_trap", 4, 0, true)).is_greater(2)
	assert_int(_agree(&"outpost", "contested_field", 4, 0, true)).is_greater(2)
	# a finished Outpost at the home-trap site covers the trap: the Extractor goes on its marked cell
	var site: Vector3 = _p.anchor(SiteToken.parse("outpost_site:home_trap"), 0, 0)
	assert_int(_b.stamp(0, Ai23Kit.def(&"outpost"), Sphere.cell_of(site, Sphere.GRID_BUILD), 0, true)).is_greater(0)
	_load()
	assert_int(_agree(&"ice_extractor", "cold_trap:home", 1)).is_equal(1)
	assert_int(_verdict(&"ice_extractor", _p.resolve_site(Ai23Kit.def(&"ice_extractor"), SiteToken.parse("cold_trap:home"), 0, 0, 0))).is_equal(Build.Reject.OK)


func test_sites_the_planner_refuses_are_refused_by_the_sim() -> void:
	var core: Vector3 = _m.slot_dir(0)
	# Outpost spacing: 500 m from the own Core (with a unit in place, so presence is not the reason)
	var near: Vector3 = Sphere.slerp_dir(core, _m.home_trap(0), 500.0 / (core.angle_to(_m.home_trap(0)) * R))
	_dart_at(near)
	assert_bool(_p.accepts(Ai23Kit.def(&"outpost"), near)).is_false()
	assert_int(_verdict(&"outpost", near)).is_equal(Build.Reject.SPACING)
	# enemy build radius: 500 m from the enemy Core, seen by a Dart of ours
	var foe_core: Vector3 = _m.slot_dir(2)
	var at_foe: Vector3 = Sphere.slerp_dir(foe_core, core, 500.0 / (foe_core.angle_to(core) * R))
	_dart_at(at_foe)
	assert_bool(_p.accepts(Ai23Kit.def(&"solar_array"), at_foe)).is_false()
	assert_int(_verdict(&"solar_array", at_foe)).is_equal(Build.Reject.ENEMY_RADIUS)
	# outside every friendly radius, no enemy: both refuse (NO_RADIUS)
	var far: Vector3 = Sphere.slerp_dir(core, _m.slot_dir(1), 900.0 / (core.angle_to(_m.slot_dir(1)) * R))
	_dart_at(far)
	assert_bool(_p.accepts(Ai23Kit.def(&"solar_array"), far)).is_false()
	assert_int(_verdict(&"solar_array", far)).is_equal(Build.Reject.NO_RADIUS)
