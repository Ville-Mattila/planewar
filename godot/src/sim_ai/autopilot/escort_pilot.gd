class_name EscortPilot extends RefCounted
## ESCORT behaviour of one ship class (05 s3.1, s5.6; AI-11): hold a formation slot behind the escortee, separated from
## friendly ships, and break out to engage. Think (the class's think slice, 3 Hz) resolves the escortee, the slot and
## the engage state and writes `guidance_vel` = formation velocity + separation; act (every tick) tracks it with
## `FlightController.track_velocity` into the caller's PilotInput. The brain owns the attack itself: while `think`
## returns ENGAGING it runs its own attack on `st.target[slot]` (05 s6.2) and skips `act`. The brain applies terrain /
## altitude shaping (05 s5.3) to `guidance_vel` if it wants it before act; the formation does not probe.
##
## State is in AiState (`aux_id` escortee, `form_slot`, `form_state`, `form_order`, `timer` = tick the engagement
## began, `target`, `integ`), so restore + continue is byte-identical. A wingman (SL-2, `escort_slot >= 0`) uses the
## `wing.json` slots in the leader's body frame; FOCUS / BREAK follow 05 s3.2 (leash and time limit from `wing.json`).

enum Outcome { FORMING, ENGAGING, LOST }
const FORM: int = 0                  ## form_state: in formation
const ENGAGE: int = 1                ## form_state: out of formation on `st.target`
const SPENT: int = 2                 ## form_state: a FOCUS / BREAK timed out; FORM until the order is re-issued
const DOCKED: int = 2                ## SimView.dock_state DOCKED

var def: ShipDef
var prm: FormationParams
var gains: FlightGains
var _tick_hz: float = 30.0


func _init(ship_def: ShipDef, params: FormationParams, flight_gains: FlightGains) -> void:
	def = ship_def
	prm = params
	gains = flight_gains
	_tick_hz = 1.0 / flight_gains.dt


## Drops the escort state of `id` (order ended or replaced by another kind).
func release(id: int, st: AiState) -> void:
	var s: int = EntityId.slot(id)
	var k: int = st.form_slot[s]
	if k < AiState.ROSTER_WIDTH and st.aux_id[s] != 0:
		var at: int = EntityId.slot(st.aux_id[s]) * AiState.ROSTER_WIDTH + k
		if st.form_roster[at] == id:
			st.form_roster[at] = 0
	st.sep_age[s] = 0
	st.sep_push[s] = Vector3.ZERO
	st.form_slot[s] = AiState.NO_SLOT
	st.form_state[s] = FORM
	st.form_order[s] = 0
	st.aux_id[s] = 0
	st.timer[s] = 0.0
	st.target[s] = 0


## One think. `threat` / `utility`: the brain's best threat (0 = none) and its 05 s6.2 utility; FORM breaks out only
## when `utility > break_utility`, the threat is within `engage_radius_m` of the escortee and the slot may break.
## FOCUS engages the order's focus target, BREAK any `threat` within `break_radius_m`. LOST: no ESCORT order, or the
## escortee is dead or DOCKED (the brain fails the order to AUTO, 05 s3.1 INVALID_TARGET).
func think(id: int, view: SimView, st: AiState, tick: int, threat: int = 0, utility: float = 0.0) -> Outcome:
	var s: int = EntityId.slot(id)
	var o: OrderSpec = view.order_head(id)
	if o == null or o.kind != OrderSpec.Kind.ESCORT:
		release(id, st)
		return Outcome.LOST
	var leader: int = o.target
	var mode: int = o.escort_mode
	var wslot: int = o.escort_slot
	var focus: int = o.focus
	var issued: int = o.issue_tick
	if not view.alive(leader) or view.dock_state(leader) == DOCKED:
		release(id, st)
		return Outcome.LOST
	if st.aux_id[s] != leader or st.form_order[s] != issued:
		release(id, st)
		st.aux_id[s] = leader
		st.form_order[s] = issued
	var p: Vector3 = view.pos(id)
	var lp: Vector3 = view.pos(leader)
	if wslot < 0 and st.form_slot[s] == AiState.NO_SLOT:
		st.form_slot[s] = _assign(id, leader, view, st)
	if _update_engage(id, s, p, lp, mode, focus, threat, utility, tick, view, st):
		return Outcome.ENGAGING
	_guide(id, s, p, lp, leader, wslot, view, st)
	return Outcome.FORMING


## Act for one tick: track the guidance velocity into `out`; false while engaging (the brain flies its attack).
func act(id: int, view: SimView, st: AiState, out: PilotInput) -> bool:
	var s: int = EntityId.slot(id)
	if st.form_state[s] == ENGAGE or st.aux_id[s] == 0:
		return false
	var p: Vector3 = view.pos(id)
	st.integ[s] = FlightController.track_velocity(view.basis(id), view.vel(id), st.guidance_vel[s], p.normalized(),
		gains, st.integ[s], out)
	return true


## Distance of `id` from its slot (INF without a live ESCORT order); the SC-39 / SL-2 tolerance check.
func slot_error(id: int, view: SimView, st: AiState) -> float:
	var s: int = EntityId.slot(id)
	var o: OrderSpec = view.order_head(id)
	if o == null or o.kind != OrderSpec.Kind.ESCORT or not view.alive(o.target):
		return INF
	var leader: int = o.target
	var wing: bool = o.escort_slot >= 0
	var idx: int = _slot_index(o.escort_slot, s, st, wing)
	var lp: Vector3 = view.pos(leader)
	return view.pos(id).distance_to(Formation.slot_world(lp, view.vel(leader), view.basis(leader), idx, wing, prm))


func _slot_index(wslot: int, s: int, st: AiState, wing: bool) -> int:
	var n: int = prm.slot_count(wing)
	var idx: int = wslot if wing else st.form_slot[s]
	return clampi(idx if idx != AiState.NO_SLOT else n - 1, 0, n - 1)


func _guide(id: int, s: int, p: Vector3, lp: Vector3, leader: int, wslot: int, view: SimView, st: AiState) -> void:
	var wing: bool = wslot >= 0
	var idx: int = _slot_index(wslot, s, st, wing)
	var lv: Vector3 = view.vel(leader)
	var slot_pos: Vector3 = Formation.slot_world(lp, lv, view.basis(leader), idx, wing, prm)
	var v: Vector3 = Formation.v_cmd(p, slot_pos, lv, def.v_cruise, prm)
	if st.sep_age[s] == 0:   # the neighbour query runs every second think (05 s10 think row); the term is held in between
		st.sep_push[s] = Separation.push(id, p, view.vel(id), view.team(id), view, prm)
		st.sep_age[s] = 1
	else:
		st.sep_age[s] = 0
	st.guidance_vel[s] = v + st.sep_push[s]
	st.guidance_point[s] = slot_pos


# Lowest free class slot in the escortee's roster row (AiState.form_roster: no spatial query); stale entries (dead, released
# or re-ordered escorts) are dropped on the way. With every slot taken the escort doubles up (modulo) without a roster entry.
func _assign(id: int, leader: int, view: SimView, st: AiState) -> int:
	var n: int = mini(prm.slot_count(false), AiState.ROSTER_WIDTH)
	var row: int = EntityId.slot(leader) * AiState.ROSTER_WIDTH
	var used: int = 0
	var count: int = 0
	for k: int in n:
		if _holds(st.form_roster[row + k], leader, k, view, st):
			used |= 1 << k
			count += 1
		else:
			st.form_roster[row + k] = 0
	var idx: int = Formation.free_slot(used, n)
	if idx == AiState.NO_SLOT:
		return count % prm.slot_count(false)
	st.form_roster[row + idx] = id
	return idx


func _holds(occ: int, leader: int, k: int, view: SimView, st: AiState) -> bool:
	if occ == 0 or not view.alive(occ):
		return false
	var os: int = EntityId.slot(occ)
	return st.cls[os] != AiState.NO_CLASS and st.aux_id[os] == leader and st.form_slot[os] == k


# Number of class-slot escorts holding a roster entry of the leader (this one included when it has one), at least 1.
func _group_size(leader: int, view: SimView, st: AiState) -> int:
	var row: int = EntityId.slot(leader) * AiState.ROSTER_WIDTH
	var n: int = 0
	for k: int in mini(prm.slot_count(false), AiState.ROSTER_WIDTH):
		n += 1 if _holds(st.form_roster[row + k], leader, k, view, st) else 0
	return maxi(n, 1)


# FORM <-> ENGAGE machine; true while engaging. Sets st.target on entering.
func _update_engage(id: int, s: int, p: Vector3, lp: Vector3, mode: int, focus: int, threat: int, utility: float,
		tick: int, view: SimView, st: AiState) -> bool:
	var tgt: int = focus if mode == OrderSpec.EscortMode.FOCUS else threat
	var fs: int = st.form_state[s]
	if fs == SPENT and mode == OrderSpec.EscortMode.FORM:
		fs = FORM
		st.form_state[s] = FORM
	if fs == ENGAGE:
		if _keep_engaging(s, p, lp, mode, tgt, tick, view, st):
			st.target[s] = tgt
			return true
		st.form_state[s] = FORM if mode == OrderSpec.EscortMode.FORM else SPENT
		st.target[s] = 0
		return false
	if fs == SPENT or tgt == 0 or not view.alive(tgt) or not view.visible_to(view.team(id), tgt):
		return false
	if not _may_start(id, mode, lp, tgt, utility, view, st):
		return false
	st.form_state[s] = ENGAGE
	st.timer[s] = float(tick)
	st.target[s] = tgt
	return true


func _may_start(id: int, mode: int, lp: Vector3, tgt: int, utility: float, view: SimView, st: AiState) -> bool:
	var d: float = view.pos(tgt).distance_to(lp)
	if mode == OrderSpec.EscortMode.BREAK:
		return d <= prm.break_radius_m
	if mode == OrderSpec.EscortMode.FOCUS:
		return d <= prm.focus_leash_m
	if utility <= prm.break_utility or d > prm.engage_radius_m:
		return false
	var s: int = EntityId.slot(id)
	return Formation.may_break(st.form_slot[s], _group_size(st.aux_id[s], view, st), prm)


func _keep_engaging(s: int, p: Vector3, lp: Vector3, mode: int, tgt: int, tick: int, view: SimView, st: AiState) -> bool:
	if tgt == 0 or not view.alive(tgt):
		return false
	var elapsed: float = float(tick - roundi(st.timer[s])) / _tick_hz
	var leash: float = prm.rejoin_radius_m
	if mode == OrderSpec.EscortMode.FOCUS:
		leash = prm.focus_leash_m
		if elapsed >= prm.focus_timeout_s:
			return false
	elif mode == OrderSpec.EscortMode.BREAK:
		if elapsed >= prm.break_s:
			return false
	return p.distance_to(lp) <= leash
