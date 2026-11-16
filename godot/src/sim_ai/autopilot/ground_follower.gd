class_name GroundFollower extends RefCounted
## Ground following (05 s5.7, R0 C1-05; AI-16), static, shared by the ground brains. `request` asks `Pathing` for a route
## and stores the ticket in `AiState.path_ticket`; `poll` (every act while pending) turns an answered ticket into the
## polyline `AiState.path` and stamps the path-grid faces it crosses; `drive` is pure pursuit with a lookahead (yaw from
## the heading error, thrust 1.0 on a straight leg down to `thrust_turn` at 45 degrees) and reports ARRIVED within
## `arrive_m` of the goal. A unit without a route waits: BRAKE (the sim stops it at once) for at most `brake_ticks`, then
## thrust 0, so waiting never reaches the sim's reverse hold (`ground_reverse_hold_s`, C2-09). All distances are flat
## (tangent plane at the unit), so a hill or the unit's bounding radius never keeps a goal out of reach. The state is
## `AiState` (`path`, `path_ticket`, `goal`, `guidance_point` = the cached aim, `ground`); nothing here is stored. No allocation per call except `poll`
## receiving a route (once per path).

enum Poll { IDLE, PENDING, READY, NO_PATH }
enum Drive { FOLLOWING, ARRIVED }

static var _empty: PackedVector3Array = PackedVector3Array()


## Flat distance between `p` and `q`: the tangent-plane component of `q - p` at `p` (exact for the short legs of a route).
static func flat(p: Vector3, q: Vector3) -> float:
	var d: Vector3 = q - p
	var n: Vector3 = p.normalized()
	return (d - n * d.dot(n)).length()


## Asks for a route from `from` to `to` (`mask` = `Pathing.mask_for(max_slope_deg)`) for slot `s`: drops its old ticket and
## route, sets `goal`, stores the new ticket. False when the sim has no free ticket (the unit waits and asks again).
static func request(s: int, from: Vector3, to: Vector3, mask: int, st: AiState, sink: CommandSink, tick: int) -> bool:
	clear(s, st, sink)
	st.goal[s] = to
	st.ground.req[s] = tick
	st.ground.stuck_pos[s] = from
	st.ground.stuck_tick[s] = tick
	var pa: Pathing = sink.pathing()
	if pa == null:
		return false
	var ticket: int = pa.request(from, to, mask)
	st.path_ticket[s] = ticket
	return ticket != PathTickets.NO_TICKET


## Drops the pending ticket (released in the sim) and the route of slot `s`.
static func clear(s: int, st: AiState, sink: CommandSink) -> void:
	var pa: Pathing = sink.pathing()
	if st.path_ticket[s] >= 0 and pa != null:
		pa.release(st.path_ticket[s])
	st.path_ticket[s] = -1
	var _e: bool = st.path.erase(s)
	st.guidance_point[s] = Vector3.ZERO
	st.ground.idx[s] = 0
	st.ground.faces[s] = 0


## True while slot `s` holds a route.
static func has_route(s: int, st: AiState) -> bool:
	return st.path.has(s)


## Polls slot `s`'s ticket: IDLE (none), PENDING, READY (the route is now `st.path[s]`, ticket released) or NO_PATH (the sim
## proved none, or the ticket is unknown; released).
static func poll(s: int, st: AiState, sink: CommandSink, view: SimView) -> Poll:
	var tk: int = st.path_ticket[s]
	if tk < 0:
		return Poll.IDLE
	var pa: Pathing = sink.pathing()
	if pa == null:
		st.path_ticket[s] = -1
		return Poll.NO_PATH
	var code: int = pa.status(tk)
	if code == PathTickets.ST_PENDING:
		return Poll.PENDING
	var done: bool = code == PathTickets.ST_DONE
	if done:
		_store(s, pa, tk, st, view)
	pa.release(tk)
	st.path_ticket[s] = -1
	return Poll.READY if done else Poll.NO_PATH


static func _store(s: int, pa: Pathing, tk: int, st: AiState, view: SimView) -> void:
	st.path[s] = pa.result(tk)
	st.guidance_point[s] = Vector3.ZERO   # the next drive scans the new route
	st.ground.idx[s] = 0
	var mask: int = 0
	for c: int in pa.result_cells(tk):
		mask |= 1 << (c >> (PathGrid.SHIFT + PathGrid.SHIFT))
	st.ground.faces[s] = mask
	st.ground.ver[s] = stamp(mask, view)


## Sum of the path-grid face versions of the faces in `mask` (`SimView.path_grid_version`).
static func stamp(mask: int, view: SimView) -> int:
	var sum: int = 0
	for f: int in PathGrid.FACES:
		if ((mask >> f) & 1) != 0:
			sum += view.path_grid_version(f)
	return sum


## True when a face the route crosses changed since it was made (a structure, a wreck): 05 s5.7 path invalidation.
static func changed(s: int, st: AiState, view: SimView) -> bool:
	return st.path.has(s) and stamp(st.ground.faces[s], view) != st.ground.ver[s]


## True when the unit is farther than `deviate_m` from the route point it has reached (it was possessed and driven away, pushed).
static func off_route(s: int, p: Vector3, st: AiState, prm: GroundParams) -> bool:
	var pts: PackedVector3Array = st.path.get(s, _empty)
	return not pts.is_empty() and flat(p, pts[mini(st.ground.idx[s], pts.size() - 1)]) > prm.deviate_m


## One stuck window (05 s5.7): false until `stuck_window_ticks` after its start; then true when the unit made less than
## `stuck_progress_m` in it, and the window restarts either way.
static func stuck(s: int, p: Vector3, tick: int, st: AiState, prm: GroundParams) -> bool:
	if tick - st.ground.stuck_tick[s] < prm.stuck_window_ticks:
		return false
	var slow: bool = flat(p, st.ground.stuck_pos[s]) < prm.stuck_progress_m
	restart_window(s, p, tick, st)
	return slow


static func restart_window(s: int, p: Vector3, tick: int, st: AiState) -> void:
	st.ground.stuck_pos[s] = p
	st.ground.stuck_tick[s] = tick


## No route yet: BRAKE only while the unbroken BRAKE run (`ground.brake_run`, whoever drove it) is under `brake_ticks`, then
## thrust 0: the sim counts its reverse hold from the first tick of an unbroken run, so a wait after an overlay's BRAKE
## must not extend it. `tick` is unused (kept for the callers' shape).
static func wait(s: int, _tick: int, st: AiState, prm: GroundParams, out: PilotInput) -> void:
	out.thrust = 0.0
	out.yaw = 0.0
	out.buttons = PilotInput.BRAKE if st.ground.brake_run[s] < prm.brake_ticks else 0


## Books the buttons driven this tick into the unbroken BRAKE run of slot `s` (call once per tick after every drive).
static func book_brake(s: int, buttons: int, st: AiState) -> void:
	st.ground.brake_run[s] = mini(st.ground.brake_run[s] + 1, 255) if (buttons & PilotInput.BRAKE) != 0 else 0


## Stand still (no BRAKE: a held BRAKE would reverse the unit).
static func stop(out: PilotInput) -> void:
	out.thrust = 0.0
	out.yaw = 0.0
	out.buttons = 0


## One tick of pure pursuit of slot `s`'s route (straight at `goal` without one) from `p` heading `fwd`, into `out`. The
## aim point (progress index + lookahead scan) is refreshed every `aim_every_ticks` ticks, staggered by slot, and cached in
## `AiState.guidance_point` between (a unit moves ~2 m in that time against a 40 m lookahead); heading error and arrival are per tick.
static func drive(s: int, p: Vector3, fwd: Vector3, tick: int, st: AiState, prm: GroundParams, out: PilotInput) -> Drive:
	var goal: Vector3 = st.goal[s]
	var n: Vector3 = p.normalized()
	var to_goal: float = _flat2(n, p, goal)
	out.buttons = 0
	if to_goal <= prm.arrive_m * prm.arrive_m:
		out.thrust = 0.0
		out.yaw = 0.0
		return Drive.ARRIVED
	var aim: Vector3 = st.guidance_point[s]
	if aim == Vector3.ZERO or (tick + s) % prm.aim_every_ticks == 0:
		aim = _aim(s, n, p, goal, st, prm)
		st.guidance_point[s] = aim
	var d: Vector3 = aim - p
	var t: Vector3 = d - n * d.dot(n)
	var err: float = atan2(fwd.cross(t).dot(n), fwd.dot(t)) if not t.is_zero_approx() else 0.0
	var a: float = absf(err)
	out.yaw = clampf(prm.kp_yaw * err, -1.0, 1.0)
	out.thrust = lerpf(1.0, prm.thrust_turn, clampf(a / prm.turn_slow_rad, 0.0, 1.0))
	if a > prm.turn_slow_rad and to_goal < prm.pivot_m * prm.pivot_m:
		out.thrust = 0.0
	return Drive.FOLLOWING


# Squared flat distance from `p` (radial `n`) to `q`: no square root, no second normalisation.
static func _flat2(n: Vector3, p: Vector3, q: Vector3) -> float:
	var d: Vector3 = q - p
	return (d - n * d.dot(n)).length_squared()


# The route point to steer at: advance the progress index while the next point is no farther than the current one, then
# take the first point at least the lookahead away; past the last point, the goal itself.
static func _aim(s: int, n: Vector3, p: Vector3, goal: Vector3, st: AiState, prm: GroundParams) -> Vector3:
	var pts: PackedVector3Array = st.path.get(s, _empty)
	var cnt: int = pts.size()
	var i: int = mini(st.ground.idx[s], maxi(cnt - 1, 0))
	var here: float = _flat2(n, p, pts[i]) if cnt > 0 else 0.0
	while i + 1 < cnt:
		var next: float = _flat2(n, p, pts[i + 1])
		if next > here:
			break
		here = next
		i += 1
	st.ground.idx[s] = i
	var look2: float = prm.lookahead_m * prm.lookahead_m
	for j: int in range(i, cnt):
		if _flat2(n, p, pts[j]) >= look2:
			return pts[j]
	return goal
