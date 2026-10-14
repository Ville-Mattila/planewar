extends GdUnitTestSuite
## NET-08 integration: real Interest over the shared SnapshotCodec cache for 4 clients on a 460-entity scene with
## teams that do not see each other everywhere. Each client gets its ENTITY_META / ROSTER_REMOVE through
## RosterCodec before its snapshot packets, decodes with its own roster (never MISSING_ROSTER), its mirror equals
## the server's, tier caps hold, no record names an entity its team cannot see, and the bytes stay under 30 KB/s.

const CLIENTS: int = 4
const TICKS: int = 300
const OVERHEAD: int = 38                                    # UDP 8 + IPv4 20 + ENet 10 (04 s4.6)

var _rig: InterestRig


func before_test() -> void:
	_rig = InterestRig.new()
	_rig.build(CLIENTS, Vector3i(40, 120, 300), Vector3i(24, 50, 120), 4, 33)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 12
	for i: int in _rig.snap.frame.count:                    # each entity seen by its own team plus a random other
		_rig.snap.frame.visible_mask[i] = 1 << (rng.randi() % 3)


func test_meta_before_records_caps_visibility_and_bandwidth() -> void:
	var decs: Array[SnapshotDecoder] = []
	var client_rosters: Array[Roster] = []
	for k: int in CLIENTS:
		client_rosters.append(Roster.new())
		var d: SnapshotDecoder = SnapshotDecoder.new(SnapRig.G, SnapRig.HZ, _rig.clients[k].team, client_rosters[k])
		var _r: int = d.gravity_def.resize(4)
		d.gravity_def[SnapRig.DEF_BOMB] = 1
		decs.append(d)
	var bytes: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])
	var packets: int = 0
	var sizes: Vector3i = Vector3i.ZERO
	var got: PackedInt32Array = PackedInt32Array()
	for t: int in TICKS:
		_rig.step_scene()
		_rig.run_interest()
		for k: int in CLIENTS:
			var cl: InterestClient = _rig.clients[k]
			assert_int(cl.a.size()).is_less_equal(InterestClient.A_CAP)
			assert_int(cl.b.size()).is_less_equal(InterestClient.B_CAP)
			assert_int(cl.c.size()).is_less_equal(InterestClient.C_CAP)
			sizes += Vector3i(cl.a.size(), cl.b.size(), cl.c.size())
			var reliable: Array[PackedByteArray] = []
			_rig.roster_packets(k, reliable)
			for p: PackedByteArray in reliable:
				var n: int = RosterCodec.decode_meta(p, client_rosters[k], got) if p[0] == Protocol.ENTITY_META \
						else RosterCodec.decode_remove(p, client_rosters[k], got)
				assert_int(n).is_greater(0)
				bytes[k] += p.size() if t >= 30 else 0
			var out: Array[PackedByteArray] = []
			var _n: int = _rig.encode(k, out)
			for p: PackedByteArray in out:
				assert_int(p.size()).is_less_equal(Protocol.MAX_UNRELIABLE_BYTES)
				assert_int(decs[k].decode(p)).is_equal(SnapshotDecoder.Status.OK)
				bytes[k] += p.size() + OVERHEAD if t >= 30 else 0
				packets += 1
			_check_visible(k)
			_rig.stores[k].ack(decs[k].store.complete_tick)
			assert_int(client_rosters[k].state_hash()).is_equal(_rig.rosters[k].state_hash())
	for k: int in CLIENTS:
		var cur: BaselineFrame = decs[k].store.frame_at(decs[k].store.complete_tick)
		assert_bool(cur.same_state(_rig.stores[k].frame_at(decs[k].store.complete_tick))).is_true()
		var bps: float = bytes[k] / ((TICKS - 30) / float(SnapRig.HZ))
		print("INTEREST_CODEC client=%d link_Bps=%d roster=%d" % [k, int(bps), _rig.clients[k].roster_count()])
		assert_float(bps).is_less(30000.0)
	var per: Vector3 = Vector3(sizes) / float(TICKS * CLIENTS)
	print("INTEREST_CODEC mean list sizes per tick a=%.1f b=%.1f c=%.1f packets=%d" % [per.x, per.y, per.z, packets])
	assert_float(per.x).is_greater(5.0)
	assert_float(per.y).is_greater(5.0)


## Every entity in this tick's lists is visible to the client's team (E1-style leak check on the snapshot path).
func _check_visible(k: int) -> void:
	var cl: InterestClient = _rig.clients[k]
	var all: PackedInt32Array = cl.a + cl.b + cl.c
	var uniq: PackedInt32Array = all.duplicate()
	uniq.sort()
	for i: int in range(1, uniq.size()):
		assert_int(uniq[i]).override_failure_message("slot in two tiers").is_not_equal(uniq[i - 1])
	for list: PackedInt32Array in [cl.a, cl.b, cl.c, _rig.refresh]:
		for s: int in list:
			assert_bool(_rig.interest.visible(s, cl.team)).override_failure_message("slot %d team %d" % [s, cl.team]).is_true()
			assert_bool(_rig.rosters[k].has(s)).is_true()
