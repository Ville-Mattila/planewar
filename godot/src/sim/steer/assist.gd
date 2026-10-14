class_name Assist extends RefCounted
## Assist substitution of tick-order step 4 (R0 B.5, C2-04; 05 s1.2, s2.4): pure functions that write the input of
## a possessed entity in place of its pilot's. `SimWorld` calls them on the server (`AssistStep`); `net`'s
## `Prediction` calls them with the same arguments for the client's own ship (ADR-07), so they read nothing but their
## arguments (S8) and a change here is reviewed for both the `sim_ai` and the `net` lane. `auto_dock` joins with AI-10.
##
## LINK_BRIDGE (05 C10, C13; R0 C2-08) is the SAFETY behaviour of 05 s2.4 while the entity stays POSSESSED: pull up
## when the time to impact is below `safety_pull_up_tti_s`, else hold the current velocity, shaped by the 05 s5.3
## terrain lift (drop-free, R0 B.12 A-69). Stateless, so the hold cannot integrate its angle of attack: `trim_lead`
## feeds the steady one forward from the lift law instead (otherwise the path sags under gravity). No pull-up
## hysteresis: the probe runs every tick. The SAFETY overlay of `sim_ai` uses `pull_up`, the threshold, the lift and
## `trim_lead` (as its integrator seed), with its own hysteresis (AiState).


## One tick of LINK_BRIDGE for a ship: one `TerrainProbe.probe` pass (6 samples) into the caller's `probe` scratch,
## then `pull_up` or `hold_velocity` into `out`. `b` is the entity basis as SimView returns it (x right, y up,
## z = -forward); `p`, `v` the sim position and world velocity. Every button is cleared (BRAKE as the law sets it).
static func link_bridge(b: Basis, p: Vector3, v: Vector3, terrain: Terrain, bp: BridgeParams, probe: ProbeResult,
		out: PilotInput) -> void:
	var u: float = v.length()
	var h_req: float = bp.probe.required_clearance(u)
	TerrainProbe.probe(terrain, p, v, bp.probe, h_req, probe)
	var up: Vector3 = p.normalized()
	out.buttons = 0
	if probe.tti_s < bp.pull_up_tti_s:
		pull_up(b, up, bp.gains, out)
	else:
		var lift: float = TerrainProbe.drop_free_lift(probe, bp.probe, h_req, u)
		hold_velocity(b, v, lift, up, bp.gains, trim_lead(v, up, bp), out)


## LINK_BRIDGE for a ground unit: stop (thrust 0 is the zero speed fraction). No BRAKE, which held for 0.5 s at
## standstill would reverse the unit (05 s1.1).
static func link_bridge_ground(out: PilotInput) -> void:
	out.thrust = 0.0
	out.pitch = 0.0
	out.yaw = 0.0
	out.roll = 0.0
	out.buttons = 0


## 05 s5.3 PULL_UP: nose (thrust axis) to the local up at the ship's own maximum rates, thrust 1, every button off.
static func pull_up(b: Basis, up_local: Vector3, g: FlightGains, out: PilotInput) -> void:
	out.buttons = 0
	FlightController.track_thrust_vector(b, up_local, 1.0, up_local, g, out)
	out.thrust = 1.0


## Hold velocity `v` as it is now (no snap to a new heading): `track_velocity` toward `v` with the radial speed
## raised by `lift_mps` (v_cmd.radial = v_r + lift, A-69) and the pitch integrator set to `lead` (rad of nose lead,
## `trim_lead`), the throttle integrator zero.
static func hold_velocity(b: Basis, v: Vector3, lift_mps: float, up_local: Vector3, g: FlightGains, lead: float,
		out: PilotInput) -> void:
	var _i: Vector2 = FlightController.track_velocity(b, v, v + up_local * lift_mps, up_local, g, Vector2(lead, 0.0),
		out)


## Steady nose lead (rad) that holds the path of velocity `v` against gravity under the ship's lift law (03 s5.3:
## body-up damping `Kinematics.k_up_effective` turns the body-up velocity into lift): sin(lead) = g_perp / (u k),
## g_perp = gravity across the path. Capped at the FlightGains pitch-integrator clamp; 0 below 1 m/s.
static func trim_lead(v: Vector3, up_local: Vector3, bp: BridgeParams) -> float:
	var u: float = v.length()
	if u < 1.0:
		return 0.0
	var s: float = (v / u).dot(up_local)
	var g_perp: float = bp.probe.gravity * sqrt(maxf(1.0 - s * s, 0.0))
	var k: float = Kinematics.k_up_effective(u, bp.ship, bp.rules)
	if k <= 0.0:
		return bp.gains.integ_max
	return minf(asin(minf(g_perp / (u * k), 1.0)), bp.gains.integ_max)
