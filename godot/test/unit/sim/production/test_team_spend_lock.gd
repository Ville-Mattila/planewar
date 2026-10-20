extends GdUnitTestSuite
## GD-17 acceptance (02 s6.4, R0 C3-08): in a 4-player team nobody spends past 800 Ore plus the Ore their own Harvesters and
## Core trickle delivered before 2:00, however large the shared pool; a PRODUCE start waits with one SPEND_LOCKED alert
## and begins as soon as the lock ends.

const K := preload("res://test/unit/sim/economy_test_kit.gd")
const C := CommandResult.Code


func _team_world() -> SimWorld:
	var w: SimWorld = SimWorld.new(WorldTestKit.content())
	var map: MapDef = MapDef.new()
	map.id = &""
	var res: Result = w.load_map(map, 7, WorldTestKit.rules())
	assert(res.ok, res.message)
	for p: int in 4:
		w.add_player(p, 0, &"", PlayerTable.KIND_HUMAN)
	w.add_player(4, 1, &"", PlayerTable.KIND_HUMAN)
	assert(w.spawn_start_kit(0, Vector3.RIGHT, Vector3.UP))
	return w


func test_a_team_member_cannot_spend_past_800_ore_before_two_minutes() -> void:
	var w: SimWorld = _team_world()
	var yard: int = w.store().id_of(K.find(w, &"shipyard"))
	var hz: int = WorldTestKit.content().rules.tick_hz
	var econ: EconomyDef = WorldTestKit.content().economy
	var lancer: int = K.def(&"lancer")
	var cost: int = WorldTestKit.content().ships[lancer - DefRanges.SHIP_BASE].cost_ore
	assert_int(K.ore(w)).is_greater_equal(4 * econ.start_ore)                # the pool alone could pay for everything
	assert_int(K.code(w, Command.produce(0, yard, lancer, 3))).is_equal(C.REJECTED_LOCKED)    # 900 > 800 in one go
	assert_int(K.code(w, Command.produce(0, yard, lancer, 2))).is_equal(C.ACCEPTED)
	assert_int(K.code(w, Command.produce(0, yard, lancer, 1))).is_equal(C.ACCEPTED)           # the ledger is settled only at a start
	var b: Build = w.economy().build
	var alerts: int = 0
	var peak: int = 0
	for _sec: int in int(econ.early_share_lock_s):                           # 2:00 in one-second slices
		alerts += K.count_alert(K.run(w, hz), AlertKind.Kind.SPEND_LOCKED)
		assert_int(b.spent_ore[0]).is_less_equal(econ.early_share_ore + b.delivered_ore[0])    # the lock invariant, every second
		peak = maxi(peak, b.spent_ore[0])
	assert_int(alerts).is_greater_equal(1)                                   # the third head waited (800 + income < 900 at first)
	assert_int(b.delivered_ore[0]).is_greater(0)                             # ... and only the player's own deliveries unlocked it
	assert_int(peak).is_greater_equal(2 * cost)
	var late: Array[SimEvent] = K.run(w, 2 * hz)
	assert_int(b.spent_ore[0]).is_equal(3 * cost)                            # after 2:00 the third started for sure
	assert_int(K.count_alert(late, AlertKind.Kind.SPEND_LOCKED)).is_equal(0)


func test_a_second_teammate_has_their_own_800() -> void:
	var w: SimWorld = _team_world()
	var yard: int = w.store().id_of(K.find(w, &"shipyard"))
	var lancer: int = K.def(&"lancer")
	assert_int(K.code(w, Command.produce(0, yard, lancer, 2))).is_equal(C.ACCEPTED)
	assert_int(K.code(w, Command.produce(1, yard, lancer, 2))).is_equal(C.ACCEPTED)           # player 1's 800 is untouched
	assert_int(w.economy().build.spent_ore[1]).is_equal(0)
