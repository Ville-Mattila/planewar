class_name AttackRun extends RefCounted
## The 05 s6.3 AttackRun sub-machine (AI-13; Dart now, Lancer / Bomber with AI-14): R1 ROUTE to an initial point
## `ip_dist_m` from the aim point at the ingress band, R2 RUN-IN straight at it (Deck and Low level; the Dart's dive
## from `band_high_agl_m` at `dive_angle_deg` otherwise), R3 RELEASE on the bomb sight (`Ballistics.predict_impact`
## at think, the closed-form refinement each tick: `flat_impact` now plus the think's stepped-minus-flat offset, which
## is `shift_impact`'s arithmetic in one stored vector), R4 EGRESS (turn `egress_turn_deg` away, deck, boost; flip on
## an inbound rocket), R5 REATTACK (bombs left, target alive, not aborted, passes < `max_passes`) or DONE.
## Ingress band (R1): **Deck** when a visible enemy Flak or Missile tower covers the aim point and no Autocannon does,
## **High** with Autocannon only, otherwise **Low**; the towers come from one structure query around the aim point
## (the threat map of 05 s7.4 does not exist yet, so the IP bearing is the direct one and only towers the team sees
## count; re-evaluated at R1 and R2 thinks). Abort (to R4): hp01 < `abort_hp01` during R2.
## State in AiState: `sub` = step | band << 4, `passes`, `goal` (aim point), `guidance_point` (IP, then the egress
## heading), `aim_lead` (bomb-sight offset), `wp` (bombs left when the stick ends), `timer` (step start tick), and the
## `bflags` bits below. No allocation except `ids_near` (the SimView list getter).

enum Step { NONE, ROUTE, RUN_IN, RELEASE, EGRESS, REATTACK, DONE }
enum Band { LOW, DECK, HIGH }
const F_ABORTED: int = 4         ## bflags: the run was aborted (no reattack)
const F_RELEASING: int = 8       ## bflags: the stick is being released (FIRE2 held)
const F_DIVING: int = 64         ## bflags: the Dart's R2 dive has begun
const F_BOOST: int = 16          ## bflags: BOOST wanted (shared with the brain)
const F_FLIP: int = 32           ## bflags: FLIP on the next act (shared with the brain)

var prm: DartParams
var terrain: Terrain
var dart_dive: bool = true       ## the Dart dives from the High band; a level bomber clears this (AI-14)
var _ps: ProjectileState = ProjectileState.new()


func _init(params: DartParams, t: Terrain) -> void:
	prm = params
	terrain = t


static func step_of(st: AiState, s: int) -> int:
	return st.sub[s] & 15


static func band_of(st: AiState, s: int) -> int:
	return st.sub[s] >> 4


## Starts a run on `aim` (R1, pass 0); `passes` are kept by a reattack.
func begin(id: int, view: SimView, st: AiState, aim: Vector3, tick: int) -> void:
	var s: int = EntityId.slot(id)
	st.goal[s] = aim
	st.passes[s] = 0
	st.bflags[s] &= ~(F_ABORTED | F_RELEASING | F_DIVING)
	_route(id, view, st, tick)


## One think of the run on `target` (0: a ground point, `goal`). Writes `guidance_vel`; returns the step.
func think(id: int, target: int, view: SimView, st: AiState, tick: int) -> int:
	var s: int = EntityId.slot(id)
	if target != 0 and view.alive(target) and view.visible_to(view.team(id), target):
		st.goal[s] = view.pos(target)
	var step: int = step_of(st, s)
	var p: Vector3 = view.pos(id)
	var v: Vector3 = view.vel(id)
	var up: Vector3 = p.normalized()
	var agl: float = p.length() - Sphere.PLANET_RADIUS - st.ground_h[s]
	if step == Step.ROUTE:
		_set_band(id, view, st, s)
		if Guidance.ground_dist(p, st.guidance_point[s]) < prm.ip_arrive:
			step = _set_step(st, s, Step.RUN_IN, tick)
	elif step == Step.RUN_IN or step == Step.RELEASE:
		step = _run_in(id, s, p, v, view, st, tick)
	elif step == Step.EGRESS and tick - roundi(st.timer[s]) >= prm.egress_ticks:
		step = _set_step(st, s, Step.REATTACK, tick)
	if step == Step.REATTACK:
		step = _reattack(id, target, view, st, tick)
	_guide(s, step, p, v, up, agl, st)
	return step_of(st, s)


## Act for one tick: the R3 sight and the stick (FIRE2), BOOST in egress, FLIP on an inbound rocket. Writes buttons only.
func act(id: int, view: SimView, st: AiState, out: PilotInput) -> void:
	var s: int = EntityId.slot(id)
	var step: int = step_of(st, s)
	if step == Step.EGRESS:
		out.buttons |= PilotInput.BOOST
		if view.incoming_rockets(id) > 0 and view.flip_cooldown01(id) <= 0.0:
			out.buttons |= PilotInput.FLIP
		return
	if step != Step.RELEASE:
		return
	if (st.bflags[s] & F_RELEASING) != 0:
		if view.bombs(id) > st.wp[s]:
			out.buttons |= PilotInput.FIRE2
		else:
			st.bflags[s] &= ~F_RELEASING
			var _e: int = _egress(id, view, st, view.tick())
		return
	var p: Vector3 = view.pos(id)
	var v: Vector3 = view.vel(id)
	var aim: Vector3 = st.goal[s]
	var hit: Vector4 = Ballistics.flat_impact(p, v, prm.bomb_def, prm.rules, terrain.height_at(aim))
	if not Ballistics.has_impact(hit):
		return
	var imp: Vector3 = Vector3(hit.x, hit.y, hit.z) + st.aim_lead[s]
	var up: Vector3 = aim.normalized()
	var h: Vector3 = Guidance.toward(p, aim, up)
	var miss: Vector3 = aim - imp
	miss -= up * miss.dot(up)
	var along: float = miss.dot(h)
	var n: int = _stick(id, view, st)
	var centre: float = 0.5 * float(n - 1) * v.length() * prm.bomb_interval   # the stick straddles the aim point
	if (miss - h * along).length() <= prm.release_tol and along <= centre + prm.release_tol:
		st.wp[s] = maxi(view.bombs(id) - n, 0)
		st.bflags[s] |= F_RELEASING
		out.buttons |= PilotInput.FIRE2


# 05 s6.3 stick: min(bombs, ceil(target hp / bomb damage)); a ground point gets every bomb (full salvo, 05 s3.2).
func _stick(id: int, view: SimView, st: AiState) -> int:
	var t: int = st.target[EntityId.slot(id)]
	var n: int = view.bombs(id)
	if t == 0 or not view.alive(t) or prm.bomb_damage <= 0.0:
		return n
	var hp: float = view.hp01(t) * prm.hp_by_def[clampi(view.def_id(t), 0, DefRanges.END - 1)]
	return clampi(ceili(hp / prm.bomb_damage), 1, n)


func _route(id: int, view: SimView, st: AiState, tick: int) -> void:
	var s: int = EntityId.slot(id)
	var p: Vector3 = view.pos(id)
	var aim: Vector3 = st.goal[s]
	var up: Vector3 = aim.normalized()
	var out_dir: Vector3 = Guidance.toward(aim, p, up)
	var a: float = prm.ip_dist / aim.length()
	st.guidance_point[s] = (up * cos(a) + out_dir * sin(a)) * aim.length()
	st.sub[s] = Step.ROUTE
	_set_band(id, view, st, s)
	st.timer[s] = float(tick)
	var v: Vector3 = view.vel(id)
	var to: Vector3 = Guidance.toward(p, aim, p.normalized())
	var h: Vector3 = v - p.normalized() * v.dot(p.normalized())
	if Guidance.ground_dist(p, aim) <= prm.ip_dist and h.length_squared() > 1.0 and h.angle_to(to) <= prm.continue_rad:
		var _r: int = _set_step(st, s, Step.RUN_IN, tick)   # 05 s2.5: within the IP distance and 30 degrees of the nose


# R1 band from the visible enemy towers covering the aim point (one structure query).
func _set_band(id: int, view: SimView, st: AiState, s: int) -> void:
	var aim: Vector3 = st.goal[s]
	var team: int = view.team(id)
	var seen: int = 0
	for t: int in view.ids_near(aim, prm.threat_scan, Spatial.MASK_STRUCTURE):
		var d: int = view.def_id(t)
		if d < 0 or d >= DefRanges.END or prm.threat_kind[d] == DartParams.THREAT_NONE:
			continue
		if view.team(t) == team or not view.visible_to(team, t):
			continue
		if view.pos(t).distance_to(aim) <= prm.threat_range[d]:
			seen |= prm.threat_kind[d]
	var band: int = Band.LOW
	if (seen & DartParams.THREAT_GUN) == 0 and (seen & (DartParams.THREAT_FLAK | DartParams.THREAT_MISSILE)) != 0:
		band = Band.DECK
	elif seen == DartParams.THREAT_GUN:
		band = Band.HIGH
	st.sub[s] = (st.sub[s] & 15) | (band << 4)


func _set_step(st: AiState, s: int, step: int, tick: int) -> int:
	st.sub[s] = (st.sub[s] & ~15) | step
	st.timer[s] = float(tick)
	return step


# R2 / R3 transitions at think: abort, the dive start, the sight refresh (stepped prediction), the miss.
func _run_in(id: int, s: int, p: Vector3, v: Vector3, view: SimView, st: AiState, tick: int) -> int:
	var step: int = step_of(st, s)
	if step == Step.RUN_IN:
		_set_band(id, view, st, s)
		if view.hp01(id) < prm.abort_hp01:
			st.bflags[s] |= F_ABORTED
			return _egress(id, view, st, tick)
	if view.bombs(id) <= 0:
		return _egress(id, view, st, tick)
	if (st.bflags[s] & F_RELEASING) != 0:
		return step
	var aim: Vector3 = st.goal[s]
	var up: Vector3 = aim.normalized()
	var h: Vector3 = Guidance.toward(p, aim, up)
	var gh: float = terrain.height_at(aim)
	var flat: Vector4 = Ballistics.flat_impact(p, v, prm.bomb_def, prm.rules, gh)
	if not Ballistics.has_impact(flat):
		return step
	var along: float = (aim - Vector3(flat.x, flat.y, flat.z)).dot(h)
	if along < -prm.release_tol and step == Step.RELEASE:
		return _egress(id, view, st, tick)   # overflown without a release: a miss, the pass counts
	var horizon: float = v.length() * prm.dt * float(3 * prm.think_ticks)   # the sight refines before the release window
	if step == Step.RUN_IN and along > horizon:
		return step
	var hit: Vector4 = Ballistics.predict_impact(p, v, prm.bomb_def, prm.rules, terrain, prm.predict_dt, prm.predict_dt,
		0.0, prm.predict_steps, _ps)
	if Ballistics.has_impact(hit):
		st.aim_lead[s] = Vector3(hit.x - flat.x, hit.y - flat.y, hit.z - flat.z)
	return _set_step(st, s, Step.RELEASE, tick) if step == Step.RUN_IN else step


func _egress(id: int, view: SimView, st: AiState, tick: int) -> int:
	var s: int = EntityId.slot(id)
	var p: Vector3 = view.pos(id)
	var up: Vector3 = p.normalized()
	var v: Vector3 = view.vel(id)
	var h: Vector3 = v - up * v.dot(up)
	if h.length_squared() < 1.0:
		h = Guidance.toward(st.goal[s], p, up)
	var turn: float = prm.egress_turn_rad if (EntityId.slot(id) & 1) == 0 else -prm.egress_turn_rad
	st.guidance_point[s] = h.normalized().rotated(up, turn)
	st.bflags[s] &= ~(F_RELEASING | F_DIVING)
	return _set_step(st, s, Step.EGRESS, tick)


func _reattack(id: int, target: int, view: SimView, st: AiState, tick: int) -> int:
	var s: int = EntityId.slot(id)
	var alive: bool = target == 0 or view.alive(target)
	if view.bombs(id) > 0 and alive and (st.bflags[s] & F_ABORTED) == 0 and st.passes[s] + 1 < prm.max_passes:
		st.passes[s] += 1
		_route(id, view, st, tick)
		return step_of(st, s)
	return _set_step(st, s, Step.DONE, tick)


# Guidance of the step into `guidance_vel` (cruise speed; terrain lift applied by the caller).
func _guide(s: int, step: int, p: Vector3, v: Vector3, up: Vector3, agl: float, st: AiState) -> void:
	var u: float = v.length()
	var band: float = _band_agl(band_of(st, s))
	var alt: float = p.length() - Sphere.PLANET_RADIUS
	var speed: float = prm.cruise_speed
	var dir: Vector3 = Guidance.toward(p, st.goal[s], up)
	if step == Step.ROUTE:
		dir = Guidance.toward(p, st.guidance_point[s], up)
	elif step == Step.EGRESS or step == Step.DONE:
		var g: Vector3 = st.guidance_point[s]
		dir = (g - up * g.dot(up)).normalized() if step == Step.EGRESS else dir
		band = prm.deck_agl
	elif dart_dive and band_of(st, s) != Band.DECK:
		band = prm.band_high
		if _dive(s, p, st, agl):
			st.guidance_vel[s] = (dir * cos(prm.dive_rad) - up * sin(prm.dive_rad)) * speed
			return
	if band == prm.deck_agl:
		speed = prm.deck_speed   # the Deck band's ridge-climbing energy (SC-09)
	var vz: float = Guidance.band_vz(agl, band, alt, prm.max_alt, prm.kp_alt, prm.vz_max)
	st.guidance_vel[s] = Guidance.level(dir, speed, vz, u, up)


# The Dart's dive (R2, not Deck): starts where the dive line through the release height (`dive_release_frac` of the
# band) meets the bomb's flat-ground throw from there; held once begun.
func _dive(s: int, p: Vector3, st: AiState, agl: float) -> bool:
	if (st.bflags[s] & F_DIVING) != 0:
		return true
	var hr: float = prm.band_high * prm.dive_release_frac
	var u: float = prm.cruise_speed
	var vz0: float = u * sin(prm.dive_rad) + prm.bomb_def.eject_down_mps
	var t: float = (-vz0 + sqrt(vz0 * vz0 + 2.0 * prm.gravity * hr)) / prm.gravity
	var x_start: float = u * cos(prm.dive_rad) * t + maxf(agl - hr, 0.0) / tan(prm.dive_rad)
	if Guidance.ground_dist(p, st.goal[s]) <= x_start and agl > hr:
		st.bflags[s] |= F_DIVING
		return true
	return false


func _band_agl(band: int) -> float:
	if band == Band.DECK:
		return prm.deck_agl
	return prm.band_high if band == Band.HIGH else prm.band_low
