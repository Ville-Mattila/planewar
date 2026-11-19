extends GdUnitTestSuite
## S4 for GD-50 (sim/ground B5): a world saved mid-slew (AUTO and possessed, a shell in flight) restores byte-equal and
## steps byte-identically; SimSerialize FORMAT 18 carries the barrels after the entity store.

const TICKS_AFTER: int = 120


func _case(possessed: bool, map_id: StringName) -> void:
	var a: SimWorld = BarrelTestKit.world(null, map_id)
	var id: int = BarrelTestKit.crawler(a, Sphere.from_lat_lon(0.1, 0.2, 1.0))
	var p: BarrelTestKit.Pilot = BarrelTestKit.pilot(a, id, possessed)
	p.input.pitch = 0.7
	for _k: int in 20:
		p.tick(a)
	p.input.buttons = PilotInput.FIRE1                          # one shell in flight, the barrel still slewing
	p.tick(a)
	p.input.buttons = 0
	for _k: int in 5:
		p.tick(a)
	assert_float(a.view().barrel_elevation(id)).is_greater(0.0)
	var q: BarrelTestKit.Pilot = BarrelTestKit.Pilot.new()
	q.deserialize(p.serialize())
	var bytes: PackedByteArray = a.serialize()
	var b: SimWorld = SimWorld.deserialize(bytes, WorldTestKit.content(), q)
	assert_object(b).is_not_null()
	assert_bool(b.serialize() == bytes).is_true()
	assert_float(b.view().barrel_elevation(id)).is_equal(a.view().barrel_elevation(id))
	for k: int in TICKS_AFTER:
		if k == 40:
			p.input.pitch = -1.0
			q.input.pitch = -1.0
		p.tick(a)
		q.tick(b)
		if a.serialize() != b.serialize():
			fail("S4 barrel divergence at step %d" % k)
			return
	assert_float(a.view().barrel_elevation(id)).is_equal(0.0)   # slewed back down to the minimum


func test_auto_mid_slew_round_trip_is_byte_identical() -> void:
	_case(false, &"")


func test_possessed_mid_slew_round_trip_is_byte_identical_on_cradle() -> void:
	_case(true, &"cradle")


func test_format_carries_the_barrels() -> void:
	assert_int(SimSerialize.FORMAT).is_greater_equal(18)
	var w: SimWorld = WorldTestKit.world()
	var id: int = BarrelTestKit.crawler(w)
	var p: BarrelTestKit.Pilot = BarrelTestKit.pilot(w, id, false)
	p.input.pitch = 1.0
	p.tick(w)
	var sizes: PackedInt32Array = SimSerialize.size_report(w)
	var store_b: StreamPeerBuffer = StreamPeerBuffer.new()
	w.store().write_state(store_b)
	var barrel_b: StreamPeerBuffer = StreamPeerBuffer.new()
	w._barrel.write_state(barrel_b)                             # lane-internal, as FireTestKit.combat reads w._combat
	assert_int(barrel_b.get_size()).is_greater(InputSlots.ENTITY_SLOTS * 12)   # f64 elevation + i32 bound per slot
	assert_int(sizes[SimSerialize.SECTIONS.find("entities")]).is_equal(store_b.get_size() + barrel_b.get_size())
	var raw: PackedByteArray = SimSerialize.write_raw(w)
	var cut: PackedByteArray = SimSerialize.pack(raw.slice(0, raw.size() - 1), WorldTestKit.content().content_hash)
	assert_object(SimWorld.deserialize(cut, WorldTestKit.content(), null)).is_null()
