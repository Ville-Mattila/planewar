extends GdUnitTestSuite
## NET-61 (R0 B.31 A-152): barrel elevation replication under a random tier schedule (entities move between A, B and C
## every few ticks, crawlers slew, 3 clients, 10 % packet loss, acks of complete ticks only). Every fully received tick
## leaves the client frame identical to the server mirror (N9); a received section-A crawler holds exactly this tick's
## byte; a received B / C entry holds none; nothing else ever holds one. 20,000 mutations of a barrel-bearing packet
## (and 20,000 of a barrel-bearing KEYFRAME) never error and change nothing unless accepted. Over LocalTransport a slewing
## Crawler's NetSimView.barrel_elevation tracks LocalSimView within one quantum.

const DEF_CRAWLER: int = 4
const TICKS: int = 600
const CLIENTS: int = 3
const HI: float = PI / 4.0
const KNOWN: int = BaselineFrame.BARREL_KNOWN

var _rig: SnapRig
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _tier: PackedInt32Array = PackedInt32Array()       # per row, per client: 0 A, 1 B, 2 C (client k at k * n + i)
var _crawler: PackedByteArray = PackedByteArray()
var _hist: Array[PackedByteArray] = []


func _build(seed_value: int) -> void:
	_rng.seed = seed_value
	_rig = SnapRig.new()
	_rig.build(Vector3i(12, 14, 14), Vector3i(8, 8, 8), 2, seed_value)
	var n: int = _rig.frame.count
	var _a: int = _crawler.resize(n)
	_crawler.fill(0)
	for i: int in n:
		if _rig.kind[i] == SnapRig.Kind.STRUCTURE and i % 3 != 2:    # ground units: crawlers on the datum
			_crawler[i] = 1
			var _ok: bool = _rig.roster.add(i, 1, DEF_CRAWLER, _rig.roster.owner_of(i), _rig.roster.team_of(i))
	var _b: int = _tier.resize(n * CLIENTS)
	for j: int in _tier.size():
		_tier[j] = _rng.randi_range(0, 2)


func _decoder(team: int) -> SnapshotDecoder:
	var d: SnapshotDecoder = _rig.new_decoder(team)
	var _r: int = d.barrel_def.resize(8)
	d.barrel_def[DEF_CRAWLER] = 1
	return d


func _step() -> void:
	_rig.tick += 1
	_rig.frame.tick = _rig.tick
	_rig.step_motion()
	for i: int in _rig.frame.count:
		if _crawler[i] != 0:
			var e: float = HI * 0.5 * (1.0 + sin(float(_rig.tick) * 0.05 + float(i)))
			var hold: bool = (_rig.tick + i * 7) % 60 < 20                  # each crawler holds still a third of the time
			_rig.frame.set_barrel(i, Codec.quantize_barrel(HI * 0.25 if hold else e, 0.0, HI))
	_rig.codec.prepare_tick(_rig.frame)


func _lists(k: int, a: PackedInt32Array, b: PackedInt32Array, c: PackedInt32Array) -> void:
	a.clear()
	b.clear()
	c.clear()
	var n: int = _rig.frame.count
	for i: int in n:
		if _rng.randf() < 0.05:
			_tier[k * n + i] = _rng.randi_range(0, 2)
		var t: int = _tier[k * n + i]
		if t == 0:
			var _x: bool = a.push_back(i)
		elif t == 1 and _rng.randf() < 0.5:
			var _y: bool = b.push_back(i)
		elif t == 2 and _rng.randf() < 0.15:
			var _z: bool = c.push_back(i)


func test_random_schedule_keeps_mirrors_identical_and_barrels_tier_a_only() -> void:
	_build(61)
	var stores: Array[BaselineStore] = []
	var decs: Array[SnapshotDecoder] = []
	for k: int in CLIENTS:
		stores.append(BaselineStore.new(k))
		decs.append(_decoder(k))
	var a: PackedInt32Array = PackedInt32Array()
	var b: PackedInt32Array = PackedInt32Array()
	var c: PackedInt32Array = PackedInt32Array()
	var checked: PackedInt32Array = PackedInt32Array([0, 0, 0])    # A crawler bytes, B / C clears, complete ticks
	for _t: int in TICKS:
		_step()
		for k: int in CLIENTS:
			_lists(k, a, b, c)
			var out: Array[PackedByteArray] = []
			var _n: int = _rig.codec.encode(stores[k], _rig.tick, a, b, c, null, out)
			var all_ok: bool = true
			for p: PackedByteArray in out:
				if _rng.randf() < 0.1:
					all_ok = false
					continue
				assert_int(decs[k].decode(p)).is_equal(SnapshotDecoder.Status.OK)
			stores[k].ack(decs[k].store.complete_tick)
			if not all_ok:
				continue
			checked[2] += 1
			var f: BaselineFrame = decs[k].current()
			assert_bool(f.same_state(stores[k].frame_at(_rig.tick))).is_true()
			for i: int in _rig.frame.count:
				if _crawler[i] == 0:
					assert_int(f.barrel[i]).is_equal(0)
				elif a.has(i):
					assert_int(f.barrel[i]).is_equal(_rig.codec.c_barrel[i])
					checked[0] += 1
				elif b.has(i) or c.has(i):
					assert_int(f.barrel[i]).is_equal(0)
					checked[1] += 1
	assert_int(checked[0]).is_greater(1000)
	assert_int(checked[1]).is_greater(200)
	assert_int(checked[2]).is_greater(TICKS)


## Tick 40 of client 0 (packet index 0, undecoded) after ticks 1-39 were decoded and acked; `_hist` keeps them.
func _barrel_packet() -> PackedByteArray:
	_build(7)
	_hist.clear()
	var store: BaselineStore = BaselineStore.new(0)
	var dec: SnapshotDecoder = _decoder(0)
	var a: PackedInt32Array = PackedInt32Array()
	var b: PackedInt32Array = PackedInt32Array()
	var c: PackedInt32Array = PackedInt32Array()
	for _t: int in 40:
		_step()
		_lists(0, a, b, c)
		var out: Array[PackedByteArray] = []
		var _n: int = _rig.codec.encode(store, _rig.tick, a, b, c, null, out)
		if _rig.tick == 40:
			return out[0]
		for p: PackedByteArray in out:
			_hist.append(p)
			var _s: int = dec.decode(p)
		store.ack(dec.store.complete_tick)
	return PackedByteArray()


func _replayed() -> SnapshotDecoder:
	var d: SnapshotDecoder = _decoder(0)
	for p: PackedByteArray in _hist:
		var _s: int = d.decode(p)
	return d


func test_random_mutations_of_a_barrel_packet_never_error() -> void:
	var pkt: PackedByteArray = _barrel_packet()
	var bars: int = 0
	for at: int in range(SnapshotCodec.HEADER_BYTES, pkt.size()):
		bars += 1 if pkt[at] == SnapshotCodec.MASK_BARREL else 0
	assert_int(bars).is_greater(0)                                   # at least one barrel-only A-DELTA
	var dec: SnapshotDecoder = _replayed()
	assert_int(_replayed().decode(pkt)).is_equal(SnapshotDecoder.Status.OK)
	var counts: PackedInt32Array = PackedInt32Array([0, 0, 0, 0, 0])
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 6161
	for i: int in 20000:
		var p: PackedByteArray = _mutate(pkt, rng, i % 4)
		var before: int = dec.current().state_hash()
		var newest: int = dec.store.newest_tick
		var st: int = dec.decode(p)
		assert_bool(st >= 0 and st <= SnapshotDecoder.Status.MISSING_ROSTER).is_true()
		counts[st] += 1
		if st != SnapshotDecoder.Status.OK:
			assert_int(dec.store.newest_tick).is_equal(newest)
			assert_int(dec.current().state_hash()).is_equal(before)
		else:
			dec = _replayed()
	assert_int(counts[SnapshotDecoder.Status.MALFORMED]).is_greater(1000)
	assert_int(counts[SnapshotDecoder.Status.OK]).is_greater(1000)
	print("BARREL_MUTATIONS ok=%d malformed=%d stale=%d no_baseline=%d missing=%d" % [counts[0], counts[1], counts[2], counts[3], counts[4]])


func test_random_mutations_of_a_barrel_keyframe_never_error() -> void:
	_build(9)
	_step()
	var all: PackedInt32Array = PackedInt32Array()
	for i: int in _rig.frame.count:
		var _p: bool = all.push_back(i)
	var msg: PackedByteArray = KeyframeCodec.new().encode(_rig.codec, BaselineStore.new(0), _rig.tick, 1, Protocol.KeyframeScope.ALL, all)
	assert_int(msg.size()).is_greater(KeyframeCodec.HEADER_BYTES)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 616
	var ok: int = 0
	var dec: SnapshotDecoder = _decoder(0)
	var kc: KeyframeCodec = KeyframeCodec.new()
	for i: int in 20000:
		var st: int = kc.decode(_mutate(msg, rng, i % 4), dec)
		assert_bool(st >= 0 and st <= KeyframeCodec.Status.MISSING_ROSTER).is_true()
		if st == KeyframeCodec.Status.OK:
			ok += 1
			dec.reset()
			kc.forget()
		else:
			assert_object(dec.current()).is_null()
	assert_int(ok).is_greater(100)


static func _mutate(src: PackedByteArray, rng: RandomNumberGenerator, kind: int) -> PackedByteArray:
	var p: PackedByteArray = src.duplicate()
	if kind == 0:
		for _k: int in rng.randi_range(1, 4):
			var at: int = rng.randi_range(9, p.size() - 1)
			p[at] = p[at] ^ (1 << rng.randi_range(0, 7))
	elif kind == 1:
		p = p.slice(0, rng.randi_range(0, p.size()))
	elif kind == 2:
		p[rng.randi_range(SnapshotCodec.HEADER_BYTES, p.size() - 1)] = rng.randi_range(0, 255)
	else:
		var _ins: int = p.insert(rng.randi_range(0, p.size()), rng.randi_range(0, 255))
	return p


## End to end over LocalTransport (NetViewRig, 04 s5.6): a slewing, then lowering Crawler stays within one barrel quantum
## of LocalSimView on every tick the client holds a tier-A value.
func test_a_slewing_crawler_tracks_the_sim_within_one_quantum_over_local_transport() -> void:
	var w: SimWorld = WorldTestKit.world()
	var id: int = BarrelTestKit.crawler(w)
	var p: BarrelTestKit.Pilot = BarrelTestKit.pilot(w, id, false)
	var rig: NetViewRig = NetViewRig.new(w, WorldTestKit.content())
	var cs: ClientSession = rig.add_client(0, 0)
	rig.pump(4)
	var quantum: float = deg_to_rad(45.0) / 255.0
	var local: SimView = w.view()
	var checked: int = 0
	var peak: float = 0.0
	for t: int in 90:
		p.input.pitch = 1.0 if t < 60 else -0.5
		p.tick(w)
		rig.send_tick(w.tick())
		rig.pump(1)
		var v: NetSimView = cs.view()
		v.sample(float(w.tick()))
		if v.alive(id) and not v.field_unknown(id, &"barrel_elevation"):
			assert_float(absf(v.barrel_elevation(id) - local.barrel_elevation(id))).is_less_equal(quantum)
			checked += 1
		peak = maxf(peak, local.barrel_elevation(id))
	assert_int(checked).is_greater(80)
	assert_float(peak).is_greater(deg_to_rad(15.0))
