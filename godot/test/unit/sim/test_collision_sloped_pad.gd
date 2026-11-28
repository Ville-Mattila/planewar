extends GdUnitTestSuite
## BUG-6 (R0 B.33 A-158; 03 s6.4 "at the pad"): the landing volume of a friendly pad is offset <= pad_radius_m and
## -(r + 0.5) <= alt <= r + 0.5 + g, g = max(0, (Terrain.surface_point(ship direction) - pos[pad]) . up[pad]), on the
## SlopedMapKit fixture (pad_radius_m 10): a ship resting 8 m uphill on 5 and 15 degree ground stands more than
## r + 0.5 above the deck and still gets C_PAD; downhill it does too; the bound is tight; g = 0 on level ground (a ship
## r + 1 above the deck gets none); the lower bound is unchanged; and the terrain is sampled at most once per ship per
## tick, only for a ship inside a pad column above the plain band (counted by a Terrain subclass).

const SHIP_R: float = 6.0
const OFF: float = 8.0
const PAD_SPHERE: float = 15.0


## Counts height_at (every surface_point / normal_at goes through it).
class CountingTerrain extends Terrain:
	var calls: int = 0

	func height_at(dir: Vector3) -> float:
		calls += 1
		return super(dir)


var _t: CountingTerrain
var _kit: CollisionTestKit


func after() -> void:
	SlopedMapKit.remove_all()


## A friendly pad on the `slope_deg` ground at +X (fwd +Y = uphill) and a tail-down ship of radius SHIP_R. x = pad, y = ship.
func _scene(slope_deg: float, load_map: bool = true) -> Vector2i:
	_t = CountingTerrain.new()
	if load_map:
		SlopedMapKit.load_into(_t, slope_deg)
	_kit = CollisionTestKit.new("", _t)
	var pad: int = _kit.entity(EntityStore.K_STRUCTURE, _t.surface_point(Vector3.RIGHT), PAD_SPHERE, 0, CollisionTestKit.PAD_DEF)
	var s: int = _kit.entity(EntityStore.K_SHIP, _kit.store.pos[pad] + _kit.store.up[pad] * SHIP_R, SHIP_R, 0)
	_kit.store.fwd[s] = _kit.store.up[pad]
	return Vector2i(pad, s)


func _alt(ps: Vector2i) -> float:
	return (_kit.store.pos[ps.y] - _kit.store.pos[ps.x]).dot(_kit.store.up[ps.x])


## g of A-158 for the ship's current position.
func _g(ps: Vector2i) -> float:
	return maxf(0.0, (_t.surface_point(_kit.store.pos[ps.y]) - _kit.store.pos[ps.x]).dot(_kit.store.up[ps.x]))


## Rests the ship `off` metres along the pad's fwd, `above` metres over its own ground clearance r, descending 1 m/s.
func _rest(ps: Vector2i, off: float, above: float = 0.0) -> void:
	_kit.store.pos[ps.y] = SlopedMapKit.resting(_t, _kit.store, ps.x, off, SHIP_R + above)
	_kit.store.vel[ps.y] = -_kit.store.up[ps.x]


func _detect(t: int) -> int:
	_t.calls = 0
	_kit.detect(t)
	return _t.calls


func test_fixture_pad_radius_is_10_and_the_slope_is_the_plane() -> void:
	var _ps: Vector2i = _scene(0.0, false)
	assert_float(_kit.pad_radius).is_equal(10.0)
	for deg: float in [5.0, 15.0]:
		var ps: Vector2i = _scene(deg)
		_rest(ps, OFF)
		assert_float(_g(ps)).is_equal_approx(OFF * tan(deg_to_rad(deg)), 0.03)
		assert_float(_t.height_at(_kit.store.pos[ps.x])).is_equal_approx(0.0, 0.01)


func test_a_ship_resting_8_m_uphill_gets_a_pad_contact_on_5_and_15_degrees() -> void:
	for deg: float in [5.0, 15.0]:
		var ps: Vector2i = _scene(deg)
		_rest(ps, OFF)
		assert_float(_alt(ps)).override_failure_message("%.0f deg: above the A-31 band" % deg) \
			.is_greater(SHIP_R + 0.5)                                    # the old rule misses it (BUG-6)
		assert_float(_alt(ps)).is_less_equal(SHIP_R + 0.5 + _g(ps))
		assert_int(_detect(1)).is_equal(1)                                # one height_at for this ship
		assert_int(_kit.count(Collision.C_PAD)).is_equal(1)
		assert_int(_kit.count(Collision.C_RAM)).is_equal(0)
		var k: int = _kit.first(Collision.C_PAD)
		assert_int(_kit.collision.c_b[k]).is_equal(_kit.store.id_of(ps.x))
		assert_int(_kit.collision.c_class[k]).is_equal(Collision.L_SAFE)
		assert_float(_kit.collision.c_value[k]).is_equal_approx(OFF, 0.05)


func test_a_ship_resting_8_m_downhill_gets_a_pad_contact_without_a_sample() -> void:
	for deg: float in [5.0, 15.0]:
		var ps: Vector2i = _scene(deg)
		_rest(ps, -OFF)
		assert_float(_alt(ps)).is_less(SHIP_R)                            # the terrain is below the deck
		assert_float(_g(ps)).is_equal(0.0)
		assert_int(_detect(1)).is_equal(0)                                # inside the plain band: no sample
		assert_int(_kit.count(Collision.C_PAD)).is_equal(1)
		assert_int(_kit.collision.c_class[_kit.first(Collision.C_PAD)]).is_equal(Collision.L_SAFE)


func test_the_raised_bound_is_r_plus_half_plus_g_exactly() -> void:
	var ps: Vector2i = _scene(15.0)
	_rest(ps, OFF, 0.4)                                                   # 0.4 m above its rest: inside
	assert_float(_alt(ps) - _g(ps)).is_less(SHIP_R + 0.5)
	var _n: int = _detect(1)
	assert_int(_kit.count(Collision.C_PAD)).is_equal(1)
	_rest(ps, OFF, 0.6)                                                   # 0.6 m above: outside
	assert_float(_alt(ps) - _g(ps)).is_greater(SHIP_R + 0.5)
	_n = _detect(2)
	assert_int(_kit.count(Collision.C_PAD)).is_equal(0)
	assert_int(_kit.count(Collision.C_RAM)).is_equal(0)                   # still above the deck (A-109)


func test_level_ground_keeps_the_plain_band() -> void:
	for loaded: bool in [false, true]:                                    # the flat stub and a level bake
		var ps: Vector2i = _scene(0.0, loaded)
		for off: float in [0.0, OFF]:
			_rest(ps, off, 1.0)                                           # r + 1 above a level deck
			assert_float(_g(ps)).is_equal(0.0)
			var _n: int = _detect(1)
			assert_int(_kit.count(Collision.C_PAD)).is_equal(0)
			_rest(ps, off, 0.5 - 0.01)
			_n = _detect(2)
			assert_int(_kit.count(Collision.C_PAD)).is_equal(1)


func test_the_lower_bound_is_unchanged() -> void:
	var ps: Vector2i = _scene(15.0)
	var up: Vector3 = _kit.store.up[ps.x]
	_kit.store.pos[ps.y] = _kit.store.pos[ps.x] - up * (SHIP_R + 0.4)
	var _n: int = _detect(1)
	assert_int(_kit.count(Collision.C_PAD)).is_equal(1)
	_kit.store.pos[ps.y] = _kit.store.pos[ps.x] - up * (SHIP_R + 0.6)
	_n = _detect(2)
	assert_int(_kit.count(Collision.C_PAD)).is_equal(0)


func test_terrain_is_sampled_once_per_ship_only_in_a_pad_column_above_the_band() -> void:
	var ps: Vector2i = _scene(15.0)
	var st: EntityStore = _kit.store
	var up: Vector3 = st.up[ps.x]
	st.pos[ps.y] = st.pos[ps.x] + up * SHIP_R                             # in the plain band
	assert_int(_detect(1)).is_equal(0)
	st.pos[ps.y] = st.pos[ps.x] + up * (SHIP_R + 5.0)                     # in the column, above the band
	assert_int(_detect(2)).is_equal(1)
	assert_int(_kit.count(Collision.C_PAD)).is_equal(0)
	st.pos[ps.y] = st.pos[ps.x] + up * (SHIP_R + 5.0) + st.fwd[ps.x] * (_kit.pad_radius + 1.0)   # beside the column
	assert_int(_detect(3)).is_equal(0)
	st.pos[ps.y] = st.pos[ps.x] + up * (SHIP_R + 5.0)
	st.team[ps.y] = 1                                                     # an enemy pad: no landing volume
	assert_int(_detect(4)).is_equal(0)
	st.team[ps.y] = 0
	st.flags[ps.y] |= EntityStore.F_DOCKED                                # docked: no landing volume
	st.link[ps.y] = st.id_of(ps.x)
	assert_int(_detect(5)).is_equal(0)
	st.flags[ps.y] &= ~EntityStore.F_DOCKED
	st.link[ps.y] = 0
	# A second pad whose column overlaps the first: the ship above both bands still samples once.
	var pad2: int = _kit.entity(EntityStore.K_STRUCTURE, _t.surface_point(st.pos[ps.x] + st.fwd[ps.x] * 14.0),
		PAD_SPHERE, 0, CollisionTestKit.PAD_DEF)
	st.up[pad2] = up
	st.pos[ps.y] = st.pos[ps.x] + up * (SHIP_R + 5.0) + st.fwd[ps.x] * 7.0
	assert_int(_detect(6)).is_equal(1)
	var other: int = _kit.entity(EntityStore.K_SHIP, st.pos[ps.x] + up * (SHIP_R + 5.0) - st.fwd[ps.x] * 3.0, SHIP_R, 0)
	st.fwd[other] = up
	assert_int(_detect(7)).is_equal(2)                                    # one per such ship
