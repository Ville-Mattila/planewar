extends GdUnitTestSuite
## OrderResolver (UX-20; docs/06 s7.2, R0 C2-06): every row of the resolver table.

const T := OrderResolver.Target
const S := OrderResolver.Sel
const P: Vector3 = Vector3(0.0, 6001.0, 0.0)


func _one(t: OrderResolver.Target, s: OrderResolver.Sel, queue: bool = false) -> Array[Command]:
	var kinds: Array[OrderResolver.Sel] = [s]
	return OrderResolver.resolve(0, t, 77, P, PackedInt32Array([5]), kinds, queue)


func _kind(c: Command) -> int:
	return c.payload.decode_u8(0)


func _mode(c: Command) -> int:
	return c.payload.decode_u8(2)


func test_enemy_armed_attacks() -> void:
	var cs: Array[Command] = _one(T.ENEMY, S.SHIP_ARMED)
	assert_int(cs.size()).is_equal(1)
	assert_int(cs[0].kind).is_equal(Command.Kind.ORDER)
	assert_int(_kind(cs[0])).is_equal(OrderSpec.Kind.ATTACK)


func test_enemy_unarmed_only_moves() -> void:
	assert_int(_kind(_one(T.ENEMY, S.HAULER)[0])).is_equal(OrderSpec.Kind.MOVE)
	assert_int(_kind(_one(T.ENEMY, S.GROUND_UNARMED)[0])).is_equal(OrderSpec.Kind.MOVE)


func test_enemy_mixed_selection_attacks() -> void:
	var kinds: Array[OrderResolver.Sel] = [S.SHIP_ARMED, S.HAULER]
	var cs: Array[Command] = OrderResolver.resolve(0, T.ENEMY, 9, P, PackedInt32Array([1, 2]), kinds)
	assert_int(cs.size()).is_equal(1)
	assert_int(_kind(cs[0])).is_equal(OrderSpec.Kind.ATTACK)


func test_tower_accepts_attack_and_guard_only() -> void:
	assert_int(_kind(_one(T.ENEMY, S.TOWER)[0])).is_equal(OrderSpec.Kind.ATTACK)
	assert_int(_kind(_one(T.FRIENDLY_STRUCTURE, S.TOWER)[0])).is_equal(OrderSpec.Kind.GUARD)
	assert_int(_one(T.GROUND, S.TOWER).size()).is_equal(0)
	assert_int(_one(T.ORE_FIELD, S.TOWER).size()).is_equal(0)
	assert_int(_one(T.WRECK, S.TOWER).size()).is_equal(0)


func test_friendly_pad_returns_ships() -> void:
	for s: OrderResolver.Sel in [S.SHIP_ARMED, S.SHIP_UNARMED, S.HARVESTER, S.HAULER]:
		assert_int(_kind(_one(T.FRIENDLY_PAD, s)[0])).is_equal(OrderSpec.Kind.RETURN)


func test_relay_station_hauler_captures_others_guard() -> void:
	var cap: Command = _one(T.RELAY_STATION, S.HAULER)[0]
	assert_int(_kind(cap)).is_equal(OrderSpec.Kind.HAUL)
	assert_int(_mode(cap)).is_equal(OrderSpec.HaulMode.CAPTURE)
	assert_int(_kind(_one(T.RELAY_STATION, S.SHIP_ARMED)[0])).is_equal(OrderSpec.Kind.GUARD)
	assert_int(_kind(_one(T.RELAY_STATION, S.HARVESTER)[0])).is_equal(OrderSpec.Kind.GUARD)


func test_relay_station_split_selection() -> void:
	var kinds: Array[OrderResolver.Sel] = [S.HAULER, S.SHIP_ARMED, S.HAULER]
	var cs: Array[Command] = OrderResolver.resolve(0, T.RELAY_STATION, 9, P, PackedInt32Array([1, 2, 3]), kinds)
	assert_int(cs.size()).is_equal(2)
	assert_int(_kind(cs[0])).is_equal(OrderSpec.Kind.HAUL)
	assert_int(cs[0].payload.decode_u8(3)).is_equal(2)
	assert_int(_kind(cs[1])).is_equal(OrderSpec.Kind.GUARD)


func test_friendly_unit_escort_and_structure_guard() -> void:
	assert_int(_kind(_one(T.FRIENDLY_UNIT, S.SHIP_ARMED)[0])).is_equal(OrderSpec.Kind.ESCORT)
	assert_int(_kind(_one(T.FRIENDLY_STRUCTURE, S.SHIP_UNARMED)[0])).is_equal(OrderSpec.Kind.GUARD)


func test_economy_targets() -> void:
	assert_int(_kind(_one(T.ORE_FIELD, S.HARVESTER)[0])).is_equal(OrderSpec.Kind.HARVEST_HERE)
	assert_int(_one(T.ORE_FIELD, S.HAULER).size()).is_equal(0)
	var ice: Command = _one(T.ICE_EXTRACTOR, S.HAULER)[0]
	assert_int(_kind(ice)).is_equal(OrderSpec.Kind.HAUL)
	assert_int(_mode(ice)).is_equal(OrderSpec.HaulMode.FERRY)
	var tow: Command = _one(T.WRECK, S.HAULER)[0]
	assert_int(_mode(tow)).is_equal(OrderSpec.HaulMode.TOW)
	assert_int(_one(T.WRECK, S.HARVESTER).size()).is_equal(0)


func test_ground_rally_and_move() -> void:
	var r: Command = _one(T.GROUND, S.FACTORY)[0]
	assert_int(r.kind).is_equal(Command.Kind.SET_RALLY)
	assert_int(r.target).is_equal(5)
	assert_int(_kind(_one(T.GROUND, S.SHIP_ARMED)[0])).is_equal(OrderSpec.Kind.MOVE)
	assert_int(_kind(_one(T.GROUND, S.GROUND_ARMED)[0])).is_equal(OrderSpec.Kind.MOVE)
	assert_int(_one(T.ENEMY, S.FACTORY).size()).is_equal(0)


func test_neutral_gives_nothing() -> void:
	assert_int(_one(T.NEUTRAL, S.SHIP_ARMED).size()).is_equal(0)


func test_queue_flag() -> void:
	assert_int(_one(T.ENEMY, S.SHIP_ARMED, true)[0].payload.decode_u8(1)).is_equal(OrderSpec.FLAG_QUEUE)
	assert_int(_one(T.ENEMY, S.SHIP_ARMED, false)[0].payload.decode_u8(1)).is_equal(0)


func test_chunks_to_wire_limit() -> void:
	var ids: PackedInt32Array = PackedInt32Array()
	var kinds: Array[OrderResolver.Sel] = []
	for i: int in 40:
		ids.append(i + 1)
		kinds.append(S.SHIP_ARMED)
	var cs: Array[Command] = OrderResolver.resolve(0, T.ENEMY, 9, P, ids, kinds)
	assert_int(cs.size()).is_equal(2)
	assert_int(cs[0].payload.decode_u8(3)).is_equal(32)
	assert_int(cs[1].payload.decode_u8(3)).is_equal(8)


func test_supply_drop() -> void:
	var cs: Array[Command] = OrderResolver.resolve_supply(0, 12, PackedInt32Array([3]))
	assert_int(cs.size()).is_equal(1)
	assert_int(_kind(cs[0])).is_equal(OrderSpec.Kind.SUPPLY_DROP)


func test_payload_roundtrip_target() -> void:
	var c: Command = _one(T.FRIENDLY_PAD, S.SHIP_ARMED)[0]
	assert_int(c.payload.decode_u32(4 + 4)).is_equal(77)
