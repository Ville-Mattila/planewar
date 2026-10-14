class_name Overlays extends RefCounted
## The overlays `sim_ai` executes in tick-order step 3 (05 s2.4, R0 C2-04; AI-08): SAFETY after every release and
## RECOVER_CEILING after the hard-ceiling release (C11). `ControlMachine` sets them in the entity store; `AiDriver`
## sees the release as the POSSESSED -> not POSSESSED edge of a registered entity (`enter`), runs the overlay every
## tick at 30 Hz after the class's act so its input wins (`run`), and skips the entity's thinks until it ends.
## LINK_BRIDGE is not here: the entity stays POSSESSED, so `Assist.link_bridge` runs it in step 4.
##
## SAFETY (ships): hold the velocity at the release (no snap to a new heading) plus the TerrainProbe lift; PULL_UP (nose to the local up, thrust
## 1) when the time to impact drops below `safety_pull_up_tti_s`, until it is >= `safety_clear_tti_s`; a system
## RETURN (FLAG_PREPEND) once when fuel is below `safety_force_rtb_fuel01`; ends at TTI >= clear and >= min hold, or at
## max hold unless a PULL_UP is running. RECOVER_CEILING: keep the heading on a `recover_ceiling_gamma_deg` path at
## `v_cruise`, SAFETY checks still apply; ends at or below `recover_ceiling_exit_alt_m`. Ground SAFETY: stop with the
## brake for `safety_min_hold_s`. Static; all per-entity state is in `AiState` (overlay, overlay_since, ov_flags,
## guidance_vel, integ, tti). One `TerrainProbe.probe` (6 samples) per overlay tick; no allocation except the one
## RETURN command per release.

const NONE: int = ControlMachine.Overlay.NONE
const SAFETY: int = ControlMachine.Overlay.SAFETY
const RECOVER_CEILING: int = ControlMachine.Overlay.RECOVER_CEILING


## Release edge of `id` at `tick`: starts RECOVER_CEILING when the ship is at or above the hard ceiling (the C11
## release happens there), SAFETY otherwise; captures the velocity to hold and seeds the pitch integrator with the
## steady trim (`Assist.trim_lead`), the throttle integrator zero.
static func enter(id: int, v: SimView, st: AiState, p: OverlayParams, tick: int) -> void:
	var s: int = EntityId.slot(id)
	var pos: Vector3 = v.pos(id)
	st.overlay[s] = RECOVER_CEILING if not p.ground and pos.length() - Sphere.PLANET_RADIUS >= p.ceiling_hard_m else SAFETY
	st.overlay_since[s] = tick
	st.ov_flags[s] = 0
	st.guidance_vel[s] = v.vel(id)
	st.integ[s] = Vector2.ZERO
	if not p.ground:
		st.integ[s] = Vector2(Assist.trim_lead(v.vel(id), pos.normalized(), p.bridge), 0.0)


## Ends the overlay of slot `s` (also when the entity is possessed again).
static func clear(st: AiState, s: int) -> void:
	st.overlay[s] = NONE
	st.ov_flags[s] = st.ov_flags[s] & AiState.OV_POSSESSED
	st.integ[s] = Vector2.ZERO


## One act tick of `id`'s overlay: writes `out` and drives it; true when the overlay ended this tick (the driver
## then wakes the brain). `probe` and `out` are the caller's scratch.
static func run(id: int, v: SimView, st: AiState, p: OverlayParams, terrain: Terrain, sink: CommandSink, tick: int,
		probe: ProbeResult, out: PilotInput) -> bool:
	var s: int = EntityId.slot(id)
	if p.ground:
		return run_ground_safety(id, st, p, sink, tick, out)
	if (v.flags(id) & (EntityStore.F_DOCKED | EntityStore.F_LANDED)) != 0:
		clear(st, s)          # 05 s2.5: a release on the pad is satisfied at once (no pull-up off the pad)
		return true
	if st.overlay[s] == RECOVER_CEILING:
		return run_recover_ceiling(id, v, st, p, terrain, sink, probe, out)
	if st.overlay[s] == SAFETY:
		return run_safety(id, v, st, p, terrain, sink, tick, probe, out)
	return false


## SAFETY for a ship (05 s2.4 run_safety).
static func run_safety(id: int, v: SimView, st: AiState, p: OverlayParams, terrain: Terrain, sink: CommandSink,
		tick: int, probe: ProbeResult, out: PilotInput) -> bool:
	var s: int = EntityId.slot(id)
	var pulling: bool = _checks(id, v, st, p, terrain, sink, probe)
	if pulling:
		Assist.pull_up(v.basis(id), v.pos(id).normalized(), p.bridge.gains, out)
	else:
		_track(id, v, st, p, _lifted(st.guidance_vel[s], v, id, p, probe), out)
	var _d: bool = sink.drive(id, out)
	var age: int = tick - st.overlay_since[s]
	if pulling or age < p.min_hold_ticks:
		return false
	if probe.tti_s >= p.clear_tti_s or age >= p.max_hold_ticks:
		clear(st, s)
		return true
	return false


## RECOVER_CEILING (05 s2.4): heading kept, flight-path angle `rc_gamma_rad`, speed `v_cruise`; SAFETY checks apply.
static func run_recover_ceiling(id: int, v: SimView, st: AiState, p: OverlayParams, terrain: Terrain,
		sink: CommandSink, probe: ProbeResult, out: PilotInput) -> bool:
	var s: int = EntityId.slot(id)
	var pos: Vector3 = v.pos(id)
	var up: Vector3 = pos.normalized()
	var pulling: bool = _checks(id, v, st, p, terrain, sink, probe)
	if pulling:
		Assist.pull_up(v.basis(id), up, p.bridge.gains, out)
	else:
		var h: Vector3 = _heading(v.vel(id), -v.basis(id).z, up)
		var path: Vector3 = (h * cos(p.rc_gamma_rad) + up * sin(p.rc_gamma_rad)) * p.v_cruise
		_track(id, v, st, p, _lifted(path, v, id, p, probe), out)
	var _d: bool = sink.drive(id, out)
	if not pulling and pos.length() - Sphere.PLANET_RADIUS <= p.rc_exit_alt_m:
		clear(st, s)
		return true
	return false


## Ground SAFETY (05 s2.4): thrust 0 with BRAKE for `min_hold_ticks`, then the brain resumes.
static func run_ground_safety(id: int, st: AiState, p: OverlayParams, sink: CommandSink, tick: int,
		out: PilotInput) -> bool:
	var s: int = EntityId.slot(id)
	Assist.link_bridge_ground(out)
	out.buttons = PilotInput.BRAKE
	var _d: bool = sink.drive(id, out)
	if tick - st.overlay_since[s] + 1 >= p.min_hold_ticks:
		clear(st, s)
		return true
	return false


# The checks every ship overlay runs (05 s2.4 steps 2-3): one probe pass (TTI cached in st.tti; the lift for the
# required clearance, 05 s5.3, shapes the guidance like every autopilot command), PULL_UP below the
# pull-up TTI held until the clear TTI (the hold velocity is re-captured when it ends), then the low-fuel RETURN.
# Returns whether PULL_UP is running.
static func _checks(id: int, v: SimView, st: AiState, p: OverlayParams, terrain: Terrain, sink: CommandSink,
		probe: ProbeResult) -> bool:
	var s: int = EntityId.slot(id)
	var vel: Vector3 = v.vel(id)
	var pr: ProbeParams = p.bridge.probe
	TerrainProbe.probe(terrain, v.pos(id), vel, pr, pr.required_clearance(vel.length()), probe)
	st.tti[s] = probe.tti_s
	var f: int = st.ov_flags[s]
	var pulling: bool = (f & AiState.OV_PULL_UP) != 0
	if probe.tti_s < p.bridge.pull_up_tti_s:
		pulling = true
	elif pulling and probe.tti_s >= p.clear_tti_s:
		pulling = false
		st.guidance_vel[s] = vel
		st.integ[s] = Vector2(Assist.trim_lead(vel, v.pos(id).normalized(), p.bridge), 0.0)
	st.ov_flags[s] = (f | AiState.OV_PULL_UP) if pulling else (f & ~AiState.OV_PULL_UP)
	_force_return(id, v, st, p, sink)
	return pulling


# 05 s2.4 step 3: below the fuel threshold, one system RETURN prepended to the resumed queue (issuer -1 in 05; the
# sink submits it for the owner slot with FLAG_PREPEND, see MODULE.md open items), at most once per overlay.
static func _force_return(id: int, v: SimView, st: AiState, p: OverlayParams, sink: CommandSink) -> void:
	var s: int = EntityId.slot(id)
	if (st.ov_flags[s] & AiState.OV_RTB_SENT) != 0 or v.fuel01(id) >= p.force_rtb_fuel01:
		return
	st.ov_flags[s] = st.ov_flags[s] | AiState.OV_RTB_SENT
	var head: OrderSpec = v.order_head(id)
	if head != null and head.kind == OrderSpec.Kind.RETURN:
		return
	var spec: OrderSpec = OrderSpec.make(OrderSpec.Kind.RETURN, 0, Vector3.ZERO, OrderSpec.FLAG_PREPEND)
	var _r: CommandResult = sink.submit(Command.order(v.owner(id), PackedInt32Array([id]), spec))


# 05 s5.3 / R0 B.12 A-69 guidance shaping: with a drop-free lift > 0 the command's radial speed becomes at least the
# current radial speed + lift (never lift added on top of a hold's own radial command).
static func _lifted(v_cmd: Vector3, v: SimView, id: int, p: OverlayParams, probe: ProbeResult) -> Vector3:
	var vel: Vector3 = v.vel(id)
	var up: Vector3 = v.pos(id).normalized()
	var u: float = vel.length()
	var lift: float = TerrainProbe.drop_free_lift(probe, p.bridge.probe, p.bridge.probe.required_clearance(u), u)
	if lift <= 0.0:
		return v_cmd
	var r: float = v_cmd.dot(up)
	return v_cmd + up * (maxf(r, vel.dot(up) + lift) - r)


static func _track(id: int, v: SimView, st: AiState, p: OverlayParams, v_cmd: Vector3, out: PilotInput) -> void:
	var s: int = EntityId.slot(id)
	out.buttons = 0
	st.integ[s] = FlightController.track_velocity(v.basis(id), v.vel(id), v_cmd, v.pos(id).normalized(),
		p.bridge.gains, st.integ[s], out)


# Unit horizontal heading: of the velocity, else of the nose, else any tangent (a vertical zoom at the ceiling).
static func _heading(vel: Vector3, fwd: Vector3, up: Vector3) -> Vector3:
	var h: Vector3 = vel - up * vel.dot(up)
	if h.length_squared() < 1.0:
		h = fwd - up * fwd.dot(up)
	if h.length_squared() < 1e-6:
		h = Sphere.tangent_frame(up).x
	return h.normalized()
