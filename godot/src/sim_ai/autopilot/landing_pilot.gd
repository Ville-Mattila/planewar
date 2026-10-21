class_name LandingPilot extends RefCounted
## RETURN landing of one ship class (05 s5.5, AI-09): the `sim_ai` side of LandingController. It reads the world
## through SimView only, keeps the per-ship landing memory in AiState (`land_*`, `integ`, `ground_h`, `lift`, the pad
## in `aux_id`, team-local pad claims in `pad_claim`) and copies it through reused scratch structs, so a call
## allocates nothing. Think (the class's think slice): pad validity and selection (the 05 `rtb.gd` choice point),
## one TerrainProbe pass, pad busy / threat flags, approach bearing at the gate, pad claim, HOLD fuel divert. Act
## (every tick): LandingController.step into the caller's PilotInput; the brain sends it with `sink.drive`.
## Pad busy = occupied by another ship, another ship first in the sim's pad queue, or claimed by another AI ship
## of this driver that is on its approach (the claim is what makes the second of two arrivals hold, SC-06).

## Keys of the `rtb` dictionary `_init` requires (05 s4.4 `rtb.fuel_reserve_s`; the rest are the 05 s5.5 pad
## selection and abort numbers, AI-09 additions).
const RTB_KEYS: PackedStringArray = ["fuel_reserve_s", "hold_fuel_reserve_s", "pad_eta_scale_s", "pad_queue_s",
	"pad_w_one_queued", "pad_w_more_queued", "threat_radius_m", "fuel01", "hp01", "fuel_margin"]
const DOCKED: int = 2                    ## SimView.dock_state DOCKED

var def: ShipDef
var prm: LandingParams
var gains: FlightGains
var probe_params: ProbeParams
var terrain: Terrain
var pad_radius_by_def: PackedFloat32Array   ## StructureDef.pad_radius_m by def id (0 = no pad)
var _common: FlightCommonDef
var _rules: RulesDef
var _rtb: PackedFloat32Array = PackedFloat32Array()   ## RTB_KEYS order
var _ship: ShipSnapshot = ShipSnapshot.new()
var _pad: PadSnapshot = PadSnapshot.new()
var _ls: LandingState = LandingState.new()
var _probe: ProbeResult = ProbeResult.new()
var _no_threat: PackedFloat32Array = PackedFloat32Array()
# Pad geometry cache by pad slot (derived from SimView, so not part of the S4 bytes; refilled on an id mismatch).
var _pad_cache_id: PackedInt32Array = PackedInt32Array()
var _pad_cache_p: PackedVector3Array = PackedVector3Array()
var _pad_cache_n: PackedVector3Array = PackedVector3Array()
var _pad_cache_r: PackedFloat32Array = PackedFloat32Array()


func _init(ship_def: ShipDef, common: FlightCommonDef, rules: RulesDef, flight_gains: FlightGains,
		landing: LandingParams, probe: ProbeParams, rtb: Dictionary, t: Terrain, pad_radius: PackedFloat32Array) -> void:
	def = ship_def
	_common = common
	_rules = rules
	gains = flight_gains
	prm = landing
	probe_params = probe
	terrain = t
	pad_radius_by_def = pad_radius
	var _r: Array[int] = [_pad_cache_id.resize(EntityStore.SLOT_COUNT), _pad_cache_p.resize(EntityStore.SLOT_COUNT),
		_pad_cache_n.resize(EntityStore.SLOT_COUNT), _pad_cache_r.resize(EntityStore.SLOT_COUNT)]
	for k: String in RTB_KEYS:
		var x: Variant = rtb.get(k)
		assert(x is float or x is int, "rtb key missing: " + k)
		var f: float = 0.0
		if x is int:
			var i: int = x
			f = float(i)
		elif x is float:
			f = x
		var _b: bool = _rtb.push_back(f)


## 05 s6 common RTB rule, fuel and hull terms: fuel01 < max(rtb.fuel01, fuel_needed01 * fuel_margin) with
## fuel_needed01 = (great circle to the nearest friendly pad / v_cruise + fuel_reserve_s) / fuel_s, or
## hp01 < rtb.hp01. The ammo term needs the class's weapons and stays with the class brain. One sim pad lookup.
func needs_rtb(id: int, view: SimView) -> bool:
	return view.fuel01(id) < fuel_floor(id, view) or view.hp01(id) < hp_floor()


## AI-13: the fuel term of `needs_rtb` alone, max(rtb.fuel01, fuel_needed01 * fuel_margin) (one pad lookup); a brain
## may cache it between thinks (the floor moves with the distance to the pad, slowly).
func fuel_floor(id: int, view: SimView) -> float:
	var pad: int = view.nearest_friendly_pad(id)
	var floor01: float = _rtb[7]
	if pad != 0:
		var d: float = view.pos(id).angle_to(view.pos(pad)) * view.pos(pad).length()
		floor01 = maxf(floor01, (d / def.v_cruise + _rtb[0]) / def.fuel_s * _rtb[9])
	return floor01


## AI-13: rtb.hp01, the hull term of `needs_rtb`.
func hp_floor() -> float:
	return _rtb[8]


## Starts a landing on `pad` (RETURN, or a divert): L1 TRANSIT, no bearing, no attempts.
func begin(id: int, pad: int, st: AiState) -> void:
	var s: int = EntityId.slot(id)
	_release_claim(id, st)
	st.aux_id[s] = pad
	st.land_phase[s] = LandingController.Phase.TRANSIT
	st.land_attempts[s] = 0
	st.land_abort[s] = LandingController.Abort.NONE
	st.land_flags[s] = 0
	st.land_bearing[s] = Vector3.ZERO
	st.land_mark[s] = Vector3.ZERO
	st.land_ga_dir[s] = Vector3.ZERO
	st.integ[s] = Vector2.ZERO


## Current landing phase of `id` (LandingController.Phase).
func phase(id: int, st: AiState) -> int:
	return st.land_phase[EntityId.slot(id)]


## Think for one landing ship (05 s4.3 slice; 05 s10 think row: one probe, one pad check, no roster scan except
## the structure scan of a pad selection, which runs only at RETURN start and on a divert).
func think(id: int, view: SimView, st: AiState) -> void:
	var s: int = EntityId.slot(id)
	if view.dock_state(id) == DOCKED:
		st.land_phase[s] = LandingController.Phase.DONE
		return
	var pad: int = st.aux_id[s]
	if not _pad_ok(id, pad, view) or st.land_abort[s] == LandingController.Abort.PAD_INVALID \
			or st.land_attempts[s] > prm.max_attempts or _hold_fuel_low(id, view, st):
		var next: int = select_pad(id, view, pad, st)
		begin(id, next if next != 0 else pad, st)
		pad = st.aux_id[s]
	var p: Vector3 = view.pos(id)
	var v: Vector3 = view.vel(id)
	TerrainProbe.probe(terrain, p, v, probe_params, probe_params.required_clearance(v.length()), _probe)
	st.tti[s] = _probe.tti_s
	st.lift[s] = _flown_lift()
	st.ground_h[s] = terrain.height_at(p)
	var flags: int = LandingPilot._busy_flag(id, pad, view, st)
	if view.team(pad) != view.team(id):
		flags |= AiState.LAND_FOREIGN
	var mask: int = ((1 << PlayerTable.TEAMS) - 1) & ~(1 << view.team(id))
	if not view.projectiles_near(view.pos(pad), _rtb[6], mask).is_empty():
		flags |= AiState.LAND_THREAT
	st.land_flags[s] = flags
	var ph: int = st.land_phase[s]
	var d: float = view.pos(pad).angle_to(p) * view.pos(pad).length()
	if ph == LandingController.Phase.TRANSIT and d < prm.gate_dist_m and st.land_bearing[s] == Vector3.ZERO:
		_fill(id, pad, view, st)
		st.land_bearing[s] = LandingController.choose_bearing(terrain, _pad, _ship, _no_threat, prm)
	if (flags & AiState.LAND_BUSY) == 0 and (ph >= LandingController.Phase.TRANSITION
			or ph == LandingController.Phase.APPROACH or (ph == LandingController.Phase.TRANSIT and d < prm.gate_dist_m)):
		st.pad_claim[EntityId.slot(pad)] = id
	elif ph == LandingController.Phase.GO_AROUND or ph == LandingController.Phase.HOLD:
		_release_claim(id, st)


## Act for one landing ship: LandingController.step into `out` (axes, thrust, BRAKE). Returns the phase.
func act(id: int, view: SimView, st: AiState, out: PilotInput) -> int:
	var s: int = EntityId.slot(id)
	if view.dock_state(id) == DOCKED:
		st.land_phase[s] = LandingController.Phase.DONE
		_release_claim(id, st)
	_fill(id, st.aux_id[s], view, st)
	_ls.phase = st.land_phase[s]
	_ls.attempts = st.land_attempts[s]
	_ls.abort_reason = st.land_abort[s]
	_ls.bearing = st.land_bearing[s]
	_ls.mark = st.land_mark[s]
	_ls.ga_dir = st.land_ga_dir[s]
	_ls.integ = st.integ[s]
	var ph: int = LandingController.step(_ls, _ship, _pad, prm, gains, out)
	st.land_phase[s] = ph
	st.land_attempts[s] = mini(_ls.attempts, 255)
	st.land_abort[s] = _ls.abort_reason
	st.land_bearing[s] = _ls.bearing
	st.land_mark[s] = _ls.mark
	st.land_ga_dir[s] = _ls.ga_dir
	st.integ[s] = _ls.integ
	return ph


func _fill(id: int, pad: int, view: SimView, st: AiState) -> void:
	var s: int = EntityId.slot(id)
	var p: Vector3 = view.pos(id)
	_ship.b = view.basis(id)
	_ship.p = p
	_ship.v = view.vel(id)
	_ship.a_thrust = def.a_thrust * Kinematics.ceiling_efficiency(p.length() - Sphere.PLANET_RADIUS, _rules)
	_ship.eff_fade_start = _common.eff_fade_start
	_ship.bounding_radius = def.bounding_radius
	_ship.v_cruise = def.v_cruise
	_ship.ground_h = st.ground_h[s]
	_ship.lift_mps = st.lift[s]
	_ship.tti_s = st.tti[s]
	var ps: int = EntityId.slot(pad)
	if _pad_cache_id[ps] != pad:   # pads do not move: position, normal and radius read once per pad id
		_pad_cache_id[ps] = pad
		_pad_cache_p[ps] = view.pos(pad)
		_pad_cache_n[ps] = view.basis(pad).y
		_pad_cache_r[ps] = _radius(pad, view)
	_pad.p = _pad_cache_p[ps]
	_pad.n = _pad_cache_n[ps]
	_pad.radius_m = _pad_cache_r[ps]
	_pad.valid = view.alive(pad) and (st.land_flags[s] & AiState.LAND_FOREIGN) == 0 and _pad.radius_m > 0.0
	_pad.busy = (st.land_flags[s] & AiState.LAND_BUSY) != 0
	_pad.threat = (st.land_flags[s] & AiState.LAND_THREAT) != 0


## 05 s5.5 pad selection: score = 1 / (1 + eta / pad_eta_scale_s) * w_free * w_hangar * (1 - risk), eta = great
## circle / v_cruise + queue length * pad_queue_s; a pad whose eta at cruise burn plus fuel_reserve_s exceeds the
## remaining fuel is rejected; if all are rejected the nearest wins. `exclude` is skipped (a divert). w_hangar and
## risk read the threat map, which does not exist yet: both are neutral (1 and 0). Ties keep the lowest slot.
func select_pad(id: int, view: SimView, exclude: int, st: AiState) -> int:
	var p: Vector3 = view.pos(id)
	var fuel_s: float = view.fuel01(id) * def.fuel_s
	var burn: float = gains.t_trim + _common.fuel_burn_idle_per_s
	var best: int = 0
	var best_score: float = -1.0
	var nearest: int = 0
	var nearest_d: float = INF
	for pad: int in view.structures():
		if pad == exclude or not _pad_ok(id, pad, view):
			continue
		var d: float = p.angle_to(view.pos(pad)) * view.pos(pad).length()
		if d < nearest_d:
			nearest_d = d
			nearest = pad
		var queued: int = _queue_len(id, pad, view, st)
		var eta: float = d / def.v_cruise + float(queued) * _rtb[3]
		if eta * burn + _rtb[0] > fuel_s:
			continue
		var w_free: float = 1.0 if queued == 0 else (_rtb[4] if queued == 1 else _rtb[5])
		var score: float = w_free / (1.0 + eta / _rtb[2])
		if score > best_score:
			best_score = score
			best = pad
	return best if best != 0 else nearest


func _radius(pad: int, view: SimView) -> float:
	var d: int = view.def_id(pad)
	return pad_radius_by_def[d] if d >= 0 and d < pad_radius_by_def.size() else 0.0


func _pad_ok(id: int, pad: int, view: SimView) -> bool:
	return pad != 0 and view.alive(pad) and view.team(pad) == view.team(id) and _radius(pad, view) > 0.0


func _queue_len(id: int, pad: int, view: SimView, st: AiState) -> int:
	var occ: int = view.pad_occupant(pad)
	var n: int = 1 if occ != 0 and occ != id else 0
	n += view.pad_queue(pad).size()
	return n + (1 if _claimed_by_other(id, pad, view, st) else 0)


static func _busy_flag(id: int, pad: int, view: SimView, st: AiState) -> int:
	var occ: int = view.pad_occupant(pad)
	var q: PackedInt32Array = view.pad_queue(pad)
	if (occ != 0 and occ != id) or (not q.is_empty() and q[0] != id) or _claimed_by_other(id, pad, view, st):
		return AiState.LAND_BUSY
	return 0


# A claim counts while its ship is alive, still landing on this pad and past the gate (APPROACH .. DONE).
static func _claimed_by_other(id: int, pad: int, view: SimView, st: AiState) -> bool:
	var c: int = st.pad_claim[EntityId.slot(pad)]
	if c == 0 or c == id or not view.alive(c):
		return false
	var cs: int = EntityId.slot(c)
	var ph: int = st.land_phase[cs]
	return st.aux_id[cs] == pad and ph != LandingController.Phase.HOLD and ph != LandingController.Phase.GO_AROUND


func _release_claim(id: int, st: AiState) -> void:
	var pad: int = st.aux_id[EntityId.slot(id)]
	if pad != 0 and st.pad_claim[EntityId.slot(pad)] == id:
		st.pad_claim[EntityId.slot(pad)] = 0


# HOLD keeps hold_fuel_reserve_s of fuel (05 s5.5), else the ship diverts.
func _hold_fuel_low(id: int, view: SimView, st: AiState) -> bool:
	return st.land_phase[EntityId.slot(id)] == LandingController.Phase.HOLD \
		and view.fuel01(id) * def.fuel_s < _rtb[1]


# TerrainProbe predicts a ballistic path; the controller holds its path against gravity, so the drop is taken
# back out of the lift (as AI-05's guidance does).
func _flown_lift() -> float:
	var t: float = _probe.worst_t_s
	var drop: float = 0.5 * probe_params.gravity * t * t / maxf(t, probe_params.lift_min_time_s)
	return maxf(_probe.lift_mps - drop, 0.0)
