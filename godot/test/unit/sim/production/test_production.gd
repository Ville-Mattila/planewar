extends GdUnitTestSuite
## Production queues (TA-19; 02 s6.4, R0 C3-08): queue cap 5 (S13), pay at start, build time over power speed,
## CAP_REACHED blocking, owner-only cancel (S12) with the 75 % refund, the early share lock (REJECTED_LOCKED until 2:00).

const K := preload("res://test/unit/sim/economy_test_kit.gd")
const C := CommandResult.Code


func _yard_id(w: SimWorld) -> int:
	return w.store().id_of(K.find(w, &"shipyard"))


func test_queue_holds_five_and_the_sixth_is_rejected() -> void:
	var w: SimWorld = K.solo_world()
	var yard: int = _yard_id(w)
	var dart: int = K.def(&"dart")
	var qmax: int = WorldTestKit.content().economy.queue_max
	assert_int(qmax).is_equal(5)
	assert_int(K.code(w, Command.produce(0, yard, dart, 3))).is_equal(C.ACCEPTED)
	w.step()
	assert_int(K.code(w, Command.produce(0, yard, dart, 3))).is_equal(C.REJECTED_CAP)     # 3 + 3 > 5
	assert_int(K.code(w, Command.produce(0, yard, dart, 2))).is_equal(C.ACCEPTED)
	w.step()
	assert_int(w.view().production_queue(yard).size()).is_equal(5)
	assert_int(K.code(w, Command.produce(0, yard, dart, 1))).is_equal(C.REJECTED_CAP)
	assert_int(K.code(w, Command.produce(0, yard, dart, 6))).is_equal(C.REJECTED_MALFORMED)
	var p: Production = w.economy().production
	assert_int(p.length(EntityId.slot(yard))).is_less_equal(p.queue_max())                # S13


func test_s13_queue_never_exceeds_max_even_for_commands_in_one_tick() -> void:
	var w: SimWorld = K.solo_world()
	var yard: int = _yard_id(w)
	for count: int in [2, 2, 2, 1]:
		assert_int(K.code(w, Command.produce(0, yard, K.def(&"scout"), count))).is_equal(C.ACCEPTED)   # the validator sees the settled queue only
	w.step()
	assert_int(w.view().production_queue(yard).size()).is_equal(5)                          # the step 1 re-check refused the third (4 + 2 > 5)
	assert_int(w.economy().production.length(EntityId.slot(yard))).is_equal(5)


func test_payment_at_start_and_unit_after_build_time() -> void:
	var w: SimWorld = K.solo_world()
	var yard: int = _yard_id(w)
	var dart_def: ShipDef = WorldTestKit.content().ships[K.def(&"dart") - DefRanges.SHIP_BASE]
	var hz: int = WorldTestKit.content().rules.tick_hz
	assert_int(K.code(w, Command.produce(0, yard, K.def(&"dart"), 2))).is_equal(C.ACCEPTED)
	var ore0: int = K.ore(w)
	var events: Array[SimEvent] = K.run(w, 1)
	assert_int(ore0 - K.ore(w)).is_equal(dart_def.cost_ore)             # head paid when it starts; the second waits unpaid
	assert_float(w.view().production_progress01(yard)).is_greater(0.0)
	var build_ticks: int = int(dart_def.build_time_s) * hz
	var spawned_at: int = -1
	for _i: int in build_ticks + 10:
		events = K.run(w, 1)
		if K.count_kind(events, SimEvent.Kind.SPAWN) > 0:
			spawned_at = w.tick()
			break
	assert_int(spawned_at).is_between(build_ticks - 3, build_ticks + 3)
	assert_int(w.store().ships.size()).is_equal(1)
	assert_int(w.store().owner[w.store().ships[0]]).is_equal(0)         # the queuer's unit
	var _next: Array[SimEvent] = K.run(w, 1)
	assert_int(w.view().production_queue(yard).size()).is_equal(1)      # the second dart is now the head
	assert_int(w.economy().build.spent_ore[0]).is_equal(dart_def.cost_ore * 2)          # ... and paid


func test_low_power_slows_production_to_the_ratio() -> void:
	var w: SimWorld = K.solo_world()
	var yard: int = _yard_id(w)
	var hz: int = WorldTestKit.content().rules.tick_hz
	var scout: ShipDef = WorldTestKit.content().ships[K.def(&"scout") - DefRanges.SHIP_BASE]
	var _pw: int = WorldTestKit.spawn(w, &"shipyard", 0, 0, WorldTestKit.at(0.0, 3000.0))
	var _pw2: int = WorldTestKit.spawn(w, &"shipyard", 0, 0, WorldTestKit.at(0.0, 3400.0))    # demand 40 vs supply 20: ratio 0.5
	assert_float(w.economy().economy.power_ratio(0)).is_equal_approx(0.5, 0.001)
	assert_int(K.code(w, Command.produce(0, yard, K.def(&"scout"), 1))).is_equal(C.ACCEPTED)
	var full: int = int(scout.build_time_s) * hz
	var early: Array[SimEvent] = K.run(w, full + 10)
	assert_int(K.count_kind(early, SimEvent.Kind.SPAWN)).is_equal(0)    # a full-speed scout would be out by now
	var late: Array[SimEvent] = K.run(w, full + 10)
	assert_int(K.count_kind(late, SimEvent.Kind.SPAWN)).is_equal(1)     # at ratio 0.5 it takes twice as long


func test_cap_reached_blocks_the_head_until_a_slot_frees() -> void:
	var r: MatchRules = WorldTestKit.rules()
	r.caps.units = 2                                                    # the start kit's Harvester holds one
	var w: SimWorld = K.solo_world(true, 7, r)
	var yard: int = _yard_id(w)
	assert_int(K.code(w, Command.produce(0, yard, K.def(&"dart"), 1))).is_equal(C.ACCEPTED)
	assert_int(K.code(w, CommandPayload.debug_spawn(0, K.def(&"dart"), 0, 0, WorldTestKit.at(500.0), Vector3.ZERO, Vector3.UP))).is_equal(C.ACCEPTED)
	var ore0: int = K.ore(w)
	var events: Array[SimEvent] = K.run(w, 5)
	assert_int(K.count_kind(events, SimEvent.Kind.CAP_REACHED)).is_equal(1)   # once per block, not per tick
	assert_int(K.count_alert(events, AlertKind.Kind.PRODUCTION_BLOCKED_CAP)).is_equal(1)
	var e: SimEvent = null
	for ev: SimEvent in events:
		if ev.kind == SimEvent.Kind.CAP_REACHED:
			e = ev
	assert_int(e.a).is_equal(0)
	assert_int(e.b).is_equal(Production.CAP_UNITS)                      # 04 s3.6: b is the cap kind, not a def
	assert_bool(K.ore(w) >= ore0).is_true()                             # nothing was paid while blocked
	assert_int(w.view().production_queue(yard).size()).is_equal(1)
	var unit: int = w.store().id_of(w.store().ships[0])
	assert_int(K.code(w, CommandPayload.debug_set(0, unit, CommandPayload.SET_KILL, 0.0))).is_equal(C.ACCEPTED)
	var _more: Array[SimEvent] = K.run(w, 5)
	assert_bool(K.ore(w) < ore0).is_true()                              # the slot freed: the head started and paid
	assert_float(w.view().production_progress01(yard)).is_greater(0.0)


func test_waiting_for_ore_alerts_once_and_starts_when_funds_arrive() -> void:
	var w: SimWorld = K.solo_world()
	var yard: int = _yard_id(w)
	var dart: ShipDef = WorldTestKit.content().ships[K.def(&"dart") - DefRanges.SHIP_BASE]
	assert_int(K.code(w, Command.produce(0, yard, K.def(&"dart"), 2))).is_equal(C.ACCEPTED)
	var _first: Array[SimEvent] = K.run(w, 1)                           # the head is paid and starts
	assert_bool(w.economy().economy.try_spend(0, K.ore(w), 0)).is_true()     # the pool is gone before the second item starts
	var events: Array[SimEvent] = K.run(w, int(dart.build_time_s) * WorldTestKit.content().rules.tick_hz + 30)
	assert_int(K.count_kind(events, SimEvent.Kind.SPAWN)).is_equal(1)   # the first dart came out
	assert_int(K.count_alert(events, AlertKind.Kind.WAITING_FOR_ORE)).is_equal(1)    # ... and the second waits, reported once
	assert_float(w.view().production_progress01(yard)).is_equal(0.0)
	w.economy().economy.credit(0, 500, 0)
	var _ev: Array[SimEvent] = K.run(w, 3)
	assert_float(w.view().production_progress01(yard)).is_greater(0.0)


func test_s12_cancel_rights_follow_the_queuer() -> void:
	var w: SimWorld = WorldTestKit.world()                              # 0 human, 2 bot (team 0), 1 enemy
	w.add_player(3, 0, &"", PlayerTable.KIND_HUMAN)
	var yard: int = WorldTestKit.spawn(w, &"shipyard", 0, 0, WorldTestKit.at(0.0, 400.0))
	var dart: int = K.def(&"dart")
	assert_int(K.code(w, Command.produce(0, yard, dart, 1))).is_equal(C.ACCEPTED)
	assert_int(K.code(w, Command.produce(3, yard, dart, 1))).is_equal(C.ACCEPTED)
	assert_int(K.code(w, Command.produce(2, yard, dart, 1))).is_equal(C.ACCEPTED)
	w.step()
	assert_int(w.view().production_queue(yard).size()).is_equal(3)
	assert_int(K.code(w, CommandPayload.cancel_produce(3, yard, 0))).is_equal(C.REJECTED_NOT_OWNER)   # item 0 is player 0's
	assert_int(K.code(w, CommandPayload.cancel_produce(1, yard, 0))).is_equal(C.REJECTED_NOT_OWNER)   # an enemy
	assert_int(K.code(w, CommandPayload.cancel_produce(0, yard, 2))).is_equal(C.ACCEPTED)             # the bot's item: any teammate
	assert_int(K.code(w, CommandPayload.cancel_produce(0, yard, 1))).is_equal(C.REJECTED_NOT_OWNER)   # a connected human's
	w.remove_player(3)
	assert_int(K.code(w, CommandPayload.cancel_produce(0, yard, 1))).is_equal(C.ACCEPTED)             # now disconnected
	assert_int(K.code(w, CommandPayload.cancel_produce(0, yard, 5))).is_equal(C.REJECTED_DEAD)        # no such item
	w.step()
	assert_int(w.view().production_queue(yard).size()).is_equal(1)
	assert_int(w.economy().production.queuer(EntityId.slot(yard), 0)).is_equal(0)


func test_cancel_refunds_75_percent_of_a_started_head_and_nothing_for_queued() -> void:
	var w: SimWorld = K.solo_world()
	var yard: int = _yard_id(w)
	var dart: ShipDef = WorldTestKit.content().ships[K.def(&"dart") - DefRanges.SHIP_BASE]
	var refund: float = WorldTestKit.content().economy.cancel_refund_assembly
	assert_int(K.code(w, Command.produce(0, yard, K.def(&"dart"), 2))).is_equal(C.ACCEPTED)
	var ore0: int = K.ore(w)
	var _ev: Array[SimEvent] = K.run(w, 1)
	assert_int(ore0 - K.ore(w)).is_equal(dart.cost_ore)
	var b: Build = w.economy().build
	assert_int(b.spent_ore[0]).is_equal(dart.cost_ore)
	assert_int(K.code(w, CommandPayload.cancel_produce(0, yard, 1))).is_equal(C.ACCEPTED)   # the queued, unpaid second item
	var _e2: Array[SimEvent] = K.run(w, 1)
	assert_int(ore0 - K.ore(w)).is_equal(dart.cost_ore)                  # a queued item refunds its payment: none was made
	assert_int(K.code(w, CommandPayload.cancel_produce(0, yard, 0))).is_equal(C.ACCEPTED)   # the paid head
	var _e3: Array[SimEvent] = K.run(w, 1)
	var back: int = floori(float(dart.cost_ore) * refund)
	assert_int(ore0 - K.ore(w)).is_equal(dart.cost_ore - back)
	assert_int(b.spent_ore[0]).is_equal(dart.cost_ore - back)            # the lock ledger follows the refund
	assert_int(w.view().production_queue(yard).size()).is_equal(0)
	assert_float(w.view().production_progress01(yard)).is_equal(0.0)


func test_early_share_lock_rejects_produce_until_two_minutes() -> void:
	var w: SimWorld = WorldTestKit.world()                              # team 0: players 0 and 2, so the lock applies
	var yard: int = WorldTestKit.spawn(w, &"shipyard", 0, 0, WorldTestKit.at(0.0, 400.0))
	var lancer: int = K.def(&"lancer")
	var econ: EconomyDef = WorldTestKit.content().economy
	var hz: int = WorldTestKit.content().rules.tick_hz
	var n: int = 3                                                      # 3 x 300 = 900 > early_share_ore 800
	assert_int(WorldTestKit.content().ships[lancer - DefRanges.SHIP_BASE].cost_ore * n).is_greater(econ.early_share_ore)
	assert_int(K.code(w, Command.produce(0, yard, lancer, n))).is_equal(C.REJECTED_LOCKED)
	assert_int(K.code(w, Command.produce(0, yard, lancer, 2))).is_equal(C.ACCEPTED)      # 600 <= 800
	var target: int = int(econ.early_share_lock_s) * hz
	while w.tick() < target - 1:
		w.step()
	assert_int(K.code(w, Command.produce(0, yard, lancer, n))).is_equal(C.REJECTED_LOCKED)   # still 1 tick before 2:00
	w.step()
	w.step()
	assert_int(K.code(w, Command.produce(0, yard, lancer, n))).is_equal(C.ACCEPTED)         # lock over
