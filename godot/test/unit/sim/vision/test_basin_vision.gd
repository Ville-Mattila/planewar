extends GdUnitTestSuite
## GD-53 (R0 B.33 A-159): basin vision is intended. On `cradle` slot 0 (floor ~335 m below the datum) the Core's team
## sees a ground unit only inside the ADR-05 horizon of the sensor's own radius, sqrt(2 |p_core| h) (h = the target's
## bounding radius, 7 m for the Siege Crawler: ~282 m), sees a ship 40 m above the floor at 600 m, and a finished Sensor
## Mast (deck_reveal_radius 1,200, ignores occlusion) sees the Crawler at 1,150 m. The flat datum gives the same answers.
## Tests only: no src change. Geometry of the horizon: Sphere.is_occluded_by_datum (A-10), Vision V1/V2.

const R: float = Sphere.PLANET_RADIUS
const SLOT0: Vector3 = Vector3(0.923879533, 0.382683432, 0.0)
const CRADLE: StringName = &"cradle"

var _w: SimWorld
var _core_r: float
var _n: Vector3
var _away: Vector3   # unit tangent at the Core pointing away from the kit's Refinery side


func _world(map_id: StringName) -> void:
	_w = WorldTestKit.world(7, null, map_id)
	_n = SLOT0.normalized()
	var f: Basis = Sphere.tangent_frame(_n)
	assert_bool(_w.spawn_start_kit(0, _n, _n + f.x * 0.1)).is_true()
	_away = -f.x
	var core: int = _find(&"core")
	_core_r = _w.store().pos[core].length()


func _find(id: StringName) -> int:
	var d: int = WorldTestKit.def_id(id)
	for s: int in _w.store().structures:
		if _w.store().def_id[s] == d and _w.store().owner[s] == 0:
			return s
	return -1


## Direction `metres` of arc from `from` toward `along` (a unit tangent at `from`).
func _step(from: Vector3, along: Vector3, metres: float) -> Vector3:
	var a: float = metres / R
	return (from * cos(a) + along * sin(a)).normalized()


## A point on the floor (terrain height at the direction) `lift` m up, `metres` of arc from the Core, bearing away.
func _floor_point(metres: float, lift: float) -> Vector3:
	var d: Vector3 = _step(_n, _away, metres)
	return d * (R + _w.terrain().height_at(d) + lift)


## A floor point beyond `from` (bearing away from the Core) whose straight distance to `from` is `dist` (+-1 m): the
## arc is corrected a few times, as the floor rises or falls along it.
func _mast_site(from: Vector3, dist: float) -> Vector3:
	var arc: float = 600.0 + dist
	var p: Vector3 = _floor_point(arc, 0.0)
	for _i: int in 6:
		arc += dist - from.distance_to(p)
		p = _floor_point(arc, 0.0)
	return p


func _enemy(def: StringName, p: Vector3) -> int:
	return VisionTestKit.put(_w, def, 1, p)


func _seen(id: int) -> bool:
	VisionTestKit.sense(_w)
	return VisionTestKit.visible(_w, 0, id)


## One scenario body shared by the basin and the flat datum (case 4).
func _check_cases() -> void:
	var rc: float = 7.0   # siege_crawler bounding_radius (ground_units.json)
	var horizon: float = sqrt(2.0 * _core_r * rc)
	assert_float(horizon).is_between(281.0 if _core_r < R - 1.0 else 289.0, 283.0 if _core_r < R - 1.0 else 291.0)
	var near: int = _enemy(&"siege_crawler", _floor_point(200.0, rc))
	var far: int = _enemy(&"siege_crawler", _floor_point(600.0, rc))
	var dart: int = _enemy(&"dart", _floor_point(600.0, 40.0))
	VisionTestKit.sense(_w)
	assert_bool(VisionTestKit.visible(_w, 0, near)).override_failure_message("crawler 200 m").is_true()
	assert_bool(VisionTestKit.visible(_w, 0, far)).override_failure_message("crawler 600 m").is_false()
	assert_bool(VisionTestKit.visible(_w, 0, dart)).override_failure_message("dart 600 m, 40 m up").is_true()
	# (3) a finished Sensor Mast 1,150 m beyond the Crawler's far side sees it through the datum
	var cp: Vector3 = _w.store().pos[EntityId.slot(far)]
	var mast_pos: Vector3 = _mast_site(cp, 1150.0)
	var mast_d: float = cp.distance_to(mast_pos)
	assert_float(mast_d).is_between(1149.0, 1151.0)
	assert_bool(Sphere.is_occluded_by_datum(mast_pos, cp)).is_true()
	var mast: int = VisionTestKit.put(_w, &"sensor_mast", 0, mast_pos)
	assert_bool(_w.store().owner[EntityId.slot(mast)] == 0).is_true()
	assert_bool(_seen(far)).override_failure_message("crawler 1,150 m from the Mast").is_true()
	assert_bool(VisionTestKit.visible(_w, 0, near)).is_true()


func test_basin_cradle_slot0() -> void:
	_world(CRADLE)
	assert_float(_core_r - R).is_between(-340.0, -330.0)
	_check_cases()


func test_flat_datum_gives_the_same_answers() -> void:
	_world(&"")
	assert_float(_core_r).is_equal_approx(R, 0.01)
	_check_cases()


func test_crawler_beyond_the_horizon_needs_the_mast() -> void:
	_world(CRADLE)
	var far: int = _enemy(&"siege_crawler", _floor_point(600.0, 7.0))
	assert_bool(_seen(far)).is_false()
	var _m: int = VisionTestKit.put(_w, &"sensor_mast", 0, _mast_site(_w.store().pos[EntityId.slot(far)], 1150.0))
	assert_bool(_seen(far)).is_true()
