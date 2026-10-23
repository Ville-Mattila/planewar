extends GdUnitTestSuite
## NET-17 TEAM_STATE (0x85) codec (04 s2.3; GD-38 CORE_SHIELD_UP in flags bit 2, R0 B.8 A-8): layout and sizes against
## the catalogue, round trips of every field at its wire range, the malformed table, and the N5 fuzz sweep (100,000
## mutations, never an error, a rejected message changes nothing, an accepted one re-encodes to the same bytes).


func _wire(rng: RandomNumberGenerator, members: int) -> TeamStateWire:
	var w: TeamStateWire = TeamStateWire.new()
	w.tick = rng.randi_range(1, 0x7FFFFFFF)
	w.ore = rng.randi()
	w.ice = rng.randi()
	w.ore_cap = rng.randi()
	w.ice_cap = rng.randi()
	w.power_supply = rng.randi_range(0, 0xFFFF)
	w.power_demand = rng.randi_range(0, 0xFFFF)
	w.unit_cap = rng.randi_range(0, 0xFFFF)
	w.structure_cap = rng.randi_range(0, 0xFFFF)
	w.flags = rng.randi_range(0, TeamStateCodec.FLAGS_MASK)
	var slots: Array[int] = [0, 1, 2, 3, 4, 5, 6, 7]
	slots.shuffle()
	for k: int in members:
		w.add_member(slots[k], rng.randi_range(0, 0xFFFF), rng.randi_range(0, 0xFFFF))
	return w


func _same(a: TeamStateWire, b: TeamStateWire) -> bool:
	return a.tick == b.tick and a.ore == b.ore and a.ice == b.ice and a.ore_cap == b.ore_cap and a.ice_cap == b.ice_cap \
			and a.power_supply == b.power_supply and a.power_demand == b.power_demand and a.unit_cap == b.unit_cap \
			and a.structure_cap == b.structure_cap and a.flags == b.flags and a.member_slot == b.member_slot \
			and a.member_units == b.member_units and a.member_structures == b.member_structures


func test_sizes_match_the_catalogue() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	assert_int(TeamStateCodec.encode(_wire(rng, 4)).size()).is_equal(51)        # 04 s4.6 "51 B (4 members)"
	assert_int(TeamStateCodec.encode(_wire(rng, 0)).size()).is_equal(TeamStateCodec.FIXED_BYTES)
	var full: PackedByteArray = TeamStateCodec.encode(_wire(rng, 8))
	assert_int(full.size()).is_equal(71)
	assert_int(full.size()).is_less_equal(Protocol.max_bytes(Protocol.TEAM_STATE))
	assert_int(Protocol.channel_of(Protocol.TEAM_STATE)).is_equal(Protocol.CH_SNAPSHOT)


func test_layout_is_little_endian_in_04_order() -> void:
	var w: TeamStateWire = TeamStateWire.new()
	w.tick = 0x01020304
	w.ore = 800
	w.ice = 300
	w.ore_cap = 5000
	w.ice_cap = 2000
	w.power_supply = 40
	w.power_demand = 25
	w.unit_cap = 60
	w.structure_cap = 40
	w.flags = Protocol.TEAM_CORE_SHIELD_UP
	w.add_member(2, 7, 9)
	var b: PackedByteArray = TeamStateCodec.encode(w)
	assert_array(Array(b.slice(0, 5))).is_equal([0x85, 4, 3, 2, 1])
	assert_int(b.decode_u32(5)).is_equal(800)
	assert_int(b.decode_u16(21)).is_equal(40)
	assert_int(b[29]).is_equal(TeamStateView.CORE_SHIELD_UP)               # GD-38: the TeamStateView bit on the wire
	assert_array(Array(b.slice(30, 36))).is_equal([1, 2, 7, 0, 9, 0])


func test_round_trip_every_field() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 85
	for i: int in 1000:
		var w: TeamStateWire = _wire(rng, i % 9)
		var b: PackedByteArray = TeamStateCodec.encode(w)
		var out: TeamStateWire = TeamStateWire.new()
		assert_bool(TeamStateCodec.decode(b, out)).is_true()
		assert_bool(_same(w, out)).is_true()
		assert_int(TeamStateCodec.tick_of(b)).is_equal(w.tick)


func test_flag_constants_equal_team_state_view() -> void:
	assert_int(Protocol.TEAM_CORE_EXPOSURE).is_equal(TeamStateView.CORE_EXPOSURE)
	assert_int(Protocol.TEAM_LOW_POWER).is_equal(TeamStateView.LOW_POWER)
	assert_int(Protocol.TEAM_CORE_SHIELD_UP).is_equal(TeamStateView.CORE_SHIELD_UP)
	assert_int(Protocol.TEAM_SPEND_LOCK_ACTIVE).is_equal(TeamStateView.SPEND_LOCK_ACTIVE)
	assert_int(TeamStateCodec.FLAGS_MASK).is_equal(15)


func test_encode_rejects_out_of_range() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	var w: TeamStateWire = _wire(rng, 9 - 1)
	w.add_member(0, 1, 1)
	assert_bool(TeamStateCodec.encode(w).is_empty()).is_true()                # 9 members
	for edit: int in 6:
		var v: TeamStateWire = _wire(rng, 2)
		match edit:
			0: v.tick = 0
			1: v.flags = 0x10
			2: v.power_supply = 0x10000
			3: v.ore = -1
			4: v.member_slot[0] = 8
			_: v.member_units[1] = 0x10000
		assert_bool(TeamStateCodec.encode(v).is_empty()).override_failure_message("edit %d" % edit).is_true()


func test_malformed_table_changes_nothing() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	var good: PackedByteArray = TeamStateCodec.encode(_wire(rng, 3))
	var bad: Array[PackedByteArray] = []
	bad.append(PackedByteArray())
	bad.append(good.slice(0, 30))
	var wrong_id: PackedByteArray = good.duplicate()
	wrong_id[0] = Protocol.SNAPSHOT
	bad.append(wrong_id)
	var trailing: PackedByteArray = good.duplicate()
	var _t: bool = trailing.push_back(0)
	bad.append(trailing)
	var count: PackedByteArray = good.duplicate()
	count[30] = 4
	bad.append(count)
	var flag: PackedByteArray = good.duplicate()
	flag[29] = 0x80
	bad.append(flag)
	var dup: PackedByteArray = good.duplicate()
	dup[36] = dup[31]
	bad.append(dup)
	var slot8: PackedByteArray = good.duplicate()
	slot8[31] = 8
	bad.append(slot8)
	var tick0: PackedByteArray = good.duplicate()
	tick0.encode_u32(1, 0)
	bad.append(tick0)
	var before: TeamStateWire = _wire(rng, 2)
	var out: TeamStateWire = TeamStateWire.new()
	out.copy_from(before)
	for b: PackedByteArray in bad:
		assert_bool(TeamStateCodec.decode(b, out)).is_false()
		assert_bool(_same(out, before)).is_true()


func test_fuzz_100000_mutations() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 0x85
	var seeds: Array[PackedByteArray] = [TeamStateCodec.encode(_wire(rng, 0)), TeamStateCodec.encode(_wire(rng, 4)),
			TeamStateCodec.encode(_wire(rng, 8))]
	var sentinel: TeamStateWire = _wire(rng, 1)
	var out: TeamStateWire = TeamStateWire.new()
	var accepted: int = 0
	for i: int in NetFuzz.MUTATIONS:
		var m: PackedByteArray = NetFuzz.mutate(rng, seeds[i % seeds.size()], 31)
		out.copy_from(sentinel)
		if TeamStateCodec.decode(m, out):
			accepted += 1
			assert_bool(TeamStateCodec.encode(out) == m).is_true()             # canonical: accepted bytes re-encode exactly
		elif not _same(out, sentinel):
			fail("rejected mutation %d changed the output" % i)
			return
	assert_int(accepted).is_greater(0)
	assert_int(accepted).is_less(NetFuzz.MUTATIONS)
