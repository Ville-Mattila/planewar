extends GdUnitTestSuite
## OrderResolver (UX-20; docs/06 s7.2, R0 C2-06): the resolver table, filtered through the real order_rules.json
## (order_rules.json wins over 06 s7.2 where they differ: Harvester return/guard, Bomber escort).

const T := OrderResolver.Target
const P: Vector3 = Vector3(0.0, 6001.0, 0.0)
const SHIPS: Array[StringName] = [&"dart", &"lancer", &"bomber", &"scout", &"hauler"]
const GROUND: Array[StringName] = [&"harvester", &"siege_crawler"]

var _rules: OrderClassRules
var _sim_rules: OrderRules


func before_test() -> void:
	var r: Result = ContentDB.load_all()
	assert_bool(r.ok).is_true()
	_rules = OrderClassRules.from_raw(ContentDB.order_rules.raw)
	_sim_rules = OrderRules.from_def(ContentDB.order_rules)
	_sim_rules.bind(ContentDB.ships, ContentDB.ground_units, ContentDB.structures)


func _res(t: OrderResolver.Target, classes: Array[StringName], queue: bool = false) -> Array[Command]:
	var ids: PackedInt32Array = PackedInt32Array()
	for i: int in classes.size():
		ids.append(i + 1)
	return OrderResolver.resolve(0, _rules, t, 77, P, ids, classes, queue)


func _kind(c: Command) -> int:
	return c.payload.decode_u8(0)


func _mode(c: Command) -> int:
	return c.payload.decode_u8(2)


func _count(c: Command) -> int:
	return c.payload.decode_u8(3)


func _one(t: OrderResolver.Target, cls: StringName, queue: bool = false) -> Array[Command]:
	var a: Array[StringName] = [cls]
	return _res(t, a, queue)


func test_class_rules_follow_order_rules_json() -> void:
	assert_bool(_rules.allows(OrderSpec.Kind.ESCORT, &"dart")).is_true()
	assert_bool(_rules.allows(OrderSpec.Kind.ESCORT, &"bomber")).is_false()
	assert_bool(_rules.allows(OrderSpec.Kind.RETURN, &"harvester")).is_false()
	assert_bool(_rules.allows(OrderSpec.Kind.GUARD, &"harvester")).is_false()
	assert_bool(_rules.allows(OrderSpec.Kind.GUARD, &"tower")).is_true()
	assert_bool(_rules.allows(OrderSpec.Kind.MOVE, &"tower")).is_false()
	assert_bool(_rules.allows(OrderSpec.Kind.SUPPLY_DROP, &"core")).is_false()   # kind not enabled
	assert_bool(_rules.allows(OrderSpec.Kind.MOVE, &"no_such_class")).is_false()


func test_enemy_attackers_attack() -> void:
	var cs: Array[Command] = _one(T.ENEMY, &"dart")
	assert_int(cs.size()).is_equal(1)
	assert_int(cs[0].kind).is_equal(Command.Kind.ORDER)
	assert_int(_kind(cs[0])).is_equal(OrderSpec.Kind.ATTACK)


func test_enemy_unarmed_only_moves() -> void:
	assert_int(_kind(_one(T.ENEMY, &"hauler")[0])).is_equal(OrderSpec.Kind.MOVE)
	assert_int(_kind(_one(T.ENEMY, &"scout")[0])).is_equal(OrderSpec.Kind.MOVE)
	assert_int(_kind(_one(T.ENEMY, &"harvester")[0])).is_equal(OrderSpec.Kind.MOVE)


func test_enemy_mixed_selection_only_attack_capable_attack() -> void:
	var cls: Array[StringName] = [&"dart", &"hauler", &"harvester", &"scout", &"bomber"]
	var cs: Array[Command] = _res(T.ENEMY, cls)
	assert_int(cs.size()).is_equal(1)
	assert_int(_kind(cs[0])).is_equal(OrderSpec.Kind.ATTACK)
	assert_int(_count(cs[0])).is_equal(2)


func test_tower_accepts_attack_and_guard_only() -> void:
	assert_int(_kind(_one(T.ENEMY, &"tower")[0])).is_equal(OrderSpec.Kind.ATTACK)
	assert_int(_kind(_one(T.FRIENDLY_STRUCTURE, &"tower")[0])).is_equal(OrderSpec.Kind.GUARD)
	for t: OrderResolver.Target in [T.GROUND, T.ORE_FIELD, T.WRECK, T.ICE_EXTRACTOR, T.NEUTRAL]:
		assert_int(_one(t, &"tower").size()).is_equal(0)


func test_friendly_pad_returns_only_return_capable() -> void:
	for c: StringName in SHIPS:
		assert_int(_kind(_one(T.FRIENDLY_PAD, c)[0])).is_equal(OrderSpec.Kind.RETURN)
	assert_int(_one(T.FRIENDLY_PAD, &"harvester").size()).is_equal(0)
	assert_int(_one(T.FRIENDLY_PAD, &"siege_crawler").size()).is_equal(0)


func test_relay_station_hauler_captures_others_guard_if_allowed() -> void:
	var cap: Command = _one(T.RELAY_STATION, &"hauler")[0]
	assert_int(_kind(cap)).is_equal(OrderSpec.Kind.HAUL)
	assert_int(_mode(cap)).is_equal(OrderSpec.HaulMode.CAPTURE)
	assert_int(_kind(_one(T.RELAY_STATION, &"dart")[0])).is_equal(OrderSpec.Kind.GUARD)
	assert_int(_one(T.RELAY_STATION, &"harvester").size()).is_equal(0)


func test_relay_station_split_selection() -> void:
	var cls: Array[StringName] = [&"hauler", &"dart", &"hauler", &"harvester"]
	var cs: Array[Command] = _res(T.RELAY_STATION, cls)
	assert_int(cs.size()).is_equal(2)
	assert_int(_kind(cs[0])).is_equal(OrderSpec.Kind.HAUL)
	assert_int(_count(cs[0])).is_equal(2)
	assert_int(_kind(cs[1])).is_equal(OrderSpec.Kind.GUARD)
	assert_int(_count(cs[1])).is_equal(1)


func test_escort_only_for_escort_classes() -> void:
	assert_int(_kind(_one(T.FRIENDLY_UNIT, &"dart")[0])).is_equal(OrderSpec.Kind.ESCORT)
	assert_int(_kind(_one(T.FRIENDLY_UNIT, &"lancer")[0])).is_equal(OrderSpec.Kind.ESCORT)
	for c: StringName in [&"bomber", &"scout", &"hauler", &"harvester", &"siege_crawler"]:
		assert_int(_one(T.FRIENDLY_UNIT, c).size()).is_equal(0)


func test_structure_guard_only_for_guard_classes() -> void:
	assert_int(_kind(_one(T.FRIENDLY_STRUCTURE, &"scout")[0])).is_equal(OrderSpec.Kind.GUARD)
	assert_int(_one(T.FRIENDLY_STRUCTURE, &"harvester").size()).is_equal(0)


func test_economy_targets() -> void:
	assert_int(_kind(_one(T.ORE_FIELD, &"harvester")[0])).is_equal(OrderSpec.Kind.HARVEST_HERE)
	assert_int(_one(T.ORE_FIELD, &"hauler").size()).is_equal(0)
	var ice: Command = _one(T.ICE_EXTRACTOR, &"hauler")[0]
	assert_int(_kind(ice)).is_equal(OrderSpec.Kind.HAUL)
	assert_int(_mode(ice)).is_equal(OrderSpec.HaulMode.FERRY)
	assert_int(_mode(_one(T.WRECK, &"hauler")[0])).is_equal(OrderSpec.HaulMode.TOW)
	assert_int(_one(T.WRECK, &"harvester").size()).is_equal(0)


func test_ground_rally_and_move() -> void:
	var r: Command = _one(T.GROUND, &"shipyard")[0]
	assert_int(r.kind).is_equal(Command.Kind.SET_RALLY)
	assert_int(r.target).is_equal(1)
	assert_int(_one(T.GROUND, &"vehicle_bay")[0].kind).is_equal(Command.Kind.SET_RALLY)
	assert_int(_kind(_one(T.GROUND, &"dart")[0])).is_equal(OrderSpec.Kind.MOVE)
	assert_int(_kind(_one(T.GROUND, &"harvester")[0])).is_equal(OrderSpec.Kind.MOVE)
	assert_int(_one(T.ENEMY, &"shipyard").size()).is_equal(0)
	assert_int(_one(T.GROUND, &"pad").size()).is_equal(0)


func test_ground_units_on_friendly_targets_get_no_move() -> void:
	for t: OrderResolver.Target in [T.FRIENDLY_PAD, T.RELAY_STATION, T.FRIENDLY_UNIT]:
		for c: StringName in GROUND:
			for cmd: Command in _one(t, c):
				assert_int(_kind(cmd)).is_not_equal(OrderSpec.Kind.MOVE)
	assert_int(_one(T.FRIENDLY_PAD, &"harvester").size()).is_equal(0)
	assert_int(_one(T.FRIENDLY_UNIT, &"siege_crawler").size()).is_equal(0)
	# the one rule that does cover a ground class: siege_crawler may GUARD a friendly structure
	assert_int(_kind(_one(T.FRIENDLY_STRUCTURE, &"siege_crawler")[0])).is_equal(OrderSpec.Kind.GUARD)


func test_neutral_gives_nothing() -> void:
	assert_int(_one(T.NEUTRAL, &"dart").size()).is_equal(0)


func test_queue_flag() -> void:
	assert_int(_one(T.ENEMY, &"dart", true)[0].payload.decode_u8(1)).is_equal(OrderSpec.FLAG_QUEUE)
	assert_int(_one(T.ENEMY, &"dart", false)[0].payload.decode_u8(1)).is_equal(0)


func test_chunks_to_wire_limit() -> void:
	var ids: PackedInt32Array = PackedInt32Array()
	var cls: Array[StringName] = []
	for i: int in 40:
		ids.append(i + 1)
		cls.append(&"dart")
	var cs: Array[Command] = OrderResolver.resolve(0, _rules, T.ENEMY, 9, P, ids, cls)
	assert_int(cs.size()).is_equal(2)
	assert_int(_count(cs[0])).is_equal(32)
	assert_int(_count(cs[1])).is_equal(8)


func test_supply_drop() -> void:
	var cs: Array[Command] = OrderResolver.resolve_supply(0, 12, PackedInt32Array([3]))
	assert_int(cs.size()).is_equal(1)
	assert_int(_kind(cs[0])).is_equal(OrderSpec.Kind.SUPPLY_DROP)


func test_payload_target() -> void:
	var c: Command = _one(T.FRIENDLY_PAD, &"dart")[0]
	assert_int(c.payload.decode_u32(4 + 4)).is_equal(77)


## The sim rejects a whole ORDER if any id's class disallows the kind (command_validator._check_order).
## Every resolver output, for every target and a selection of every shipped class, must pass the same check.
func test_every_output_passes_the_sim_order_check() -> void:
	var cls: Array[StringName] = []
	var defs: PackedInt32Array = PackedInt32Array()
	for c: StringName in SHIPS + GROUND:
		cls.append(c)
		defs.append(ContentDB.def_index(c))
	var tower_def: int = -1
	for i: int in ContentDB.structures.size():
		if not ContentDB.structures[i].tower.is_empty():
			tower_def = DefRanges.STRUCTURE_BASE + i
			break
	assert_int(tower_def).is_greater_equal(0)
	cls.append(&"tower")
	defs.append(tower_def)
	var subsets: Array[Array] = [range(cls.size())]
	for i: int in cls.size():
		subsets.append([i])
	for t: int in T.values():
		for sub: Array in subsets:
			_check_subset(t as OrderResolver.Target, cls, defs, sub)


func _check_subset(t: OrderResolver.Target, cls: Array[StringName], defs: PackedInt32Array, sub: Array) -> void:
	var ids: PackedInt32Array = PackedInt32Array()
	var sc: Array[StringName] = []
	for i: int in sub:
		ids.append(i + 1)
		sc.append(cls[i])
	var spec: OrderSpec = OrderSpec.new()
	var rid: PackedInt32Array = PackedInt32Array()
	for cmd: Command in OrderResolver.resolve(0, _rules, t, 77, P, ids, sc):
		if cmd.kind != Command.Kind.ORDER:
			continue
		assert_bool(CommandPayload.read_order(cmd, spec, rid)).is_true()
		for id: int in rid:
			var v: OrderRules.Verdict = _sim_rules.validate(spec, defs[id - 1], true)
			assert_int(v).override_failure_message("target %d class %s kind %d" % [t, cls[id - 1], spec.kind]).is_equal(OrderRules.Verdict.OK)
