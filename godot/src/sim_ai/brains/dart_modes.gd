class_name DartModes extends RefCounted
## The Dart's per-order thinks (05 s6.2, s3.2; AI-13), called by `DartBrain` once per think: RETURN (LandingPilot; no
## pad: LOITER over home at `no_pad_loiter_altitude_m`, pad selection retried each choice period), ESCORT (EscortPilot;
## its engagements fly DartCombat), ATTACK (a ship: DartCombat on it; a structure / ground unit / point: AttackRun),
## MOVE (band: Deck with FLAG_LOW at `deck_speed_mps`, else the point's AGL or `default_move_agl_m`; orbits the point
## once arrived),
## PATROL legs, HOLD / GUARD orbits (`order_rules.json` radii) and the AUTO patrol (6 points on `patrol_radius_m`
## around home at `cruise_alt_agl_m`). The target choice point (TargetChooser.choose_ship over the TeamPicture's visible
## enemy ships within the radius) runs every `choice_period_thinks`, staggered by slot (TC2: at most every other think).
## Each returns the next DartBrain.Mode and leaves the command in `guidance_vel` (shaped by the brain).
## AI-14 switches: `engages` false (Bomber, Scout) flies PATROL / GUARD / AUTO without the choice point; `auto_guard`
## (Lancer) makes AUTO a GUARD orbit around `home`; `ground` (Lancer) adds the team's seen enemy ground units and
## structures (its Perception contacts of the last refresh, `intel`) to the candidates, and a ground pick flies an
## AttackRun (mode BOMB) instead of DartCombat.

const B_RUN_DONE: int = 2

var prm: DartParams
var terrain: Terrain
var landing: LandingPilot
var escort: EscortPilot
var run: AttackRun
var combat: DartCombat
var targets: TargetParams
var stats_choices: int = 0
var picture: TeamPicture = TeamPicture.new()   ## per-tick visible enemy ships per team (the choice points' candidates)
var intel: TeamIntel = null      ## AI-14: the driver's per-team intel (AiBrain.bind_intel); null: none
var engages: bool = true         ## AI-14: the choice point runs (false: Bomber, Scout)
var auto_guard: bool = false     ## AI-14: AUTO is a GUARD orbit around home (Lancer, 05 s6.4)
var ground: bool = false         ## AI-14: ground units and structures are candidates (Lancer, 05 s6.4)
var stats_ground: int = 0        ## AI-14: ground candidates added (work counter)
var _cand: PackedInt32Array = PackedInt32Array()
var _ctx: Array[TargetContext] = []
var _pick: PackedInt32Array = PackedInt32Array()


func _init(params: DartParams, t: Terrain, lp: LandingPilot, ep: EscortPilot, ar: AttackRun, dc: DartCombat,
		tp: TargetParams) -> void:
	prm = params
	terrain = t
	landing = lp
	escort = ep
	run = ar
	combat = dc
	targets = tp
	var _p: int = _pick.resize(tp.max_candidates)
	picture.period = params.vision_period
	for k: int in PlayerTable.TEAMS:
		_ctx.append(TargetContext.new())


## Patrol waypoint `k` of `n` on the `radius` circle around `home` (05 s6.2: 6 points, 1,200 m).
static func patrol_point(home: Vector3, k: int, n: int, radius: float) -> Vector3:
	var up: Vector3 = home.normalized()
	var f: Basis = Sphere.tangent_frame(up)
	var a: float = radius / home.length()
	var th: float = TAU * float(k % n) / float(n)
	return (up * cos(a) + (f.x * cos(th) + f.y * sin(th)) * sin(a)) * home.length()


static func is_combat(m: int) -> bool:
	return m == AiTag.Tag.INTERCEPT or m == AiTag.Tag.ENGAGE or m == AiTag.Tag.EXTEND \
		or m == AiTag.Tag.EVADE


func think_return(id: int, s: int, m: int, head: OrderSpec, view: SimView, st: AiState, tick: int) -> int:
	if m != AiTag.Tag.RETURN:
		var pad: int = head.target if head.target != 0 and view.alive(head.target) else 0
		if pad == 0 and (m != AiTag.Tag.LOITER or choice_due(s, tick)):
			pad = landing.select_pad(id, view, 0, st)
		if pad == 0:
			return _orbit(id, s, st.home[s], prm.hold_orbit, prm.loiter_alt, view, st, AiTag.Tag.LOITER)
		landing.begin(id, pad, st)
	landing.think(id, view, st)
	return AiTag.Tag.RETURN


func think_escort(id: int, s: int, m: int, head: OrderSpec, view: SimView, st: AiState, tick: int) -> int:
	var threat: int = 0
	var utility: float = 0.0
	if choice_due(s, tick) and view.alive(head.target):
		var lp: Vector3 = view.pos(head.target)
		threat = _choose(id, s, view, st, lp, escort.prm.engage_radius_m, tick, false)
		if threat != 0:
			utility = targets.weight(view.def_id(threat), view.cargo(threat) > 0.0) / (1.0 + lp.distance_to(view.pos(threat)) / targets.falloff_m)
	var out: EscortPilot.Outcome = escort.think(id, view, st, tick, threat, utility)
	if out == EscortPilot.Outcome.ENGAGING:
		if not is_combat(m):
			st.seen_tick[s] = tick
		var cm: int = combat.think(id, m if is_combat(m) else AiTag.Tag.INTERCEPT, view, st, tick)
		return cm if cm != AiTag.Tag.NONE else AiTag.Tag.ESCORT
	if out == EscortPilot.Outcome.LOST:
		return think_patrol(id, s, m, null, -1, view, st, tick)
	return AiTag.Tag.ESCORT


func think_attack(id: int, s: int, m: int, head: OrderSpec, view: SimView, st: AiState, tick: int) -> int:
	var t: int = head.target
	if t != 0 and view.def_kind(t) == EntityStore.K_SHIP:
		var cm: int = combat.think(id, m if is_combat(m) else AiTag.Tag.INTERCEPT, view, st, tick)
		if cm != AiTag.Tag.NONE:
			return cm
		st.bflags[s] |= B_RUN_DONE
		return think_patrol(id, s, m, null, -1, view, st, tick)
	if m != AiTag.Tag.BOMB:
		if run.rounds(id, view) <= 0:
			st.bflags[s] |= B_RUN_DONE
			return think_patrol(id, s, m, null, -1, view, st, tick)
		var seen: bool = t != 0 and view.alive(t) and view.visible_to(view.team(id), t)
		if t != 0 and not seen:
			return think_patrol(id, s, m, null, -1, view, st, tick)   # never seen: no aim point to fly at (vision only)
		run.begin(id, view, st, view.pos(t) if seen else head.point, tick)
	if run.think(id, t, view, st, tick) != AttackRun.Step.DONE:
		return AiTag.Tag.BOMB
	st.bflags[s] |= B_RUN_DONE
	return think_patrol(id, s, AiTag.Tag.BOMB, null, -1, view, st, tick)


func think_move(id: int, s: int, head: OrderSpec, view: SimView, st: AiState) -> int:
	var to: Vector3 = head.point
	var agl_pt: float = to.length() - Sphere.PLANET_RADIUS - terrain.height_at(to)
	var band: float = prm.move_agl if agl_pt < prm.deck_agl else agl_pt
	if (head.flags & OrderSpec.FLAG_LOW) != 0:
		band = prm.deck_agl
	var p: Vector3 = view.pos(id)
	if Guidance.ground_dist(p, to) <= prm.arrival:
		st.sub[s] = 1                                  # arrived: orbit the point (completion is the sim's, C4)
	if st.sub[s] != 0:
		return _orbit(id, s, to, prm.hold_orbit, band, view, st, AiTag.Tag.MOVE)
	var speed: float = prm.deck_speed if (head.flags & OrderSpec.FLAG_LOW) != 0 else prm.cruise_speed
	return _fly(id, s, Guidance.toward(p, to, p.normalized()), band, view, st, AiTag.Tag.MOVE, speed)


## AUTO patrol around home, ordered PATROL legs, HOLD and GUARD orbits; the choice point; combat once engaged.
func think_patrol(id: int, s: int, m: int, head: OrderSpec, kind: int, view: SimView, st: AiState, tick: int) -> int:
	var p: Vector3 = view.pos(id)
	var origin: Vector3 = st.home[s]
	var radius: float = prm.intercept_radius
	var guard: bool = kind == OrderSpec.Kind.GUARD or (auto_guard and kind != OrderSpec.Kind.PATROL
		and kind != OrderSpec.Kind.HOLD)
	if kind == OrderSpec.Kind.PATROL:
		origin = p
		radius = prm.patrol_engage
	elif guard:
		if kind == OrderSpec.Kind.GUARD:
			origin = view.pos(head.target) if head.target != 0 and view.alive(head.target) else head.point
		radius = prm.guard_engage
	if engages and kind != OrderSpec.Kind.HOLD:
		var cm: int = _engagements(id, s, m, origin, radius, view, st, tick)
		if cm != AiTag.Tag.NONE:
			return cm
	if kind == OrderSpec.Kind.HOLD:
		var hold_agl: float = head.point.length() - Sphere.PLANET_RADIUS - terrain.height_at(head.point)
		return _orbit(id, s, head.point, prm.hold_orbit, maxf(prm.deck_agl, hold_agl), view, st, AiTag.Tag.HOLD)
	if guard:
		return _orbit(id, s, origin, prm.guard_orbit, prm.cruise_agl, view, st, AiTag.Tag.GUARD)
	return _legs(id, s, m, p, head if kind == OrderSpec.Kind.PATROL and head.points.size() >= 2 else null, view, st)


# Engaged modes and the choice point of think_patrol: an AUTO / PATROL / GUARD AttackRun on a picked ground target
# (Lancer), DartCombat on a ship, else a new pick on the choice period. NONE: nothing to fight.
func _engagements(id: int, s: int, m: int, origin: Vector3, radius: float, view: SimView, st: AiState, tick: int) -> int:
	if m == AiTag.Tag.BOMB:
		if st.target[s] != 0 and run.think(id, st.target[s], view, st, tick) != AttackRun.Step.DONE:
			return AiTag.Tag.BOMB
		st.set_target(s, 0)
	if is_combat(m):
		var cm: int = _engaged(id, s, m, origin, radius, view, st, tick)
		if cm != AiTag.Tag.NONE:
			return cm
	if choice_due(s, tick) or is_combat(m):
		if _choose(id, s, view, st, origin, radius, tick, true) != 0:
			st.seen_tick[s] = tick
			return _engage(id, s, view, st, tick)
	return AiTag.Tag.NONE


# A fresh pick: a ship -> INTERCEPT (DartCombat); a ground unit or structure (Lancer) -> an AttackRun on it.
func _engage(id: int, s: int, view: SimView, st: AiState, tick: int) -> int:
	var t: int = st.target[s]
	if view.def_kind(t) == EntityStore.K_SHIP or not ground:
		return combat.think(id, AiTag.Tag.INTERCEPT, view, st, tick)
	run.begin(id, view, st, view.pos(t), tick)
	var _step: int = run.think(id, t, view, st, tick)
	return AiTag.Tag.BOMB


# Engaged: the choice point re-runs on its period while the target is inside the radius (hysteresis keeps it); a target
# chased out of the radius is kept until it is lost (TC1 alone would drop it for any candidate). NONE: target gone.
func _engaged(id: int, s: int, m: int, origin: Vector3, radius: float, view: SimView, st: AiState, tick: int) -> int:
	var cur: int = st.target[s]
	if choice_due(s, tick) and cur != 0:
		var pick: int = _choose_engaged(id, s, view, st, origin, radius, tick)
		if pick != cur and pick != 0:
			st.set_target(s, pick)
			st.seen_tick[s] = tick
			return _engage(id, s, view, st, tick)
	var cm: int = combat.think(id, m, view, st, tick)
	if cm == AiTag.Tag.NONE:
		st.set_target(s, 0)
	return cm


# Patrol waypoints: the ordered PATROL legs (looped) or the AUTO circle around home.
func _legs(id: int, s: int, m: int, p: Vector3, legs: OrderSpec, view: SimView, st: AiState) -> int:
	var n: int = legs.points.size() if legs != null else prm.patrol_points
	if m != AiTag.Tag.PATROL or st.guidance_point[s] == Vector3.ZERO:
		st.wp[s] = _next_wp(p, st.home[s], legs, n)
		st.guidance_point[s] = _wp_pos(st.home[s], legs, st.wp[s], n)
	var wp: Vector3 = st.guidance_point[s]   # the waypoint, cached in PATROL (computed on entry and on each switch)
	if Guidance.ground_dist(p, wp) < prm.patrol_switch:
		st.wp[s] = (st.wp[s] + 1) % n
		st.guidance_point[s] = _wp_pos(st.home[s], legs, st.wp[s], n)
	return _fly(id, s, Guidance.toward(p, wp, p.normalized()), prm.cruise_agl, view, st, AiTag.Tag.PATROL)


## AI-14: `_fly` for the class brains (the Scout's search leg).
func fly(id: int, s: int, dir: Vector3, band: float, view: SimView, st: AiState, m: int, speed: float = -1.0) -> int:
	return _fly(id, s, dir, band, view, st, m, speed)


## Level flight along `dir` at `speed` (default cruise) in the `band` (AGL) hold.
func _fly(id: int, s: int, dir: Vector3, band: float, view: SimView, st: AiState, m: int, speed: float = -1.0) -> int:
	var p: Vector3 = view.pos(id)
	var agl: float = p.length() - Sphere.PLANET_RADIUS - st.ground_h[s]
	var vz: float = Guidance.band_vz(agl, band, p.length() - Sphere.PLANET_RADIUS, prm.max_alt, prm.kp_alt, prm.vz_max)
	st.guidance_vel[s] = Guidance.level(dir, speed if speed > 0.0 else prm.cruise_speed, vz, view.vel(id).length(),
		p.normalized())
	return m


## Orbit of `radius` around `c` (counter-clockwise from above): tangent plus the radial error, closed at full rate one
## radius out.
func _orbit(id: int, s: int, c: Vector3, radius: float, band: float, view: SimView, st: AiState, m: int) -> int:
	var p: Vector3 = view.pos(id)
	var up: Vector3 = p.normalized()
	var r: Vector3 = p - c
	r -= up * r.dot(up)
	var d: float = r.length()
	var rh: Vector3 = r / d if d > 1.0 else Sphere.tangent_frame(up).x
	var dir: Vector3 = (up.cross(rh) + rh * clampf((radius - d) / radius, -1.0, 1.0)).normalized()
	return _fly(id, s, dir, band, view, st, m)


## True on the think phase of `s` that runs the choice point (every `choice_period_thinks`, staggered by slot).
func choice_due(s: int, tick: int) -> bool:
	return (MathX.floori_div(tick, prm.think_ticks) + s) % prm.choice_period == 0


## Choice point (05 s6.2): visible enemy ships near `origin`. `take`: the pick becomes the target; an escort only reports
## it as its threat. The focus-fire counts are AiState.target_count (derived, S4-exact), copied for the candidates into
## the team's TargetContext scratch.
func _choose(id: int, s: int, view: SimView, st: AiState, origin: Vector3, radius: float, tick: int, take: bool) -> int:
	var cur: int = st.target[s] if take else 0
	var pick: int = _pick_near(id, view, st, origin, radius, cur, tick, take)
	if take:
		st.set_target(s, pick)
	return pick


## The engaged re-evaluation: hysteresis against the current target, which is kept when it just left the radius.
func _choose_engaged(id: int, s: int, view: SimView, st: AiState, origin: Vector3, radius: float, tick: int) -> int:
	var cur: int = st.target[s]
	var pick: int = _pick_near(id, view, st, origin, radius, cur, tick)
	if pick != cur and view.alive(cur) and view.visible_to(view.team(id), cur) and origin.distance_to(view.pos(cur)) > radius:
		return cur   # the current target just left the radius: kept (only a candidate's hysteresis may replace it)
	return pick


func _pick_near(id: int, view: SimView, st: AiState, origin: Vector3, radius: float, cur: int, tick: int,
		with_ground: bool = true) -> int:
	var team: int = view.team(id)
	if team < 0 or team >= _ctx.size():
		return 0
	stats_choices += 1
	var ctx: TargetContext = _ctx[team]
	var n: int = picture.near(view, team, tick, origin, radius)
	var cand: PackedInt32Array = picture.near_ids()
	var perc: Perception = intel.perception(team) if ground and with_ground and intel != null else null
	if perc != null:
		n = _with_ground(perc, cand, n, origin, radius)
		cand = _cand
	for i: int in n:
		var cs: int = EntityId.slot(cand[i])
		ctx.targeted_by[cs] = st.target_count[cs]
	return TargetChooser.choose_ship(view, team, cand, n, origin, radius, cur, tick, ctx, targets, _pick)


# The picture's `n` ships copied into `_cand`, then the Perception's enemy ground units and structures seen at its last
# refresh within `radius` of `origin` (their last-seen positions; the chooser re-checks visibility and position now).
func _with_ground(perc: Perception, ships: PackedInt32Array, n: int, origin: Vector3, radius: float) -> int:
	var need: int = n + perc.n_known
	if _cand.size() < need:
		var _r: int = _cand.resize(need)
	for i: int in n:
		_cand[i] = ships[i]
	var r2: float = radius * radius
	for i: int in perc.n_known:
		var sl: int = perc.known[i]
		var kind: int = DefRanges.kind_of(perc.k_def[sl])
		if perc.k_seen[sl] != perc.last_refresh or (kind != DefRanges.K_GROUND and kind != DefRanges.K_STRUCTURE):
			continue
		if origin.distance_squared_to(perc.k_pos[sl]) <= r2:
			_cand[n] = perc.k_id[sl]
			n += 1
			stats_ground += 1
	return n


func _wp_pos(home: Vector3, legs: OrderSpec, k: int, n: int) -> Vector3:
	return legs.points[k % n] if legs != null else patrol_point(home, k, n, prm.patrol_radius)


# The waypoint after the nearest one (a ship joining the circle flies on round it).
func _next_wp(p: Vector3, home: Vector3, legs: OrderSpec, n: int) -> int:
	var best: int = 0
	var best_d: float = INF
	for k: int in n:
		var q: Vector3 = legs.points[k] if legs != null else patrol_point(home, k, n, prm.patrol_radius)
		var d: float = p.distance_squared_to(q)
		if d < best_d:
			best_d = d
			best = k
	return (best + 1) % n
