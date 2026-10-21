class_name DartBrain extends AiBrain
## The Dart autopilot (05 s6.2, AI-13): a flat FSM over `AiState.mode` with the shared sub-machines (LandingPilot for
## RETURN, AttackRun for ATTACK on a structure / ground unit / point, EscortPilot for ESCORT) and the air-to-air modes
## (DartCombat); the per-order thinks are `DartModes`. Think (3 Hz slice, 05 s4.3): docked check, one TerrainProbe
## pass (TTI, the A-69 drop-free lift, the A-89 visible clearance), PULL_UP exit (TTI >= `safety_clear_tti_s` after
## `pull_up_min_hold_s`), the common RTB rule (one system RETURN, FLAG_PREPEND, per head), head-order dispatch, then
## the shaping every flown command gets (Separation.term, the lift on the current radial speed, the deck floor,
## `max_alt_m`). Act (every tick): every `pull_up_check_ticks` (staggered by slot) the 05 s5.3 trigger, the 1.0 s
## ballistic re-sample below 0 OR the visible clearance below `FlightController.pull_up_loss` (R0 B.15 A-89), starts
## PULL_UP (`Assist.pull_up`); otherwise the mode's controller into one reused PilotInput and `sink.drive`. The mode
## is the HUD tag (`set_ai_tag`, 05 s6.1). Order completion (05 C4) is not wired in the sim yet: an ATTACK whose run is
## over stays the head and the Dart flies its AUTO patrol under it (`B_RUN_DONE`); a MOVE that arrived orbits the point.

const B_RTB_SENT: int = 1        ## bflags: the RTB rule's system RETURN was submitted for this head
const B_RUN_DONE: int = DartModes.B_RUN_DONE   ## bflags: the head ATTACK is over (target dead, no bombs, passes flown)
const DOCKED_STATE: int = 2      ## SimView.dock_state DOCKED
const SEP_PHASES: int = 3        ## separation refresh every SEP_PHASES thinks (A-84 lever 2; closing pairs every think)

var prm: DartParams
var gains: FlightGains
var probe_params: ProbeParams
var terrain: Terrain
var modes: DartModes
var stats_pull_ups: int = 0      ## PULL_UP entries (tests)
var stats_longest_pull_up: int = 0   ## longest PULL_UP hold in ticks (A-92: reported, no max hold in v1)
var stats_thinks: int = 0        ## shaped thinks (the counters' denominators, perf tests)
var stats_refreshes: int = 0     ## Separation.term refreshes in `_shape`
var stats_shape_loss: int = 0    ## exact pull_up_loss calls of the sink limit (at most one per shaped think)
var stats_checks: int = 0        ## act-time PULL_UP checks (every `pull_up_check_ticks` per ship)
var stats_check_loss: int = 0    ## pull_up_loss calls of those checks (only while sinking)
var _probe: ProbeResult = ProbeResult.new()
var _inp: PilotInput = PilotInput.new()
var _rtb_ids: PackedInt32Array = PackedInt32Array([0])


## The Dart brain from content: `ap` = its autopilot def's raw dictionary (05 s4.4 + the AI-13 blocks), the ship def,
## the map's terrain. Null when a block is missing (ADR-09). `ring2_m` = the collision hash's ring-2 radius
## (`Spatial.ring2_m`; the separation query stays on the ring path). Flight gains use ContentSet's FlightCommonDef (A-90).
static func from_content(c: ContentSet, ap: Dictionary, def: ShipDef, t: Terrain, ring2_m: float = INF) -> DartBrain:
	var dp: DartParams = DartParams.from_content(ap, def, c)
	var fg: FlightGains = FlightGains.from_dict(DartParams.block(ap, "flight"), def, c.rules.tick_hz, c.rules, c.flight_common)
	var lp: LandingParams = LandingParams.from_dict(DartParams.block(ap, "landing"), c.rules.gravity)
	var bp: BridgeParams = BridgeParams.from_autopilot(ap, def, c.rules, c.rules.tick_hz, c.flight_common)
	var orr: Dictionary = c.order_rules.raw if c.order_rules != null else {}
	var engage: float = TargetParams.as_num(orr.get("escort_engage_radius_m"), -1.0)
	var fp: FormationParams = null
	if engage > 0.0:
		fp = FormationParams.from_dict(DartParams.block(ap, "separation"), DartParams.block(ap, "formation"), c.wing,
			c.rules.ceiling_soft_m, engage, ring2_m)
	var tp: TargetParams = TargetParams.from_dict(ap)
	if dp == null or fg == null or lp == null or bp == null or fp == null or tp == null:
		return null
	tp.bind(c.entity_index)
	var pads: PackedFloat32Array = PackedFloat32Array()
	var _r: int = pads.resize(DefRanges.END)
	for sd: StructureDef in c.structures:
		var d: int = c.entity_index.get(sd.id, -1)
		if d >= 0 and d < DefRanges.END and sd.pads > 0:
			pads[d] = sd.pad_radius_m
	var b: DartBrain = DartBrain.new()
	b.prm = dp
	b.gains = fg
	b.probe_params = bp.probe
	b.terrain = t
	b.modes = DartModes.new(dp, t, LandingPilot.new(def, c.flight_common, c.rules, fg, lp, bp.probe,
		DartParams.block(ap, "rtb"), t, pads), EscortPilot.new(def, fp, fg), AttackRun.new(dp, t), DartCombat.new(dp, fg), tp)
	return b


func bind_rng(rng: Rng) -> void:
	modes.combat.rng = rng
	modes.picture.reset()   # bound on set_brain and after deserialize: no list survives a restore


func think_batch(ids: PackedInt32Array, n: int, view: SimView, st: AiState, sink: CommandSink, tick: int) -> void:
	for i: int in n:
		_think(ids[i], view, st, sink, tick)


func act_batch(ids: PackedInt32Array, view: SimView, st: AiState, sink: CommandSink) -> void:
	var tick: int = view.tick()
	for id: int in ids:
		var s: int = EntityId.slot(id)
		var m: int = st.mode[s]
		if m == AiTag.Tag.NONE or m == AiTag.Tag.DOCKED or st.overlay[s] != Overlays.NONE \
				or view.control_state(id) == ControlMachine.State.POSSESSED:
			continue   # a dead id is refused by sink.drive (S11); the driver drops it at its next think
		_act(id, s, m, view, st, sink, tick)
		var _d: bool = sink.drive(id, _inp)


## One think of `id` (public for rigs that drive the brain without a driver).
func think_one(id: int, view: SimView, st: AiState, sink: CommandSink, tick: int) -> void:
	_think(id, view, st, sink, tick)


func _think(id: int, view: SimView, st: AiState, sink: CommandSink, tick: int) -> void:
	var s: int = EntityId.slot(id)
	if view.dock_state(id) == DOCKED_STATE:
		_mode(id, s, AiTag.Tag.DOCKED, st, sink, tick)
		return
	var head: OrderSpec = view.order_head(id)
	var kind: int = head.kind if head != null else -1
	_order_edge(id, s, head, st)
	var m: int = st.mode[s]
	if kind != OrderSpec.Kind.RETURN or m != AiTag.Tag.RETURN:
		_sense(id, s, view, st)
	if m == AiTag.Tag.NONE or m == AiTag.Tag.DOCKED:
		var pad: int = view.nearest_friendly_pad(id)
		st.home[s] = view.pos(pad) if pad != 0 else view.pos(id)
		st.hp_mark[s] = view.hp01(id)
		st.mark_tick[s] = tick
		var launching: bool = m == AiTag.Tag.DOCKED or view.vel(id).length() < prm.launch_max_speed   # off a pad, not in flight
		m = AiTag.Tag.LAUNCH if launching and _agl(id, s, view, st) < prm.launch_climb_agl else AiTag.Tag.PATROL
	if m == AiTag.Tag.LAUNCH and _agl(id, s, view, st) < prm.launch_climb_agl:
		_mode(id, s, m, st, sink, tick)
		return
	if m != AiTag.Tag.PULL_UP and m != AiTag.Tag.RETURN and st.tti[s] < prm.pull_up_tti:
		_enter_pull_up(id, s, m, st, sink, tick)   # the think's TTI below safety_pull_up_tti_s: the 05 s2.4 threshold, ahead of act
		m = AiTag.Tag.PULL_UP
	if m == AiTag.Tag.PULL_UP:
		# exit (05 s5.3 / s6.2 as amended by R0 B.17 A-92): TTI >= safety_clear_tti_s, pull_up_min_hold_s held, and no
		# drop-free climb need left (`lift` = climb_need_mps capped above: <= 0 exactly when the need is)
		if st.tti[s] < prm.clear_tti or st.lift[s] > 0.0 or tick - st.mode_since[s] < prm.pull_up_hold_ticks:
			return
		stats_longest_pull_up = maxi(stats_longest_pull_up, tick - st.mode_since[s])
		m = st.prev_mode[s]
	if kind != OrderSpec.Kind.RETURN and (st.bflags[s] & B_RTB_SENT) == 0 and _needs_rtb(id, s, view, st, tick):
		_send_rtb(id, s, view, st, sink)
	var choices: int = modes.stats_choices
	m = _dispatch(id, s, m, head, kind, view, st, tick)
	if kind == OrderSpec.Kind.ATTACK and AttackRun.step_of(st, s) == AttackRun.Step.DONE and view.bombs(id) == 0 \
			and (st.bflags[s] & B_RTB_SENT) == 0:
		_send_rtb(id, s, view, st, sink)   # 05 s6.2 BOMB: run done -> RETURN if bombs = 0
	if m != AiTag.Tag.RETURN and m != AiTag.Tag.ENGAGE:
		_shape(id, s, m, view, st, modes.stats_choices != choices, tick)
	_mode(id, s, m, st, sink, tick)


func _dispatch(id: int, s: int, m: int, head: OrderSpec, kind: int, view: SimView, st: AiState, tick: int) -> int:
	if kind == OrderSpec.Kind.RETURN:
		return modes.think_return(id, s, m, head, view, st, tick)
	if kind == OrderSpec.Kind.ESCORT:
		return modes.think_escort(id, s, m, head, view, st, tick)
	if kind == OrderSpec.Kind.ATTACK and (st.bflags[s] & B_RUN_DONE) == 0:
		return modes.think_attack(id, s, m, head, view, st, tick)
	if kind == OrderSpec.Kind.MOVE:
		return modes.think_move(id, s, head, view, st)
	return modes.think_patrol(id, s, m, head, kind, view, st, tick)


# A new head order (issue tick changed): sub-machine state reset; the escort slot is dropped when leaving ESCORT
# (EscortPilot's release rule); an ATTACK on an entity makes it the target.
func _order_edge(id: int, s: int, head: OrderSpec, st: AiState) -> void:
	var issue: int = head.issue_tick if head != null else -1
	if issue == st.order_tick[s]:
		return
	if st.form_slot[s] != AiState.NO_SLOT and (head == null or head.kind != OrderSpec.Kind.ESCORT):
		modes.escort.release(id, st)
	st.order_tick[s] = issue
	st.sub[s] = 0
	st.passes[s] = 0
	st.wp[s] = 0
	st.bflags[s] = 0
	st.set_target(s, head.target if head != null and head.kind == OrderSpec.Kind.ATTACK else 0)
	if _order_bound(st.mode[s]):
		st.mode[s] = AiTag.Tag.PATROL
	if st.mode[s] == AiTag.Tag.PULL_UP and _order_bound(st.prev_mode[s]):
		st.prev_mode[s] = AiTag.Tag.PATROL


static func _order_bound(m: int) -> bool:
	return m == AiTag.Tag.RETURN or m == AiTag.Tag.LOITER or m == AiTag.Tag.BOMB or m == AiTag.Tag.MOVE or m == AiTag.Tag.ESCORT or DartModes.is_combat(m)


# One TerrainProbe pass (6 samples) + the height under the ship: TTI (ballistic), the A-69 drop-free lift and the
# visible clearance of A-89 (min of the AGL and the worst drop-free clearance).
func _sense(id: int, s: int, view: SimView, st: AiState) -> void:
	var p: Vector3 = view.pos(id)
	var v: Vector3 = view.vel(id)
	var u: float = v.length()
	var h_req: float = probe_params.required_clearance(u)
	st.ground_h[s] = terrain.height_at(p)
	TerrainProbe.probe(terrain, p, v, probe_params, h_req, _probe)
	st.tti[s] = _probe.tti_s
	st.lift[s] = minf(_probe.climb_need_mps, probe_params.lift_max_frac * u)   # signed: A-69 over every sample
	st.clear_m[s] = minf(p.length() - Sphere.PLANET_RADIUS - st.ground_h[s], Guidance.drop_free_clearance(_probe, prm.gravity))


# The shaping every flown command gets (05 s5.3, s5.4): EVADE / EXTEND headings, Separation.term (EscortPilot adds its
# own; held on a think that ran the choice point unless a pair is closing, so the two costly parts never stack), the
# drop-free terrain need on the current radial speed (A-69 over every sample), the deck floor, the pull-up-budget sink
# limit, no climb at `max_alt_m`.
func _shape(id: int, s: int, m: int, view: SimView, st: AiState, chose: bool, tick: int) -> void:
	var p: Vector3 = view.pos(id)
	var v: Vector3 = view.vel(id)
	var up: Vector3 = p.normalized()
	var agl: float = p.length() - Sphere.PLANET_RADIUS - st.ground_h[s]
	var alt: float = p.length() - Sphere.PLANET_RADIUS
	if m == AiTag.Tag.EVADE or m == AiTag.Tag.EXTEND:
		var g: Vector3 = st.guidance_point[s]
		var vz: float = Guidance.band_vz(agl, prm.deck_agl if m == AiTag.Tag.EVADE else agl, alt, prm.max_alt, prm.kp_alt,
			prm.vz_max)
		var speed: float = prm.boost_speed if m == AiTag.Tag.EXTEND else prm.cruise_speed
		st.guidance_vel[s] = Guidance.level((g - up * g.dot(up)).normalized(), speed, vz, v.length(), up)
	var c: Vector3 = st.guidance_vel[s]
	if m != AiTag.Tag.ESCORT:
		c += _separation(id, s, p, v, view, st, chose, tick)
	c = Guidance.floored(Guidance.cleared(c, v, up, st.lift[s]), up, agl, prm.deck_agl, prm.kp_alt, prm.vz_max)
	if c.dot(up) < 0.0:
		stats_shape_loss += 1   # sink_limited's one exact loss
	c = Guidance.sink_limited(c, view.basis(id), up, gains, agl - probe_params.required_clearance(v.length()))
	stats_thinks += 1
	if alt >= prm.max_alt and c.dot(up) > 0.0:
		c -= up * c.dot(up)
	st.guidance_vel[s] = c


# A-84 lever 2: the separation term refreshes on every third think (think phase 1 mod 3: never a choice think, which
# falls on phase 0 mod `choice_period_thinks` 6) and on every think while a pair closes (AI-11's safety rule: once a
# refresh sees a closing pair, every think refreshes until none is left); otherwise the cached term is held.
func _separation(id: int, s: int, p: Vector3, v: Vector3, view: SimView, st: AiState, chose: bool, tick: int) -> Vector3:
	var closing: bool = (st.sep_age[s] & Separation.AGE_CLOSING) != 0
	var due: bool = (MathX.floori_div(tick, prm.think_ticks) + s) % SEP_PHASES == 1
	if not closing and (chose or not due):
		return st.sep_push[s]
	st.sep_age[s] = 0   # due: force the refresh (Separation.term's own hold would skip it)
	stats_refreshes += 1
	return Separation.term(s, id, p, v, view.team(id), view, modes.escort.prm, st)


func _act(id: int, s: int, m: int, view: SimView, st: AiState, sink: CommandSink, tick: int) -> void:
	var p: Vector3 = view.pos(id)
	var v: Vector3 = view.vel(id)
	var up: Vector3 = p.normalized()
	var b: Basis = view.basis(id)
	_inp.buttons = 0   # one reused input: buttons cleared first, so a controller's BRAKE bit survives
	if m == AiTag.Tag.RETURN:
		var _ph: int = modes.landing.act(id, view, st, _inp)
		return
	if m == AiTag.Tag.LAUNCH:
		_act_launch(s, p, up, b, st)
		return
	if m != AiTag.Tag.PULL_UP and (tick + s) % prm.check_ticks == 0:
		var agl: float = p.length() - Sphere.PLANET_RADIUS - terrain.height_at(p)
		if _pull_up_due(b, p, v, up, minf(agl, st.clear_m[s])):
			_enter_pull_up(id, s, m, st, sink, tick)
			m = AiTag.Tag.PULL_UP
	if m == AiTag.Tag.PULL_UP:
		Assist.pull_up(b, v, up, gains, _inp)
		return
	if m == AiTag.Tag.ENGAGE:
		modes.combat.act_engage(id, view, st, _inp, p, v, b, tick)
	elif m != AiTag.Tag.ESCORT or not modes.escort.act(id, view, st, _inp):
		st.integ[s] = FlightController.track_velocity(b, v, st.guidance_vel[s], up, gains, st.integ[s], _inp)
	if m == AiTag.Tag.BOMB:
		modes.run.act(id, view, st, _inp)
	var f: int = st.bflags[s]
	if (f & AttackRun.F_BOOST) != 0 and view.boost_state(id) == 0:
		_inp.buttons |= PilotInput.BOOST
	if (f & AttackRun.F_FLIP) != 0:
		_inp.buttons |= PilotInput.FLIP
		st.bflags[s] = f & ~AttackRun.F_FLIP


# Guidance.pull_up_due with the counters: one pull_up_loss per check while sinking.
func _pull_up_due(b: Basis, p: Vector3, v: Vector3, up: Vector3, visible: float) -> bool:
	stats_checks += 1
	if TerrainProbe.sample_clearance(terrain, p, v, gains.gravity, prm.sample_s) < 0.0:
		return true
	if v.dot(up) >= 0.0:
		return false
	stats_check_loss += 1
	return visible < FlightController.pull_up_loss(b, v, up, gains)


func _enter_pull_up(id: int, s: int, m: int, st: AiState, sink: CommandSink, tick: int) -> void:
	st.prev_mode[s] = m
	st.mode[s] = AiTag.Tag.PULL_UP
	st.mode_since[s] = tick
	st.integ[s] = Vector2.ZERO
	sink.set_ai_tag(id, AiTag.Tag.PULL_UP)   # 05 s6.1: the HUD shows PULL_UP
	stats_pull_ups += 1


# 05 s6.2 LAUNCH: the thrust axis along the local up to `pitch_over_agl_m`, then tilted `launch_tilt_deg` toward the
# first patrol waypoint; the think hands over to PATROL above `launch_climb_agl_m`.
func _act_launch(s: int, p: Vector3, up: Vector3, b: Basis, st: AiState) -> void:
	var t_dir: Vector3 = up
	if p.length() - Sphere.PLANET_RADIUS - st.ground_h[s] >= prm.pitch_over_agl:
		var wp: Vector3 = DartModes.patrol_point(st.home[s], 0, prm.patrol_points, prm.patrol_radius)
		t_dir = up * cos(prm.launch_tilt_rad) + Guidance.toward(p, wp, up) * sin(prm.launch_tilt_rad)
	FlightController.track_thrust_vector(b, t_dir, 1.0, up, gains, _inp)


func _mode(id: int, s: int, m: int, st: AiState, sink: CommandSink, tick: int) -> void:
	if st.mode[s] != m:
		st.integ[s] = Vector2.ZERO
		sink.set_ai_tag(id, m)
	st.set_mode(id, m, tick)


func _agl(id: int, s: int, view: SimView, st: AiState) -> float:
	return view.pos(id).length() - Sphere.PLANET_RADIUS - st.ground_h[s]


# 05 s6 common RTB rule, every think: fuel below the floor, hull below rtb.hp01, or the gun empty with no bombs. The
# fuel floor (the pad lookup and its great-circle term, LandingPilot.fuel_floor) is cached in AiState.rtb_floor and
# refreshed on the choice period (and when unset); the inequality itself runs every think.
func _needs_rtb(id: int, s: int, view: SimView, st: AiState, tick: int) -> bool:
	if st.rtb_floor[s] <= 0.0 or modes.choice_due(s, tick):
		st.rtb_floor[s] = modes.landing.fuel_floor(id, view)
	return view.fuel01(id) < st.rtb_floor[s] or view.hp01(id) < modes.landing.hp_floor() \
		or (view.ammo(id) <= prm.rtb_ammo and view.bombs(id) == 0)


func _send_rtb(id: int, s: int, view: SimView, st: AiState, sink: CommandSink) -> void:
	st.bflags[s] |= B_RTB_SENT
	_rtb_ids[0] = id
	var spec: OrderSpec = OrderSpec.make(OrderSpec.Kind.RETURN, 0, Vector3.ZERO, OrderSpec.FLAG_PREPEND)
	var _r: CommandResult = sink.submit(Command.order(view.owner(id), _rtb_ids, spec))
