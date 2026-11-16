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
	assert_int(sp.size()).is_equal(3)                                    # the Core, the finished Outpost and the Outpost site (the sim counts sites); not the pad
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


# --- agreement with Build.can_place on a real SimWorld (construction sites count for SPACING) ---

const EK := preload("res://test/unit/sim/economy_test_kit.gd")


func _world_with_unit_at(metres: float) -> SimWorld:
	var w: SimWorld = EK.solo_world()
	var s: int = -1
	for l: PackedInt32Array in [w.store().ships, w.store().ground]:
		if s < 0 and not l.is_empty():
			s = l[0]
	assert_int(s).is_greater(-1)
	w.store().pos[s] = Sphere.cell_center_dir(EK.cell_west(metres), Sphere.GRID_BUILD) * (Sphere.PLANET_RADIUS + 50.0)
	w.store().flags[s] &= ~EntityStore.F_DOCKED
	return w


func _rings_of(w: SimWorld, kind: PlacementRing.Kind, source: int) -> int:
	var n: int = 0
	for r: PlacementRing in PlacementRings.rings(w.view(), 0, &"outpost"):
		if r.kind == kind and r.source == source:
			n += 1
	return n


func test_friendly_outpost_site_spacing_ring_agrees_with_can_place() -> void:
	var w: SimWorld = _world_with_unit_at(1000.0)
	var b: Build = w.economy().build
	var o: int = EK.def(&"outpost")
	assert_int(b.can_place(0, o, EK.cell_west(1000.0), 0)).is_equal(Build.Reject.OK)
	var site: int = b.stamp(0, o, EK.cell_west(1500.0), 0, false)       # an unfinished Outpost 500 m from the ghost
	assert_int(site).is_greater(0)
	assert_int(b.can_place(0, o, EK.cell_west(1000.0), 0)).is_equal(Build.Reject.SPACING)
	assert_int(_rings_of(w, PlacementRing.Kind.SPACING_FRIENDLY, site)).is_equal(1)
	assert_int(_rings_of(w, PlacementRing.Kind.BUILD, site)).is_equal(0)   # sites give no build radius


func test_enemy_outpost_site_spacing_ring_agrees_with_can_place() -> void:
	var w: SimWorld = _world_with_unit_at(1000.0)
	var b: Build = w.economy().build
	var o: int = EK.def(&"outpost")
	var site: int = b.stamp(1, o, EK.cell_west(1900.0), 0, false)       # an enemy site 900 m away, inside Core sensor range
	assert_int(site).is_greater(0)
	assert_int(b.can_place(0, o, EK.cell_west(1000.0), 0)).is_equal(Build.Reject.SPACING)
	var id: int = site
	assert_int(_rings_of(w, PlacementRing.Kind.SPACING_ENEMY, id)).is_equal(0)      # fog: not visible, no ring (the sim still says SPACING)
	w.store().visible_mask[EntityId.slot(id)] |= 1                                   # team 0 sees it
	assert_bool(w.view().visible_to(0, id)).is_true()
	assert_int(_rings_of(w, PlacementRing.Kind.SPACING_ENEMY, id)).is_equal(1)
