extends GdUnitTestSuite
## AI-16 contract tests: `GroundFollower` / `GroundParams` (05 s5.7: tickets, pure pursuit with a 40 m lookahead, yaw
## kp 2.0, thrust 1.0 -> 0.4 at 45 degrees, stuck window, path invalidation; R0 C1-05, C2-09: a unit without a route waits
## on BRAKE and never reaches the sim's reverse hold). Geometry on a hand-built AiState; tickets on a real SimWorld's Pathing.

const R: float = Sphere.PLANET_RADIUS
const S: int = 3

var _st: AiState
var _prm: GroundParams
var _out: PilotInput


func before_test() -> void:
	_st = AiState.new(16)
	_prm = HarvesterParams.from_content(Ai16Kit.content(), Ai16Kit.ap(), Ai16Kit.ground_def()).ground
	_out = PilotInput.new()


# A world point on the equator `east` m along +Y from +X and `north` m up +Z.
func _pt(east: float, north: float = 0.0) -> Vector3:
	return Ai16Kit.dir_at(east, north) * R


# One drive tick from the origin heading east (+Y) along `pts` (a route), goal `goal`.
func _drive(pts: PackedVector3Array, goal: Vector3, p: Vector3 = _pt(0.0), tick: int = 1) -> GroundFollower.Drive:
	_st.path[S] = pts
	_st.goal[S] = goal
	_st.guidance_point[S] = Vector3.ZERO
	return GroundFollower.drive(S, p, Vector3(0, 1, 0), tick, _st, _prm, _out)


func _line(to_east: float, step_m: float = 37.0) -> PackedVector3Array:
	var pts: PackedVector3Array = PackedVector3Array()
	var e: float = step_m
	while e < to_east:
		var _a: bool = pts.push_back(_pt(e))
		e += step_m
	var _b: bool = pts.push_back(_pt(to_east))
	return pts


func test_params_come_from_the_follow_block_and_the_sim_reverse_hold() -> void:
	var c: ContentSet = Ai16Kit.content()
	assert_float(_prm.lookahead_m).is_equal(40.0)
	assert_float(_prm.kp_yaw).is_equal(2.0)
	assert_float(_prm.thrust_turn).is_equal(0.4)
	assert_float(_prm.turn_slow_rad).is_equal_approx(deg_to_rad(45.0), 1e-6)
	assert_int(_prm.path_wait_ticks).is_equal(30)
	assert_float(_prm.stuck_progress_m).is_equal(5.0)
	assert_int(_prm.stuck_window_ticks).is_equal(10 * c.rules.tick_hz)
	# BRAKE is held one tick short of the reverse hold: 0.5 s x 30 Hz = 15 ticks, reverse starts on the 15th
	assert_int(_prm.brake_ticks).is_equal(14)
	var follow: Dictionary = (Ai16Kit.ap()["follow"] as Dictionary).duplicate()
	var _e: bool = follow.erase("kp_yaw")
	assert_object(GroundParams.from_dict(follow, c.ground_common, c.rules.tick_hz)).is_null()   # no default (ADR-09)
	follow["kp_yaw"] = 0.0
	assert_object(GroundParams.from_dict(follow, c.ground_common, c.rules.tick_hz)).is_null()


func test_flat_distance_ignores_the_radial_offset() -> void:
	var a: Vector3 = _pt(0.0)
	var b: Vector3 = _pt(30.0) * (1.0 + 20.0 / R)   # 30 m along, 20 m higher
	assert_float(GroundFollower.flat(a, b)).is_equal_approx(30.0, 0.1)
	assert_float(GroundFollower.flat(a, a * 1.002)).is_less(0.001)


func test_a_straight_leg_is_full_thrust_with_no_yaw() -> void:
	assert_int(_drive(_line(300.0), _pt(300.0))).is_equal(GroundFollower.Drive.FOLLOWING)
	assert_float(_out.thrust).is_equal(1.0)
	assert_float(_out.yaw).is_equal_approx(0.0, 1e-6)
	assert_int(_out.buttons).is_equal(0)


func test_yaw_is_kp_times_the_heading_error_left_positive() -> void:
	var left: float = 0.1                                                  # rad
	var d: float = 200.0
	var _a: GroundFollower.Drive = _drive(PackedVector3Array([_pt(d * cos(left), d * sin(left))]), _pt(d * cos(left), d * sin(left)))
	assert_float(_out.yaw).is_equal_approx(2.0 * left, 0.005)             # + = left (north when facing east)
	var _b: GroundFollower.Drive = _drive(PackedVector3Array([_pt(d * cos(left), -d * sin(left))]), _pt(d * cos(left), -d * sin(left)))
	assert_float(_out.yaw).is_equal_approx(-2.0 * left, 0.005)
	var _c: GroundFollower.Drive = _drive(PackedVector3Array([_pt(0.0, d)]), _pt(0.0, d))   # 90 degrees: clamped
	assert_float(_out.yaw).is_equal(1.0)


func test_thrust_falls_from_one_to_the_turn_thrust_at_45_degrees() -> void:
	var d: float = 300.0
	for deg: float in [0.0, 22.5, 45.0, 90.0]:
		var r: float = deg_to_rad(deg)
		var g: Vector3 = _pt(d * cos(r), d * sin(r))
		var _x: GroundFollower.Drive = _drive(PackedVector3Array([g]), g)
		var want: float = lerpf(1.0, 0.4, minf(deg / 45.0, 1.0))
		assert_float(_out.thrust).override_failure_message("heading error %s deg" % deg).is_equal_approx(want, 0.002)


func test_the_goal_is_reached_within_arrive_m_and_the_unit_stands() -> void:
	var g: Vector3 = _pt(2.0)
	assert_int(_drive(PackedVector3Array([g]), g)).is_equal(GroundFollower.Drive.ARRIVED)
	assert_float(_out.thrust).is_equal(0.0)
	assert_int(_out.buttons).is_equal(0)                                  # standing, not BRAKE: a held BRAKE would reverse
	g = _pt(4.0)
	assert_int(_drive(PackedVector3Array([g]), g)).is_equal(GroundFollower.Drive.FOLLOWING)


func test_near_a_goal_behind_it_turns_on_the_spot() -> void:
	var g: Vector3 = _pt(-10.0, 4.0)                                       # 10 m behind, inside pivot_m
	var _a: GroundFollower.Drive = _drive(PackedVector3Array([g]), g)
	assert_float(_out.thrust).is_equal(0.0)
	assert_float(absf(_out.yaw)).is_equal(1.0)
	g = _pt(-60.0, 4.0)                                                    # far behind: it drives, slowly
	var _b: GroundFollower.Drive = _drive(PackedVector3Array([g]), g)
	assert_float(_out.thrust).is_equal_approx(0.4, 1e-6)


func test_the_aim_is_the_first_route_point_a_lookahead_away() -> void:
	var pts: PackedVector3Array = PackedVector3Array([_pt(10.0), _pt(25.0), _pt(35.0, 10.0), _pt(50.0, 20.0), _pt(100.0, 60.0)])
	var g: Vector3 = _pt(100.0, 60.0)
	var _a: GroundFollower.Drive = _drive(pts, g)
	# the points at 10 / 25 / 36 m are under the 40 m lookahead: it steers at (50, 20), 54 m away
	assert_float(_out.yaw).is_equal_approx(2.0 * atan2(20.0, 50.0), 0.02)
	assert_int(_st.ground.idx[S]).is_equal(0)


func test_progress_only_moves_forward_along_the_route() -> void:
	var pts: PackedVector3Array = _line(400.0)
	var g: Vector3 = _pt(400.0)
	var _a: GroundFollower.Drive = _drive(pts, g, _pt(150.0))
	var at: int = _st.ground.idx[S]
	assert_int(at).is_between(3, 4)                                       # 150 m / 37 m
	var _b: GroundFollower.Drive = _drive(pts, g, _pt(40.0))               # pushed back: the index does not rewind
	assert_int(_st.ground.idx[S]).is_equal(at)


func test_the_aim_is_rescanned_every_aim_every_ticks_and_cached_between() -> void:
	assert_int(_prm.aim_every_ticks).is_equal(4)
	var pts: PackedVector3Array = _line(400.0)
	var g: Vector3 = _pt(400.0)
	var _a: GroundFollower.Drive = _drive(pts, g, _pt(0.0), 1)                  # (1 + 3) % 4 == 0: a rescan
	var aim: Vector3 = _st.guidance_point[S]
	assert_bool(aim != Vector3.ZERO).is_true()
	_st.ground.idx[S] = 0
	var _b: GroundFollower.Drive = GroundFollower.drive(S, _pt(100.0), Vector3(0, 1, 0), 2, _st, _prm, _out)   # not a rescan tick
	assert_object(_st.guidance_point[S]).is_equal(aim)                           # the cached aim, the index untouched
	assert_int(_st.ground.idx[S]).is_equal(0)
	var _c: GroundFollower.Drive = GroundFollower.drive(S, _pt(100.0), Vector3(0, 1, 0), 5, _st, _prm, _out)   # (5 + 3) % 4 == 0
	assert_int(_st.ground.idx[S]).is_greater(0)
	assert_bool(_st.guidance_point[S] != aim).is_true()


func test_without_a_route_it_drives_straight_at_the_goal() -> void:
	_st.path.erase(S)
	_st.goal[S] = _pt(300.0)
	assert_int(GroundFollower.drive(S, _pt(0.0), Vector3(0, 1, 0), 1, _st, _prm, _out)).is_equal(GroundFollower.Drive.FOLLOWING)
	assert_float(_out.thrust).is_equal(1.0)


func test_waiting_brakes_for_at_most_the_brake_ticks_then_stands() -> void:
	_st.ground.req[S] = 100
	var run: int = 0
	var longest: int = 0
	for t: int in range(100, 140):
		GroundFollower.wait(S, t, _st, _prm, _out)
		assert_float(_out.thrust).is_equal(0.0)
		run = run + 1 if (_out.buttons & PilotInput.BRAKE) != 0 else 0
		longest = maxi(longest, run)
		if t == 100:
			assert_int(_out.buttons).is_equal(PilotInput.BRAKE)           # braked from the tick it asked
	assert_int(longest).is_equal(_prm.brake_ticks)
	var hold: int = ceili(Ai16Kit.content().ground_common.ground_reverse_hold_s * float(Ai16Kit.content().rules.tick_hz))
	assert_int(longest).is_less(hold)                                      # never the sim's reverse hold
	GroundFollower.wait(S, 139, _st, _prm, _out)
	assert_int(_out.buttons).is_equal(0)


func test_stuck_is_less_than_5_m_of_progress_in_the_window() -> void:
	var w: int = _prm.stuck_window_ticks
	GroundFollower.restart_window(S, _pt(0.0), 1000, _st)
	assert_bool(GroundFollower.stuck(S, _pt(0.0), 1000 + w - 1, _st, _prm)).is_false()       # window not over
	assert_bool(GroundFollower.stuck(S, _pt(3.0), 1000 + w, _st, _prm)).is_true()            # 3 m in 10 s
	assert_int(_st.ground.stuck_tick[S]).is_equal(1000 + w)                                  # the window restarted
	assert_bool(GroundFollower.stuck(S, _pt(30.0), 1000 + 2 * w, _st, _prm)).is_false()      # 27 m: moving
	assert_float(_st.ground.stuck_pos[S].distance_to(_pt(30.0))).is_less(0.001)


func test_off_route_is_beyond_deviate_m_of_the_reached_point() -> void:
	_st.path[S] = _line(400.0)
	assert_bool(GroundFollower.off_route(S, _pt(5.0, 100.0), _st, _prm)).is_false()
	assert_bool(GroundFollower.off_route(S, _pt(5.0, 150.0), _st, _prm)).is_true()           # deviate_m 120
	_st.path.erase(S)
	assert_bool(GroundFollower.off_route(S, _pt(5.0, 500.0), _st, _prm)).is_false()          # no route: nothing to leave


# --- tickets on a real world's Pathing ----------------------------------------------------------------------------------

class PathSink extends CommandSinkBase:
	var pa: Pathing
	func pathing() -> Pathing:
		return pa


func _rig() -> Array:
	var w: SimWorld = Ai16Kit.world(5)
	var inner: PathSink = PathSink.new()
	inner.pa = w._pathing
	var sink: CommandSink = CommandSink.new()
	sink.bind(inner)
	return [w, sink]


func test_request_poll_stores_the_route_the_faces_and_releases_the_ticket() -> void:
	var rig: Array = _rig()
	var w: SimWorld = rig[0]
	var sink: CommandSink = rig[1]
	var pa: Pathing = w._pathing
	var mask: int = HarvesterParams.from_content(Ai16Kit.content(), Ai16Kit.ap(), Ai16Kit.ground_def()).mask
	assert_int(GroundFollower.poll(S, _st, sink, w.view())).is_equal(GroundFollower.Poll.IDLE)
	assert_bool(GroundFollower.request(S, _pt(0.0), _pt(600.0), mask, _st, sink, 50)).is_true()
	assert_int(_st.ground.req[S]).is_equal(50)
	assert_float(_st.goal[S].distance_to(_pt(600.0))).is_less(0.001)
	assert_bool(_st.path_ticket[S] >= 0).is_true()
	assert_int(GroundFollower.poll(S, _st, sink, w.view())).is_equal(GroundFollower.Poll.PENDING)
	assert_bool(GroundFollower.has_route(S, _st)).is_false()
	var ticket: int = _st.path_ticket[S]
	for _k: int in 40:
		var _u: int = pa.advance()
	assert_int(GroundFollower.poll(S, _st, sink, w.view())).is_equal(GroundFollower.Poll.READY)
	assert_int(_st.path_ticket[S]).is_equal(-1)
	assert_int(pa.status(ticket)).is_not_equal(PathTickets.ST_DONE)       # released
	assert_bool(GroundFollower.has_route(S, _st)).is_true()
	var route: PackedVector3Array = _st.path[S]
	assert_int(route.size()).is_greater(10)                                # 600 m of 37 m cells
	assert_int(_st.ground.idx[S]).is_equal(0)
	assert_int(_st.ground.faces[S]).is_not_equal(0)
	assert_bool(GroundFollower.changed(S, _st, w.view())).is_false()
	pa.set_weight(PathGrid.cell_of(_pt(3000.0, 900.0)), PathGrid.W_BLOCKED)   # any change on a face the route crosses
	assert_bool(GroundFollower.changed(S, _st, w.view())).is_true()
	GroundFollower.clear(S, _st, sink)
	assert_bool(GroundFollower.has_route(S, _st)).is_false()
	assert_int(_st.ground.faces[S]).is_equal(0)


func test_a_second_request_drops_the_first_ticket_and_route() -> void:
	var rig: Array = _rig()
	var w: SimWorld = rig[0]
	var sink: CommandSink = rig[1]
	var pa: Pathing = w._pathing
	var first: bool = GroundFollower.request(S, _pt(0.0), _pt(400.0), 25, _st, sink, 10)
	var t1: int = _st.path_ticket[S]
	var second: bool = GroundFollower.request(S, _pt(0.0), _pt(500.0), 25, _st, sink, 20)
	assert_bool(first and second).is_true()
	assert_int(_st.path_ticket[S]).is_not_equal(t1)
	assert_int(pa.status(t1)).is_not_equal(PathTickets.ST_PENDING)         # the first was released
	assert_int(_st.ground.req[S]).is_equal(20)


func test_no_path_is_reported_once_and_frees_the_ticket() -> void:
	var rig: Array = _rig()
	var w: SimWorld = rig[0]
	var sink: CommandSink = rig[1]
	var pa: Pathing = w._pathing
	var goal: Vector3 = _pt(500.0)
	pa.set_weight(PathGrid.cell_of(goal), PathGrid.W_BLOCKED)
	assert_bool(GroundFollower.request(S, _pt(0.0), goal, 25, _st, sink, 5)).is_true()
	var got: int = GroundFollower.Poll.PENDING
	for _k: int in 400:
		var _u: int = pa.advance()
		got = GroundFollower.poll(S, _st, sink, w.view())
		if got != GroundFollower.Poll.PENDING:
			break
	assert_int(got).is_equal(GroundFollower.Poll.NO_PATH)
	assert_int(_st.path_ticket[S]).is_equal(-1)
	assert_bool(GroundFollower.has_route(S, _st)).is_false()


func test_an_unbound_sink_is_no_path_not_a_crash() -> void:
	var sink: CommandSink = CommandSink.new()
	assert_bool(GroundFollower.request(S, _pt(0.0), _pt(100.0), 25, _st, sink, 5)).is_false()
	assert_int(GroundFollower.poll(S, _st, sink, SimView.new())).is_equal(GroundFollower.Poll.IDLE)
