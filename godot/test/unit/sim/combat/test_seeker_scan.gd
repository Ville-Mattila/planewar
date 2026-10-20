extends GdUnitTestSuite
## SeekerScan (A-73 extraction from WeaponFire, GD-13): the boresight score and the nearest-to-boresight pick.

const R: float = Sphere.PLANET_RADIUS


func _pos(east: float) -> Vector3:
	return Vector3(R + 100.0, east, 0.0)


func test_score_is_the_boresight_cosine_for_a_hostile_in_range() -> void:
	var pos: PackedVector3Array = [_pos(0.0), _pos(500.0), _pos(-500.0)]
	var tm: PackedByteArray = [0, 1, 1]
	var fwd: Vector3 = Vector3.BACK.cross(Vector3.RIGHT)             # along +Y (east)
	assert_float(SeekerScan.score(pos, tm, 0, fwd, 1, 1000.0 * 1000.0, -1.0)).is_equal_approx(1.0, 0.001)
	assert_float(SeekerScan.score(pos, tm, 0, fwd, 2, 1000.0 * 1000.0, -1.0)).is_equal_approx(-1.0, 0.001)
	assert_float(SeekerScan.score(pos, tm, 0, fwd, 2, 1000.0 * 1000.0, 0.5)).is_equal(-2.0)      # outside the cone
	assert_float(SeekerScan.score(pos, tm, 0, fwd, 1, 100.0 * 100.0, -1.0)).is_equal(-2.0)        # out of range


func test_score_rejects_friendly_neutral_and_self_position() -> void:
	var pos: PackedVector3Array = [_pos(0.0), _pos(300.0), _pos(300.0), _pos(0.0)]
	var tm: PackedByteArray = [0, 0, EntityStore.NONE_U8, 1]
	assert_float(SeekerScan.score(pos, tm, 0, Vector3.UP, 1, 1.0e6, -1.0)).is_equal(-2.0)         # friendly
	assert_float(SeekerScan.score(pos, tm, 0, Vector3.UP, 2, 1.0e6, -1.0)).is_equal(-2.0)         # neutral
	assert_float(SeekerScan.score(pos, tm, 0, Vector3.UP, 3, 1.0e6, -1.0)).is_equal(-2.0)         # same point
