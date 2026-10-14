extends GdUnitTestSuite
## BUILD / CANCEL_BUILD through SimWorld (TA-19; 02 s6.3, R0 C3-08): sites, construction slots, payment when assembly
## starts, HP by progress, BUILD_DONE, cancel refunds (100 % queued / 75 % assembling) and S12 rights, deaths freeing
## the footprint, and S4 over Build / Economy / Construction / Production mid-flight.

const K := preload("res://test/unit/sim/economy_test_kit.gd")
const C := CommandResult.Code

var _solar: int
var _cfg: EconomyDef
var _sd: StructureDef


func before_test() -> void:
	_solar = K.def(&"solar_array")
	_cfg = WorldTestKit.content().economy
	_sd = WorldTestKit.content().structures[_solar - DefRanges.STRUCTURE_BASE]


func _place(w: SimWorld, metres: float, player: int = 0) -> int:
	return K.code(w, Command.build(player, _solar, K.cell_west(metres), 0))


# The site entity (F_BUILDING solar array) nearest `metres` west of the Core, -1 when none.
func _site_at(w: SimWorld, metres: float) -> int:
	var cell: int = K.cell_west(metres)
	for s: int in w.store().structures:
		if w.store().def_id[s] == _solar and w.store().anchor_cell[s] == cell:
			return s
	return -1


func test_build_command_makes_a_site_and_pays_when_assembly_starts() -> void:
	var w: SimWorld = K.solo_world()
	var ore0: int = K.ore(w)
	assert_int(_place(w, 250.0)).is_equal(C.ACCEPTED)
	assert_int(_site_at(w, 250.0)).is_equal(-1)                         # S1: queued, not placed yet
	var events: Array[SimEvent] = K.run(w, 1)
	var s: int = _site_at(w, 250.0)
	assert_int(s).is_greater_equal(0)
	assert_int(w.store().flags[s] & EntityStore.F_BUILDING).is_equal(EntityStore.F_BUILDING)
	assert_int(w.store().owner[s]).is_equal(0)
	assert_float(w.store().hp[s]).is_equal_approx(float(_sd.hp) * _cfg.site_hp_fraction, 0.01)   # 02 s6.3: hp x max(0.1, progress)
	assert_int(ore0 - K.ore(w)).is_equal(_sd.cost_ore)                  # a free slot: paid and started in the same tick
	assert_int(K.count_kind(events, SimEvent.Kind.BUILD_STARTED)).is_equal(1)
	assert_int(w.economy().construction.state[s]).is_equal(Construction.State.ASSEMBLING)
	assert_int(w.economy().build.grid.flags_of(w.store().anchor_cell[s]) & BuildGrid.OCCUPIED).is_equal(BuildGrid.OCCUPIED)


func test_rejected_placement_carries_the_reason_and_changes_nothing() -> void:
	var w: SimWorld = K.solo_world()
	var res: CommandResult = w.apply_command(Command.build(0, _solar, K.cell_west(250.0), 9))
	assert_int(res.code).is_equal(C.REJECTED_MALFORMED)
	var far: CommandResult = w.apply_command(Command.build(0, _solar, K.cell_west(1500.0), 0))     # seen (sensor 2,000 m) but outside every build radius (600 m)
	assert_int(far.code).is_equal(C.REJECTED_PLACEMENT)
	assert_int(far.reject).is_equal(Build.Reject.NO_RADIUS)
	var before: int = w.store().structures.size()
	var _ev: Array[SimEvent] = K.run(w, 3)
	assert_int(w.store().structures.size()).is_equal(before)


func test_two_slots_then_queued_sites_start_in_placement_order() -> void:
	var w: SimWorld = K.solo_world()
	for m: float in [250.0, 330.0, 410.0]:
		assert_int(_place(w, m)).is_equal(C.ACCEPTED)
	var _ev: Array[SimEvent] = K.run(w, 1)
	var cons: Construction = w.economy().construction
	assert_int(cons.state[_site_at(w, 250.0)]).is_equal(Construction.State.ASSEMBLING)
	assert_int(cons.state[_site_at(w, 330.0)]).is_equal(Construction.State.ASSEMBLING)
	assert_int(cons.state[_site_at(w, 410.0)]).is_equal(Construction.State.QUEUED)     # base 2 slots (no Outpost)
	assert_int(cons.slot_limit(0)).is_equal(_cfg.construction_slots_base)
	assert_int(cons.slot_limit(1)).is_equal(_cfg.construction_slots_base + 1)
	assert_int(cons.slot_limit(99)).is_equal(_cfg.construction_slots_max)
	assert_float(w.store().hp[_site_at(w, 410.0)]).is_equal_approx(float(_sd.hp) * _cfg.site_hp_fraction, 0.01)
	var hz: int = WorldTestKit.content().rules.tick_hz
	var done: Array[SimEvent] = K.run(w, int(_sd.build_time_s) * hz + 2)
	assert_int(K.count_kind(done, SimEvent.Kind.BUILD_DONE)).is_greater_equal(2)
	assert_int(cons.state[_site_at(w, 410.0)]).is_equal(Construction.State.ASSEMBLING)  # a slot freed: the queued one started
	assert_int(w.store().flags[_site_at(w, 250.0)] & EntityStore.F_BUILDING).is_equal(0)


func test_hp_follows_progress_and_completion_updates_power_and_caps() -> void:
	var w: SimWorld = K.solo_world()
	var e: Economy = w.economy().economy
	assert_int(_place(w, 250.0)).is_equal(C.ACCEPTED)
	var hz: int = WorldTestKit.content().rules.tick_hz
	var half: int = int(_sd.build_time_s) * hz / 2
	var _a: Array[SimEvent] = K.run(w, half)
	var s: int = _site_at(w, 250.0)
	assert_float(w.view().hp01(w.store().id_of(s))).is_equal_approx(0.5, 0.05)         # hp x progress
	assert_float(w.view().power_balance(0).x).is_equal(20.0)                           # unfinished: no output yet
	var done: Array[SimEvent] = K.run(w, half + 3)
	assert_int(K.count_kind(done, SimEvent.Kind.BUILD_DONE)).is_equal(1)
	assert_int(K.count_alert(done, AlertKind.Kind.BUILD_DONE)).is_equal(1)
	assert_float(w.view().hp01(w.store().id_of(s))).is_equal_approx(1.0, 0.001)
	assert_float(w.view().power_balance(0).x).is_greater(20.0)
	assert_float(e.power_ratio(0)).is_equal(1.0)
	assert_bool(w.economy().construction.is_site(s)).is_false()


func test_a_site_waits_for_ore_with_one_alert_and_starts_when_funds_arrive() -> void:
	var w: SimWorld = K.solo_world()
	var e: Economy = w.economy().economy
	for m: float in [250.0, 330.0, 410.0]:
		assert_int(_place(w, m)).is_equal(C.ACCEPTED)
	var _ev: Array[SimEvent] = K.run(w, 1)
	assert_bool(e.try_spend(0, K.ore(w), 0)).is_true()                  # the third site cannot pay once a slot frees
	var hz: int = WorldTestKit.content().rules.tick_hz
	var done: Array[SimEvent] = K.run(w, int(_sd.build_time_s) * hz + 5)
	assert_int(K.count_alert(done, AlertKind.Kind.WAITING_FOR_ORE)).is_equal(1)
	var third: int = _site_at(w, 410.0)
	assert_int(w.economy().construction.state[third]).is_equal(Construction.State.QUEUED)
	e.credit(0, _sd.cost_ore, 0)
	var _more: Array[SimEvent] = K.run(w, 2)
	assert_int(w.economy().construction.state[third]).is_equal(Construction.State.ASSEMBLING)


func test_cancel_refunds_75_percent_in_assembly_and_100_percent_queued() -> void:
	var w: SimWorld = K.solo_world()
	var e: Economy = w.economy().economy
	for m: float in [250.0, 330.0, 410.0]:
		assert_int(_place(w, m)).is_equal(C.ACCEPTED)
	var _ev: Array[SimEvent] = K.run(w, 1)
	var ore0: int = K.ore(w)
	var queued: int = w.store().id_of(_site_at(w, 410.0))
	var assembling: int = w.store().id_of(_site_at(w, 250.0))
	assert_int(K.code(w, CommandPayload.cancel_build(0, queued))).is_equal(C.ACCEPTED)
	var _e1: Array[SimEvent] = K.run(w, 1)
	assert_int(K.ore(w) - ore0).is_equal(0)                             # 100 % of 0 paid
	assert_bool(w.store().alive(queued)).is_false()
	assert_int(K.code(w, CommandPayload.cancel_build(0, assembling))).is_equal(C.ACCEPTED)
	var _e2: Array[SimEvent] = K.run(w, 1)
	assert_int(K.ore(w) - ore0).is_equal(floori(float(_sd.cost_ore) * _cfg.cancel_refund_assembly))
	assert_bool(w.store().alive(assembling)).is_false()
	assert_int(w.economy().build.spent_ore[0]).is_equal(_sd.cost_ore * 2 - floori(float(_sd.cost_ore) * _cfg.cancel_refund_assembly))
	assert_int(e.stockpile(0).x).is_equal(K.ore(w))
	# the footprints are free again
	assert_int(w.economy().build.can_place(0, _solar, K.cell_west(250.0), 0)).is_equal(Build.Reject.OK)
	assert_int(w.economy().build.can_place(0, _solar, K.cell_west(410.0), 0)).is_equal(Build.Reject.OK)


func test_s12_cancel_build_rights_on_real_sites() -> void:
	var w: SimWorld = WorldTestKit.world()                              # 0 human + 2 bot on team 0
	w.add_player(3, 0, &"", PlayerTable.KIND_HUMAN)
	assert_bool(w.spawn_start_kit(0, Vector3.RIGHT, Vector3.UP)).is_true()
	assert_int(K.code(w, Command.build(0, _solar, K.cell_west(250.0), 0))).is_equal(C.ACCEPTED)
	assert_int(K.code(w, Command.build(2, _solar, K.cell_west(330.0), 0))).is_equal(C.ACCEPTED)
	var _ev: Array[SimEvent] = K.run(w, 1)
	var mine: int = w.store().id_of(_site_at(w, 250.0))
	var bots: int = w.store().id_of(_site_at(w, 330.0))
	assert_int(K.code(w, CommandPayload.cancel_build(3, mine))).is_equal(C.REJECTED_NOT_OWNER)   # a connected human teammate
	assert_int(K.code(w, CommandPayload.cancel_build(1, mine))).is_equal(C.REJECTED_NOT_OWNER)   # an enemy
	assert_int(K.code(w, CommandPayload.cancel_build(3, bots))).is_equal(C.ACCEPTED)             # the placer is a bot
	w.remove_player(0)
	assert_int(K.code(w, CommandPayload.cancel_build(3, mine))).is_equal(C.ACCEPTED)             # the placer disconnected
	var _e2: Array[SimEvent] = K.run(w, 1)
	assert_bool(w.store().alive(mine)).is_false()
	assert_bool(w.store().alive(bots)).is_false()


func test_a_destroyed_site_frees_its_footprint_without_refund_or_wreck() -> void:
	var w: SimWorld = K.solo_world()
	assert_int(_place(w, 250.0)).is_equal(C.ACCEPTED)
	var _ev: Array[SimEvent] = K.run(w, 3)
	var s: int = _site_at(w, 250.0)
	var id: int = w.store().id_of(s)
	var ore0: int = K.ore(w)
	assert_int(K.code(w, CommandPayload.debug_set(0, id, CommandPayload.SET_KILL, 0.0))).is_equal(C.ACCEPTED)
	var events: Array[SimEvent] = K.run(w, 1)
	assert_bool(w.store().alive(id)).is_false()
	assert_int(K.ore(w)).is_equal(ore0)                                 # no refund for a destroyed site
	assert_int(w.store().wrecks.size()).is_equal(0)
	assert_int(K.count_kind(events, SimEvent.Kind.STRUCTURE_LOST)).is_equal(0)   # a site is not a lost structure
	assert_int(w.economy().build.can_place(0, _solar, K.cell_west(250.0), 0)).is_equal(Build.Reject.OK)
	assert_bool(w.economy().construction.is_site(s)).is_false()


func test_a_destroyed_factory_loses_its_queue_and_reports_structure_lost() -> void:
	var w: SimWorld = K.solo_world()
	var yard: int = w.store().id_of(K.find(w, &"shipyard"))
	assert_int(K.code(w, Command.produce(0, yard, K.def(&"dart"), 3))).is_equal(C.ACCEPTED)
	var _ev: Array[SimEvent] = K.run(w, 2)
	var cell: int = w.store().anchor_cell[EntityId.slot(yard)]
	assert_int(K.code(w, CommandPayload.debug_set(0, yard, CommandPayload.SET_KILL, 0.0))).is_equal(C.ACCEPTED)
	var events: Array[SimEvent] = K.run(w, 1)
	assert_int(K.count_kind(events, SimEvent.Kind.STRUCTURE_LOST)).is_equal(1)
	assert_int(w.economy().production.length(EntityId.slot(yard))).is_equal(0)
	assert_int(w.economy().build.grid.flags_of(cell) & BuildGrid.OCCUPIED).is_equal(0)
	assert_int(w.economy().economy.caps(0).x).is_equal(4500)            # still the Core + Refinery
	assert_int(K.code(w, Command.produce(0, yard, K.def(&"dart"), 1))).is_equal(C.REJECTED_DEAD)


func test_s4_round_trip_mid_construction_and_production_is_byte_identical() -> void:
	var a: SimWorld = K.solo_world()
	for m: float in [250.0, 330.0, 410.0]:
		assert_int(_place(a, m)).is_equal(C.ACCEPTED)
	var yard: int = a.store().id_of(K.find(a, &"shipyard"))
	assert_int(K.code(a, Command.produce(0, yard, K.def(&"dart"), 3))).is_equal(C.ACCEPTED)
	var _ev: Array[SimEvent] = K.run(a, 200)
	var bytes: PackedByteArray = a.serialize()
	var b: SimWorld = SimWorld.deserialize(bytes, WorldTestKit.content(), null)
	assert_object(b).is_not_null()
	assert_bool(b.serialize() == bytes).is_true()
	assert_int(b.economy().production.length(EntityId.slot(yard))).is_equal(3)
	assert_int(b.economy().construction.state[_site_at(b, 410.0)]).is_equal(Construction.State.QUEUED)
	assert_int(b.economy().build.spent_ore[0]).is_equal(a.economy().build.spent_ore[0])
	for _k: int in 10:
		var _x: Array[SimEvent] = K.run(a, 60)
		var _y: Array[SimEvent] = K.run(b, 60)
		assert_bool(SimSerialize.write_raw(a) == SimSerialize.write_raw(b)).is_true()
	assert_int(a.economy().production.length(EntityId.slot(yard))).is_less(3)             # something was produced meanwhile
	assert_bool(_site_at(a, 410.0) >= 0).is_true()


func test_s4_refuses_economy_state_of_the_wrong_shape() -> void:
	var w: SimWorld = K.solo_world()
	var hub: EconomyHub = w.economy()
	var buf: StreamPeerBuffer = StreamPeerBuffer.new()
	hub.production.write_state(buf)
	buf.seek(0)
	assert_bool(hub.production.read_state(buf)).is_true()
	var bad: Production = Production.new(w.store(), PlayerTable.new(), WorldDefs.new(WorldTestKit.content()), WorldTestKit.rules(),
		SimEvents.new(), hub.economy, null)
	var _r: int = bad.q_len.resize(3)                                  # an array of the wrong length
	var wrong: StreamPeerBuffer = StreamPeerBuffer.new()
	bad.write_state(wrong)
	wrong.seek(0)
	assert_bool(hub.production.read_state(wrong)).is_false()
	var cut: StreamPeerBuffer = StreamPeerBuffer.new()
	cut.data_array = PackedByteArray()
	assert_bool(hub.construction.read_state(cut)).is_false()
	assert_bool(hub.economy.read_state(cut)).is_false()
	assert_bool(hub.build.read_state(cut)).is_false()
