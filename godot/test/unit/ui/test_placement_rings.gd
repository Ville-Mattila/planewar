extends GdUnitTestSuite
## PlacementRings (UX-21; docs/06 s7.3): Outpost presence and spacing rings, build radius rings for every other def.

const K := PlacementRing.Kind

var _v: PlaceMockView


class PlaceMockView extends DrawerMockView:
	var seen: Dictionary = {}

	func visible_to(_team: int, id: int) -> bool:
		return seen.get(id, false)


func before_test() -> void:
	var r: Result = ContentDB.load_all()
	assert_bool(r.ok).is_true()
	_v = PlaceMockView.new()
	_v.add_structure(1, &"core", 0, 0, Vector3(6000.0, 0.0, 0.0))
	_v.add_structure(2, &"outpost", 0, 0, Vector3(6000.0, 900.0, 0.0))
	_v.add_structure(3, &"outpost", 0, 0, Vector3(6000.0, 2000.0, 0.0), DrawerMockView.BUILDING)
	_v.add_structure(4, &"core", 1, 1, Vector3(6000.0, 0.0, 4000.0))
	_v.add_structure(5, &"pad", 0, 0, Vector3(6000.0, 0.0, 100.0))


func _of(rs: Array[PlacementRing], kind: PlacementRing.Kind) -> Array[PlacementRing]:
	var out: Array[PlacementRing] = []
	for r: PlacementRing in rs:
		if r.kind == kind:
			out.append(r)
	return out


func test_outpost_shows_presence_and_friendly_spacing_not_build_radius() -> void:
	var rs: Array[PlacementRing] = PlacementRings.rings(_v, 0, &"outpost")
	assert_int(_of(rs, K.BUILD).size()).is_equal(0)                      # no radius requirement
	var pres: Array[PlacementRing] = _of(rs, K.PRESENCE)
	assert_int(pres.size()).is_equal(1)
	assert_float(pres[0].radius_m).is_equal(ContentDB.economy.outpost_presence_radius_m)
	assert_bool(pres[0].follows_ghost).is_true()
	var sp: Array[PlacementRing] = _of(rs, K.SPACING_FRIENDLY)
	assert_int(sp.size()).is_equal(2)                                    # the Core and the finished Outpost; not the site, not the pad
	for r: PlacementRing in sp:
		assert_float(r.radius_m).is_equal(ContentDB.economy.outpost_spacing_friendly_m)
		assert_bool(r.follows_ghost).is_false()
	assert_object(sp[0].color()).is_equal(UiTokens.UI_WARN)
	assert_object(pres[0].color()).is_not_equal(sp[0].color())


func test_enemy_spacing_ring_only_when_the_enemy_is_known() -> void:
	assert_int(_of(PlacementRings.rings(_v, 0, &"outpost"), K.SPACING_ENEMY).size()).is_equal(0)   # fog: nothing leaks
	_v.seen[4] = true
	var e: Array[PlacementRing] = _of(PlacementRings.rings(_v, 0, &"outpost"), K.SPACING_ENEMY)
	assert_int(e.size()).is_equal(1)
	assert_float(e[0].radius_m).is_equal(ContentDB.economy.outpost_spacing_enemy_m)
	assert_object(e[0].center).is_equal(Vector3(6000.0, 0.0, 4000.0))
	assert_int(e[0].source).is_equal(4)
	assert_object(e[0].color()).is_equal(UiTokens.UI_DANGER)


func test_other_defs_show_build_radius_of_finished_own_structures() -> void:
	var rs: Array[PlacementRing] = PlacementRings.rings(_v, 0, &"relay_pylon")
	assert_int(_of(rs, K.PRESENCE).size()).is_equal(0)
	assert_int(_of(rs, K.SPACING_FRIENDLY).size()).is_equal(0)
	var b: Array[PlacementRing] = _of(rs, K.BUILD)
	var radii: PackedFloat32Array = PackedFloat32Array()
	for r: PlacementRing in b:
		var _a: bool = radii.append(r.radius_m)
	assert_int(radii.size()).is_equal(2)                                 # Core 600, Outpost 400; the site and the pad (no radius) are absent
	assert_bool(radii.has(600.0)).is_true()
	assert_bool(radii.has(400.0)).is_true()
	assert_object(b[0].color()).is_equal(UiTokens.UI_OK)


func test_visible_enemy_build_radius_is_red_and_hidden_enemy_is_not_drawn() -> void:
	assert_int(_of(PlacementRings.rings(_v, 0, &"relay_pylon"), K.ENEMY_BUILD).size()).is_equal(0)
	_v.seen[4] = true
	var e: Array[PlacementRing] = _of(PlacementRings.rings(_v, 0, &"relay_pylon"), K.ENEMY_BUILD)
	assert_int(e.size()).is_equal(1)
	assert_float(e[0].radius_m).is_equal(600.0)


func test_unknown_def_or_null_view_gives_no_rings() -> void:
	assert_int(PlacementRings.rings(null, 0, &"relay_pylon").size()).is_equal(0)
	assert_int(PlacementRings.rings(_v, 0, &"nope").size()).is_equal(0)
