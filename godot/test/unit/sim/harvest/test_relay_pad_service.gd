extends GdUnitTestSuite
## GD-14 I8 (sim/harvest/MODULE.md; 02 s5.3, 02 s2.3): the Relay Station's pad services the ships of the team that holds it
## at the normal service costs (a Hauler's refuel: `refuel_ice` Ice) and not the ships of the other team. The capture that
## hands the Relay Station its team is GD-23; here the holder is set by the test.

var _w: SimWorld


func before_test() -> void:
	_w = WorldTestKit.world()
	var _e: Array[SimEvent] = _w.drain_events()


func _docked_hauler(team: int, owner: int, pad: int) -> int:
	var id: int = DockingTestKit.direct(_w, &"hauler", owner, team, DockingTestKit.far(_w))
	DockingTestKit.dock(_w, id, pad)
	_w.store().fuel[EntityId.slot(id)] = 0.0
	return id


func test_the_relay_station_is_a_service_pad_in_the_def() -> void:
	var sd: StructureDef = WorldTestKit.content().structures[WorldTestKit.def_id(&"relay_station") - DefRanges.STRUCTURE_BASE]
	assert_int(sd.pads).is_equal(1)
	assert_float(sd.pad_radius_m).is_equal(12.0)
	assert_bool(sd.invulnerable).is_true()


func test_a_held_relay_station_refuels_a_friendly_hauler_for_the_normal_ice_cost() -> void:
	var relay: int = DockingTestKit.pad(_w, &"relay_station", 0, 0)
	var hd: ShipDef = DockingTestKit.ship_def(&"hauler")
	var id: int = _docked_hauler(0, 0, relay)
	_w.economy().economy.credit(0, 0, 1000)
	var ice0: int = DockingTestKit.pool(_w, 0).y
	var served: bool = false
	for _i: int in int((hd.refuel_time_s + 2.0) * float(WorldTestKit.content().rules.tick_hz)):
		_w.step()
		served = served or not DockingTestKit.of_kind(_w.drain_events(), SimEvent.Kind.SERVICED).is_empty()
	assert_bool(served).is_true()
	assert_float(_w.store().fuel[EntityId.slot(id)]).is_greater_equal(hd.fuel_s - 0.01)
	assert_int(ice0 - DockingTestKit.pool(_w, 0).y).is_equal(hd.refuel_ice)


func test_a_ship_of_the_other_team_is_not_served_by_the_held_relay_station() -> void:
	var relay: int = DockingTestKit.pad(_w, &"relay_station", 0, 0)
	var id: int = _docked_hauler(1, 1, relay)
	_w.economy().economy.credit(1, 0, 1000)
	for _i: int in 600:
		_w.step()
	assert_float(_w.store().fuel[EntityId.slot(id)]).is_equal(0.0)
