extends GdUnitTestSuite
## TA-21 S4 with every subsystem active (ADR-10): ships on autopilot and possessed holding the fire buttons, ground
## units with orders, structures with towers firing, pending commands, control requests, vision passes and a brain
## stub driving Pathing through the sink. serialize() -> deserialize() -> step() equals step() on the original, byte
## for byte, over 1,000 random ticks (the world is re-restored every RESYNC_EVERY ticks); then the format policy
## (version refusal, truncation, trailing garbage, corruption), the size report and determinism of the bytes.

const TICKS: int = 1000
const RESYNC_EVERY: int = 40
const MAP: StringName = &"tiny_test"


func _put(w: SimWorld, def: StringName, owner: int, team: int, alt: float, east: float, v: Vector3) -> int:
	var p: Vector3 = WorldTestKit.at(alt, east)
	if alt <= 0.0:
		p = p.normalized() * (Sphere.PLANET_RADIUS + w.terrain().height_at(p.normalized()) + 2.0)
	return WorldTestKit.spawn(w, def, owner, team, p, v)


# Darts of players 0 and 1 over enemy towers, ground units of both, structures; returns the controllable ids.
func _populate(w: SimWorld) -> PackedInt32Array:
	var ids: PackedInt32Array = PackedInt32Array()
	for k: int in 10:
		var o: int = k % 3
		ids.push_back(_put(w, &"dart", o, 1 if o == 1 else 0, 120.0 + 25.0 * k, -500.0 + 110.0 * k, Vector3(-4.0 * k, 55.0, 0.0)))
	ids.push_back(_put(w, &"lancer", 0, 0, 200.0, 0.0, Vector3(0, 50.0, 0)))
	ids.push_back(_put(w, &"harvester", 0, 0, 0.0, -300.0, Vector3.ZERO))
	ids.push_back(_put(w, &"siege_crawler", 1, 1, 0.0, 300.0, Vector3.ZERO))
	for k: int in 4:
		var d: StringName = [&"autocannon_turret", &"flak_battery", &"pad", &"relay_pylon"][k]
		var _s: int = _put(w, d, 1 if k % 2 == 0 else 0, 1 if k % 2 == 0 else 0, 0.0, -200.0 + 150.0 * k, Vector3.ZERO)
	return ids


func _random_tick(ws: Array[SimWorld], rng: RandomNumberGenerator, ids: PackedInt32Array) -> void:
	var cmds: Array[Command] = []
	var id: int = ids[rng.randi_range(0, ids.size() - 1)]
	var player: int = rng.randi_range(0, 2)
	match rng.randi_range(0, 11):
		0:
			cmds.append(Command.possess(player, id))
		1:
			cmds.append(Command.release(player))
		2, 3, 4:
			var inp: PilotInput = PilotInput.new()
			inp.thrust = rng.randf()
			inp.pitch = rng.randf_range(-1.0, 1.0)
			inp.roll = rng.randf_range(-1.0, 1.0)
			inp.buttons = (PilotInput.FIRE1 | (PilotInput.FIRE2 if rng.randf() < 0.3 else 0)) if rng.randf() < 0.7 else 0
			cmds.append(Command.pilot(player, 0, inp))
		5, 6:
			var p: Vector3 = WorldTestKit.at(rng.randf_range(60.0, 700.0), rng.randf_range(-700.0, 700.0))
			cmds.append(Command.order(player, PackedInt32Array([id]), OrderSpec.make(OrderSpec.Kind.MOVE, 0, p)))
		7:
			cmds.append(CommandPayload.debug_spawn(0, WorldTestKit.def_id(&"dart"), player, 1 if player == 1 else 0,
				WorldTestKit.at(rng.randf_range(80.0, 800.0), rng.randf_range(-800.0, 800.0)),
				Vector3(rng.randf_range(-20.0, 20.0), rng.randf_range(-70.0, 70.0), 0.0), Vector3(0, 1, 0)))
		8:
			cmds.append(CommandPayload.debug_set(0, id, CommandPayload.SET_FUEL, rng.randf_range(0.0, 60.0)))
		9:
			cmds.append(Command.set_adjutant(player, rng.randf() < 0.5, 0, 0))
		10:
			if rng.randf() < 0.05:
				cmds.append(CommandPayload.debug_set(0, id, CommandPayload.SET_KILL, 0.0))
	for w: SimWorld in ws:
		for c: Command in cmds:
			var _r: CommandResult = w.apply_command(c)


func _events_bytes(events: Array[SimEvent]) -> PackedByteArray:
	var b: StreamPeerBuffer = StreamPeerBuffer.new()
	for e: SimEvent in events:
		b.put_var([e.kind, e.tick, e.a, e.b, e.pos, e.value, e.team, e.extra])
	return b.data_array


func _brain(w: SimWorld) -> PathBrainStub:
	var h: PathBrainStub = PathBrainStub.new()
	w.set_ai_hook(h)
	return h


func _mask_of(id: StringName) -> int:
	for g: GroundUnitDef in WorldTestKit.content().ground_units:
		if g.id == id:
			return Pathing.mask_for(g.max_slope_deg)
	return 0


func test_s4_all_subsystems_1000_random_ticks() -> void:
	var a: SimWorld = WorldTestKit.world(61, null, MAP)
	var hook_a: PathBrainStub = _brain(a)
	var ids: PackedInt32Array = _populate(a)
	hook_a.populate(hook_a.seen, Vector3(1.0, 0.2, 0.1).normalized(), 10, 6, _mask_of(&"harvester"), _mask_of(&"siege_crawler"))
	var b: SimWorld = SimWorld.deserialize(a.serialize(), WorldTestKit.content(), PathBrainStub.new())
	assert_object(b).is_not_null()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 2121
	var events: int = 0
	var shots: int = 0
	var seen_bits: int = 0
	var ordered: int = 0
	for t: int in TICKS:
		if t % RESYNC_EVERY == RESYNC_EVERY - 1:
			var bytes: PackedByteArray = a.serialize()
			b = SimWorld.deserialize(bytes, WorldTestKit.content(), PathBrainStub.new())
			assert_object(b).is_not_null()
			assert_bool(b.serialize() == bytes).is_true()
		_random_tick([a, b] as Array[SimWorld], rng, ids)
		a.step()
		b.step()
		var ea: Array[SimEvent] = a.drain_events()
		events += ea.size()
		assert_bool(_events_bytes(ea) == _events_bytes(b.drain_events())).is_true()
		if a.serialize() != b.serialize():
			fail("S4 divergence at tick %d" % a.tick())
			return
		shots = maxi(shots, a.projectiles().live_count())
		var st: EntityStore = a.store()
		for s: int in st.ships:
			seen_bits |= st.visible_mask[s]
			ordered += 1 if st.order_kind[s] != EntityStore.NONE_U8 else 0
	assert_int(events).is_greater(100)
	assert_int(shots).is_greater(0)                        # Combat spawned projectiles (fire state exercised)
	assert_int(seen_bits).is_greater(0)                    # Vision wrote interest bits
	assert_int(ordered).is_greater(0)                      # orders were live
	assert_int(hook_a.done_count()).is_greater(20)         # pathing tickets finished; hook bytes round-tripped
	assert_bool(SimWorld.deserialize(a.serialize(), WorldTestKit.content(), null) != null).is_true()


func test_format_header_and_version_refusal() -> void:
	var a: SimWorld = WorldTestKit.world()
	var bytes: PackedByteArray = a.serialize()
	assert_int(SimSerialize.check(bytes)).is_equal(SimSerialize.Status.OK)
	assert_int(bytes.decode_u32(4)).is_equal(SimSerialize.FORMAT)
	assert_object(SimWorld.deserialize(bytes, WorldTestKit.content(), null)).is_not_null()
	var older: PackedByteArray = bytes.duplicate()
	older.encode_u32(4, SimSerialize.FORMAT - 1)
	assert_int(SimSerialize.check(older)).is_equal(SimSerialize.Status.OLD_FORMAT)
	assert_object(SimWorld.deserialize(older, WorldTestKit.content(), null)).is_null()
	var newer: PackedByteArray = bytes.duplicate()
	newer.encode_u32(4, SimSerialize.FORMAT + 1)
	assert_int(SimSerialize.check(newer)).is_equal(SimSerialize.Status.NEWER_FORMAT)
	assert_object(SimWorld.deserialize(newer, WorldTestKit.content(), null)).is_null()
	var foreign: PackedByteArray = bytes.duplicate()
	foreign.encode_u32(0, 0x12345678)
	assert_int(SimSerialize.check(foreign)).is_equal(SimSerialize.Status.BAD_MAGIC)
	assert_int(SimSerialize.check(bytes.slice(0, 7))).is_equal(SimSerialize.Status.TOO_SHORT)
	assert_int(SimSerialize.check(PackedByteArray())).is_equal(SimSerialize.Status.TOO_SHORT)

	assert_int(bytes.size()).is_greater(SimSerialize.HEADER_BYTES)
	assert_int(SimSerialize.HEADER_BYTES).is_equal(12 + 2 * SimSerialize.HASH_BYTES)


func test_content_hash_in_header_and_mismatch_refusal() -> void:
	var c: ContentSet = WorldTestKit.content()
	assert_int(c.content_hash.size()).is_equal(SimSerialize.HASH_BYTES)
	var bytes: PackedByteArray = WorldTestKit.world().serialize()
	assert_array(bytes.slice(12 + SimSerialize.HASH_BYTES, SimSerialize.HEADER_BYTES)).is_equal(c.content_hash)
	assert_int(SimSerialize.check_content(bytes, c)).is_equal(SimSerialize.Status.OK)
	var other: ContentSet = ContentSet.new()
	other.content_hash = c.content_hash.duplicate()
	other.content_hash[0] ^= 1
	assert_int(SimSerialize.check_content(bytes, other)).is_equal(SimSerialize.Status.CONTENT_MISMATCH)
	assert_object(SimWorld.deserialize(bytes, other, null)).is_null()
	assert_object(SimWorld.deserialize(bytes, c, null)).is_not_null()


# A file with `raw` as its body and the header (hash included) of `bytes`: a body changed behind the checksum.
func _file_with_raw(bytes: PackedByteArray, raw: PackedByteArray) -> PackedByteArray:
	var out: PackedByteArray = bytes.slice(0, SimSerialize.HEADER_BYTES)
	out.encode_u32(8, raw.size())
	out.append_array(raw.compress(SimSerialize.COMPRESSION))
	return out


func test_truncated_and_resized_bytes_give_null() -> void:
	var a: SimWorld = WorldTestKit.world(3, null, MAP)
	var _id: int = _put(a, &"dart", 0, 0, 300.0, 0.0, Vector3(0, 40.0, 0))
	var bytes: PackedByteArray = a.serialize()
	var c: ContentSet = WorldTestKit.content()
	for cut: int in [SimSerialize.HEADER_BYTES, SimSerialize.HEADER_BYTES + 1, bytes.size() / 2, bytes.size() - 1]:
		assert_object(SimWorld.deserialize(bytes.slice(0, cut), c, null)).is_null()
	var wrong: PackedByteArray = bytes.duplicate()
	wrong.encode_u32(8, bytes.decode_u32(8) + 5)
	assert_object(SimWorld.deserialize(wrong, c, null)).is_null()
	assert_object(SimWorld.deserialize(bytes, c, null)).is_not_null()


func test_declared_size_is_capped_before_allocation() -> void:
	var bytes: PackedByteArray = WorldTestKit.world().serialize()
	var tiny: PackedByteArray = bytes.slice(0, SimSerialize.HEADER_BYTES + 1)
	tiny.encode_u32(8, SimSerialize.MAX_RAW_BYTES)
	assert_int(SimSerialize.unpack(tiny).size()).is_equal(0)
	tiny.encode_u32(8, SimSerialize.MAX_RAW_BYTES + 1)
	assert_int(SimSerialize.unpack(tiny).size()).is_equal(0)


func test_any_flipped_byte_is_refused() -> void:
	var a: SimWorld = WorldTestKit.world(3, null, MAP)
	var _ids: PackedInt32Array = _populate(a)
	var bytes: PackedByteArray = a.serialize()
	var c: ContentSet = WorldTestKit.content()
	var raw: PackedByteArray = SimSerialize.unpack(bytes)
	var offsets: Array[int] = [10, 100, 1000, raw.size() / 3, raw.size() / 2, raw.size() - 2]
	for off: int in offsets:               # inside the raw body, behind the checksum
		var bad: PackedByteArray = raw.duplicate()
		bad[off] ^= 0x10
		assert_object(SimWorld.deserialize(_file_with_raw(bytes, bad), c, null)).override_failure_message("raw byte %d" % off).is_null()
	for off: int in [SimSerialize.HEADER_BYTES + 3, bytes.size() / 2, bytes.size() - 1]:   # inside the zstd frame
		var bad2: PackedByteArray = bytes.duplicate()
		bad2[off] ^= 0x01
		assert_object(SimWorld.deserialize(bad2, c, null)).override_failure_message("file byte %d" % off).is_null()
	for off: int in [12, 27, 43]:          # inside the stored hash
		var bad3: PackedByteArray = bytes.duplicate()
		bad3[off] ^= 0x80
		assert_object(SimWorld.deserialize(bad3, c, null)).override_failure_message("hash byte %d" % off).is_null()
	assert_object(SimWorld.deserialize(bytes, c, null)).is_not_null()


func test_refused_read_leaves_the_hook_untouched() -> void:
	var a: SimWorld = WorldTestKit.world(3, null, MAP)
	a.set_ai_hook(WorldTestKit.RecordingHook.new())
	var raw: PackedByteArray = SimSerialize.write_raw(a)
	var hook: WorldTestKit.RecordingHook = WorldTestKit.RecordingHook.new()
	hook.counter = 99
	var c: ContentSet = WorldTestKit.content()
	raw.append(7)                                          # trailing byte, valid checksum
	assert_object(SimWorld.deserialize(SimSerialize.pack(raw, c.content_hash), c, hook)).is_null()
	assert_int(hook.counter).is_equal(99)
	assert_object(SimWorld.deserialize(SimSerialize.pack(SimSerialize.write_raw(a), c.content_hash), c, hook)).is_not_null()
	assert_int(hook.counter).is_equal(0)


func test_out_of_range_state_is_refused_behind_a_valid_checksum() -> void:
	var c: ContentSet = WorldTestKit.content()
	var a: SimWorld = WorldTestKit.world(3, null, MAP)
	a._rules.tick_hz = 0
	assert_object(SimWorld.deserialize(a.serialize(), c, null)).is_null()
	var b: SimWorld = WorldTestKit.world(3, null, MAP)
	b._state.tick = -5
	assert_object(SimWorld.deserialize(b.serialize(), c, null)).is_null()
	var d: SimWorld = WorldTestKit.world(3, null, MAP)
	d.store()._free_n[0] = 100000
	assert_object(SimWorld.deserialize(d.serialize(), c, null)).is_null()
	var e: SimWorld = WorldTestKit.world(3, null, MAP)
	e.store().ships.push_back(EntityStore.SLOT_COUNT + 4)
	assert_object(SimWorld.deserialize(e.serialize(), c, null)).is_null()
	var f: SimWorld = WorldTestKit.world(3, null, MAP)
	f.projectiles()._q_head = ProjectileStore.SLOT_COUNT + 1
	assert_object(SimWorld.deserialize(f.serialize(), c, null)).is_null()
	var g: SimWorld = WorldTestKit.world(3, null, MAP)
	var _ok: bool = g.store().team.resize(10)
	assert_object(SimWorld.deserialize(g.serialize(), c, null)).is_null()


func test_size_report_sections_sum_to_the_raw_body() -> void:
	var a: SimWorld = WorldTestKit.world(3, null, MAP)
	var _ids: PackedInt32Array = _populate(a)
	var rep: PackedInt32Array = SimSerialize.size_report(a)
	assert_int(rep.size()).is_equal(SimSerialize.SECTIONS.size())
	var total: int = 0
	for n: int in rep:
		assert_int(n).is_greater(0)
		total += n
	assert_int(total).is_equal(SimSerialize.write_raw(a).size())
	assert_int(SimSerialize.unpack(a.serialize()).size()).is_equal(total)
	assert_int(a.serialize().size()).is_less(total)         # the packed arrays compress


func test_same_inputs_give_identical_bytes_across_worlds() -> void:
	var out: Array[PackedByteArray] = []
	for _i: int in 2:
		var w: SimWorld = WorldTestKit.world(17, null, MAP)
		var hook: PathBrainStub = _brain(w)
		var ids: PackedInt32Array = _populate(w)
		hook.populate(hook.seen, Vector3(1.0, 0.2, 0.1).normalized(), 4, 2, _mask_of(&"harvester"), _mask_of(&"siege_crawler"))
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.seed = 5
		for _t: int in 150:
			_random_tick([w] as Array[SimWorld], rng, ids)
			w.step()
			var _e: Array[SimEvent] = w.drain_events()
		out.append(w.serialize())
	assert_bool(out[0] == out[1]).is_true()


func test_vision_pass_clock_survives_a_save() -> void:
	var a: SimWorld = WorldTestKit.world(3, null, MAP)
	var _ids: PackedInt32Array = _populate(a)
	for _t: int in 12:
		a.step()
	assert_int(a.vision.last_pass[0]).is_greater(0)
	var b: SimWorld = SimWorld.deserialize(a.serialize(), WorldTestKit.content(), null)
	assert_array(b.vision.last_pass).is_equal(a.vision.last_pass)


func test_build_state_round_trip() -> void:
	var content: ContentSet = WorldTestKit.content()
	var defs: WorldDefs = WorldDefs.new(content)
	var store: EntityStore = EntityStore.new()
	var players: PlayerTable = PlayerTable.new()
	var terrain: Terrain = Terrain.new()
	var a: Build = Build.new(defs, store, players, terrain, WorldTestKit.rules())
	a.grid.occupy(PackedInt32Array([5, 99, 4000]))
	a.grid.mark_node(77, true)
	a.spent_ore[1] = 300
	a.delivered_ore[2] = 45
	a.set_clock(321)
	var buf: StreamPeerBuffer = StreamPeerBuffer.new()
	a.write_state(buf)
	var b: Build = Build.new(defs, store, players, terrain, WorldTestKit.rules())
	var rd: StreamPeerBuffer = StreamPeerBuffer.new()
	rd.data_array = buf.data_array
	assert_bool(b.read_state(rd)).is_true()
	assert_int(b.grid.flags_of(99)).is_equal(BuildGrid.OCCUPIED)
	assert_int(b.grid.flags_of(77)).is_equal(BuildGrid.NODE | BuildGrid.COLD_TRAP)
	assert_int(b.spent_ore[1]).is_equal(300)
	assert_int(b.delivered_ore[2]).is_equal(45)
	var again: StreamPeerBuffer = StreamPeerBuffer.new()
	b.write_state(again)
	assert_bool(again.data_array == buf.data_array).is_true()
	var short: StreamPeerBuffer = StreamPeerBuffer.new()
	short.data_array = PackedByteArray()
	assert_bool(b.read_state(short)).is_false()
