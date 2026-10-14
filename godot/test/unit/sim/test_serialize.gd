extends GdUnitTestSuite
## S4 and determinism (TA-18; ADR-10): serialize() then deserialize() then step() equals step() on the original,
## byte for byte, over 1,000 ticks of random commands, projectiles and terrain contacts; the AI hook's opaque bytes
## round-trip; Collision's per-slot state (episodes, projectile first ticks) is part of the bytes; two worlds fed the
## same seed and command stream stay byte-identical; TA-50: pending tickets, the search in flight and a warm route
## cache survive a save (Pathing bytes). TA-21: the format and its policy are in sim/serialize.gd (test_serialize_all.gd).

const TICKS: int = 1000
const RESYNC_EVERY: int = 25
const MAP: StringName = &"tiny_test"


# One tick of random input for every world in `ws` (identical across them): commands, projectiles, a teleport.
func _random_tick(ws: Array[SimWorld], rng: RandomNumberGenerator, darts: PackedInt32Array) -> void:
	var roll: int = rng.randi_range(0, 9)
	var cmd: Command = null
	var id: int = darts[rng.randi_range(0, darts.size() - 1)]
	var player: int = rng.randi_range(0, 2)
	match roll:
		0:
			cmd = Command.possess(player, id)
		1:
			cmd = Command.release(player)
		2:
			var inp: PilotInput = PilotInput.new()
			inp.thrust = rng.randf()
			inp.pitch = rng.randf_range(-1.0, 1.0)
			inp.roll = rng.randf_range(-1.0, 1.0)
			inp.buttons = rng.randi_range(0, 127)
			cmd = Command.pilot(player, 0, inp)
		3:
			var p: Vector3 = WorldTestKit.at(rng.randf_range(100.0, 900.0), rng.randf_range(-800.0, 800.0))
			cmd = Command.order(player, PackedInt32Array([id]), OrderSpec.make(OrderSpec.Kind.MOVE, 0, p))
		4:
			cmd = CommandPayload.debug_spawn(0, WorldTestKit.def_id(&"dart"), player, 1 if player == 1 else 0,
				WorldTestKit.at(rng.randf_range(50.0, 900.0), rng.randf_range(-900.0, 900.0)),
				Vector3(rng.randf_range(-30.0, 30.0), rng.randf_range(-80.0, 80.0), 0.0), Vector3(0, 1, 0))
		5:
			cmd = CommandPayload.debug_set(0, id, CommandPayload.SET_FUEL, rng.randf_range(0.0, 60.0))
	var slug_p: Vector3 = WorldTestKit.at(rng.randf_range(20.0, 900.0), rng.randf_range(-900.0, 900.0))
	var slug_v: Vector3 = Vector3(rng.randf_range(-300.0, 0.0), rng.randf_range(-300.0, 300.0), rng.randf_range(-50.0, 50.0))
	var kill: bool = rng.randf() < 0.02
	for w: SimWorld in ws:
		if cmd != null:
			w.apply_command(cmd)
		for k: int in 3:
			WorldTestKit.projectile(w, &"slug_light" if k < 2 else &"bomb", slug_p + Vector3(0, 0, 40.0 * k), slug_v, k % 2, 3.0)
		if kill:
			w.apply_command(CommandPayload.debug_set(0, id, CommandPayload.SET_KILL, 0.0))


# Step 8's Contact records: Collision's episode state shows up here before any consumer reacts to it.
func _contacts_bytes(c: Collision) -> PackedByteArray:
	var b: StreamPeerBuffer = StreamPeerBuffer.new()
	for k: int in c.contact_count:
		b.put_var([c.c_kind[k], c.c_class[k], c.c_a[k], c.c_b[k], c.c_value[k], c.c_point[k], c.c_vec[k]])
	return b.data_array


func _events_bytes(events: Array[SimEvent]) -> PackedByteArray:
	var b: StreamPeerBuffer = StreamPeerBuffer.new()
	for e: SimEvent in events:
		b.put_var([e.kind, e.tick, e.a, e.b, e.pos, e.value, e.team, e.extra])
	return b.data_array


func test_s4_round_trip_then_step_is_byte_identical_over_1000_ticks() -> void:
	var a: SimWorld = WorldTestKit.world(31, null, MAP)
	var hook_a: WorldTestKit.RecordingHook = WorldTestKit.RecordingHook.new()
	a.set_ai_hook(hook_a)
	var darts: PackedInt32Array = PackedInt32Array()
	for k: int in 12:
		darts.push_back(WorldTestKit.spawn(a, &"dart", k % 3, 1 if k % 3 == 1 else 0,
			WorldTestKit.at(40.0 + 70.0 * k, -600.0 + 100.0 * k), Vector3(-5.0 * k, 60.0, 0.0)))
	var hook_b: WorldTestKit.RecordingHook = WorldTestKit.RecordingHook.new()
	var b: SimWorld = SimWorld.deserialize(a.serialize(), WorldTestKit.content(), hook_b)
	assert_object(b).is_not_null()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 4242
	var terrain_contacts: int = 0
	var events: int = 0
	for t: int in TICKS:
		if t % RESYNC_EVERY == RESYNC_EVERY - 1:
			hook_b = WorldTestKit.RecordingHook.new()
			b = SimWorld.deserialize(a.serialize(), WorldTestKit.content(), hook_b)
			assert_int(hook_b.counter).is_equal(hook_a.counter)
		_random_tick([a, b] as Array[SimWorld], rng, darts)
		a.step()
		b.step()
		var ea: Array[SimEvent] = a.drain_events()
		events += ea.size()
		assert_bool(_events_bytes(ea) == _events_bytes(b.drain_events())).is_true()
		if _contacts_bytes(a.collision) != _contacts_bytes(b.collision):
			fail("S4 contact divergence at tick %d" % a.tick())
			return
		var sa: PackedByteArray = a.serialize()
		if sa != b.serialize():
			fail("S4 divergence at tick %d" % a.tick())
			return
		for k: int in a.collision.contact_count:
			if a.collision.c_kind[k] == Collision.C_TERRAIN:
				terrain_contacts += 1
	assert_int(a.tick()).is_equal(TICKS + 12)
	assert_int(terrain_contacts).is_greater(0)               # Collision episode state was exercised
	assert_int(events).is_greater(20)


static func _mask_of(id: StringName) -> int:
	for g: GroundUnitDef in WorldTestKit.content().ground_units:
		if g.id == id:
			return Pathing.mask_for(g.max_slope_deg)
	return 0


# TA-50 / A-55: a brain stub drives Pathing through the sink; the world is saved every 7 ticks (tickets pending, a
# cell or region search in flight, cache warm) and the restored copy must stay byte-identical, hook bytes included.
func test_s4_round_trip_with_pending_tickets_and_warm_cache() -> void:
	var a: SimWorld = WorldTestKit.world(41, null, MAP)
	var hook_a: PathBrainStub = PathBrainStub.new()
	a.set_ai_hook(hook_a)
	a.step()
	var p: Pathing = hook_a.seen
	assert_object(p).is_not_null()
	hook_a.populate(p, Vector3(1.0, 0.2, 0.1).normalized(), 12, 8, _mask_of(&"harvester"), _mask_of(&"siege_crawler"))
	var b: SimWorld = null
	var in_flight: int = 0
	var warm: int = 0
	for t: int in 240:
		if t % 7 == 0:
			if p.pending() > 0 and (p.grid.state == PathSearch.RUNNING or p.clusters.state == PathSearch.RUNNING):
				in_flight += 1
			if p.pending() > 0 and p.cache.size() > 0:
				warm += 1
			b = SimWorld.deserialize(a.serialize(), WorldTestKit.content(), PathBrainStub.new())
			assert_object(b).is_not_null()
			assert_bool(b.serialize() == a.serialize()).is_true()
		a.step()
		b.step()
		assert_bool(_events_bytes(a.drain_events()) == _events_bytes(b.drain_events())).is_true()
		if a.serialize() != b.serialize():
			fail("S4 pathing divergence at tick %d" % a.tick())
			return
	assert_int(in_flight).is_greater(0)
	assert_int(warm).is_greater(0)
	assert_int(p.cache_hits).is_greater(0)
	assert_int(hook_a.done_count()).is_greater(20)


func test_round_trip_reproduces_collision_and_store_state() -> void:
	var a: SimWorld = WorldTestKit.world(5)
	var c: FlightCommonDef = WorldTestKit.content().flight_common
	var id: int = WorldTestKit.spawn(a, &"dart", 0, 0, WorldTestKit.at(5.0), Vector3(-c.terrain_damage_speed - 1.0, 0, 0))
	for _i: int in 10:
		a.step()
	var s: int = EntityId.slot(id)
	assert_int(a.collision.ep_gen[s]).is_equal(EntityId.gen(id))
	var b: SimWorld = SimWorld.deserialize(a.serialize(), WorldTestKit.content(), null)
	assert_int(b.collision.ep_gen[s]).is_equal(a.collision.ep_gen[s])
	assert_int(b.collision.ep_last[s]).is_equal(a.collision.ep_last[s])
	assert_bool(b.serialize() == a.serialize()).is_true()
	assert_int(b.tick()).is_equal(a.tick())
	assert_vector(b.view().pos(id)).is_equal(a.view().pos(id))


func test_pending_commands_survive_a_save() -> void:
	var a: SimWorld = WorldTestKit.world()
	var id: int = WorldTestKit.spawn(a, &"dart", 0, 0, WorldTestKit.at(500.0))
	a.apply_command(Command.possess(0, id))
	var b: SimWorld = SimWorld.deserialize(a.serialize(), WorldTestKit.content(), null)
	b.step()
	assert_int(b.view().possessor(id)).is_equal(0)


func test_malformed_bytes_give_null() -> void:
	var a: SimWorld = WorldTestKit.world()
	var bytes: PackedByteArray = a.serialize()
	assert_object(SimWorld.deserialize(PackedByteArray([1, 2, 3]), WorldTestKit.content(), null)).is_null()
	assert_object(SimWorld.deserialize(bytes.slice(0, bytes.size() / 2), WorldTestKit.content(), null)).is_null()


func test_entity_store_state_round_trip_keeps_free_stacks() -> void:
	var a: EntityStore = EntityStore.new()
	var ids: PackedInt32Array = PackedInt32Array()
	for k: int in 40:
		ids.push_back(a.alloc(k % 4, k))
	for k: int in range(0, 40, 3):
		a.free_slot(EntityId.slot(ids[k]), 50)
	var buf: StreamPeerBuffer = StreamPeerBuffer.new()
	a.write_state(buf)
	var b: EntityStore = EntityStore.new()
	var rd: StreamPeerBuffer = StreamPeerBuffer.new()
	rd.data_array = buf.data_array
	assert_bool(b.read_state(rd)).is_true()
	for k: int in 30:
		assert_int(b.alloc(EntityStore.K_SHIP, 200 + k)).is_equal(a.alloc(EntityStore.K_SHIP, 200 + k))
	assert_int(b.quarantined_count(EntityStore.RANGE_MAIN)).is_equal(a.quarantined_count(EntityStore.RANGE_MAIN))


func test_projectile_store_state_round_trip() -> void:
	var a: ProjectileStore = ProjectileStore.new(100)
	for k: int in 20:
		a.alloc(ProjectileStore.SLUG, k)
	a.free_slot(3, 30)
	var buf: StreamPeerBuffer = StreamPeerBuffer.new()
	a.write_state(buf)
	var b: ProjectileStore = ProjectileStore.new(5)
	var rd: StreamPeerBuffer = StreamPeerBuffer.new()
	rd.data_array = buf.data_array
	assert_bool(b.read_state(rd)).is_true()
	assert_int(b.live_cap).is_equal(100)
	assert_int(b.alloc(ProjectileStore.BOMB, 31)).is_equal(a.alloc(ProjectileStore.BOMB, 31))


func test_same_seed_and_commands_are_deterministic() -> void:
	var ws: Array[SimWorld] = [WorldTestKit.world(9, null, MAP), WorldTestKit.world(9, null, MAP)]
	var darts: PackedInt32Array = PackedInt32Array()
	for k: int in 6:
		var id0: int = WorldTestKit.spawn(ws[0], &"dart", k % 3, 1 if k % 3 == 1 else 0, WorldTestKit.at(60.0 + 90.0 * k, 50.0 * k))
		var id1: int = WorldTestKit.spawn(ws[1], &"dart", k % 3, 1 if k % 3 == 1 else 0, WorldTestKit.at(60.0 + 90.0 * k, 50.0 * k))
		assert_int(id1).is_equal(id0)
		darts.push_back(id0)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 77
	for _t: int in 300:
		_random_tick(ws, rng, darts)
		ws[0].step()
		ws[1].step()
		assert_bool(_events_bytes(ws[0].drain_events()) == _events_bytes(ws[1].drain_events())).is_true()
	assert_bool(ws[0].serialize() == ws[1].serialize()).is_true()
	assert_bool(ws[0].rng.state() == ws[1].rng.state()).is_true()
