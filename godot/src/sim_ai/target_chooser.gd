class_name TargetChooser extends RefCounted
## Utility choice points for targets (05 s4.2, s6.2, s6.8; R0 C2-15). Static and pure apart from the preallocated
## scratch in `TargetContext`. Scoring is a pure function of numbers (`score_ship`, `score_tower`: table-testable);
## `pick` applies the hysteresis; `choose_ship` / `choose_tower` gather the numbers from `SimView` (visible enemies only,
## so a bot never targets what its team cannot see) and call them. Ties go to the earlier candidate, so the result is a
## function of state. Budget: 05 s10 think row, one choice point (25 us) per think.

const NONE: int = 0
const TIE_REL: float = 0.000001


## 05 s6.2: `w * 1 / (1 + dist / falloff)` x attacked x low-hp x under-tower x focus-fire factors.
static func score_ship(w: float, dist: float, hp01: float, attacked: bool, under_tower: bool, targeters: int,
		p: TargetParams) -> float:
	var u: float = w / (1.0 + dist / p.falloff_m)
	if attacked:
		u *= p.attacked_mult
	if hp01 < p.low_hp01:
		u *= p.low_hp_mult
	if under_tower:
		u *= p.under_tower_penalty
	if targeters >= p.focus_count:
		u *= p.focus_mult
	return u


## 05 s6.8: `base x attacking x (1 + gain (1 - hp01)) x crowd x guard / (1 + time_to_slew_s)`.
static func score_tower(base: float, attacking: bool, hp01: float, towers_on_it: int, guard_attacker: bool,
		slew_s: float, p: TargetParams) -> float:
	var u: float = base * (1.0 + p.tower_hp_gain * (1.0 - hp01))
	if attacking:
		u *= p.tower_attacking_mult
	if towers_on_it > p.tower_crowd_count:
		u *= p.tower_crowd_mult
	if guard_attacker:
		u *= p.guard_mult
	return u / (1.0 + slew_s)


## Highest score wins (earliest on a tie), unless `current` is among the candidates and the best does not beat
## `margin x` its score: then `current` stays. A `current` that is not a candidate (dead, hidden, out of range) is dropped.
## Returns NONE when `n` is 0 or every score is 0.
static func pick(ids: PackedInt32Array, scores: PackedFloat32Array, n: int, current: int, margin: float) -> int:
	var best: int = NONE
	var best_u: float = 0.0
	var cur_u: float = -1.0
	for i: int in n:
		var u: float = scores[i]
		if ids[i] == current:
			cur_u = u
		if u > best_u:
			best_u = u
			best = ids[i]
	if cur_u > 0.0 and best != current and best_u <= margin * cur_u:
		return current
	return best


## Dart / Lancer choice point: `cand[0..n)` are ids from `view.ids_near`; only team-visible, living enemies of weighted
## class within `radius` of `origin` qualify. The cost is bounded whatever `n` is: one cheap pass (6 `SimView` reads per
## candidate) keeps the best `p.max_candidates` by the unmodified `w / (1 + dist / falloff)`, then only those are fully
## scored (`out` and `ctx.scores` must hold that many). `current` is the caller's own target: it counts in
## `ctx.targeted_by`, so it is excluded from the focus-fire count of that candidate. Returns the pick.
static func choose_ship(view: SimView, team: int, cand: PackedInt32Array, n: int, origin: Vector3, radius: float,
		current: int, tick: int, ctx: TargetContext, p: TargetParams, out: PackedInt32Array) -> int:
	assert(out.size() >= p.max_candidates and ctx.scores.size() >= p.max_candidates, "choice-point scratch too small")
	var k: int = 0
	var r2: float = radius * radius
	for i: int in n:
		var id: int = cand[i]
		if not view.alive(id) or view.team(id) == team or not view.visible_to(team, id):
			continue
		var d2: float = origin.distance_squared_to(view.pos(id))
		var w: float = p.weight(view.def_id(id), view.cargo(id) > 0.0, _building(view, id, p))
		if d2 > r2 or w <= 0.0:
			continue
		k = _keep_best(out, ctx.scores, k, p.max_candidates, id, w / (1.0 + sqrt(d2) / p.falloff_m))
	for j: int in k:
		var id: int = out[j]
		var pos: Vector3 = view.pos(id)
		var def_id: int = view.def_id(id)
		var under: bool = p.under_tower_penalty < 1.0 and ctx.under_tower(pos, def_id, view.terrain_height(pos))
		var w: float = p.weight(def_id, view.cargo(id) > 0.0, _building(view, id, p))
		ctx.scores[j] = score_ship(w, origin.distance_to(pos), view.hp01(id), ctx.attacked_recently(id, tick), under,
			_others(ctx, id, current), p)
	return pick(out, ctx.scores, k, current, p.switch_margin)


## Tower choice point: eligible = visible enemy inside the envelope and range (`TowerEnvelope.eligible`); `aim` is the
## turret's current unit direction, `slew_s` = angle to the target / turret rate. Bounded like `choose_ship`: the best
## `p.max_candidates` by priority weight are scored. `guarded` (0 = no GUARD order) doubles attackers of that structure
## (the caller marks them with `ctx.mark_attacker`). `current` is excluded from its own crowd count.
static func choose_tower(view: SimView, team: int, tower_pos: Vector3, aim: Vector3, env: TowerEnvelope,
		range_m: float, cand: PackedInt32Array, n: int, current: int, tick: int, ctx: TargetContext, p: TargetParams,
		guarded: int, out: PackedInt32Array) -> int:
	assert(out.size() >= p.max_candidates and ctx.scores.size() >= p.max_candidates, "choice-point scratch too small")
	var k: int = 0
	for i: int in n:
		var id: int = cand[i]
		if not view.alive(id) or view.team(id) == team or not view.visible_to(team, id):
			continue
		var pos: Vector3 = view.pos(id)
		var def_id: int = view.def_id(id)
		var base: float = env.base_weight(def_id, view.cargo(id) > 0.0)
		if base <= 0.0 or not env.eligible(tower_pos, pos, def_id, range_m, view.terrain_height(pos)):
			continue
		k = _keep_best(out, ctx.scores, k, p.max_candidates, id, base)
	for j: int in k:
		var id: int = out[j]
		var pos: Vector3 = view.pos(id)
		var slew: float = aim.angle_to((pos - tower_pos).normalized()) / env.turn_rad_s if env.turn_rad_s > 0.0 else 0.0
		var attacking: bool = ctx.attacked_recently(id, tick)
		ctx.scores[j] = score_tower(env.base_weight(view.def_id(id), view.cargo(id) > 0.0), attacking, view.hp01(id),
			_others(ctx, id, current), guarded != 0 and attacking, slew, p)
	return pick(out, ctx.scores, k, current, p.tower_switch_margin)


# AI-14: a structure under construction (read only when the params weigh `structure_building`).
static func _building(view: SimView, id: int, p: TargetParams) -> bool:
	return p.w_building > 0.0 and (view.flags(id) & EntityStore.F_BUILDING) != 0


# Friendly units targeting `id` other than the chooser itself (which is counted when `id` is its current target).
static func _others(ctx: TargetContext, id: int, current: int) -> int:
	return ctx.targeted_by[EntityId.slot(id)] - (1 if id == current else 0)


# Insertion into the top-`cap` list ordered by descending pre-score; an equal score goes behind the earlier candidate.
static func _keep_best(ids: PackedInt32Array, sc: PackedFloat32Array, k: int, cap: int, id: int, u: float) -> int:
	var at: int = k
	var lim: float = u * (1.0 - TIE_REL)           # scores are float32: values equal to float32 precision tie
	while at > 0 and sc[at - 1] < lim:
		at -= 1
	if at >= cap:
		return k
	var last: int = mini(k, cap - 1)
	for j: int in range(last, at, -1):
		ids[j] = ids[j - 1]
		sc[j] = sc[j - 1]
	ids[at] = id
	sc[at] = u
	return mini(k + 1, cap)
