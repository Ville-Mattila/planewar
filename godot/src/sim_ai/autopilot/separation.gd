class_name Separation extends RefCounted
## Friendly-ship separation (05 s5.4), static only. Ramming kills both ships (01 s3.1.3), so it outranks formation
## keeping. Two terms over the friendly ships in one `SimView.ids_near(p, query_radius_m)`:
## - proximity (05 s5.4): for j inside `sep_radius_m`: `gain * (p - p_j).normalized() * (R - d) / R * push`;
## - look-ahead (AI-11): for a pair that is closing and whose closest approach, or its distance at `look_s` when that comes later, misses by less than
##   `look_miss_m`: a push sideways that closes the deficit `look_miss_m - m` in the time left after the controller's lag,
##   `deficit / (look_eff * max(t - look_lag_s, look_min_s))`, at most `look_max_mps`, and for a neighbour ahead the closing speed
##   times the urgency `deficit / look_miss_m` times `look_brake` is taken off the speed (an overtaker slows to the leader).
##   The proximity ring alone gives a head-on pair 0.3 s and cannot separate an overtaking pair at all (the push is along
##   the line of closing); the look-ahead pushes sideways, early. A pair that is exactly aligned splits by id order.
## Enemy ships are never avoided here (guns and the flip handle them). Structures are the terrain probe's job.
## Cost (05 s10 think row, "1 neighbour query"): one `ids_near` plus a few reads per neighbour in range.
## Refresh policy (`term`, AI-11 review round 3; R0 B.14 A-84 does not narrow the acceptance): a think refreshes the term
## unless the previous think refreshed it and found no closing pair; then it holds it once. A closing pair is a friendly
## neighbour in the query whose distance shrinks at >= 1 m/s (the look-ahead's own entry gate, so a superset of "the
## look-ahead term is non-zero": a pair turning onto a collision course during the hold is caught one think earlier).
## Parallel flight holds every second think; a swarm or a closing pair refreshes every think. The flags live in
## `AiState.sep_age` (u8, in the S4 bytes): AGE_FRESH = the last think refreshed, AGE_CLOSING = it found a closing pair.

const AGE_FRESH: int = 1     ## sep_age bit: the previous think refreshed the term
const AGE_CLOSING: int = 2   ## sep_age bit: that refresh found a closing pair (a friendly approaching at >= 1 m/s)

static var _closing: bool = false   # set by every `push`: it saw a closing pair (read at once by `term`; the sim tick is single-threaded)


## Whether a think with flags `age` refreshes: false only right after a refresh that found no closing pair.
static func needs_refresh(age: int) -> bool:
	return (age & AGE_FRESH) == 0 or (age & AGE_CLOSING) != 0


## One think's separation term for the ship `id` in AiState slot `s`: refreshes `st.sep_push[s]` by `push` when
## `needs_refresh(st.sep_age[s])`, else holds it; updates `st.sep_age[s]` and returns the term. EscortPilot and the
## swarm rig both call this, so the policy exists once.
static func term(s: int, id: int, p: Vector3, v: Vector3, team: int, view: SimView, prm: FormationParams, st: AiState) -> Vector3:
	if not needs_refresh(st.sep_age[s]):
		st.sep_age[s] = 0
		return st.sep_push[s]
	var out: Vector3 = push(id, p, v, team, view, prm)
	st.sep_push[s] = out
	st.sep_age[s] = AGE_FRESH | (AGE_CLOSING if _closing else 0)
	return out


## The velocity to add to a guidance command for the ship `id` at `p` moving at `v` (team `team`); ZERO when nobody
## is close. Only ships of `team` count. Coincident neighbours are pushed along a tangent chosen by id order.
static func push(id: int, p: Vector3, v: Vector3, team: int, view: SimView, prm: FormationParams) -> Vector3:
	var near_sum: Vector3 = Vector3.ZERO
	var look_sum: Vector3 = Vector3.ZERO
	var closing: bool = false
	var r: float = prm.sep_radius_m
	var q2: float = prm.query_radius_m * prm.query_radius_m
	for j: int in view.ids_near(p, prm.query_radius_m, Spatial.MASK_SHIP):
		if j == id or view.team(j) != team:   # team() is -1 for an id that died since the hash was built
			continue
		var d: Vector3 = p - view.pos(j)
		var d2: float = d.length_squared()
		if d2 >= q2:
			continue
		var dist: float = sqrt(d2)
		if dist < r:
			near_sum += (d / dist if dist > 0.01 else _tangent(p, id < j)) * ((r - dist) / r)
		var vr: Vector3 = v - view.vel(j)
		closing = closing or (vr.length_squared() >= 1.0 and d.dot(vr) < 0.0)
		var lk: Vector3 = _look_ahead(id, j, p, v, d, vr, prm)
		if lk.length_squared() > look_sum.length_squared():
			look_sum = lk
	_closing = closing
	return (near_sum * prm.sep_push_mps + look_sum) * prm.sep_gain


# Push (m/s) of one converging neighbour: `d` = p - p_j, `vr` = v - v_j.
static func _look_ahead(id: int, j: int, p: Vector3, v: Vector3, d: Vector3, vr: Vector3, prm: FormationParams) -> Vector3:
	var vv: float = vr.length_squared()
	if vv < 1.0:
		return Vector3.ZERO
	var t: float = -d.dot(vr) / vv
	if t <= 0.0:
		return Vector3.ZERO
	t = minf(t, prm.look_s)   # a slow closer is judged at the horizon: the distance it will have left by then
	var miss: Vector3 = d + vr * t
	var m: float = miss.length()
	if m >= prm.look_miss_m:
		return Vector3.ZERO
	var urgency: float = (prm.look_miss_m - m) / prm.look_miss_m
	var rate: float = minf((prm.look_miss_m - m) / (prm.look_eff * maxf(t - prm.look_lag_s, prm.look_min_s)), prm.look_max_mps)
	var out: Vector3 = _side(id, j, p, miss, vr, m) * rate
	var speed: float = v.length()
	if speed > 1.0 and d.dot(v) < 0.0 and vr.dot(v) > 0.0:   # catching up on a neighbour ahead: shed the closing speed (car-following)
		out -= v / speed * (minf(-d.dot(vr) / maxf(d.length(), 0.01), prm.look_max_mps) * urgency * prm.look_brake)
	return out


# Direction of the look-ahead push: the horizontal part of the predicted miss vector when it carries it, else the
# horizontal normal of the closing velocity (`up x vr`: opposite for the two ships of a pair, so they split). Ships turn
# faster than they change altitude, so the push stays in the local horizontal plane.
static func _side(id: int, j: int, p: Vector3, miss: Vector3, vr: Vector3, m: float) -> Vector3:
	var up: Vector3 = p.normalized()
	var h: Vector3 = miss - up * miss.dot(up)
	if h.length() > 0.5 * m and m > 0.01:
		return h.normalized()
	var c: Vector3 = up.cross(vr)
	if c.length_squared() < 1.0:
		return _tangent(p, id < j)
	return c.normalized()


static func _tangent(p: Vector3, plus: bool) -> Vector3:
	var up: Vector3 = p.normalized()
	var t: Vector3 = up.cross(Vector3.BACK)
	if t.length_squared() < 0.01:
		t = up.cross(Vector3.RIGHT)
	t = t.normalized()
	return t if plus else -t
