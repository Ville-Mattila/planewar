extends GdUnitTestSuite
## NET-58 (R0 B.22 A-112; 04 s3.1, s3.6, s4.1): the roster's projectile block. index = slot for EntityStore slots
## 0-1,535 and 1,536 + (slot - 4,096) for ProjectileStore slots 4,096-6,143, CAPACITY 3,584, every sized array follows;
## ENTITY_META / ROSTER_REMOVE / KEYFRAME carry the sim slot and reject 1,536-4,095 and >= 6,144; prepare_tick caches
## ROCKET / BOMB / SIEGE_SHELL / CANISTER rows only; a projectile entity is visible to a team through its own team, its
## shooter or its target; bombs dead-reckon with gravity, rockets linearly; a new generation in an index is a FULL;
## Interest removes a projectile the tick it dies or leaves V. Decoders are total: seeded mutation sweeps in which every
## accepted message re-encodes to the identical bytes (the NET-04 standard). ProjectileStore ordinals are pinned.

const G: float = 6.0
const HZ: int = 30
const P0: int = EntityId.PROJECTILE_SLOT_MIN
const PI0: int = Roster.PROJECTILE_INDEX_MIN


func _here(east_m: float = 0.0, alt: float = 800.0) -> Vector3:
	var c: Vector3 = Sphere.from_lat_lon(0.31, 1.17, Sphere.PLANET_RADIUS + alt)
	return c + Sphere.tangent_frame(c).x * east_m


func test_index_mapping_and_capacities() -> void:
	assert_int(Roster.CAPACITY).is_equal(3584)
	assert_int(Roster.ENTITY_SLOTS).is_equal(1536)
	assert_int(PI0).is_equal(1536)
	for s: int in [0, 1, 1279, 1280, 1535]:
		assert_int(Roster.index_of_slot(s)).is_equal(s)
		assert_int(Roster.slot_of_index(s)).is_equal(s)
	assert_int(Roster.index_of_slot(4096)).is_equal(1536)
	assert_int(Roster.index_of_slot(6143)).is_equal(3583)
	assert_int(Roster.slot_of_index(1536)).is_equal(4096)
	assert_int(Roster.slot_of_index(3583)).is_equal(6143)
	for bad: int in [-1, 1536, 2000, 3583, 3584, 4095, 6144, 0xFFFF, 0xFFFFF]:
		assert_int(Roster.index_of_slot(bad)).override_failure_message("slot %d" % bad).is_equal(-1)
	for bad_i: int in [-1, 3584, 4096]:
		assert_int(Roster.slot_of_index(bad_i)).is_equal(-1)
	for i: int in Roster.CAPACITY:                          # a bijection between the two ranges
		assert_int(Roster.index_of_slot(Roster.slot_of_index(i))).is_equal(i)
	for cap: int in [BaselineFrame.CAPACITY, SnapshotCodec.CAPACITY, SnapshotByteCache.CAPACITY, Interest.CAPACITY,
			InterestClient.CAPACITY, KeyframeCodec.COUNT_MAX, VisibleSets.CAPACITY]:
		assert_int(cap).is_equal(Roster.CAPACITY)
	assert_int(InterestClient._KEY_SHIFT).is_equal(12)
	assert_bool((1 << InterestClient._KEY_SHIFT) >= Roster.CAPACITY).is_true()
	var r: Roster = Roster.new()
	assert_bool(r.add(3583, 2, 1283, 1, 1)).is_true()
	assert_bool(r.add(3584, 2, 1283, 1, 1)).is_false()


func test_projectile_store_ordinals_are_mirrored() -> void:
	assert_int(SnapshotFrame.SLUG).is_equal(ProjectileStore.SLUG)
	assert_int(SnapshotFrame.BOMB).is_equal(ProjectileStore.BOMB)
	assert_int(SnapshotFrame.ROCKET).is_equal(ProjectileStore.ROCKET)
	assert_int(SnapshotFrame.FLAK).is_equal(ProjectileStore.FLAK)
	assert_int(SnapshotFrame.RAIL).is_equal(ProjectileStore.RAIL)
	assert_int(SnapshotFrame.SIEGE_SHELL).is_equal(ProjectileStore.SIEGE_SHELL)
	assert_int(SnapshotFrame.CANISTER).is_equal(ProjectileStore.CANISTER)
	var want: Array = [false, true, true, false, false, true, true, false]
	for k: int in 8:
		assert_bool(SnapshotFrame.replicated_kind(k)).override_failure_message("kind %d" % k).is_equal(want[k])
	assert_bool(SnapshotFrame.replicated_kind(-1)).is_false()


func _roster_with_projectiles() -> Roster:
	var r: Roster = Roster.new()
	var _a: bool = r.add(5, 1, 2, 0, 0)
	var _b: bool = r.add(1535, 4, 2, 1, 1)
	var _c: bool = r.add(PI0, 7, 1283, 1, 1)                 # slot 4,096
	var _d: bool = r.add(PI0 + 10, 2047, 1281, 3, 2)          # slot 4,106
	var _e: bool = r.add(Roster.CAPACITY - 1, 1, 1282, 0, 0)  # slot 6,143
	return r


func test_meta_carries_the_sim_slot_and_round_trips_projectile_entries() -> void:
	var src: Roster = _roster_with_projectiles()
	var idx: PackedInt32Array = PackedInt32Array([5, 1535, PI0, PI0 + 10, Roster.CAPACITY - 1])
	var out: Array[PackedByteArray] = []
	assert_int(RosterCodec.encode_meta(src, idx, out)).is_equal(1)
	var b: PackedByteArray = out[0]
	assert_int(b.size()).is_equal(2 + 5 * RosterCodec.META_FIXED_BYTES)
	var wire: Array = []
	for k: int in 5:
		wire.append(b.decode_u16(2 + k * RosterCodec.META_FIXED_BYTES))
	assert_array(wire).is_equal([5, 1535, 4096, 4106, 6143])
	var dst: Roster = Roster.new()
	var got: PackedInt32Array = PackedInt32Array()
	assert_int(RosterCodec.decode_meta(b, dst, got)).is_equal(5)
	assert_array(Array(got)).is_equal(Array(idx))
	assert_int(dst.state_hash()).is_equal(src.state_hash())
	assert_int(dst.def_of(PI0 + 10)).is_equal(1281)
	assert_int(dst.owner_of(PI0 + 10)).is_equal(3)
	assert_int(dst.team_of(PI0 + 10)).is_equal(2)


func test_meta_rejects_slots_outside_both_ranges() -> void:
	var src: Roster = _roster_with_projectiles()
	var out: Array[PackedByteArray] = []
	var _n: int = RosterCodec.encode_meta(src, PackedInt32Array([5, PI0]), out)
	var good: PackedByteArray = out[0]
	for slot: int in [4096, 6143, 0, 1535]:
		var m: PackedByteArray = good.duplicate()
		m.encode_u16(2 + RosterCodec.META_FIXED_BYTES, slot)
		assert_int(RosterCodec.decode_meta(m, Roster.new(), PackedInt32Array())).is_equal(2)
	for slot: int in [1536, 2048, 3583, 3584, 4095, 6144, 8191, 0xFFFF]:
		var m: PackedByteArray = good.duplicate()
		m.encode_u16(2 + RosterCodec.META_FIXED_BYTES, slot)
		var dst: Roster = Roster.new()
		assert_int(RosterCodec.decode_meta(m, dst, PackedInt32Array())).override_failure_message("slot %d" % slot).is_equal(-1)
		assert_int(dst.count()).is_equal(0)                  # the valid first entry is not applied either


func test_remove_carries_the_sim_slot_and_rejects_the_gap() -> void:
	var src: Roster = _roster_with_projectiles()
	var out: Array[PackedByteArray] = []
	var idx: PackedInt32Array = PackedInt32Array([PI0, 5, Roster.CAPACITY - 1])
	var reasons: PackedInt32Array = PackedInt32Array([Protocol.RosterRemoveReason.DEATH, Protocol.RosterRemoveReason.OUT_OF_VISION,
			Protocol.RosterRemoveReason.DEATH])
	assert_int(RosterCodec.encode_remove(idx, reasons, out)).is_equal(1)
	assert_int(out[0].decode_u16(2)).is_equal(4096)
	assert_int(out[0].decode_u16(8)).is_equal(6143)
	var got: PackedInt32Array = PackedInt32Array()
	assert_int(RosterCodec.decode_remove(out[0], src, got)).is_equal(3)
	assert_array(Array(got)).is_equal(Array(idx))
	assert_bool(src.has(PI0) or src.has(Roster.CAPACITY - 1)).is_false()
	assert_int(src.removal_reason_of(PI0)).is_equal(Protocol.RosterRemoveReason.DEATH)
	for slot: int in [1536, 4095, 6144, 0xFFFF]:
		var m: PackedByteArray = out[0].duplicate()
		m.encode_u16(5, slot)
		var r: Roster = _roster_with_projectiles()
		assert_int(RosterCodec.decode_remove(m, r, PackedInt32Array())).is_equal(-1)
		assert_int(r.state_hash()).is_equal(_roster_with_projectiles().state_hash())
	var skipped: Array[PackedByteArray] = []                # the encoder never writes an index outside the roster
	assert_int(RosterCodec.encode_remove(PackedInt32Array([Roster.CAPACITY]), PackedInt32Array([0]), skipped)).is_equal(0)


## A frame of `n_ent` ships (slots 1..n_ent, team t % 3, visible to every team) plus `kinds` projectile rows at slots
## 4,096 + 3k (shooter ship 1, target ship 2).
func _frame(tick: int, n_ent: int, kinds: PackedInt32Array, gen: int = 1) -> SnapshotFrame:
	var f: SnapshotFrame = SnapshotFrame.new()
	f.resize(n_ent + kinds.size())
	f.tick = tick
	for i: int in n_ent:
		f.set_entity(i, i + 1, _here(40.0 * i), Vector3(10, 0, 0), Quaternion.IDENTITY, 1.0, 0, i % 3, 0, false, 0x7)
		f.gen[i] = 1
	for k: int in kinds.size():
		var grav: bool = kinds[k] == SnapshotFrame.BOMB or kinds[k] == SnapshotFrame.SIEGE_SHELL
		f.set_projectile(n_ent + k, P0 + 3 * k, kinds[k], _here(5.0 * k, 900.0), Vector3(0, 0, 50), 1, grav,
				EntityId.make(1, 1), EntityId.make(2, 1), gen)
	return f


func test_prepare_tick_caches_the_four_replicated_kinds_only() -> void:
	var codec: SnapshotCodec = SnapshotCodec.new(G, HZ)
	var kinds: PackedInt32Array = PackedInt32Array([0, 1, 2, 3, 4, 5, 6])
	var f: SnapshotFrame = _frame(5, 3, kinds)
	codec.prepare_tick(f)
	for k: int in kinds.size():
		var s: int = PI0 + 3 * k
		assert_int(f.index_of_row(3 + k)).is_equal(s if SnapshotFrame.replicated_kind(kinds[k]) else -1)
		assert_bool(codec.c_tick[s] == 5).override_failure_message("kind %d" % kinds[k]).is_equal(SnapshotFrame.replicated_kind(kinds[k]))
	assert_int(codec.c_grav[PI0 + 3]).is_equal(1)            # bomb
	assert_int(codec.c_grav[PI0 + 6]).is_equal(0)            # rocket
	assert_int(codec.c_grav[PI0 + 15]).is_equal(1)           # siege shell
	assert_int(codec.c_team[PI0 + 6]).is_equal(1)
	var bad: SnapshotFrame = _frame(6, 1, PackedInt32Array())
	bad.resize(3)
	bad.set_entity(1, 1536, _here(), Vector3.ZERO, Quaternion.IDENTITY, 1.0, 0, 0)    # slots no roster holds
	bad.set_entity(2, 6144, _here(), Vector3.ZERO, Quaternion.IDENTITY, 1.0, 0, 0)
	codec.prepare_tick(bad)
	assert_array(Array(codec.team_visible(0))).is_equal([1])


func test_projectile_visibility_follows_team_shooter_and_target() -> void:
	var codec: SnapshotCodec = SnapshotCodec.new(G, HZ)
	var f: SnapshotFrame = SnapshotFrame.new()
	f.resize(7)
	f.tick = 9
	f.set_entity(0, 10, _here(0.0), Vector3.ZERO, Quaternion.IDENTITY, 1.0, 0, 0, 0, false, 0)         # A: team 0
	f.set_entity(1, 11, _here(50.0), Vector3.ZERO, Quaternion.IDENTITY, 1.0, 0, 1, 0, false, 1 << 0)   # B: team 1, seen by 0
	f.set_entity(2, 12, _here(90.0), Vector3.ZERO, Quaternion.IDENTITY, 1.0, 0, 1, 0, false, 0)        # C: team 1, unseen by 0
	for i: int in 3:
		f.gen[i] = 4
	var a: int = EntityId.make(10, 4)
	var b: int = EntityId.make(11, 4)
	var c: int = EntityId.make(12, 4)
	f.set_projectile(3, P0 + 1, SnapshotFrame.ROCKET, _here(10.0), Vector3.ZERO, 0, false, c, c, 1)        # own team
	f.set_projectile(4, P0 + 2, SnapshotFrame.ROCKET, _here(20.0), Vector3.ZERO, 1, false, b, 0, 1)        # shooter in V
	f.set_projectile(5, P0 + 3, SnapshotFrame.BOMB, _here(30.0), Vector3.ZERO, 1, true, c, a, 1)           # target in V
	f.set_projectile(6, P0 + 4, SnapshotFrame.ROCKET, _here(40.0), Vector3.ZERO, 1, false, c, c, 1)        # none
	codec.prepare_tick(f)
	assert_array(Array(codec.team_visible(0))).is_equal([10, 11, PI0 + 1, PI0 + 2, PI0 + 3])
	assert_array(Array(codec.team_visible(1))).is_equal([11, 12, PI0 + 1, PI0 + 2, PI0 + 3, PI0 + 4])   # PI0 + 1 via its shooter c
	f.set_projectile(4, P0 + 2, SnapshotFrame.ROCKET, _here(20.0), Vector3.ZERO, 1, false, EntityId.make(11, 5), 0, 1)
	f.tick = 10
	codec.prepare_tick(f)                                   # a stale shooter generation lends no visibility
	assert_bool(codec.team_visible(0).has(PI0 + 2)).is_false()
	var it: Interest = Interest.new()
	it.begin_tick(f, codec)
	assert_bool(it.visible(PI0 + 3, 0)).is_true()
	assert_bool(it.visible(PI0 + 4, 0)).is_false()


## Bomb (gravity def) and rocket (linear) over 60 ticks: after the FULL the bomb's gravity-aware dead reckoning needs
## only a few records, far fewer than the same fall encoded without the gravity flag; the rocket needs none; the client
## mirror equals the server's and shows the bomb within 0.5 m of the truth (residuals under 4 quanta are not sent).
func test_bombs_dead_reckon_with_gravity_rockets_linearly() -> void:
	var counts: PackedInt32Array = PackedInt32Array()
	for grav_flag: bool in [true, false]:
		var codec: SnapshotCodec = SnapshotCodec.new(G, HZ)
		var store: BaselineStore = BaselineStore.new(0)
		var roster: Roster = Roster.new()
		var _a: bool = roster.add(PI0, 1, 1281, 0, 1)        # bomb
		var _b: bool = roster.add(PI0 + 1, 1, 1283, 0, 1)    # rocket
		var dec: SnapshotDecoder = SnapshotDecoder.new(G, HZ, 0, roster)
		var _r: int = dec.gravity_def.resize(1536)
		dec.gravity_def[1281] = 1 if grav_flag else 0
		var bp: Vector3 = _here(0.0, 1400.0)
		var bv: Vector3 = Sphere.tangent_frame(bp).x * 60.0
		var rp: Vector3 = _here(200.0, 900.0)
		var rv: Vector3 = Sphere.tangent_frame(rp).y * 140.0
		var f: SnapshotFrame = SnapshotFrame.new()
		f.resize(2)
		var records: PackedInt32Array = PackedInt32Array([0, 0])
		for t: int in range(1, 61):
			bv -= bp.normalized() * (G / float(HZ))
			bp += bv / float(HZ)
			rp += rv / float(HZ)
			f.tick = t
			f.set_projectile(0, P0, SnapshotFrame.BOMB, bp, bv, 1, grav_flag, 0, 0, 1)
			f.set_projectile(1, P0 + 1, SnapshotFrame.ROCKET, rp, rv, 1, false, 0, 0, 1)
			codec.prepare_tick(f)
			var before: int = codec.n_full + codec.n_delta
			var out: Array[PackedByteArray] = []
			var _n: int = codec.encode(store, t, PackedInt32Array([PI0, PI0 + 1]), PackedInt32Array(), PackedInt32Array(), null, out)
			for p: PackedByteArray in out:
				assert_int(dec.decode(p)).is_equal(SnapshotDecoder.Status.OK)
			store.ack(t)
			records[0] += codec.n_full + codec.n_delta - before
			var fr: BaselineFrame = dec.current()
			var lv: Vector3i = fr.shown_levels(PI0, t, grav_flag, G, 1.0 / float(HZ))
			var shown: Vector3 = Codec.dequantize_pos(Codec.pack_pos(Codec.pos_cell(fr.pos[PI0]), lv.x, lv.y, lv.z))
			assert_float(shown.distance_to(bp)).override_failure_message("tick %d" % t).is_less(0.5)
			assert_bool(dec.current().same_state(store.frame_at(t))).is_true()
		var _x: bool = counts.push_back(records[0])
	print("PROJECTILE_DR records over 60 ticks: gravity=%d without=%d" % [counts[0], counts[1]])
	assert_int(counts[0]).is_less(counts[1])
	assert_int(counts[0]).is_less_equal(20)                 # of 120 entity-ticks: 2 FULLs + quantisation corrections


func test_a_new_generation_in_a_projectile_index_is_sent_full() -> void:
	var codec: SnapshotCodec = SnapshotCodec.new(G, HZ)
	var store: BaselineStore = BaselineStore.new(1)
	var lists: PackedInt32Array = PackedInt32Array([PI0 + 27])
	for t: int in range(1, 6):
		var f: SnapshotFrame = _frame(t, 0, PackedInt32Array([SnapshotFrame.ROCKET]), 1 if t < 4 else 2)
		f.set_projectile(0, P0 + 27, SnapshotFrame.ROCKET, _here(0.0, 900.0), Vector3(0, 0, 50), 1, false, 0, 0, 1 if t < 4 else 2)
		codec.prepare_tick(f)
		var full0: int = codec.n_full
		var out: Array[PackedByteArray] = []
		var _n: int = codec.encode(store, t, lists, PackedInt32Array(), PackedInt32Array(), null, out)
		store.ack(t)
		var want_full: int = 1 if t == 1 or t == 4 else 0     # the spawn, then the recycled slot's new generation
		assert_int(codec.n_full - full0).override_failure_message("tick %d" % t).is_equal(want_full)


## InterestClient: a projectile joins when tiered and leaves HOLD_TICKS (100 ms) after it leaves V (OUT_OF_VISION) or dies
## (DEATH), on any tick, with no 30 s ghost; an entity in the same situation is kept as a ghost.
func test_interest_removes_projectiles_the_tick_they_go() -> void:
	var codec: SnapshotCodec = SnapshotCodec.new(G, HZ)
	var it: Interest = Interest.new()
	var cl: InterestClient = InterestClient.new(1, 0)
	cl.possessed = 10
	var a: int = EntityId.make(10, 1)
	var c: int = EntityId.make(12, 1)
	for t: int in range(1, 13):
		var f: SnapshotFrame = SnapshotFrame.new()
		f.resize(4 if t < 6 else 3)
		f.tick = t
		f.set_entity(0, 10, _here(0.0), Vector3.ZERO, Quaternion.IDENTITY, 1.0, 0, 0, 0, false, 0)
		f.set_entity(1, 12, _here(80.0), Vector3.ZERO, Quaternion.IDENTITY, 1.0, 0, 1, 0, false, 1 if t < 4 else 0)
		f.gen[0] = 1
		f.gen[1] = 1
		f.set_projectile(2, P0 + 1, SnapshotFrame.ROCKET, _here(20.0), Vector3.ZERO, 1, false, c, c, 1)       # V via c
		if t < 6:
			f.set_projectile(3, P0 + 2, SnapshotFrame.BOMB, _here(30.0), Vector3.ZERO, 1, true, c, a, 1)      # V via a
		codec.prepare_tick(f)
		it.begin_tick(f, codec)
		it.assign(cl)
		if t == 1:
			assert_bool(cl.added.has(PI0 + 1) and cl.added.has(PI0 + 2)).is_true()
			assert_bool(cl.a.has(PI0 + 1)).is_true()
		if t == 4 + ProjectileMembers.HOLD_TICKS:            # c left V at 4: the rocket goes HOLD_TICKS later, c stays a ghost
			assert_array(Array(cl.removed)).is_equal([PI0 + 1])
			assert_array(Array(cl.removed_reason)).is_equal([Protocol.RosterRemoveReason.OUT_OF_VISION])
			assert_bool(cl.in_roster(12)).is_true()
		if t == 6 + ProjectileMembers.HOLD_TICKS:            # the bomb died at 6: DEATH HOLD_TICKS later, on any tick
			assert_array(Array(cl.removed)).is_equal([PI0 + 2])
			assert_array(Array(cl.removed_reason)).is_equal([Protocol.RosterRemoveReason.DEATH])
	assert_int(cl.roster_count()).is_equal(2)


## A projectile slot recycled across teams (0-tick quarantine, A-20): the old generation stays listed nowhere, is removed
## (DEATH) HOLD_TICKS later, and the index is held 2 x HOLD_TICKS before the new one joins (ProjectileMembers).
func test_a_recycled_projectile_index_is_held_before_it_rejoins() -> void:
	var codec: SnapshotCodec = SnapshotCodec.new(G, HZ)
	var it: Interest = Interest.new()
	var cl: InterestClient = InterestClient.new(1, 0)
	cl.possessed = 10
	var joined: int = -1
	for t: int in range(1, 12):
		var f: SnapshotFrame = SnapshotFrame.new()
		f.resize(2)
		f.tick = t
		f.set_entity(0, 10, _here(0.0), Vector3.ZERO, Quaternion.IDENTITY, 1.0, 0, 0, 0, false, 0)
		f.gen[0] = 1
		var g: int = 1 if t < 3 else 2                      # tick 3: the slot holds a team-1 rocket aimed at our unit
		f.set_projectile(1, P0 + 5, SnapshotFrame.ROCKET, _here(20.0), Vector3.ZERO, 0 if g == 1 else 1, false,
				EntityId.make(10, 1), EntityId.make(10, 1), g)
		codec.prepare_tick(f)
		it.begin_tick(f, codec)
		it.assign(cl)
		var listed: bool = cl.a.has(PI0 + 5) or cl.b.has(PI0 + 5) or cl.c.has(PI0 + 5) or cl.c_set.has(PI0 + 5)
		var h: int = ProjectileMembers.HOLD_TICKS
		if t == 3 + h:
			assert_array(Array(cl.removed)).is_equal([PI0 + 5])
			assert_array(Array(cl.removed_reason)).is_equal([Protocol.RosterRemoveReason.DEATH])
		else:
			assert_bool(cl.removed.is_empty()).is_true()
		if t >= 3 and t < 3 + 2 * h:
			assert_bool(listed or cl.added.has(PI0 + 5)).override_failure_message("tick %d" % t).is_false()
			assert_bool(cl.in_roster(PI0 + 5)).is_equal(t < 3 + h)
		if cl.added.has(PI0 + 5) and t >= 3:
			joined = t
			assert_bool(cl.a.has(PI0 + 5)).is_true()
	assert_int(joined).is_equal(3 + 2 * ProjectileMembers.HOLD_TICKS)


func _keyframe_scene() -> Array:
	var codec: SnapshotCodec = SnapshotCodec.new(G, HZ)
	var roster: Roster = Roster.new()
	for s: int in [1, 2, 3]:
		var _a: bool = roster.add(s, 1, 2, (s - 1) % 3, (s - 1) % 3)   # the frame's teams (_frame: slot i + 1, team i % 3)
	for k: int in 3:
		var _b: bool = roster.add(PI0 + 3 * k, 1, 1283, 1, 1)
	codec.prepare_tick(_frame(7, 3, PackedInt32Array([SnapshotFrame.ROCKET, SnapshotFrame.BOMB, SnapshotFrame.CANISTER])))
	return [codec, roster]


func test_keyframe_gap_chain_runs_over_sim_slots() -> void:
	var sc: Array = _keyframe_scene()
	var codec: SnapshotCodec = sc[0]
	var roster: Roster = sc[1]
	var kc: KeyframeCodec = KeyframeCodec.new()
	var server: BaselineStore = BaselineStore.new(0)
	var idx: PackedInt32Array = PackedInt32Array([1, 2, 3, PI0, PI0 + 3, PI0 + 6])
	var b: PackedByteArray = kc.encode(codec, server, 7, 1, Protocol.KeyframeScope.ALL, idx)
	var own: int = 1                                        # slot 1 is team 0
	assert_int(b.size()).is_equal(KeyframeCodec.size_for(6, own, 1))
	var at: int = KeyframeCodec.HEADER_BYTES + 3 * 19 + own
	assert_int(b[at]).is_equal(SnapshotCodec.GAP_ESCAPE)    # the jump into the block: one escape to slot 4,096
	assert_int(b.decode_u16(at + 1)).is_equal(4096)
	assert_int(b[at + 3 + 18]).is_equal(3)                  # then u8 gaps in slot space
	var dec: SnapshotDecoder = SnapshotDecoder.new(G, HZ, 0, roster)
	var kd: KeyframeCodec = KeyframeCodec.new()
	assert_int(kd.decode(b, dec)).is_equal(KeyframeCodec.Status.OK)
	assert_bool(dec.current().same_state(server.frame_at(7))).is_true()
	assert_array(kd.reencode()).is_equal(b)
	for slot: int in [1536, 3583, 4095, 6144, 0xFFFF]:      # escapes into slots no roster holds
		var m: PackedByteArray = b.duplicate()
		m.encode_u16(at + 1, slot)
		kd.forget()
		assert_int(kd.decode(m, dec)).override_failure_message("slot %d" % slot).is_equal(KeyframeCodec.Status.MALFORMED)
	var _l: bool = roster.add(Roster.CAPACITY - 1, 1, 1283, 1, 1)
	var g: PackedByteArray = b.duplicate()                  # a u8 gap that steps past the block's last slot
	g.encode_u16(at + 1, 6143)
	g[at + 3 + 18] = 1
	kd.forget()
	assert_int(kd.decode(g, dec)).is_equal(KeyframeCodec.Status.MALFORMED)


## Seeded mutation sweeps (NET-04 standard; N5 / NET-23 count): ENTITY_META and ROSTER_REMOVE seeds with projectile
## slots, NetFuzz.MUTATIONS each; KEYFRAME 20,000. Never an error; an accepted META re-encodes to the same roster, an
## accepted REMOVE names only valid slots, an accepted KEYFRAME re-encodes to the identical bytes.
func test_mutation_sweeps_with_projectile_slots_reencode_equal() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 58
	var src: Roster = _roster_with_projectiles()
	var all: PackedInt32Array = PackedInt32Array([5, 1535, PI0, PI0 + 10, Roster.CAPACITY - 1])
	var metas: Array[PackedByteArray] = []
	var _m: int = RosterCodec.encode_meta(src, all, metas)
	var rems: Array[PackedByteArray] = []
	var _r: int = RosterCodec.encode_remove(all, PackedInt32Array([0, 1, 2, 0, 1]), rems)
	var ok: Vector2i = Vector2i.ZERO
	for i: int in NetFuzz.MUTATIONS:
		var m: PackedByteArray = NetFuzz.mutate(rng, metas[0], 12)
		var dst: Roster = Roster.new()
		var got: PackedInt32Array = PackedInt32Array()
		if RosterCodec.decode_meta(m, dst, got) >= 0:
			ok.x += 1
			var again: Array[PackedByteArray] = []
			var _e: int = RosterCodec.encode_meta(dst, got, again)
			var back: Roster = Roster.new()                 # what was accepted re-encodes to the same roster
			for p: PackedByteArray in again:
				assert_int(RosterCodec.decode_meta(p, back, PackedInt32Array())).is_greater_equal(0)
			assert_int(back.state_hash()).is_equal(dst.state_hash())
		var rm: PackedByteArray = NetFuzz.mutate(rng, rems[0], 8)
		var r2: Roster = _roster_with_projectiles()
		var gone: PackedInt32Array = PackedInt32Array()
		if RosterCodec.decode_remove(rm, r2, gone) >= 0:
			ok.y += 1
			for k: int in rm[1]:
				assert_int(Roster.index_of_slot(rm.decode_u16(2 + 3 * k))).is_greater_equal(0)
	print("PROJECTILE_FUZZ meta_ok=%d remove_ok=%d of %d" % [ok.x, ok.y, NetFuzz.MUTATIONS])
	assert_int(ok.x).is_greater(100)
	assert_int(ok.y).is_greater(100)
	_keyframe_sweep(rng)


func _keyframe_sweep(rng: RandomNumberGenerator) -> void:
	var sc: Array = _keyframe_scene()
	var codec: SnapshotCodec = sc[0]
	var roster: Roster = sc[1]
	var kc: KeyframeCodec = KeyframeCodec.new()
	var good: PackedByteArray = kc.encode(codec, BaselineStore.new(0), 7, 1, Protocol.KeyframeScope.ALL,
			PackedInt32Array([1, 2, 3, PI0, PI0 + 3, PI0 + 6]))
	var dec: SnapshotDecoder = SnapshotDecoder.new(G, HZ, 0, roster)
	var accepted: int = 0
	for i: int in 20000:
		var m: PackedByteArray = NetFuzz.mutate(rng, good, 16)
		kc.forget()
		if kc.decode(m, dec) == KeyframeCodec.Status.OK:
			accepted += 1
			assert_array(kc.reencode()).is_equal(m)
	assert_int(accepted).is_greater(50)
