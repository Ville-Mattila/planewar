class_name DartCombat extends RefCounted
## The Dart's air-to-air modes of 05 s6.2 (AI-13): INTERCEPT (lead pursuit `p_t + v_t t_close`, boost while farther
## than `boost_close_m`), ENGAGE (straight-line gun solution `AimSolver.lead_point`, R0 C1-03: slugs fly straight,
## launched at shooter velocity + `speed_mps`; `v_cmd` toward the lead at the target's speed + `engage_speed_margin_mps`;
## 0.6 s / 0.3 s bursts while the nose is inside `atan(fire_cone_k r / dist)` and dist < `fire_range_m`; per-burst aim
## error N(0, `aim_error_deg`) per axis from the AI RNG, a class property identical at every difficulty), EXTEND
## (straight at boost for `extend_s` after an overshoot: target behind the 3-9 line closer than `overshoot_m`) and EVADE
## (flip when ready, then `heading_change_deg` off and down to the deck for `duration_s`, on an HP drop of
## `hp_drop_trigger` within `hp_window_s`). Target lost (not visible for `lost_s`): the caller's choice point.
## Brains read only what the team sees: an invisible target's last seen position is `goal` (no velocity).

const F_BOOST: int = AttackRun.F_BOOST
const F_FLIP: int = AttackRun.F_FLIP

var prm: DartParams
var gains: FlightGains
var rng: Rng = null
var stats_draws: int = 0         ## aim-error draws (tests: the AI stream is used after a restore)
var stats_engage_acts: int = 0   ## ENGAGE acts (perf counter)
var stats_engage_visible: int = 0   ## visible_to calls in them (R0 B.17 A-97: exactly one per act)


func _init(params: DartParams, flight_gains: FlightGains) -> void:
	prm = params
	gains = flight_gains


## One combat think in `mode` (DartBrain.Mode INTERCEPT, ENGAGE, EXTEND, EVADE); returns the next mode, or
## AiTag.Tag.NONE when the target is gone (dead, or not visible for `lost_s`).
func think(id: int, mode: int, view: SimView, st: AiState, tick: int) -> int:
	var s: int = EntityId.slot(id)
	var t: int = st.target[s]
	if t == 0 or not view.alive(t):
		return AiTag.Tag.NONE
	if view.visible_to(view.team(id), t):
		st.seen_tick[s] = tick
		st.goal[s] = view.pos(t)
	elif tick - st.seen_tick[s] > prm.lost_ticks:
		return AiTag.Tag.NONE
	var p: Vector3 = view.pos(id)
	var d: float = p.distance_to(st.goal[s])
	st.bflags[s] &= ~F_BOOST
	if mode != AiTag.Tag.EVADE and _hp_dropped(id, view, st, tick):
		return _evade(id, view, st, tick)
	if mode == AiTag.Tag.EXTEND:
		if tick - roundi(st.timer[s]) < prm.extend_ticks:
			st.bflags[s] |= F_BOOST
			st.guidance_vel[s] = _heading(st.guidance_point[s], p) * prm.boost_speed
			return mode
		mode = AiTag.Tag.INTERCEPT
	if mode == AiTag.Tag.EVADE:
		if tick - roundi(st.timer[s]) < prm.evade_ticks:
			return mode
		mode = AiTag.Tag.ENGAGE
	if mode == AiTag.Tag.ENGAGE:
		if d > prm.fire_range + 2.0 * prm.engage_extra:
			mode = AiTag.Tag.INTERCEPT
		elif (d < prm.overshoot and (st.goal[s] - p).dot(-view.basis(id).z) < 0.0) or _ramming(id, t, p, d, view):
			return _extend(id, view, st, tick)
		else:
			_cache_lead(id, s, p, view, st)
			return mode
	if d < prm.fire_range + prm.engage_extra:
		st.burst_tick[s] = 0
		_cache_lead(id, s, p, view, st)
		return AiTag.Tag.ENGAGE
	_intercept(id, s, p, d, view, st)
	return AiTag.Tag.INTERCEPT


## ENGAGE act: inside fire range the per-tick lead point with the burst's aim error, outside it the think's cached
## lead; `track_velocity` toward it, FIRE1 inside the cone.
## Shaping: A-69 lift and the deck floor (05 s5.3), from the think's cached lift and ground height.
func act_engage(id: int, view: SimView, st: AiState, out: PilotInput, p: Vector3, v: Vector3, b: Basis, tick: int) -> void:
	var s: int = EntityId.slot(id)
	var t: int = st.target[s]
	var up: Vector3 = p.normalized()
	stats_engage_acts += 1
	var seen: bool = _visible(view, view.team(id), t)   # false for a dead id: the one visibility read of the act
	var pt: Vector3 = view.pos(t) if seen else st.goal[s]
	var vt: Vector3 = view.vel(t) if seen else Vector3.ZERO
	var dist: float = p.distance_to(pt)
	var in_range: bool = seen and dist < prm.fire_range
	var dir: Vector3 = (st.aim_lead[s] - p).normalized()   # outside fire range: the think's cached lead (05 s4.3)
	if in_range:
		dir = aim_offset((AimSolver.lead_point(p, v, pt, vt, prm.slug_speed) - p).normalized(), st.aim_err[s], up)
	var speed: float = vt.length() + (prm.engage_margin if dist > prm.standoff else -prm.engage_margin)
	var v_cmd: Vector3 = _nose_on(dir, v, -b.z) * maxf(speed, prm.engage_margin)
	var agl: float = p.length() - Sphere.PLANET_RADIUS - st.ground_h[s]
	v_cmd = Guidance.floored(Guidance.cleared(v_cmd, v, up, st.lift[s]), up, agl, prm.deck_agl, prm.kp_alt, prm.vz_max)
	out.buttons = 0
	st.integ[s] = FlightController.track_velocity(b, v, v_cmd, up, gains, st.integ[s], out)
	if not in_range:
		st.burst_tick[s] = 0
		return
	if st.burst_tick[s] == 0 or tick - st.burst_tick[s] >= prm.cycle_ticks:
		st.burst_tick[s] = tick
		st.aim_err[s] = gauss2(rng) * prm.aim_error_rad if rng != null else Vector2.ZERO
		stats_draws += 1
	if tick - st.burst_tick[s] < prm.burst_ticks and AimSolver.in_fire_cone(-b.z, dir, prm.fire_cone_k, view.radius(t), dist) \
			and view.ammo(id) > 0:
		out.buttons |= PilotInput.FIRE1


## The velocity direction that puts the nose on `dir`: `dir` minus the nose's current offset from the velocity (the
## angle of attack), applied up to `aoa_comp_max_deg`; the slugs leave along the nose, not the velocity.
func _nose_on(dir: Vector3, v: Vector3, nose: Vector3) -> Vector3:
	var u: float = v.length()
	if u < 1.0:
		return dir
	var vh: Vector3 = v / u
	if nose.dot(vh) < prm.aoa_comp_cos:
		return dir
	return (dir - (nose - vh)).normalized()


## Two independent standard normals (Box-Muller over two `range_f` draws of `r`).
static func gauss2(r: Rng) -> Vector2:
	var u1: float = maxf(r.next_float(), 1e-12)
	var u2: float = r.next_float()
	var m: float = sqrt(-2.0 * log(u1))
	return Vector2(m * cos(TAU * u2), m * sin(TAU * u2))


## The unit `dir` turned by the small aim error `err` (rad): `err.x` along the horizontal right of `dir`, `err.y` along
## its up (the small-angle form of the two rotations: the per-burst error is ~1 degree; no rotation per tick).
static func aim_offset(dir: Vector3, err: Vector2, up: Vector3) -> Vector3:
	if err == Vector2.ZERO:
		return dir
	var right: Vector3 = dir.cross(up)
	if right.length_squared() < 1e-8:
		return dir
	right = right.normalized()
	return (dir + right * err.x + right.cross(dir) * err.y).normalized()


# The lead the act steers on outside fire range, refreshed each think (AiState.aim_lead).
func _cache_lead(id: int, s: int, p: Vector3, view: SimView, st: AiState) -> void:
	var t: int = st.target[s]
	var vt: Vector3 = view.vel(t) if view.visible_to(view.team(id), t) else Vector3.ZERO
	st.aim_lead[s] = AimSolver.lead_point(p, view.vel(id), st.goal[s], vt, prm.slug_speed)


func _intercept(id: int, s: int, p: Vector3, d: float, view: SimView, st: AiState) -> void:
	var t: int = st.target[s]
	var seen: bool = view.visible_to(view.team(id), t)
	var vt: Vector3 = view.vel(t) if seen else Vector3.ZERO
	var dir: Vector3 = (st.goal[s] - p).normalized()
	var closing: float = maxf(prm.boost_speed - vt.dot(dir), prm.engage_margin)
	var aim: Vector3 = st.goal[s] + vt * (d / closing)
	var boost: bool = d > prm.boost_close
	if boost:
		st.bflags[s] |= F_BOOST
	st.guidance_vel[s] = (aim - p).normalized() * (prm.boost_speed if boost else prm.cruise_speed)


# Ramming kills both ships (01 s3.1.3): break off when the time to collision with the target is under `break_ttc_s`.
func _ramming(id: int, t: int, p: Vector3, d: float, view: SimView) -> bool:
	if not view.visible_to(view.team(id), t):
		return false
	var r: Vector3 = view.pos(t) - p
	var closing: float = -r.dot(view.vel(t) - view.vel(id)) / maxf(d, 1.0)
	return closing > 0.0 and (d - view.radius(t) - view.radius(id)) < closing * prm.break_ttc


# EXTEND heading: away from the target; with the target ahead (a closing pass) a 90 degree break to the side away
# from it, so the ship never turns into it.
func _extend(id: int, view: SimView, st: AiState, tick: int) -> int:
	var s: int = EntityId.slot(id)
	var p: Vector3 = view.pos(id)
	var up: Vector3 = p.normalized()
	var h: Vector3 = _heading(view.vel(id), p)
	var away: Vector3 = p - st.goal[s]
	away -= up * away.dot(up)
	away = away.normalized() if away.length_squared() > 1.0 else h
	if away.dot(h) > -0.5:
		st.guidance_point[s] = (h + away).normalized()
	else:
		var side: float = -1.0 if h.cross(st.goal[s] - p).dot(up) > 0.0 else 1.0
		st.guidance_point[s] = h.rotated(up, side * PI * 0.5)
	st.timer[s] = float(tick)
	st.bflags[s] |= F_BOOST
	st.guidance_vel[s] = st.guidance_point[s] * prm.boost_speed
	return AiTag.Tag.EXTEND


func _evade(id: int, view: SimView, st: AiState, tick: int) -> int:
	var s: int = EntityId.slot(id)
	var p: Vector3 = view.pos(id)
	var up: Vector3 = p.normalized()
	var turn: float = prm.evade_turn_rad if (s & 1) == 0 else -prm.evade_turn_rad
	st.guidance_point[s] = _heading(view.vel(id), p).rotated(up, turn)
	st.timer[s] = float(tick)
	st.hp_mark[s] = view.hp01(id)
	st.mark_tick[s] = tick
	if view.flip_cooldown01(id) <= 0.0:
		st.bflags[s] |= F_FLIP
	return AiTag.Tag.EVADE


# 05 s6.2 EVADE trigger: hp01 fell by `hp_drop` since the mark; the mark moves every `hp_window_ticks`.
func _hp_dropped(id: int, view: SimView, st: AiState, tick: int) -> bool:
	var s: int = EntityId.slot(id)
	var hp: float = view.hp01(id)
	if st.hp_mark[s] - hp >= prm.hp_drop:
		return true
	if tick - st.mark_tick[s] >= prm.hp_window_ticks or hp > st.hp_mark[s]:
		st.hp_mark[s] = hp
		st.mark_tick[s] = tick
	return false


# Unit horizontal heading of `v` at `p` (any tangent when vertical).
static func _heading(v: Vector3, p: Vector3) -> Vector3:
	var up: Vector3 = p.normalized()
	var h: Vector3 = v - up * v.dot(up)
	return h.normalized() if h.length_squared() > 1e-6 else Sphere.tangent_frame(up).x


# Every visibility read of an ENGAGE act goes through here, so stats_engage_visible counts them (A-97: one per act).
func _visible(view: SimView, team: int, t: int) -> bool:
	stats_engage_visible += 1
	return view.visible_to(team, t)
