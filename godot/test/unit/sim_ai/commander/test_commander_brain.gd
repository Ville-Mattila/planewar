extends GdUnitTestSuite
## AI-23 contract: `CommanderBrain` (the bot half of `AiBrain`; 05 s7.2-7.3, s7.8, s7.9): book choice by doctrine (weighted,
## AI RNG), a command cap per think by tier, orders only to units that are not POSSESSED and not under a human order lock,
## Outposts only with a unit in place, Perception-only knowledge, S4 bytes.

const HZ: int = Ai23Kit.HZ


func _world(doctrine: StringName = &"vanguard") -> SimWorld:
	return Ai23Kit.world(23, &"cradle", false, doctrine)


func _drive(w: SimWorld, cb: CommanderBrain, tier: int = 1, seed_value: int = 3) -> AiDriver:
	var d: AiDriver = Ai14Kit.driver(w, true, seed_value)
	d.set_brain(15, cb, true)
	d.schedule_bot(0, tier)
	return d


func test_the_book_is_chosen_by_doctrine_with_weights() -> void:
	var counts: Dictionary = {}
	for seed_value: int in 60:
		var w: SimWorld = _world(&"bulwark")
		var cb: CommanderBrain = Ai23Kit.commander()
		var _d: AiDriver = _drive(w, cb, 1, seed_value)
		var _e: Array[SimEvent] = Ai23Kit.run(w, 32)
		var id: StringName = cb.book_of(0).id
		counts[id] = int(counts.get(id, 0)) + 1
	assert_int(counts.size()).is_equal(2)
	assert_bool(counts.has(&"bulwark_standard") and counts.has(&"bulwark_greedy")).is_true()
	assert_int(int(counts[&"bulwark_standard"])).is_greater(int(counts[&"bulwark_greedy"]))   # weight 2 : 1


func test_the_pick_is_deterministic_for_a_seed() -> void:
	var picks: Array[StringName] = []
	for _i: int in 2:
		var w: SimWorld = _world()
		var cb: CommanderBrain = Ai23Kit.commander()
		var _d: AiDriver = _drive(w, cb, 1, 11)
		var _e: Array[SimEvent] = Ai23Kit.run(w, 32)
		picks.append(cb.book_of(0).id)
	assert_str(String(picks[0])).is_equal(String(picks[1]))


func test_a_doctrine_without_a_book_idles() -> void:
	var w: SimWorld = _world(&"foundry")
	var cb: CommanderBrain = Ai23Kit.commander(&"cradle", [Ai23Kit.book(&"vanguard_standard")])
	var d: AiDriver = _drive(w, cb)
	var _e: Array[SimEvent] = Ai23Kit.run(w, 120)
	assert_object(cb.book_of(0)).is_null()
	assert_int(cb.st_cmds).is_equal(0)
	assert_int(d.stats()["bot_thinks"]).is_greater(0)


func test_easy_bot_issues_at_most_two_commands_per_think() -> void:
	var w: SimWorld = _world()
	var cb: CommanderBrain = Ai23Kit.commander(&"cradle", [Ai23Kit.book(&"vanguard_rush")])
	var d: AiDriver = _drive(w, cb, 0)
	var most: int = 0
	for _t: int in 20 * HZ:
		w.step()
		var _e: Array[SimEvent] = w.drain_events()
		most = maxi(most, int(d.stats()["submits"]))
	assert_int(most).is_greater(0)
	assert_int(most).is_less_equal(2)


func test_an_order_skips_a_unit_a_human_ordered_and_a_possessed_one() -> void:
	var w: SimWorld = Ai23Kit.world(24, &"cradle", false)
	w.add_player(1, 0, &"vanguard", PlayerTable.KIND_HUMAN)
	var home: Vector3 = Ai23Kit.sites().slot_dir(0)
	var ids: PackedInt32Array = PackedInt32Array()
	for k: int in 3:
		var _a: bool = ids.push_back(IntelKit.spawn(w, &"dart", 0, 0, IntelKit.at(w, home, 100.0 + 60.0 * float(k), 100.0, 250.0)))
	var human_order: CommandResult = w.apply_command(Command.order(1, PackedInt32Array([ids[0]]), OrderSpec.make(OrderSpec.Kind.MOVE, 0, IntelKit.at(w, home, 2000.0, 0.0, 300.0))))
	assert_int(human_order.code).is_equal(CommandResult.Code.ACCEPTED)
	assert_int(w.apply_command(Command.possess(1, ids[1])).code).is_equal(CommandResult.Code.ACCEPTED)
	var book: OpeningBook = _single_order_book()
	var cb: CommanderBrain = Ai23Kit.commander(&"cradle", [book])
	var _d: AiDriver = _drive(w, cb)
	var _e: Array[SimEvent] = Ai23Kit.run(w, 4 * HZ)
	var v: SimView = w.view()
	assert_int(v.order_issuer(ids[0])).is_equal(1)   # the human's order stands
	assert_int(v.possessor(ids[1])).is_equal(1)
	assert_int(v.order_issuer(ids[2])).is_equal(0)   # the bot used the one free Dart


func _single_order_book() -> OpeningBook:
	var errs: Array[String] = []
	var b: OpeningBook = OpeningBook.compile({"id": "one_order", "doctrine": "vanguard",
		"steps": [{"do": "order", "kind": "move", "unit": "dart", "to": "contested_field"}]}, Ai23Kit.content(), errs)
	assert_object(b).is_not_null()
	return b


func test_brain_bytes_round_trip_and_refuse_junk() -> void:
	var w: SimWorld = _world()
	var cb: CommanderBrain = Ai23Kit.commander()
	var _d: AiDriver = _drive(w, cb)
	var _e: Array[SimEvent] = Ai23Kit.run(w, 90)
	var bytes: PackedByteArray = cb.serialize()
	var cb2: CommanderBrain = Ai23Kit.commander()
	assert_bool(cb2.deserialize(bytes)).is_true()
	assert_bool(cb2.serialize() == bytes).is_true()
	assert_bool(Ai23Kit.commander().deserialize(PackedByteArray([9, 9, 9]))).is_false()
	assert_int(AiDriver.FORMAT).is_equal(3)
