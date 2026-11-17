class_name CrawlerBrain extends AiBrain
## The Siege Crawler autopilot (05 s6.7, s5.7; AI-18). AUTO = HOLD (01 s4.3): it stands, no BRAKE. MOVE drives to the
## point and stands. ATTACK (mode SIEGE): a firing spot 1,000-1,150 m from the target's last seen position on ground no
## steeper than 10 degrees (its own position when that qualifies, else the ring point nearest its approach), the route
## there (GroundFollower), then traverse in place onto the target's bearing and hold FIRE1 (the sim fires per def
## cadence) while the lofted solve (`SiegeAim.loft`, A-74) has a solution. An enemy bomb landing within 60 m
## (BOMB_IMPACT through `on_impact`, which the driver turns into a wake) moves it `relocate_step_m` along the ring away
## from the impact (mode RELOCATE), then SIEGE again. Ammo 0 = NO_AMMO: it holds (05 s6.7; the order failure itself
## needs a sink call, brains/MODULE.md Open). Vision only: the target is read only while the team sees it; never seen
## under this order = no spot, HOLD; a ground-unit target out of sight is not fired at. State is AiState only: mode,
## `order_tick`, `target`, `home` = target's last seen position, `seen_tick`, `goal` = the spot, `aux_id` = spot search
## index, `bflags`, `fire_mask` (1 = solved), `tti` = the solved elevation, `aim_lead` = own position at the last act,
## `sub` = team + 1, `land_mark` = the last near impact, `path`, `ground`.

const B_ARRIVED: int = 1   ## bflags: the act reached the goal
const B_NOPATH: int = 2    ## bflags: the sim proved the last request has no route
const B_BLAST: int = 4     ## bflags: an enemy bomb landed within relocate_m (set by on_impact, taken by the think)
const B_EMPTY: int = 8     ## bflags: NO_AMMO already counted for this empty magazine
const B_GAVE_UP: int = 16  ## bflags: no spot / route on this order: hold until a new order (cleared by it)
const B_AIMED: int = 32    ## bflags: the act found the heading on the bearing: hold it without a view read (cleared by every think)

var prm: CrawlerParams
var terrain: Terrain
var stats_thinks: int = 0
var stats_spots: int = 0         ## spot searches
var stats_solves: int = 0        ## lofted solves (SiegeAim.loft calls)
var stats_relocations: int = 0
var stats_no_ammo: int = 0       ## NO_AMMO decisions (05 s6.7; ORDER_FAILED(NO_AMMO) has no sink call yet)
var stats_gave_up: int = 0
var stats_strikes: int = 0
var _inp: PilotInput = PilotInput.new()
var _ps: ProjectileState = ProjectileState.new()


## The Crawler brain from content (`ap` = the `ap_crawler` dictionary, `t` the map terrain); null when a key is bad.
static func create(c: ContentSet, ap: Dictionary, def: GroundUnitDef, t: Terrain) -> CrawlerBrain:
	var p: CrawlerParams = CrawlerParams.from_content(c, ap, def)
	if p == null or t == null:
		return null
	var b: CrawlerBrain = CrawlerBrain.new()
	b.prm = p
	b.terrain = t
	return b


func think_batch(ids: PackedInt32Array, n: int, view: SimView, st: AiState, sink: CommandSink, tick: int) -> void:
	for i: int in n:
		think_one(ids[i], view, st, sink, tick)


func act_batch(ids: PackedInt32Array, view: SimView, st: AiState, sink: CommandSink) -> void:
	var tick: int = view.tick()
	for id: int in ids:
		_act(id, EntityId.slot(id), view, st, sink, tick)


func hears_impacts() -> bool:
	return true


## BOMB_IMPACT (the driver, before the tick's thinks): an enemy bomb within `relocate_m` of a sieging Crawler's position
## at its last act marks a relocation; true = wake it.
func on_impact(id: int, ev: SimEvent, st: AiState) -> bool:
	var s: int = EntityId.slot(id)
	var m: int = st.mode[s]
	if (m != AiTag.Tag.SIEGE and m != AiTag.Tag.RELOCATE) or st.sub[s] == 0 or ev.team == st.sub[s] - 1:
		return false
	if ev.pos.distance_to(st.aim_lead[s]) > prm.relocate_m:
		return false
	st.land_mark[s] = ev.pos
	st.bflags[s] |= B_BLAST
	return true


# --- act -------------------------------------------------------------------------------------------------------------

## True for the modes that follow a route until B_ARRIVED.
static func moving(m: int) -> bool:
	return m == AiTag.Tag.SIEGE or m == AiTag.Tag.RELOCATE or m == AiTag.Tag.MOVE


func _act(id: int, s: int, view: SimView, st: AiState, sink: CommandSink, tick: int) -> void:
	_inp.pitch = 0.0
	_inp.roll = 0.0
	var m: int = st.mode[s]
	var f: int = st.bflags[s]
	if not moving(m):
		GroundFollower.stop(_inp)
	elif (f & B_AIMED) != 0:
		_fire(s, m, st)                          # standing on the bearing: nothing to read until the next think
	elif (f & B_ARRIVED) != 0:
		var q: Vector3 = view.pos(id)
		st.aim_lead[s] = q
		_traverse(s, q, -view.basis(id).z, m, st)
	else:
		var p: Vector3 = view.pos(id)
		st.aim_lead[s] = p
		if GroundFollower.poll(s, st, sink, view) == GroundFollower.Poll.NO_PATH:
			st.bflags[s] |= B_NOPATH
		if GroundFollower.has_route(s, st):
			if GroundFollower.drive(s, p, -view.basis(id).z, tick, st, prm.ground, _inp) == GroundFollower.Drive.ARRIVED:
				st.bflags[s] |= B_ARRIVED
		else:
			GroundFollower.wait(s, tick, st, prm.ground, _inp)
	if not sink.drive(id, _inp):
		GroundFollower.lose_brake(s, st)        # refused: the pilot drives, its BRAKE run is unknown to the AI
	elif st.overlay[s] == Overlays.NONE:        # an overlay overrides this drive and books its own
		GroundFollower.book_brake(s, _inp.buttons, st)


# At the spot: turn in place onto the target's bearing; within `aim_tol` stop turning (B_AIMED) and fire.
func _traverse(s: int, p: Vector3, fwd: Vector3, m: int, st: AiState) -> void:
	var err: float = SiegeAim.heading_error(p, fwd, st.home[s])
	if absf(err) <= prm.aim_tol_rad:
		st.bflags[s] |= B_AIMED
		_fire(s, m, st)
		return
	_inp.thrust = 0.0
	_inp.yaw = clampf(prm.ground.kp_yaw * err, -1.0, 1.0)
	_inp.buttons = 0


# Stand still on the bearing; FIRE1 while solved (SIEGE only): the sim fires at the def cadence.
func _fire(s: int, m: int, st: AiState) -> void:
	_inp.thrust = 0.0
	_inp.yaw = 0.0
	_inp.buttons = PilotInput.FIRE1 if m == AiTag.Tag.SIEGE and st.fire_mask[s] != 0 else 0


# --- think -----------------------------------------------------------------------------------------------------------

## One think of `id` (rigs, perf).
func think_one(id: int, view: SimView, st: AiState, sink: CommandSink, tick: int) -> void:
	stats_thinks += 1
	var s: int = EntityId.slot(id)
	var p: Vector3 = view.pos(id)
	var team: int = view.team(id)
	st.sub[s] = team + 1
	st.aim_lead[s] = p
	st.bflags[s] &= ~B_AIMED                     # the act re-checks the bearing after every think
	var head: OrderSpec = view.order_head(id)
	var kind: int = head.kind if head != null else -1
	var issued: int = head.issue_tick if head != null else -1
	if issued != st.order_tick[s]:
		st.order_tick[s] = issued
		_reset(s, st, sink)
		st.bflags[s] = 0
		st.seen_tick[s] = 0
		st.mode[s] = AiTag.Tag.NONE
	if kind == OrderSpec.Kind.MOVE:
		_move(id, s, head.point, p, view, st, sink, tick)
	elif kind == OrderSpec.Kind.ATTACK:
		_siege(id, s, head.target, team, p, view, st, sink, tick)
	else:
		_hold(id, s, st, sink, tick)             # AUTO = HOLD (01 s4.3); HOLD; PATROL / GUARD hold in v1


func _mode(id: int, s: int, m: int, st: AiState, sink: CommandSink, tick: int) -> void:
	if st.mode[s] != m:
		sink.set_ai_tag(id, m)
		st.set_mode(id, m, tick)


func _reset(s: int, st: AiState, sink: CommandSink) -> void:
	GroundFollower.clear(s, st, sink)
	st.ground.strikes[s] = 0
	st.bflags[s] &= ~(B_ARRIVED | B_NOPATH | B_BLAST)
	st.aux_id[s] = 0
	st.fire_mask[s] = 0


func _hold(id: int, s: int, st: AiState, sink: CommandSink, tick: int) -> void:
	if st.mode[s] != AiTag.Tag.HOLD:
		_reset(s, st, sink)
	_mode(id, s, AiTag.Tag.HOLD, st, sink, tick)


func _move(id: int, s: int, point: Vector3, p: Vector3, view: SimView, st: AiState, sink: CommandSink, tick: int) -> void:
	if st.mode[s] != AiTag.Tag.MOVE:
		_mode(id, s, AiTag.Tag.MOVE, st, sink, tick)
		_start(s, p, point, st, sink, tick)
	elif (st.bflags[s] & B_ARRIVED) == 0:
		_route_health(id, s, p, view, st, sink, tick)


# Asks for a route to `goal`; the unit waits (BRAKE within the run rule) until it arrives.
func _start(s: int, p: Vector3, goal: Vector3, st: AiState, sink: CommandSink, tick: int) -> void:
	st.bflags[s] &= ~(B_ARRIVED | B_NOPATH)
	st.fire_mask[s] = 0
	var _ok: bool = GroundFollower.request(s, p, goal, prm.mask, st, sink, tick)


# --- siege -----------------------------------------------------------------------------------------------------------

func _siege(id: int, s: int, t: int, team: int, p: Vector3, view: SimView, st: AiState, sink: CommandSink, tick: int) -> void:
	if st.target[s] != t:
		st.set_target(s, t)
	if view.ammo(id) <= 0:
		_no_ammo(id, s, st, sink, tick)
		return
	st.bflags[s] &= ~B_EMPTY
	if (st.bflags[s] & B_GAVE_UP) != 0:
		_hold(id, s, st, sink, tick)
		return
	if t == 0 or not view.alive(t):
		_hold(id, s, st, sink, tick)             # gone (the order's end is the sim's C4, brains/MODULE.md Open)
		return
	var seen: bool = view.visible_to(team, t)
	if seen:
		var moved: bool = st.seen_tick[s] != 0 and st.home[s].distance_to(view.pos(t)) > prm.loft_tol_m
		st.home[s] = view.pos(t)
		st.seen_tick[s] = tick
		st.wp[s] = 1 if view.def_kind(t) == EntityStore.K_GROUND else 0   # a mover: fired at only while seen
		if moved:
			st.fire_mask[s] = 0                  # re-solve for the new aim point
	elif st.seen_tick[s] == 0:
		_hold(id, s, st, sink, tick)             # never seen under this order: nothing to aim at (vision only)
		return
	if (st.bflags[s] & B_BLAST) != 0:
		_relocate(id, s, p, st, sink, tick)
		return
	var m: int = st.mode[s]
	if m != AiTag.Tag.SIEGE and m != AiTag.Tag.RELOCATE:
		_mode(id, s, AiTag.Tag.SIEGE, st, sink, tick)
		_spot(s, p, p, sink, st, tick)
	elif (st.bflags[s] & B_ARRIVED) == 0:
		_route_health(id, s, p, view, st, sink, tick)
	else:
		_at_spot(id, s, p, seen or st.wp[s] == 0, st, sink, tick)


# Arrived: SIEGE; the spot must still be in the band of the (maybe moved) target and the unit on it; then the solve.
func _at_spot(id: int, s: int, p: Vector3, can_fire: bool, st: AiState, sink: CommandSink, tick: int) -> void:
	_mode(id, s, AiTag.Tag.SIEGE, st, sink, tick)
	if path_left(s, st):
		GroundFollower.clear(s, st, sink)
		st.ground.strikes[s] = 0
	if not prm.in_band(p.distance_to(st.home[s])) or GroundFollower.flat(p, st.goal[s]) > prm.ground.deviate_m:
		_spot(s, p, p, sink, st, tick)           # the target moved or the unit was pushed / driven off
		return
	if not can_fire:
		st.fire_mask[s] = 0                      # a ground unit out of sight is not fired at
		return
	if st.fire_mask[s] == 0:
		stats_solves += 1
		var muzzle: Vector3 = p + SiegeAim.tangent_to(p, st.home[s]) * prm.radius
		var e: float = SiegeAim.loft(muzzle, st.home[s], prm.speed, prm.shell, prm.rules, terrain, 2.0 * prm.dt,
			prm.max_steps, CrawlerParams.LOFT_ITERS, prm.loft_tol_m, _ps)
		if is_nan(e):
			st.aux_id[s] += 1                    # masked from here: the next ring candidate
			_spot(s, p, st.goal[s], sink, st, tick)
			return
		st.tti[s] = e
		st.fire_mask[s] = 1


static func path_left(s: int, st: AiState) -> bool:
	return GroundFollower.has_route(s, st) or st.path_ticket[s] >= 0


func _no_ammo(id: int, s: int, st: AiState, sink: CommandSink, tick: int) -> void:
	if (st.bflags[s] & B_EMPTY) == 0:
		stats_no_ammo += 1
		_hold(id, s, st, sink, tick)
		st.bflags[s] |= B_EMPTY
	else:
		_mode(id, s, AiTag.Tag.HOLD, st, sink, tick)


# A firing spot for the target at `home`: `p` itself when in the band on flat enough ground and no candidate is being
# skipped, else the first good ring point from the bearing toward `from`, by `aux_id` candidates on; none: HOLD.
func _spot(s: int, p: Vector3, from: Vector3, sink: CommandSink, st: AiState, tick: int) -> void:
	stats_spots += 1
	var t: Vector3 = st.home[s]
	if st.aux_id[s] == 0 and prm.in_band(p.distance_to(t)) and _good(p.normalized(), sink):
		st.goal[s] = p
		GroundFollower.clear(s, st, sink)
		st.bflags[s] |= B_ARRIVED
		st.bflags[s] &= ~B_NOPATH
		st.fire_mask[s] = 0
		return
	var tn: Vector3 = t.normalized()
	var bearing: Vector3 = SiegeAim.tangent_to(t, from)
	if bearing == Vector3.ZERO:
		bearing = Sphere.tangent_frame(tn).y
	var step: float = TAU / float(prm.samples)
	for k: int in range(st.aux_id[s], prm.samples):
		var turn: float = float((k + 1) >> 1) * step * (1.0 if (k & 1) == 0 else -1.0)
		var d: Vector3 = SiegeAim.ring_point(tn, bearing, turn, prm.spot_mid_m)
		if _good(d, sink):
			st.aux_id[s] = k
			_start(s, p, d * (Sphere.PLANET_RADIUS + terrain.height_at(d)), st, sink, tick)
			return
	st.bflags[s] |= B_GAVE_UP                    # no spot: the next think holds (UNREACHABLE needs the sim's C5 call)
	stats_gave_up += 1


# A spot stands on ground no steeper than `slope_max_deg` and on a path cell that does not block.
func _good(d: Vector3, sink: CommandSink) -> bool:
	if terrain.slope_deg_at_dir(d) > prm.slope_max_deg:
		return false
	var pa: Pathing = sink.pathing()
	return pa == null or not PathGrid.blocks(pa.weight(PathGrid.cell_of(d)))


# A near bomb: `relocate_step_m` along the ring from the current spot, the side away from the impact first, then the
# other side, then two and three steps; none: a fresh ring search.
func _relocate(id: int, s: int, p: Vector3, st: AiState, sink: CommandSink, tick: int) -> void:
	st.bflags[s] &= ~B_BLAST
	stats_relocations += 1
	_mode(id, s, AiTag.Tag.RELOCATE, st, sink, tick)
	var t: Vector3 = st.home[s]
	var tn: Vector3 = t.normalized()
	var bearing: Vector3 = SiegeAim.tangent_to(t, p)
	if bearing == Vector3.ZERO:
		bearing = Sphere.tangent_frame(tn).y
	var away: float = -1.0 if SiegeAim.heading_error(t, bearing, st.land_mark[s]) > 0.0 else 1.0
	var step: float = prm.relocate_step_m / prm.spot_mid_m
	for k: int in 6:
		var turn: float = away * step * float(1 + (k >> 1)) * (1.0 if (k & 1) == 0 else -1.0)
		var d: Vector3 = SiegeAim.ring_point(tn, bearing, turn, prm.spot_mid_m)
		if _good(d, sink):
			_start(s, p, d * (Sphere.PLANET_RADIUS + terrain.height_at(d)), st, sink, tick)
			return
	st.aux_id[s] = 1
	_spot(s, p, p, sink, st, tick)


# --- route health (05 s5.7, as the Harvester) ------------------------------------------------------------------------

func _route_health(id: int, s: int, p: Vector3, view: SimView, st: AiState, sink: CommandSink, tick: int) -> void:
	var g: AiGround = st.ground
	if (st.bflags[s] & B_NOPATH) != 0:
		st.bflags[s] &= ~B_NOPATH
		g.strikes[s] = maxi(g.strikes[s], 1)
		_strike(id, s, p, st, sink, tick)
	elif st.path_ticket[s] >= 0:
		if tick - g.req[s] >= prm.ground.path_wait_ticks:
			_strike(id, s, p, st, sink, tick)
	elif not GroundFollower.has_route(s, st):
		_start(s, p, st.goal[s], st, sink, tick)
	elif GroundFollower.changed(s, st, view) or GroundFollower.off_route(s, p, st, prm.ground):
		_start(s, p, st.goal[s], st, sink, tick)
	elif GroundFollower.stuck(s, p, tick, st, prm.ground):
		_strike(id, s, p, st, sink, tick)


# Strike 1: repath. Strike 2: the next ring candidate (MOVE: repath). Strike 3: give the destination up and hold.
func _strike(id: int, s: int, p: Vector3, st: AiState, sink: CommandSink, tick: int) -> void:
	stats_strikes += 1
	var n: int = st.ground.strikes[s] + 1
	st.ground.strikes[s] = n
	var m: int = st.mode[s]
	if n == 1 or (m == AiTag.Tag.MOVE and n == 2):
		_start(s, p, st.goal[s], st, sink, tick)
	elif n == 2:
		st.aux_id[s] += 1
		_spot(s, p, st.goal[s], sink, st, tick)
	else:
		stats_gave_up += 1
		_hold(id, s, st, sink, tick)
		st.bflags[s] |= B_GAVE_UP if m != AiTag.Tag.MOVE else 0
