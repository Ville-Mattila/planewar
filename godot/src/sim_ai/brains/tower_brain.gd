class_name TowerBrain extends AiBrain
## The tower autopilot (05 s6.8, R0 C2-15; AI-17), one brain for every tower def. The sim fires (weapon rate, ammo,
## unsupplied 50 % and power scaling, lock time, flak fuse at the closest approach); the brain picks the target and
## writes the input: `pitch` / `yaw` slew rates (`TurretAim`, capped by `turret_turn_dps`) and `FIRE1`.
## Think (staggered, every `think_period_ticks`): idle states first (under construction: IDLE; the team's power ratio
## below `tower_offline_ratio`: OFFLINE; a HOLD order: HOLD), else the choice point `TargetChooser.choose_tower` over
## the team-visible enemy ships (TeamPicture) and, for a tower whose `target_kinds` list ground, the ground units the
## team's Perception saw at its last refresh, inside the weapon's `range_m` and the tower's `towers.json` envelope
## (`TowerEnvelope`; no envelope number lives here). ATTACK takes the ordered target when eligible; GUARD doubles the
## attackers of the guarded structure (`AiHitLog`). Act (every tick): while TRACK, slew to the straight-line lead
## (`AimSolver`, shell speed from the projectile def, no gravity, R0 B.5) or, for the guided rocket, to the target, and
## hold FIRE1 while the muzzle is inside the fire cone, the target in range, the envelope and the pool not empty. A
## Missile Tower holds the trigger through the seeker's `lock_time_s` (`lock_tick` = the hold's start). Vision only.

const B_DRIVEN: int = 1   ## bflags: the last drive carried a slew or FIRE1, so a zero drive must follow when it ends

var prm: TowerParams
var picture: TeamPicture = TeamPicture.new()
var intel: TeamIntel = null
var stats_thinks: int = 0
var stats_choices: int = 0
var stats_ground_builds: int = 0   ## per-team ground-contact lists rebuilt (once per Perception refresh)
var stats_acts: int = 0            ## acts that tracked a target
var stats_visible: int = 0         ## visible_to calls of those acts (one each)
var stats_lock_starts: int = 0
var _ctx: Array[TargetContext] = []
var _cand: PackedInt32Array = PackedInt32Array()
var _pick: PackedInt32Array = PackedInt32Array()
var _g_stamp: PackedInt32Array = PackedInt32Array()          ## by team: Perception refresh the ground list is of (-2 none)
var _g_ids: Array[PackedInt32Array] = []
var _g_pos: Array[PackedVector3Array] = []
var _g_buf: PackedInt32Array = PackedInt32Array()
var _g_pbuf: PackedVector3Array = PackedVector3Array()
var _inp: PilotInput = PilotInput.new()
var _pw_tick: PackedInt32Array = PackedInt32Array()          ## by team: the tick `_pw` was read (-1 none)
var _pw: PackedFloat32Array = PackedFloat32Array()           ## by team: power ratio of that tick (SimView.stockpile is 13 us)


## The tower brain from content (`ap` = the `ap_tower` dictionary); null when a key or a tower's weapon is missing.
static func create(c: ContentSet, ap: Dictionary) -> TowerBrain:
	var b: TowerBrain = TowerBrain.new()
	b.prm = TowerParams.from_content(ap, c)
	if b.prm == null:
		return null
	b.picture.period = b.prm.vision_period
	var _r: Array[int] = [b._pick.resize(b.prm.targets.max_candidates), b._g_stamp.resize(PlayerTable.TEAMS),
		b._pw_tick.resize(PlayerTable.TEAMS), b._pw.resize(PlayerTable.TEAMS)]
	b._g_stamp.fill(-2)
	b._pw_tick.fill(-1)
	for t: int in PlayerTable.TEAMS:
		b._ctx.append(TargetContext.new())
		b._g_ids.append(PackedInt32Array())
		b._g_pos.append(PackedVector3Array())
	return b


func bind_rng(_rng: Rng) -> void:
	picture.reset()   # bound on set_brain and after deserialize: no list survives a restore
	_g_stamp.fill(-2)
	_pw_tick.fill(-1)


func bind_intel(i: TeamIntel) -> void:
	intel = i
	_g_stamp.fill(-2)


func think_batch(ids: PackedInt32Array, n: int, view: SimView, st: AiState, sink: CommandSink, tick: int) -> void:
	for i: int in n:
		_think(ids[i], view, st, sink, tick)


## One think of `id` (rigs and perf tests).
func think_one(id: int, view: SimView, st: AiState, sink: CommandSink, tick: int) -> void:
	_think(id, view, st, sink, tick)


func act_batch(ids: PackedInt32Array, view: SimView, st: AiState, sink: CommandSink) -> void:
	var tick: int = view.tick()
	for id: int in ids:
		var s: int = EntityId.slot(id)
		if st.mode[s] == AiTag.Tag.TRACK and st.target[s] != 0:
			_track(id, s, view, st, sink, tick)
		elif (st.bflags[s] & B_DRIVEN) != 0:
			_release(id, s, st, sink)


func _think(id: int, view: SimView, st: AiState, sink: CommandSink, tick: int) -> void:
	var s: int = EntityId.slot(id)
	var env: TowerEnvelope = prm.envelope(view.def_id(id))
	if env == null:
		return
	stats_thinks += 1
	var head: OrderSpec = view.order_head(id)
	var m: int = _idle_mode(id, head, view, tick)
	var pick: int = 0
	if m == AiTag.Tag.NONE:
		pick = _choose(id, s, env, head, view, st, tick)
		m = AiTag.Tag.TRACK if pick != 0 else AiTag.Tag.IDLE
	st.set_target(s, pick)
	if pick == 0:
		st.lock_tick[s] = 0
	if st.mode[s] != m:
		sink.set_ai_tag(id, m)
	st.set_mode(id, m, tick)


# The tag a tower holds without a choice point, or NONE when it works: under construction, offline for power, HOLD.
func _idle_mode(id: int, head: OrderSpec, view: SimView, tick: int) -> int:
	if (view.flags(id) & EntityStore.F_BUILDING) != 0:
		return AiTag.Tag.IDLE
	if _power(view.team(id), view, tick) < prm.off_ratio:
		return AiTag.Tag.OFFLINE
	if head != null and head.kind == OrderSpec.Kind.HOLD:
		return AiTag.Tag.HOLD
	return AiTag.Tag.NONE


# The team's power ratio of `tick`, read once per team per tick (a function of the tick's state: not AI state).
func _power(team: int, view: SimView, tick: int) -> float:
	if team < 0 or team >= _pw.size():
		return 1.0
	if _pw_tick[team] != tick:
		_pw_tick[team] = tick
		_pw[team] = view.stockpile(team).z
	return _pw[team]


func _choose(id: int, s: int, env: TowerEnvelope, head: OrderSpec, view: SimView, st: AiState, tick: int) -> int:
	var team: int = view.team(id)
	if team < 0 or team >= _ctx.size():
		return 0
	stats_choices += 1
	var p: Vector3 = view.pos(id)
	var rng_m: float = prm.range_m[view.def_id(id) - DefRanges.STRUCTURE_BASE]
	var guarded: int = head.target if head != null and head.kind == OrderSpec.Kind.GUARD else 0
	var n: int = _gather(view, team, tick, p, rng_m, env)
	var ctx: TargetContext = _ctx[team]
	_mark(ctx, st, team, tick, p, n, guarded)
	var pick: int = TargetChooser.choose_tower(view, team, p, -view.basis(id).z, env, rng_m, _cand, n, st.target[s], tick,
		ctx, prm.targets, guarded, _pick)
	if head != null and head.kind == OrderSpec.Kind.ATTACK and head.target != 0 \
			and _ordered(head.target, team, p, rng_m, env, view):
		return head.target   # 05 s6.8: the ordered target if eligible, else the normal choice
	return pick


func _ordered(t: int, team: int, p: Vector3, rng_m: float, env: TowerEnvelope, view: SimView) -> bool:
	if not view.alive(t) or view.team(t) == team or not view.visible_to(team, t):
		return false
	var tp: Vector3 = view.pos(t)
	return env.eligible(p, tp, view.def_id(t), rng_m, view.terrain_height(tp) if env.has_floor() else 0.0)


# Candidates into `_cand`: the visible enemy ships in range, then (ground-capable towers) the ground units of the last
# Perception refresh within range of where they were seen; `choose_tower` re-reads the live state of each.
func _gather(view: SimView, team: int, tick: int, p: Vector3, rng_m: float, env: TowerEnvelope) -> int:
	var n: int = picture.near_built(view, team, tick, p, rng_m + prm.slack_m)   # the choice point re-checks the live range
	var perc: Perception = intel.perception(team) if intel != null and (env.kinds & TowerEnvelope.KIND_GROUND) != 0 else null
	if perc != null:
		_refresh_ground(team, perc)
	var gi: PackedInt32Array = _g_ids[team] if perc != null else PackedInt32Array()
	if _cand.size() < n + gi.size():
		var _r: int = _cand.resize(n + gi.size())
	var ships: PackedInt32Array = picture.near_ids()
	for i: int in n:
		_cand[i] = ships[i]
	var gp: PackedVector3Array = _g_pos[team]
	var r2: float = rng_m * rng_m
	for k: int in gi.size():
		if p.distance_squared_to(gp[k]) <= r2:
			_cand[n] = gi[k]
			n += 1
	return n


# The team's ground-unit contacts of the Perception's last refresh (a function of that refresh alone: not state).
func _refresh_ground(team: int, perc: Perception) -> void:
	if _g_stamp[team] == perc.last_refresh:
		return
	_g_stamp[team] = perc.last_refresh
	stats_ground_builds += 1
	if _g_buf.size() < perc.n_known:
		var _r: Array[int] = [_g_buf.resize(perc.n_known), _g_pbuf.resize(perc.n_known)]
	var g: int = 0
	for i: int in perc.n_known:
		var sl: int = perc.known[i]
		if perc.k_seen[sl] == perc.last_refresh and DefRanges.kind_of(perc.k_def[sl]) == DefRanges.K_GROUND:
			_g_buf[g] = perc.k_id[sl]
			_g_pbuf[g] = perc.k_pos[sl]
			g += 1
	_g_ids[team] = _g_buf.slice(0, g)
	_g_pos[team] = _g_pbuf.slice(0, g)


# Per candidate: its crowd count, the x1.5 "attacked a friendly asset within the radius" mark and the GUARD mark.
func _mark(ctx: TargetContext, st: AiState, team: int, tick: int, p: Vector3, n: int, guarded: int) -> void:
	var hits: AiHitLog = st.hits
	for i: int in n:
		var cs: int = EntityId.slot(_cand[i])
		ctx.targeted_by[cs] = st.target_count[cs]
		var hit: bool = hits.team[cs] == team   # a candidate that never hit this team's assets skips the window tests
		ctx.attacked_until[cs] = tick + 1 if hit and hits.attacking(cs, team, tick, prm.window_ticks, p, prm.attack_r2) else 0
		if guarded != 0:
			ctx.guard_until[cs] = tick + 1 if hit and hits.guarding(cs, guarded, tick, prm.window_ticks) else 0


# TRACK act: slew to the lead, hold FIRE1 on target.
func _track(id: int, s: int, view: SimView, st: AiState, sink: CommandSink, tick: int) -> void:
	if view.control_state(id) == ControlMachine.State.POSSESSED:
		return
	var out: PilotInput = _inp
	out.pitch = 0.0
	out.yaw = 0.0
	out.buttons = 0
	var t: int = st.target[s]
	stats_acts += 1
	stats_visible += 1
	if view.visible_to(view.team(id), t):   # false for a dead id: the one read both gates the act and keeps it fair
		_aim(id, s, t, view, st, tick, out)
	else:
		st.lock_tick[s] = 0
	st.bflags[s] |= B_DRIVEN
	var _d: bool = sink.drive(id, out)


func _aim(id: int, s: int, t: int, view: SimView, st: AiState, tick: int, out: PilotInput) -> void:
	var di: int = view.def_id(id) - DefRanges.STRUCTURE_BASE
	var env: TowerEnvelope = prm.env[di]
	var p: Vector3 = view.pos(id)
	var tp: Vector3 = view.pos(t)
	var rel: Vector3 = tp - p
	var dist: float = rel.length()
	var sp: float = prm.speed[di]
	var dir: Vector3 = AimSolver.aim_dir(p, Vector3.ZERO, tp, view.vel(t), sp) if sp > 0.0 else Vector3.ZERO
	var solved: bool = dir != Vector3.ZERO or sp <= 0.0
	if dir == Vector3.ZERO:
		dir = rel / dist if dist > 0.0 else -view.basis(id).z   # no solution (or a guided rocket): at the target
	var ang: float = TurretAim.slew(view.basis(id), dir, env.turn_rad_s, prm.dt, out)
	var agl: float = tp.length() - Sphere.PLANET_RADIUS - view.terrain_height(tp) if env.has_floor() else 0.0   # AGL only where a floor is set
	var fire: bool = solved and dist <= prm.range_m[di] and ang < atan(prm.cone_k * view.radius(t) / maxf(dist, 1.0)) \
			and env.in_envelope(tp.length() - p.length(), agl) and view.ammo(id) > 0
	if fire:
		out.buttons = PilotInput.FIRE1
		if prm.lock_ticks[di] > 0 and st.lock_tick[s] == 0:
			st.lock_tick[s] = tick
			stats_lock_starts += 1
	elif prm.lock_ticks[di] > 0:
		st.lock_tick[s] = 0


# A zero drive after a driven stretch (target gone, mode left TRACK): releases the trigger and stops the slew.
func _release(id: int, s: int, st: AiState, sink: CommandSink) -> void:
	_inp.pitch = 0.0
	_inp.yaw = 0.0
	_inp.buttons = 0
	if sink.drive(id, _inp):
		st.bflags[s] &= ~B_DRIVEN
		st.lock_tick[s] = 0
