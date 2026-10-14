extends GdUnitTestSuite
## S4 for GroundMotion (TA-38): a world with driven ground units, saved mid-drive (BRAKE hold timer, headings, input
## slots all in the bytes), restores and steps byte-identically to the original, flat datum and the cradle map.

const TICKS_BEFORE: int = 70
const TICKS_AFTER: int = 90


func _round_trip(map_id: StringName) -> void:
	var a: SimWorld = WorldTestKit.world(9, null, map_id)
	var r: float = Sphere.PLANET_RADIUS + 3.0
	var h_id: int = WorldTestKit.spawn(a, &"harvester", 0, 0, Sphere.from_lat_lon(0.0, 0.5, 1.0) * r)
	var c_id: int = WorldTestKit.spawn(a, &"siege_crawler", 0, 0, Sphere.from_lat_lon(0.05, 0.5, 1.0) * r)
	var hook: WorldTestKit.RecordingHook = WorldTestKit.RecordingHook.new()
	hook.drive_id = h_id
	hook.input.thrust = 1.0
	hook.input.yaw = 0.3
	a.set_ai_hook(hook)
	for _i: int in TICKS_BEFORE:
		a.step()
	hook.input.buttons = PilotInput.BRAKE
	hook.drive_id = c_id
	hook.input.thrust = 0.0
	for _i: int in 8:     # mid-hold: timer_b is part of the bytes
		a.step()
	var start: Vector3 = a.view().pos(h_id)
	var hook_b: WorldTestKit.RecordingHook = WorldTestKit.RecordingHook.new()
	hook_b.drive_id = hook.drive_id
	hook_b.input = hook.input
	var b: SimWorld = SimWorld.deserialize(a.serialize(), WorldTestKit.content(), hook_b)
	assert_bool(b.serialize() == a.serialize()).is_true()
	for k: int in TICKS_AFTER:
		a.step()
		b.step()
		if a.serialize() != b.serialize():
			fail("S4 ground divergence at step %d" % k)
			return
	assert_float(start.distance_to(a.view().pos(h_id))).is_greater(10.0)    # the unit did move


func test_round_trip_is_byte_identical_on_the_flat_datum() -> void:
	_round_trip(&"")


func test_round_trip_is_byte_identical_on_the_cradle_map() -> void:
	_round_trip(&"cradle")
