extends GdUnitTestSuite
## R0 A-87 (03 s6.1): a ship is never RAM-tested against an own-team structure whose def has `launch_pad: true` (the
## Shipyard), docked or not, at the socket or at the sphere edge; every other own-team structure and every enemy
## structure still rams it.

const R: float = Sphere.PLANET_RADIUS
const STRUCT_RADIUS: float = 46.0
const SHIP_RADIUS: float = 6.0

var _kit: CollisionTestKit


func before_test() -> void:
	_kit = CollisionTestKit.new()


func _at(alt: float, east: float = 0.0) -> Vector3:
	return Vector3(R + alt, east, 0.0)


# A structure of `def` and team `st` at the origin and a team-0 ship at `ship_pos`.
func _scene(def: int, st: int, ship_pos: Vector3) -> int:
	var _o: int = _kit.entity(EntityStore.K_STRUCTURE, _at(0.0), STRUCT_RADIUS, st, def)
	return _kit.entity(EntityStore.K_SHIP, ship_pos, SHIP_RADIUS, 0)


func test_own_ship_at_the_socket_is_not_rammed_by_its_shipyard() -> void:
	var _s: int = _scene(CollisionTestKit.LAUNCH_DEF, 0, _at(SHIP_RADIUS))   # parked on the pad, first LAUNCHED tick: not DOCKED
	_kit.detect(1)
	assert_int(_kit.count(Collision.C_RAM)).is_equal(0)


func test_own_ship_at_the_sphere_edge_is_not_rammed_by_its_shipyard() -> void:
	var _s: int = _scene(CollisionTestKit.LAUNCH_DEF, 0, _at(STRUCT_RADIUS + SHIP_RADIUS - 1.0))   # still inside the sphere by 1 m
	_kit.detect(1)
	assert_int(_kit.count(Collision.C_RAM)).is_equal(0)


func test_the_same_ship_is_rammed_by_an_own_refinery() -> void:
	var _s: int = _scene(CollisionTestKit.PLAIN_DEF, 0, _at(SHIP_RADIUS))
	_kit.detect(1)
	assert_int(_kit.count(Collision.C_RAM)).is_equal(1)


func test_an_enemy_ship_inside_the_shipyard_sphere_is_rammed() -> void:
	var s: int = _scene(CollisionTestKit.LAUNCH_DEF, 0, _at(SHIP_RADIUS))
	_kit.store.team[s] = 1
	_kit.detect(1)
	assert_int(_kit.count(Collision.C_RAM)).is_equal(1)


func test_a_ship_outside_the_sphere_is_not_rammed() -> void:
	var s: int = _scene(CollisionTestKit.PLAIN_DEF, 0, _at(STRUCT_RADIUS + SHIP_RADIUS + 1.0))
	_kit.detect(1)
	assert_int(_kit.count(Collision.C_RAM)).is_equal(0)
	assert_int(s).is_greater(0)
