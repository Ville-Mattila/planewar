extends GdUnitTestSuite
## GroundMotion (TA-38; 03 s5.3, R0 C2-09, C2-11): the 02 slope speed formula, the max-slope and path-weight blocks,
## terrain snap on the cradle map, the BRAKE stop / reverse rule, steering, a path across a cube edge, determinism.
## Invariants G1..G6 of sim/ground/MODULE.md; S4 round trip at world level (test_ground_state.gd).

const DT: float = 1.0 / 30.0
const R: float = Sphere.PLANET_RADIUS
const CRADLE: String = "res://content/maps/cradle"
const CM: float = 0.01

var _defs: WorldDefs
var _store: EntityStore
var _inputs: InputSlots
var _gm: GroundMotion
var _rules: RulesDef


## A terrain whose baked slope is a constant, or `steep` beyond the wall at dir.y > WALL_Y (flat otherwise).
class SlopeTerrain extends Terrain:
	const WALL_Y: float = 0.01
	var slope: float = 0.0
	var steep: float = -1.0

	func slope_deg_at_dir(dir: Vector3) -> float:
		return steep if steep >= 0.0 and dir.y > WALL_Y else slope


func _rig(terrain: Terrain, pathing: Pathing = null) -> void:
	_defs = WorldDefs.new(WorldTestKit.content())
	_rules = _defs.rules
	_store = EntityStore.new()
	_inputs = InputSlots.new()
	_gm = GroundMotion.new(_store, _inputs, _defs, terrain, pathing)


func _spawn(id: StringName, dir: Vector3, heading: Vector3) -> int:
	var eid: int = _store.alloc(EntityStore.K_GROUND, 0)
	var s: int = EntityId.slot(eid)
	_store.def_id[s] = WorldTestKit.def_id(id)
	_store.owner[s] = 0
	_store.pos[s] = dir.normalized() * R
	_store.fwd[s] = heading
	return s


func _drive(s: int, thrust: float, yaw: float, buttons: int = 0) -> void:
	_inputs.e_thrust[s] = thrust
	_inputs.e_yaw[s] = yaw
	_inputs.e_buttons[s] = buttons


func _run(ticks: int) -> void:
	for t: int in ticks:
		_gm.step(t, DT)


func _def(id: StringName) -> GroundUnitDef:
	return _defs.base.ground_unit(WorldTestKit.def_id(id))


func _east() -> Vector3:
	return Vector3(0.0, 1.0, 0.0)


# region G1 slope speed formula
func test_speed_factor_is_the_02_formula() -> void:
	assert_float(GroundMotion.speed_factor(0.0, 25.0, 0.6)).is_equal(1.0)
	assert_float(GroundMotion.speed_factor(10.0, 25.0, 0.6)).is_equal_approx(1.0 - 0.6 * 10.0 / 25.0, 1e-12)
	assert_float(GroundMotion.speed_factor(25.0, 25.0, 0.6)).is_equal_approx(0.4, 1e-12)
	assert_float(GroundMotion.speed_factor(50.0, 25.0, 0.6)).is_equal(0.0)   # floored, never negative
	assert_float(GroundMotion.speed_factor(40.0, 0.0, 0.6)).is_equal(1.0)    # no slope limit, no slowdown


func test_slope_scales_the_distance_travelled_exactly() -> void:
	var tt: SlopeTerrain = SlopeTerrain.new()
	tt.slope = 10.0
	_rig(tt)
	var g: GroundUnitDef = _def(&"harvester")
	var s: int = _spawn(&"harvester", Vector3(1, 0, 0), _east())
	_drive(s, 1.0, 0.0)
	_run(30)
	var want: float = g.ground_speed * (1.0 - _rules.ground_slope_speed_loss * 10.0 / g.max_slope_deg) * 30.0 * DT
	assert_float(Sphere.great_circle(Vector3(1, 0, 0), _store.pos[s])).is_equal_approx(want, CM)


func test_thrust_is_a_speed_fraction_and_cargo_uses_the_loaded_speed() -> void:
	_rig(Terrain.new())
	var g: GroundUnitDef = _def(&"harvester")
	var a: int = _spawn(&"harvester", Vector3(1, 0, 0), _east())
	var b: int = _spawn(&"harvester", Vector3(1, 0, 0.1), _east())
	var c: int = _spawn(&"harvester", Vector3(1, 0.0, -0.1), _east())
	_drive(a, 0.5, 0.0)
	_drive(b, 1.0, 0.0)
	_drive(c, 1.0, 0.0)
	_store.cargo[c] = 100.0
	_run(30)
	assert_float(Sphere.great_circle(Vector3(1, 0, 0), _store.pos[a])).is_equal_approx(0.5 * g.ground_speed, CM)
	assert_float(Sphere.great_circle(Vector3(1, 0, 0.1), _store.pos[b])).is_equal_approx(g.ground_speed, CM)
	assert_float(Sphere.great_circle(Vector3(1, 0, -0.1), _store.pos[c])).is_equal_approx(g.ground_speed_loaded, CM)
	assert_float(_store.vel[c].length()).is_equal_approx(g.ground_speed_loaded, 1e-3)


# region G2 blocks
func test_terrain_steeper_than_max_slope_stops_the_unit() -> void:
	var tt: SlopeTerrain = SlopeTerrain.new()
	tt.steep = _def(&"siege_crawler").max_slope_deg + 1.0
	_rig(tt)
	var s: int = _spawn(&"siege_crawler", Vector3(1, 0.0095, 0), _east())
	_drive(s, 1.0, 0.0)
	_run(120)
	assert_float(_store.pos[s].normalized().y).is_less_equal(SlopeTerrain.WALL_Y)
	assert_vector(_store.vel[s]).is_equal(Vector3.ZERO)
	assert_float(_store.pos[s].normalized().y).is_greater(SlopeTerrain.WALL_Y - 0.001)   # it did drive up to the wall


func test_a_unit_on_too_steep_ground_can_always_climb_out() -> void:
	var tt: SlopeTerrain = SlopeTerrain.new()
	tt.steep = _def(&"harvester").max_slope_deg + 5.0
	tt.slope = 5.0
	_rig(tt)
	var s: int = _spawn(&"harvester", Vector3(1, 0.05, 0), -_east())
	_drive(s, 1.0, 0.0)
	_run(30)
	assert_float(_store.pos[s].normalized().y).is_less(0.05)
	assert_vector(_store.vel[s]).is_not_equal(Vector3.ZERO)


func test_impassable_path_weight_blocks_but_the_cell_a_unit_stands_on_does_not() -> void:
	var pf: Pathing = Pathing.new(120)
	_rig(Terrain.new(), pf)
	var s: int = _spawn(&"harvester", Vector3(1, 0, 0), _east())
	var here: int = PathGrid.cell_of(_store.pos[s])
	var ahead: int = PathGrid.cell_of(Sphere.from_lat_lon(0.0, 0.0125, 1.0))
	pf.set_weight(ahead, PathGrid.W_BLOCKED)
	pf.set_weight(here, PathGrid.W_BLOCKED)    # standing on a blocked cell must not freeze the unit
	_drive(s, 1.0, 0.0)
	_run(300)
	var lon: float = Sphere.lat_lon(_store.pos[s]).y
	assert_float(lon).is_greater(0.0)
	assert_float(lon).is_less(0.0125)
	assert_bool(PathGrid.cell_of(_store.pos[s]) != ahead).is_true()
	assert_vector(_store.vel[s]).is_equal(Vector3.ZERO)


# region G3 brake / reverse
func test_brake_stops_at_once_and_reverses_only_after_the_hold() -> void:
	_rig(Terrain.new())
	var g: GroundUnitDef = _def(&"harvester")
	var s: int = _spawn(&"harvester", Vector3(1, 0, 0), _east())
	_drive(s, 1.0, 0.0)
	_run(10)
	var moving: Vector3 = _store.pos[s]
	assert_float(_store.vel[s].length()).is_equal_approx(g.ground_speed, 1e-3)
	_drive(s, 1.0, 0.0, PilotInput.BRAKE)     # thrust is ignored while BRAKE is held
	var hold_ticks: int = roundi(_rules.ground_reverse_hold_s / DT)
	for k: int in hold_ticks - 1:
		_gm.step(k, DT)
		assert_float(_store.pos[s].distance_to(moving)).is_less(0.002)   # re-snap jitter is one float32 ulp
		assert_vector(_store.vel[s]).is_equal(Vector3.ZERO)
	_gm.step(hold_ticks, DT)
	assert_float(_store.vel[s].dot(_store.fwd[s])).is_equal_approx(-_rules.ground_reverse_speed_mps, 1e-3)
	assert_float(Sphere.great_circle(moving, _store.pos[s])).is_equal_approx(_rules.ground_reverse_speed_mps * DT, CM)
	assert_float(Sphere.lat_lon(_store.pos[s]).y).is_less(Sphere.lat_lon(moving).y)


func test_releasing_brake_resets_the_hold() -> void:
	_rig(Terrain.new())
	var s: int = _spawn(&"harvester", Vector3(1, 0, 0), _east())
	var hold_ticks: int = roundi(_rules.ground_reverse_hold_s / DT)
	_drive(s, 0.0, 0.0, PilotInput.BRAKE)
	_run(hold_ticks - 1)
	_drive(s, 0.0, 0.0, 0)
	_gm.step(0, DT)
	assert_float(_store.timer_b[s]).is_equal(0.0)
	_drive(s, 0.0, 0.0, PilotInput.BRAKE)
	_run(hold_ticks - 1)                                      # a fresh hold: still stopped
	assert_vector(_store.vel[s]).is_equal(Vector3.ZERO)
	_gm.step(0, DT)
	assert_float(_store.vel[s].length()).is_greater(0.0)


func test_reverse_speed_never_exceeds_the_reverse_cap_or_the_slope_factor() -> void:
	var tt: SlopeTerrain = SlopeTerrain.new()
	tt.slope = 20.0
	_rig(tt)
	var g: GroundUnitDef = _def(&"harvester")
	var s: int = _spawn(&"harvester", Vector3(1, 0, 0), _east())
	_drive(s, 1.0, 0.0, PilotInput.BRAKE)
	_run(roundi(_rules.ground_reverse_hold_s / DT) + 5)
	var f: float = GroundMotion.speed_factor(20.0, g.max_slope_deg, _rules.ground_slope_speed_loss)
	assert_float(_store.vel[s].length()).is_equal_approx(_rules.ground_reverse_speed_mps * f, 1e-3)


# region steering
func test_yaw_turns_left_at_the_configured_rate_without_moving() -> void:
	_rig(Terrain.new())
	var s: int = _spawn(&"harvester", Vector3(1, 0, 0), _east())
	_drive(s, 0.0, 1.0)
	_run(30)
	var f: Vector3 = _store.fwd[s]
	assert_float(rad_to_deg(_east().angle_to(f))).is_equal_approx(_rules.ground_turn_rate_dps, 0.01)
	assert_float(f.z).is_greater(0.0)                                 # + yaw = nose left = toward north
	assert_float(Sphere.great_circle(Vector3(1, 0, 0), _store.pos[s])).is_less(CM)
	assert_float(f.length()).is_equal_approx(1.0, 1e-5)


# region G4 snap on the cradle map
func test_snap_follows_the_cradle_surface_within_a_centimetre() -> void:
	var t: Terrain = Terrain.new()
	assert_int(t.load_map(CRADLE)).is_equal(OK)
	_rig(t)
	var g: GroundUnitDef = _def(&"harvester")
	var rng: Rng = Rng.new(38)
	var s: int = _spawn(&"harvester", Sphere.from_lat_lon(0.1, 0.3, 1.0), _east())
	_drive(s, 1.0, 0.0)
	for k: int in 600:
		if k % 20 == 0:
			_drive(s, rng.next_float(), rng.next_float() * 2.0 - 1.0)
		_gm.step(k, DT)
		var d: Vector3 = _store.pos[s].normalized()
		assert_float(_store.pos[s].length()).is_equal_approx(R + t.height_at(d) + g.bounding_radius, CM)
		assert_float(_store.up[s].angle_to(t.normal_at(d))).is_less(1e-4)
		assert_float(absf(_store.fwd[s].dot(d))).is_less(1e-4)
		assert_float(_store.fwd[s].length()).is_equal_approx(1.0, 1e-5)


func test_a_unit_without_input_settles_onto_the_surface() -> void:
	var t: Terrain = Terrain.new()
	assert_int(t.load_map(CRADLE)).is_equal(OK)
	_rig(t)
	var g: GroundUnitDef = _def(&"siege_crawler")
	var s: int = _spawn(&"siege_crawler", Sphere.from_lat_lon(0.2, -0.4, 1.0), _east())
	_store.pos[s] = _store.pos[s] * (1.0 + 50.0 / R)
	_run(1)
	var d: Vector3 = _store.pos[s].normalized()
	assert_float(_store.pos[s].length()).is_equal_approx(R + t.height_at(d) + g.bounding_radius, CM)
	var before: Vector3 = _store.pos[s]
	_run(30)
	assert_float(before.distance_to(_store.pos[s])).is_less(CM)


func test_an_idle_unit_is_re_snapped_within_the_resnap_period() -> void:
	var t: Terrain = Terrain.new()
	assert_int(t.load_map(CRADLE)).is_equal(OK)
	_rig(t)
	var g: GroundUnitDef = _def(&"harvester")
	var s: int = _spawn(&"harvester", Sphere.from_lat_lon(0.2, -0.4, 1.0), _east())
	_run(20)
	_store.pos[s] = _store.pos[s] * (1.0 + 30.0 / R)                  # lifted off the surface (a terrain change)
	for k: int in GroundMotion.RESNAP_TICKS:
		_gm.step(20 + k, DT)
	var d: Vector3 = _store.pos[s].normalized()
	assert_float(_store.pos[s].length()).is_equal_approx(R + t.height_at(d) + g.bounding_radius, CM)


# region G5 cube edge
func test_straight_drive_across_a_cube_edge_has_no_jump() -> void:
	var t: Terrain = Terrain.new()
	assert_int(t.load_map(CRADLE)).is_equal(OK)
	_rig(t)
	var g: GroundUnitDef = _def(&"harvester")
	var start: Vector3 = Sphere.from_lat_lon(0.0, deg_to_rad(44.5), 1.0)   # +X / +Y face edge at 45 degrees
	var s: int = _spawn(&"harvester", start, Vector3(-1.0, 1.0, 0.0))
	_gm.step(-1, DT)                                                  # settle onto the surface first
	_drive(s, 1.0, 0.0)
	var face0: int = int(Sphere.dir_to_face_uv(_store.pos[s]).x)
	var crossed: bool = false
	var prev: Vector3 = _store.pos[s]
	for k: int in 200:
		_gm.step(k, DT)
		var p: Vector3 = _store.pos[s]
		var dh: float = absf(t.height_at(p.normalized()) - t.height_at(prev.normalized()))
		assert_float(p.distance_to(prev)).is_less_equal(g.ground_speed * DT + dh + CM)
		crossed = crossed or int(Sphere.dir_to_face_uv(p).x) != face0
		prev = p
	assert_bool(crossed).is_true()


func test_a_pathing_route_across_a_cube_edge_is_followed_to_the_goal() -> void:
	var t: Terrain = Terrain.new()
	assert_int(t.load_map(CRADLE)).is_equal(OK)
	var pf: Pathing = Pathing.new(120)
	assert_int(pf.load_weights(CRADLE)).is_equal(OK)
	pf.set_terrain(t)
	_rig(t, pf)
	var g: GroundUnitDef = _def(&"harvester")
	var a: Vector3 = Sphere.from_lat_lon(0.0, deg_to_rad(40.0), 1.0)
	var b: Vector3 = Sphere.from_lat_lon(0.0, deg_to_rad(50.0), 1.0)
	var ticket: int = pf.request(a * R, b * R, Pathing.mask_for(g.max_slope_deg))
	for _i: int in 400:
		var _u: int = pf.advance()
	assert_int(pf.status(ticket)).is_equal(Pathing.ST_DONE)
	var route: PackedVector3Array = pf.result(ticket)
	var s: int = _spawn(&"harvester", route[0], route[1] - route[0])
	var faces: Dictionary = {}
	_gm.step(-1, DT)                                                  # settle onto the surface first
	var prev: Vector3 = _store.pos[s]
	var at: int = 1
	for k: int in 6000:
		var d: Vector3 = _store.pos[s].normalized()
		if Sphere.great_circle(d, route[at]) < 20.0:
			at += 1
			if at == route.size():
				break
		var want: Vector3 = (route[at].normalized() - d)
		want = (want - d * want.dot(d)).normalized()
		var err: float = _store.fwd[s].signed_angle_to(want, d)
		_drive(s, 1.0 if absf(err) < 0.6 else 0.2, clampf(err / (deg_to_rad(_rules.ground_turn_rate_dps) * DT), -1.0, 1.0))
		_gm.step(k, DT)
		var p: Vector3 = _store.pos[s]
		var dh: float = absf(t.height_at(p.normalized()) - t.height_at(prev.normalized()))
		assert_float(p.distance_to(prev)).is_less_equal(g.ground_speed * DT + dh + CM)
		faces[int(Sphere.dir_to_face_uv(p).x)] = true
		prev = p
	assert_int(at).is_equal(route.size())
	assert_int(faces.size()).is_greater(1)


# region G6 determinism
func _scripted(seed_value: int, ticks: int) -> PackedByteArray:
	var t: Terrain = Terrain.new()
	assert_int(t.load_map(CRADLE)).is_equal(OK)
	_rig(t, null)
	var rng: Rng = Rng.new(seed_value)
	var ids: PackedInt32Array = PackedInt32Array()
	for k: int in 6:
		ids.push_back(_spawn(&"harvester" if k % 2 == 0 else &"siege_crawler", Sphere.from_lat_lon(0.05 * float(k), 0.7, 1.0), _east()))
	for k: int in ticks:
		for s: int in ids:
			if rng.range_i(0, 9) == 0:
				_drive(s, rng.next_float(), rng.next_float() * 2.0 - 1.0, PilotInput.BRAKE if rng.range_i(0, 4) == 0 else 0)
		_gm.step(k, DT)
	var buf: StreamPeerBuffer = StreamPeerBuffer.new()
	_store.write_state(buf)
	return buf.data_array


func test_same_inputs_give_identical_bytes() -> void:
	var a: PackedByteArray = _scripted(5, 400)
	var b: PackedByteArray = _scripted(5, 400)
	assert_bool(a == b).is_true()
	assert_bool(a == _scripted(6, 400)).is_false()
