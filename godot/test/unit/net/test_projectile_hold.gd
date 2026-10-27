extends GdUnitTestSuite
## NET-58 (R0 B.22 A-112) interest hold and KEYFRAME cap: projectile members leave the roster HOLD_TICKS after they fail
## (no 30 s ghost); a recycled projectile index (0-tick quarantine, A-20) is neither listed nor admitted until HOLD_TICKS
## after the old entry's ROSTER_REMOVE, whatever the old member's first failure was (review round 2); one KEYFRAME encode
## writes at most RECORDS_MAX records.

const G: float = 6.0
const HZ: int = 30
const P0: int = EntityId.PROJECTILE_SLOT_MIN
const PI0: int = Roster.PROJECTILE_INDEX_MIN


func _here(east_m: float = 0.0, alt: float = 800.0) -> Vector3:
	var c: Vector3 = Sphere.from_lat_lon(0.31, 1.17, Sphere.PLANET_RADIUS + alt)
	return c + Sphere.tangent_frame(c).x * east_m


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


## Review round 2: a member that first fails for another reason (OUT_OF_VISION, LEFT_INTEREST) and then dies within the
## hold, its slot recycled to another team's projectile, is still held: the old entry is removed (DEATH) HOLD_TICKS after
## the first failure, and the new generation is neither listed nor admitted until HOLD_TICKS after that REMOVE.
func test_out_of_vision_then_recycled_is_held() -> void:
	_recycle_after_failure(false)


func test_left_interest_then_recycled_is_held() -> void:
	_recycle_after_failure(true)


func _recycle_after_failure(left_interest: bool) -> void:
	var codec: SnapshotCodec = SnapshotCodec.new(G, HZ)
	var it: Interest = Interest.new()
	var cl: InterestClient = InterestClient.new(1, 0)
	cl.possessed = 10
	var h: int = ProjectileMembers.HOLD_TICKS
	var fail_at: int = 2 + InterestClient.GHOST_TICKS if left_interest else 3   # first tick the old member fails
	var recycle_at: int = fail_at + 1                       # dies and is recycled inside the hold
	var a: int = EntityId.make(10, 1)
	var c: int = EntityId.make(12, 1)
	var removed_at: int = -1
	var joined: int = -1
	for t: int in range(1, recycle_at + 3 * h + 2):
		if left_interest:                                   # tiered once, then untiered (caps 0) until the recycle
			var cap: int = 0 if t > 1 and t < recycle_at else 40
			cl.a_cap = cap
			cl.b_cap = cap
			cl.c_cap = cap
		var f: SnapshotFrame = SnapshotFrame.new()
		f.resize(3)
		f.tick = t
		f.set_entity(0, 10, _here(0.0), Vector3.ZERO, Quaternion.IDENTITY, 1.0, 0, 0, 0, false, 0)
		f.set_entity(1, 12, _here(80.0), Vector3.ZERO, Quaternion.IDENTITY, 1.0, 0, 1, 0, false, 1 if left_interest or t < 3 else 0)
		f.gen[0] = 1
		f.gen[1] = 1
		if t < recycle_at:                                  # team-1 rocket, in V through c (OUT_OF_VISION case: c leaves V at 3)
			f.set_projectile(2, P0 + 5, SnapshotFrame.ROCKET, _here(20.0), Vector3.ZERO, 1, false, c, c, 1)
		else:                                               # recycled: a team-2 rocket aimed at our unit (in V via its target)
			f.set_projectile(2, P0 + 5, SnapshotFrame.ROCKET, _here(20.0), Vector3.ZERO, 2, false, 0, a, 2)
		codec.prepare_tick(f)
		it.begin_tick(f, codec)
		it.assign(cl)
		var listed: bool = cl.a.has(PI0 + 5) or cl.b.has(PI0 + 5) or cl.c.has(PI0 + 5) or cl.c_set.has(PI0 + 5)
		if t == 1:
			assert_bool(cl.added.has(PI0 + 5)).is_true()
		if cl.removed.has(PI0 + 5):
			assert_int(removed_at).override_failure_message("removed twice").is_equal(-1)
			removed_at = t
			assert_int(cl.removed_reason[cl.removed.find(PI0 + 5)]).is_equal(Protocol.RosterRemoveReason.DEATH)
		if t > 1 and cl.added.has(PI0 + 5):
			joined = t if joined < 0 else joined
		if t >= recycle_at and joined < 0:
			assert_bool(listed).override_failure_message("listed during the hold at %d" % t).is_false()
	assert_int(removed_at).is_equal(fail_at + h)
	assert_int(joined).is_equal(removed_at + h)


## KEYFRAME encodes at most RECORDS_MAX records (the message stays <= Protocol.MAX_RELIABLE_BYTES even at the worst record
## size) over a cache holding more: every entity slot plus 1,500 projectile entities; the mirror equals the decode.
func test_keyframe_caps_the_records_of_one_encode() -> void:
	var codec: SnapshotCodec = SnapshotCodec.new(G, HZ)
	var roster: Roster = Roster.new()
	var f: SnapshotFrame = SnapshotFrame.new()
	var n_ent: int = Roster.ENTITY_SLOTS - 1
	f.resize(n_ent + 1500)
	f.tick = 4
	var idx: PackedInt32Array = PackedInt32Array()
	for i: int in n_ent:
		f.set_entity(i, i + 1, _here(3.0 * i), Vector3.ZERO, Quaternion.IDENTITY, 1.0, 0, 0, 0, false, 0)   # own team: +ai_tag
		var _a: bool = roster.add(i + 1, 1, 2, 0, 0)
		var _b: bool = idx.push_back(i + 1)
	for k: int in 1500:
		f.set_projectile(n_ent + k, P0 + k, SnapshotFrame.ROCKET, _here(2.0 * k, 900.0), Vector3.ZERO, 0, false, 0, 0, 1)
		var _c: bool = roster.add(PI0 + k, 1, 1283, 0, 0)
		var _d: bool = idx.push_back(PI0 + k)
	codec.prepare_tick(f)
	assert_int(idx.size()).is_greater(KeyframeCodec.RECORDS_MAX)
	var kc: KeyframeCodec = KeyframeCodec.new()
	var server: BaselineStore = BaselineStore.new(0)
	var b: PackedByteArray = kc.encode(codec, server, 4, 1, Protocol.KeyframeScope.ALL, idx)
	assert_int(kc.count).is_equal(KeyframeCodec.RECORDS_MAX)
	assert_int(b.size()).is_less_equal(Protocol.MAX_RELIABLE_BYTES)
	assert_int(KeyframeCodec.HEADER_BYTES + KeyframeCodec.RECORDS_MAX * KeyframeCodec.RECORD_WORST_BYTES).is_less_equal(Protocol.MAX_RELIABLE_BYTES)
	var dec: SnapshotDecoder = SnapshotDecoder.new(G, HZ, 0, roster)
	assert_int(KeyframeCodec.new().decode(b, dec)).is_equal(KeyframeCodec.Status.OK)
	assert_bool(dec.current().same_state(server.frame_at(4))).is_true()
