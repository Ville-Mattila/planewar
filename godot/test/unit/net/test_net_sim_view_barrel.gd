extends GdUnitTestSuite
## NET-61 (R0 B.31 A-152): NetSimView.barrel_elevation reads the replicated barrel byte. A live entity whose def has a
## barrel answers the decoded elevation (within one wire quantum of the sim) while the client holds a tier-A value, and
## 0.0 with field_unknown true otherwise (tier B / C, a KEYFRAME); an entity whose def has no barrel answers 0.0, known;
## a dead id 0.0. 'barrel_elevation' is no longer in NetUnknown.NEVER. NetDefs mirrors BarrelSlew's def tables. The
## LocalTransport case is test/net/test_barrel_replication.gd. The possessing client shows the replicated value.

const I: int = 7
const DART_I: int = 8

var _content: ContentSet
var _roster: Roster
var _dec: SnapshotDecoder
var _view: NetSimView
var _crawler_def: int = 0


func before_test() -> void:
	_content = WorldTestKit.content()
	_crawler_def = WorldTestKit.def_id(&"siege_crawler")
	_roster = Roster.new()
	var _a: bool = _roster.add(I, 3, _crawler_def, 0, 0)
	var _b: bool = _roster.add(DART_I, 2, WorldTestKit.def_id(&"dart"), 0, 0)
	_dec = SnapshotDecoder.new(6.0, 30, 0, _roster)
	_view = NetSimView.new(_roster, _dec)
	_view.bind(NetDefs.new(_content), null)


func _id() -> int:
	return EntityId.make(I, 3)


func _frame(t: int, barrel: int) -> void:
	var f: BaselineFrame = _dec.store.begin(t, 0)
	var pq: int = Codec.quantize_pos(Sphere.from_lat_lon(0.4, 1.1, Sphere.PLANET_RADIUS))
	f.set_full(I, t, pq, Codec.quantize_quat(Quaternion.IDENTITY), 0, 255, 0, 0, barrel)
	f.set_full(DART_I, t, pq, Codec.quantize_quat(Quaternion.IDENTITY), 0, 255, 0, 0)
	_dec.store.newest_tick = t
	_view.sample(float(t))


func test_net_defs_mirror_the_sim_barrel_tables() -> void:
	var nd: NetDefs = NetDefs.new(_content)
	var w: SimWorld = WorldTestKit.world()
	var bs: BarrelSlew = (w.view() as LocalSimView).barrel
	var n: int = 0
	for k: int in _content.ground_units.size():
		var d: int = DefRanges.GROUND_BASE + k
		assert_bool(nd.barrel_def[d] != 0).is_equal(bs.has_barrel(d))
		n += 1 if bs.has_barrel(d) else 0
	assert_int(n).is_greater(0)
	assert_float(nd.barrel_lo[_crawler_def]).is_equal(0.0)
	assert_float(nd.barrel_hi[_crawler_def]).is_equal_approx(deg_to_rad(45.0), 1e-12)
	assert_int(nd.barrel_def[WorldTestKit.def_id(&"harvester")]).is_equal(0)
	assert_int(nd.barrel_def[WorldTestKit.def_id(&"dart")]).is_equal(0)
	assert_int(nd.barrel_byte(_crawler_def, deg_to_rad(17.0))).is_equal(96)
	assert_int(nd.barrel_byte(WorldTestKit.def_id(&"dart"), 0.3)).is_equal(-1)
	assert_int(nd.barrel_byte(-5, 0.3)).is_equal(-1)


func test_tier_a_value_is_decoded_and_known() -> void:
	assert_bool(NetUnknown.NEVER.has("barrel_elevation")).is_false()
	_frame(10, BaselineFrame.BARREL_KNOWN | 96)
	var want: float = deg_to_rad(45.0) * 96.0 / 255.0
	assert_float(_view.barrel_elevation(_id())).is_equal_approx(want, 1e-9)
	assert_float(absf(_view.barrel_elevation(_id()) - deg_to_rad(17.0))).is_less_equal(deg_to_rad(45.0) / 255.0)
	assert_bool(_view.field_unknown(_id(), &"barrel_elevation")).is_false()


func test_no_tier_a_value_is_zero_and_unknown() -> void:
	_frame(10, 0)                                            # last record in section B / C, or a KEYFRAME
	assert_float(_view.barrel_elevation(_id())).is_equal(0.0)
	assert_bool(_view.field_unknown(_id(), &"barrel_elevation")).is_true()


func test_no_barrel_def_is_zero_and_known_and_dead_is_zero() -> void:
	_frame(10, BaselineFrame.BARREL_KNOWN | 96)
	var dart: int = EntityId.make(DART_I, 2)
	assert_float(_view.barrel_elevation(dart)).is_equal(0.0)
	assert_bool(_view.field_unknown(dart, &"barrel_elevation")).is_false()
	var dead: int = EntityId.make(I, 4)
	assert_float(_view.barrel_elevation(dead)).is_equal(0.0)
	assert_float(_view.barrel_elevation(0)).is_equal(0.0)
