extends GdUnitTestSuite
## NET-62 NetOwnReads: the own-unit pilot-block and TEAM_STATE reads NetSimView delegates to (04 s3.7). The view and the helper agree;
## a pilot field is the SimView default for a unit that is not the own possessed one or before a pilot block has arrived.

const I: int = 7
const DEF: int = 2

var _roster: Roster
var _dec: SnapshotDecoder
var _view: NetSimView


func before_test() -> void:
	_roster = Roster.new()
	var _a: bool = _roster.add(I, 3, DEF, 1, 1)
	_dec = SnapshotDecoder.new(6.0, 30, 0, _roster)
	_view = NetSimView.new(_roster, _dec)
	_view.team_id = 1
	_view.slot_id = 0


func test_pilot_reads_default_without_pilot_block_or_possession() -> void:
	_dec.pilot.ammo = 9
	assert_int(NetOwnReads.ammo(_view, EntityId.make(I, 3))).is_equal(0)       # no pilot block yet, nothing possessed
	assert_int(NetOwnReads.unit_count(_view, 0)).is_equal(0)
	assert_vector(NetOwnReads.stockpile(_view, 1)).is_equal(Vector3.ZERO)


func test_team_state_reads_own_team_only() -> void:
	var w: TeamStateWire = TeamStateWire.new()
	w.tick = 5
	w.ore = 120
	w.ice = 30
	w.ore_cap = 500
	w.ice_cap = 250
	w.power_supply = 5
	w.power_demand = 10
	w.add_member(0, 4, 1)
	_view.set_team_state(w)
	assert_vector(NetOwnReads.stockpile(_view, 1)).is_equal(Vector3(120.0, 30.0, 0.5))
	assert_vector(NetOwnReads.stockpile(_view, 2)).is_equal(Vector3.ZERO)
	assert_vector(NetOwnReads.stockpile_cap(_view, 1)).is_equal(Vector2i(500, 250))
	assert_vector(NetOwnReads.power_balance(_view, 1)).is_equal(Vector2(5.0, 10.0))
	assert_vector(NetOwnReads.power_balance(_view, 0)).is_equal(Vector2.ZERO)
	assert_int(NetOwnReads.unit_count(_view, 0)).is_equal(4)
	assert_int(_view.unit_count(0)).is_equal(4)                                # the view delegates
	assert_vector(_view.stockpile(1)).is_equal(NetOwnReads.stockpile(_view, 1))
