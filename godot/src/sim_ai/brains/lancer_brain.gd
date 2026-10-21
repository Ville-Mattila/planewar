class_name LancerBrain extends DartBrain
## The Lancer autopilot (05 s6.4, AI-14) on the DartBrain pipeline. AUTO = GUARD: an orbit of `guard_orbit_radius_m`
## at its `cruise_alt_agl_m` (200) around the centroid of the friendly structures within `guard_cluster_m` of the home
## pad (one structure query when AUTO starts, `_on_home`), the choice point centred there over `guard_engage_radius_m`.
## Candidates are ground-first (`target_weights`): the team's visible enemy ships (TeamPicture) plus the enemy ground
## units and structures its Perception saw at the last refresh (`DartModes.ground`; structures count while under
## construction, the `structure_building` weight). A ship pick flies DartCombat (gun, 05 s6.2 rules); a ground pick an
## AttackRun with rockets (level at the band, R3 inside `lock_range_m` with the nose on the target, salvo
## ceil(hp / rocket damage)). ESCORT is its ordered job (EscortPilot, as the Dart).
## Rockets (05 s6.4; INTERCEPT, ENGAGE, R3): FIRE2 is held while the target stays inside the seeker's cone
## (`lock_cone_deg`) and within `lock_range_m`; the sim's seeker fires once that has held `lock_time_s` (02 s4.4), so the
## first rocket leaves `lock_ticks` after `AiState.lock_tick` (the brain's mirror of the lock start, 0 = none). While an
## enemy bomber is known (a Perception contact or ghost) within `bomber_known_m` (evaluated on the first think and every
## choice period into `fire_mask` FIRE_RESERVE), `bomber_reserve` rockets are kept for bombers. The gun fires in R3
## inside `fire_range_m` and the 05 s6.2 cone.

var lp: LancerParams
var stats_lock_starts: int = 0   ## lock attempts begun (lock_tick set)
var stats_fire2_acts: int = 0    ## acts holding FIRE2
var stats_cluster_queries: int = 0   ## structure queries of `_on_home` (one per AUTO start)
var stats_weapon_acts: int = 0   ## acts that ran the rocket / R3 weapons (INTERCEPT, ENGAGE, R3)
var stats_weapon_visible: int = 0   ## visible_to calls of those acts (exactly one each)


## The Lancer brain from content (`ap` = ap_lancer's dictionary); null when a required block is missing.
static func create(c: ContentSet, ap: Dictionary, def: ShipDef, t: Terrain, ring2_m: float = INF) -> LancerBrain:
	var b: LancerBrain = LancerBrain.new()
	if not DartBrain.fill(b, c, ap, def, t, ring2_m) or not b.prm.has_rockets:
		return null
	b.lp = LancerParams.from_content(ap, def, c)
	if b.lp == null:
		return null
	b.modes.auto_guard = true
	b.modes.ground = true
	var run: AttackRun = b.modes.run
	run.dart_dive = false
	run.rockets = true
	run.release_range = b.lp.lock_range
	run.breakaway = b.lp.breakaway
	run.round_damage = b.lp.rocket_damage
	run.reserve_rounds = b.lp.bomber_reserve
	return b


func _dispatch(id: int, s: int, m: int, head: OrderSpec, kind: int, view: SimView, st: AiState, tick: int) -> int:
	if modes.choice_due(s, tick) or (st.fire_mask[s] & AttackRun.FIRE_CHECKED) == 0:
		_reserve(id, s, view, st, tick)
	return super._dispatch(id, s, m, head, kind, view, st, tick)


# 05 s6.4: keep `bomber_reserve` rockets while an enemy bomber is known within `bomber_known_m`: a contact (seen or a
# remembered ghost) of the team's Perception, else (no intel) one the team sees now.
func _reserve(id: int, s: int, view: SimView, st: AiState, tick: int) -> void:
	var p: Vector3 = view.pos(id)
	var r2: float = lp.bomber_known * lp.bomber_known
	var known: bool = false
	var perc: Perception = modes.intel.perception(view.team(id)) if modes.intel != null else null
	if perc != null:
		for i: int in perc.n_known:
			var sl: int = perc.known[i]
			if perc.k_def[sl] == lp.bomber_def and p.distance_squared_to(perc.k_pos[sl]) <= r2:
				known = true
				break
	else:
		for e: int in modes.picture.enemies(view, view.team(id), tick):
			if view.def_id(e) == lp.bomber_def and view.alive(e) and p.distance_squared_to(view.pos(e)) <= r2:
				known = true
				break
	var f: int = st.fire_mask[s] & ~AttackRun.FIRE_RESERVE
	st.fire_mask[s] = f | AttackRun.FIRE_CHECKED | (AttackRun.FIRE_RESERVE if known else 0)


## AUTO GUARD centre: the centroid of the friendly structures within `guard_cluster_m` of the home pad (05 s6.4).
func _on_home(id: int, s: int, view: SimView, st: AiState) -> void:
	var home: Vector3 = st.home[s]
	var team: int = view.team(id)
	var sum: Vector3 = Vector3.ZERO
	var n: int = 0
	stats_cluster_queries += 1
	for e: int in view.ids_near(home, lp.guard_cluster, Spatial.MASK_STRUCTURE):
		if view.team(e) == team:
			sum += view.pos(e)
			n += 1
	if n > 0:
		st.home[s] = sum / float(n)


## INTERCEPT / ENGAGE: rockets on the lock (beside DartCombat's gun); R3 of a rocket run: rockets and the gun.
func _weapons(id: int, s: int, m: int, view: SimView, st: AiState, out: PilotInput, tick: int) -> void:
	var release: bool = m == AiTag.Tag.BOMB and AttackRun.step_of(st, s) == AttackRun.Step.RELEASE
	if m != AiTag.Tag.ENGAGE and m != AiTag.Tag.INTERCEPT and not release:
		st.lock_tick[s] = 0
		if m == AiTag.Tag.BOMB:
			modes.run.act(id, view, st, out)   # EGRESS boost / flip
		return
	var t: int = st.target[s]
	stats_weapon_acts += 1
	stats_weapon_visible += 1
	if t == 0 or not view.visible_to(view.team(id), t):
		st.lock_tick[s] = 0
		return
	var p: Vector3 = view.pos(id)
	var rel: Vector3 = view.pos(t) - p
	var d: float = rel.length()
	var nose: Vector3 = -view.basis(id).z
	var hold: bool = d > 0.0 and d <= lp.lock_range and nose.dot(rel / d) >= lp.cone_cos \
		and view.rockets(id) > _keep(s, m, t, view, st)
	if hold:
		if st.lock_tick[s] == 0:
			st.lock_tick[s] = tick
			stats_lock_starts += 1
		stats_fire2_acts += 1
		out.buttons |= PilotInput.FIRE2
	else:
		st.lock_tick[s] = 0
	if release and d > 0.0 and d < prm.fire_range and view.ammo(id) > 0 \
			and AimSolver.in_fire_cone(nose, rel / d, prm.fire_cone_k, view.radius(t), d):
		out.buttons |= PilotInput.FIRE1


# Rockets that must stay: in R3 the pass's end count (`wp`, the reserve included); in ENGAGE the bomber reserve unless
# the target is a bomber.
func _keep(s: int, m: int, t: int, view: SimView, st: AiState) -> int:
	if m == AiTag.Tag.BOMB:
		return st.wp[s]
	if (st.fire_mask[s] & AttackRun.FIRE_RESERVE) == 0 or view.def_id(t) == lp.bomber_def:
		return 0
	return lp.bomber_reserve
