extends GdUnitTestSuite
## GD-23 (sim/relay/MODULE.md R7-R9; 02 s5.3, 05 C18): what a capture changes. The holder's team and owner are what every reader
## sees (`SimView.team` / `owner`, which AI-22 Perception re-reads every refresh), the Relay Station's sensors follow the holder,
## the pad serves the holder, and a mid-capture S4 restore runs on byte for byte. The solar Plateau is loaded from the map.

const K: GDScript = preload("res://test/unit/sim/relay/relay_test_kit.gd")

var _w: SimWorld
var _relay: int


func before_test() -> void:
	_w = K.world()
	_relay = K.relay(_w)


func _run(w: SimWorld, seconds: float) -> void:
	for _i: int in K.seconds(seconds):
		w.step()


func test_the_view_reports_the_new_team_and_owner_after_a_capture() -> void:
	assert_int(_w.view().team(_relay)).is_equal(K.NEUTRAL)
	var _h: int = K.docked(_w, &"hauler", 1, _relay)
	_run(_w, 21.0)
	assert_int(_w.view().team(_relay)).is_equal(1)
	assert_int(_w.view().owner(_relay)).is_equal(1)


func test_the_losing_team_drops_its_sensor_cover_and_the_winner_gains_it() -> void:
	var sd: StructureDef = WorldTestKit.content().structures[WorldTestKit.def_id(&"relay_station") - DefRanges.STRUCTURE_BASE]
	var foe: int = DockingTestKit.direct(_w, &"dart", 1, 1, WorldTestKit.at(100.0, sd.sensor_radius - 500.0))   # inside the Relay's reach
	var h0: int = K.docked(_w, &"hauler", 0, _relay)
	_run(_w, 21.0)
	assert_int(K.team_of(_w, _relay)).is_equal(0)
	assert_bool(_w.view().visible_ids(0).has(foe)).is_true()
	DockingTestKit.clear(_w, h0)
	var _h1: int = K.docked(_w, &"hauler", 1, _relay)
	_run(_w, 22.0)
	assert_int(K.team_of(_w, _relay)).is_equal(1)
	assert_bool(_w.view().visible_ids(0).has(foe)).is_false()


func test_a_captured_pad_serves_the_new_holder() -> void:
	var h: int = K.docked(_w, &"hauler", 1, _relay)
	_w.economy().economy.credit(1, 0, 1000)
	_run(_w, 21.0)
	assert_int(K.team_of(_w, _relay)).is_equal(1)
	_w.store().fuel[EntityId.slot(h)] = 0.0
	var hd: ShipDef = DockingTestKit.ship_def(&"hauler")
	_run(_w, hd.refuel_time_s + 2.0)
	assert_float(_w.store().fuel[EntityId.slot(h)]).is_greater_equal(hd.fuel_s - 0.01)


func test_a_mid_capture_restore_continues_byte_for_byte() -> void:
	var _h: int = K.docked(_w, &"hauler", 0, _relay)
	_run(_w, 8.0)
	var w2: SimWorld = SimWorld.deserialize(_w.serialize(), WorldTestKit.content(), null)
	assert_object(w2).is_not_null()
	for _i: int in K.seconds(14.0):
		_w.step()
		w2.step()
	assert_int(K.team_of(_w, _relay)).is_equal(0)
	assert_int(K.team_of(w2, _relay)).is_equal(0)
	assert_array(SimSerialize.write_raw(w2)).is_equal(SimSerialize.write_raw(_w))


func test_the_plateau_centres_load_from_the_map_features() -> void:
	var c: PackedVector3Array = SunPath.load_plateaus("res://content/maps/tiny_test")
	assert_int(c.size()).is_equal(1)
	assert_vector(c[0]).is_equal_approx(Vector3.BACK, Vector3.ONE * 0.0001)
	assert_int(SunPath.load_plateaus("res://content/maps/none").size()).is_equal(0)


func test_a_solar_array_on_the_loaded_plateau_gets_the_multiplier() -> void:
	var w: SimWorld = WorldTestKit.world(7, null, &"tiny_test")
	var e: Economy = w.economy().economy
	var r: float = WorldTestKit.R
	var _a: int = WorldTestKit.spawn(w, &"shipyard", 0, 0, Vector3(0.0, r, 0.0))
	var _a2: int = WorldTestKit.spawn(w, &"shipyard", 0, 0, Vector3(0.0, r, 200.0))
	var _b: int = WorldTestKit.spawn(w, &"solar_array", 0, 0, Vector3(0.0, 0.0, r))      # the north pole: inside the Plateau
	var mult: float = WorldTestKit.content().economy.solar_plateau_mult
	assert_float(e.power_ratio(0)).is_equal_approx((20.0 + 12.0 * mult) / 40.0, 0.0001)
