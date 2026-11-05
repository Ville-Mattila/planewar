extends GdUnitTestSuite
## UX-22 against the sim's own validation (UX-20 review lesson): for every unit and structure tile, over a real
## SimWorld and its LocalSimView, the tile state agrees with what CommandValidator answers to the command the tile issues.
## AVAILABLE tiles are never rejected for tech / cap / cost / lock; every other state matches its reject code.

const K := preload("res://test/unit/sim/economy_test_kit.gd")
const C := CommandResult.Code
const S := DrawerMath.State

var _units: Array[StringName] = []
var _structs: Array[StringName] = []


func before_test() -> void:
	var r: Result = ContentDB.load_all()
	assert_bool(r.ok).is_true()
	_units = DrawerCatalog.unit_ids()
	_structs = DrawerCatalog.structure_ids()


func _lock_left(w: SimWorld, player: int) -> int:
	# needs sim: LocalSimView.player_state fills early_spend_left_ore (still -1); read the same ledger the validator reads.
	var b: Build = w.economy().build
	var econ: EconomyDef = WorldTestKit.content().economy
	if float(w.tick()) >= econ.early_share_lock_s * float(WorldTestKit.content().rules.tick_hz):
		return -1
	return econ.early_share_ore + b.delivered_ore[player] - b.spent_ore[player]


func _unit_code(w: SimWorld, id: StringName) -> int:
	var f: int = DrawerModel.best_factory(w.view(), 0, id, Vector3.ZERO)
	var factory: int = f if f >= 0 else w.store().id_of(K.find(w, DrawerCatalog.factory_of(id)))
	return K.code(w, Command.produce(0, factory, K.def(id), 1))


func test_unit_tiles_agree_with_the_produce_validator() -> void:
	for id: StringName in _units:
		var w: SimWorld = K.solo_world()
		var t: TileInfo = DrawerModel.tile(w.view(), DrawerContextKit.from_view(w.view(), 0, _lock_left(w, 0)), id)
		var code: int = _unit_code(w, id)
		if t.state == S.AVAILABLE:
			assert_int(code).is_equal(C.ACCEPTED)
		else:
			assert_int(t.state).is_equal(S.LOCKED)                                 # start kit: Bomber needs a Hangar, Crawler an Outpost
			assert_int(code).is_equal(C.REJECTED_PREREQ)
	var w2: SimWorld = K.solo_world()
	assert_int(DrawerModel.tile(w2.view(), DrawerContextKit.from_view(w2.view(), 0, -1), &"dart").state).is_equal(S.AVAILABLE)
	assert_int(DrawerModel.tile(w2.view(), DrawerContextKit.from_view(w2.view(), 0, -1), &"bomber").state).is_equal(S.LOCKED)
	assert_int(DrawerModel.tile(w2.view(), DrawerContextKit.from_view(w2.view(), 0, -1), &"siege_crawler").state).is_equal(S.LOCKED)


func test_unaffordable_unit_tiles_are_rejected_for_cost() -> void:
	for id: StringName in _units:
		var w: SimWorld = K.solo_world()
		assert_bool(w.economy().economy.try_spend(0, 790, 0)).is_true()           # 10 Ore left
		var t: TileInfo = DrawerModel.tile(w.view(), DrawerContextKit.from_view(w.view(), 0, -1), id)
		var code: int = _unit_code(w, id)
		if t.state == S.UNAFFORDABLE:
			assert_int(code).is_equal(C.REJECTED_COST)
		else:
			assert_int(t.state).is_equal(S.LOCKED)
			assert_int(code).is_equal(C.REJECTED_PREREQ)                            # tech is checked before cost


func test_unit_cap_agrees_with_rejected_cap() -> void:
	var r: MatchRules = WorldTestKit.rules()
	r.caps.units = 1                                                               # the start kit's Harvester fills it
	var w: SimWorld = K.solo_world(true, 7, r)
	var t: TileInfo = DrawerModel.tile(w.view(), DrawerContextKit.from_view(w.view(), 0, -1), &"dart")
	assert_int(t.state).is_equal(S.CAP_REACHED)
	assert_int(_unit_code(w, &"dart")).is_equal(C.REJECTED_CAP)


func test_full_queue_agrees_with_rejected_cap() -> void:
	var w: SimWorld = K.solo_world()
	var yard: int = w.store().id_of(K.find(w, &"shipyard"))
	assert_int(K.code(w, Command.produce(0, yard, K.def(&"scout"), 5))).is_equal(C.ACCEPTED)
	w.step()
	var t: TileInfo = DrawerModel.tile(w.view(), DrawerContextKit.from_view(w.view(), 0, -1), &"dart")
	assert_int(t.state).is_equal(S.CAP_REACHED)
	assert_int(t.queued).is_equal(0)
	assert_int(DrawerModel.tile(w.view(), DrawerContextKit.from_view(w.view(), 0, -1), &"scout").queued).is_equal(DrawerMath.queue_max())   # the queue list is head first, paid head included
	assert_int(K.code(w, Command.produce(0, yard, K.def(&"dart"), 1))).is_equal(C.REJECTED_CAP)
	assert_int(DrawerModel.tile(w.view(), DrawerContextKit.from_view(w.view(), 0, -1), &"harvester").state).is_equal(S.AVAILABLE)   # the Vehicle Bay queue is empty


func test_spend_locked_agrees_with_rejected_locked() -> void:
	var w: SimWorld = K.solo_world()
	w.add_player(2, 0, &"", PlayerTable.KIND_HUMAN)                                # a second player on team 0 switches the lock on
	w.economy().build.spent_ore[0] = 700                                           # 100 Ore of the 800 share left
	var left: int = _lock_left(w, 0)
	assert_int(left).is_equal(100)
	var dart: TileInfo = DrawerModel.tile(w.view(), DrawerContextKit.from_view(w.view(), 0, left), &"dart")
	assert_int(dart.state).is_equal(S.SPEND_LOCKED)
	assert_int(_unit_code(w, &"dart")).is_equal(C.REJECTED_LOCKED)
	var scout: TileInfo = DrawerModel.tile(w.view(), DrawerContextKit.from_view(w.view(), 0, left), &"scout")
	assert_int(scout.state).is_equal(S.AVAILABLE)                                  # 60 Ore fits
	assert_int(_unit_code(w, &"scout")).is_equal(C.ACCEPTED)
	for id: StringName in _structs:
		var t: TileInfo = DrawerModel.tile(w.view(), DrawerContextKit.from_view(w.view(), 0, left), id)
		if t.state == S.SPEND_LOCKED:
			assert_bool(DrawerMath.lock_blocks(left, t.cost.x)).is_true()
			assert_bool(w.economy().build.lock_blocks(0, t.cost.x)).is_true()      # the ledger the validator reads (geometry rejects first)
		else:
			assert_bool(w.economy().build.lock_blocks(0, t.cost.x)).is_equal(DrawerMath.lock_blocks(left, t.cost.x))


func test_structure_tiles_agree_with_can_place() -> void:
	for id: StringName in _structs:
		var w: SimWorld = K.solo_world()
		var t: TileInfo = DrawerModel.tile(w.view(), DrawerContextKit.from_view(w.view(), 0, -1), id)
		var res: CommandResult = w.apply_command(Command.build(0, K.def(id), K.cell_west(600.0), 0))
		var gate: bool = res.code == C.REJECTED_COST or res.code == C.REJECTED_CAP \
				or (res.code == C.REJECTED_PLACEMENT and res.reject in [Build.Reject.PREREQ, Build.Reject.CAP, Build.Reject.FUNDS, Build.Reject.SPEND_LOCKED])
		match t.state:
			S.AVAILABLE:
				assert_bool(gate).is_false()                                       # only geometry may still reject (UX-21)
			S.LOCKED:
				if res.code == C.REJECTED_COST:
					assert_vector(t.short).is_not_equal(Vector2i.ZERO)                # the validator checks cost before tech; the tile shows tech
				else:
					assert_int(res.code).is_equal(C.REJECTED_PLACEMENT)
					assert_int(res.reject).is_equal(Build.Reject.PREREQ)
			S.UNAFFORDABLE:
				assert_int(res.code).is_equal(C.REJECTED_COST)
			S.CAP_REACHED:
				assert_bool(res.code == C.REJECTED_CAP or res.reject == Build.Reject.CAP).is_true()
			_:
				assert_bool(false).is_true()


func test_structure_cap_per_player_agrees() -> void:
	var w: SimWorld = K.solo_world()
	var _a: int = WorldTestKit.spawn(w, &"vehicle_bay", 0, 0, WorldTestKit.at(0.0, 2000.0))   # the start kit has one: max_per_player 2
	w.step()
	var t: TileInfo = DrawerModel.tile(w.view(), DrawerContextKit.from_view(w.view(), 0, -1), &"vehicle_bay")
	assert_int(t.state).is_equal(S.CAP_REACHED)
	var res: CommandResult = w.apply_command(Command.build(0, K.def(&"vehicle_bay"), K.cell_west(600.0), 0))
	assert_int(res.reject).is_equal(Build.Reject.CAP)


func test_unit_tiles_use_the_factory_the_validator_accepts() -> void:
	var w: SimWorld = K.solo_world()
	for id: StringName in _units:
		var fs: PackedInt32Array = DrawerModel.factories(w.view(), 0, id)
		if DrawerModel.tile(w.view(), DrawerContextKit.from_view(w.view(), 0, -1), id).state == S.AVAILABLE:
			assert_int(fs.size()).is_greater(0)
			for f: int in fs:
				assert_int(K.code(w, Command.produce(0, f, K.def(id), 1))).is_equal(C.ACCEPTED)
				break
