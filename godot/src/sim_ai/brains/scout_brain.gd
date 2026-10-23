class_name ScoutBrain extends DartBrain
## The Scout autopilot (05 s6.4, AI-14) on the DartBrain pipeline; unarmed, so it never takes a target
## (`DartModes.engages` off) and the RTB rule has no ammo term.
## AUTO = SEARCH (expanding search): the team's `last_seen` per interest cell (the driver's TeamIntel ThreatMap, 384
## cells, refreshed at 1 Hz from the team's sensors, the Scout's own included) gives each cell a staleness; the Scout
## flies at `search.agl_m` toward the cell maximising `staleness_s / (1 + dist_km)` among the cells within its fuel
## radius (out there and back home at cruise, `rtb.fuel_reserve_s` kept) and with no air threat on the map, then the
## next once the team has seen its cell since the choice, or the map shows an air threat in it (the scan runs at most
## once per choice period). No cell qualifies (all fresh, threatened or out of fuel reach) or no intel: it flies the
## AUTO patrol circle round home (PATROL) and re-scans on the period; the RTB rule takes it home at the fuel floor.
## FLEE (every think, before the order, also on the way home until the landing's approach): an armed enemy ship the
## team sees within `flee_radius_m` and closing (or flying at the Scout) -> turn
## directly away (FLIP first when it is ahead and the flip is ready), down to the deck band, BOOST, for `search.flee_s`
## or until it is beyond `search.flee_clear_m`; then the order or the search resumes. ORDERED MOVE / PATROL make it a
## picket (the DartModes legs, no choice point). State: `goal` = the chosen cell's ground point, `timer` = the choice
## (SEARCH) or flee start (FLEE) tick, `target` = the threat while fleeing, `guidance_point` = the flee heading.

var sp: ScoutParams
var stats_scans: int = 0         ## cell scans (at most one per choice period per Scout)
var stats_flees: int = 0         ## FLEE starts


## The Scout brain from content (`ap` = ap_scout's dictionary); null when a required block is missing.
static func create(c: ContentSet, ap: Dictionary, def: ShipDef, t: Terrain, ring2_m: float = INF) -> ScoutBrain:
	var b: ScoutBrain = ScoutBrain.new()
	if not DartBrain.fill(b, c, ap, def, t, ring2_m, false, false):
		return null
	b.sp = ScoutParams.from_content(ap, def, c)
	if b.sp == null:
		return null
	b.modes.engages = false
	return b


func _dispatch(id: int, s: int, m: int, head: OrderSpec, kind: int, view: SimView, st: AiState, tick: int) -> int:
	st.bflags[s] &= ~AttackRun.F_BOOST
	var landing: bool = m == AiTag.Tag.RETURN and st.land_phase[s] != LandingController.Phase.TRANSIT
	if not landing and _flee(id, s, m, view, st, tick):
		return AiTag.Tag.FLEE   # also on the way home: a RETURN restarts its landing after the flee
	if kind == OrderSpec.Kind.RETURN:
		return modes.think_return(id, s, m, head, view, st, tick)
	if kind == OrderSpec.Kind.MOVE:
		return modes.think_move(id, s, head, view, st)
	if kind >= 0:
		return modes.think_patrol(id, s, m, head, kind, view, st, tick)
	return _search(id, s, m, view, st, tick)


# FLEE: true while fleeing (a running flee or a new threat); writes the heading and the command.
func _flee(id: int, s: int, m: int, view: SimView, st: AiState, tick: int) -> bool:
	var p: Vector3 = view.pos(id)
	var team: int = view.team(id)
	var t: int = st.target[s] if m == AiTag.Tag.FLEE else 0
	if t != 0 and (tick - roundi(st.timer[s]) >= sp.flee_ticks or not view.alive(t) or not view.visible_to(team, t)
			or p.distance_to(view.pos(t)) > sp.flee_clear):
		t = 0
	if t == 0:
		st.set_target(s, 0)
		t = _threat(id, p, view, team, tick)
		if t == 0:
			return false
		st.set_target(s, t)
		st.timer[s] = float(tick)
		stats_flees += 1
		var ahead: bool = (view.pos(t) - p).dot(-view.basis(id).z) > 0.0
		if ahead and view.flip_cooldown01(id) <= 0.0:
			st.bflags[s] |= AttackRun.F_FLIP
	var up: Vector3 = p.normalized()
	var away: Vector3 = Guidance.toward(view.pos(t), p, up)   # directly away from the threat
	st.guidance_point[s] = away
	st.bflags[s] |= AttackRun.F_BOOST
	var agl: float = p.length() - Sphere.PLANET_RADIUS - st.ground_h[s]
	var vz: float = Guidance.band_vz(agl, prm.deck_agl, p.length() - Sphere.PLANET_RADIUS, prm.max_alt, prm.kp_alt, prm.vz_max)
	st.guidance_vel[s] = Guidance.level(away, prm.boost_speed, vz, view.vel(id).length(), up)
	return true


# The nearest armed enemy ship the team sees within `flee_radius_m` that is closing (0: none). The TeamPicture list.
# Closing: the gap shrinks or the enemy flies toward the Scout (a pursuer holding the gap still counts).
func _threat(id: int, p: Vector3, view: SimView, team: int, tick: int) -> int:
	var n: int = modes.picture.near(view, team, tick, p, sp.flee_radius)
	var ids: PackedInt32Array = modes.picture.near_ids()
	var v: Vector3 = view.vel(id)
	var best: int = 0
	var best_d2: float = INF
	for i: int in n:
		var e: int = ids[i]
		var d: int = view.def_id(e)
		if d < 0 or d >= DefRanges.END or sp.armed_by_def[d] == 0:
			continue
		var rel: Vector3 = view.pos(e) - p
		var ve: Vector3 = view.vel(e)
		if rel.dot(ve - v) >= 0.0 and rel.dot(ve) >= 0.0:
			continue   # opening and flying away
		var d2: float = rel.length_squared()
		if d2 < best_d2:
			best_d2 = d2
			best = e
	return best


# SEARCH: keep the chosen cell until the team has seen it since the choice (or the Scout is over it), then re-scan at
# most once per choice period; fly to it at `search.agl_m`.
func _search(id: int, s: int, m: int, view: SimView, st: AiState, tick: int) -> int:
	var map: ThreatMap = modes.intel.threat_map(view.team(id)) if modes.intel != null else null
	if map == null:
		return modes.think_patrol(id, s, m, null, -1, view, st, tick)
	var p: Vector3 = view.pos(id)
	var chosen: int = roundi(st.timer[s])
	var need: bool = m != AiTag.Tag.SEARCH or st.goal[s] == Vector3.ZERO
	if not need:
		var c: int = map.tables.cell_of(st.goal[s], -1)
		need = map.last_seen[c] >= chosen or Guidance.ground_dist(p, st.goal[s]) < prm.arrival \
			or map.threat_at(c, ThreatMap.AIR_HIGH) > 0.0   # seen, reached, or a threat moved in
	# PATROL is the fallback orbit (nothing qualified): it re-scans on the period like SEARCH
	var due: bool = tick - chosen >= prm.think_ticks * prm.choice_period \
		or (m != AiTag.Tag.SEARCH and m != AiTag.Tag.PATROL)
	if need and due:
		var cell: int = _pick_cell(id, p, view, st, map, tick)
		var dir: Vector3 = map.tables.centre[cell] if cell >= 0 else Vector3.ZERO
		st.goal[s] = dir * (Sphere.PLANET_RADIUS + terrain.height_at(dir)) if cell >= 0 else Vector3.ZERO
		st.timer[s] = float(tick)
	if st.goal[s] == Vector3.ZERO:
		return modes.think_patrol(id, s, m, null, -1, view, st, tick)
	return modes.fly(id, s, Guidance.toward(p, st.goal[s], p.normalized()), sp.search_agl, view, st, AiTag.Tag.SEARCH)


# 05 s6.4 cell choice: max staleness_s / (1 + dist_km) over the cells with no air threat whose round trip (here -> cell
# -> home) fits the fuel at cruise less the reserve; the fuel test only for an improving cell. -1: none.
func _pick_cell(id: int, p: Vector3, view: SimView, st: AiState, map: ThreatMap, tick: int) -> int:
	stats_scans += 1
	var up: Vector3 = p.normalized()
	var home: Vector3 = st.home[EntityId.slot(id)].normalized()
	var reach: float = (view.fuel01(id) * sp.fuel_s - sp.fuel_reserve_s) * prm.cruise_speed
	var hz: float = float(prm.tick_hz)
	var centre: PackedVector3Array = map.tables.centre
	var seen: PackedInt32Array = map.last_seen
	var best: int = -1
	var best_u: float = 0.0
	for c: int in ThreatMap.CELLS:
		var ls: int = seen[c]
		var stale: float = float(tick - ls) / hz if ls >= 0 else float(tick + 1) / hz
		var d1: float = acos(clampf(up.dot(centre[c]), -1.0, 1.0)) * Sphere.PLANET_RADIUS
		var u: float = stale / (1.0 + d1 * 0.001)
		if u <= best_u or map.threat_at(c, ThreatMap.AIR_HIGH) > 0.0:
			continue
		if d1 + home.angle_to(centre[c]) * Sphere.PLANET_RADIUS > reach:
			continue
		best_u = u
		best = c
	return best
