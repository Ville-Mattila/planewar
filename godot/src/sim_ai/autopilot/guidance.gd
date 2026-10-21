class_name Guidance extends RefCounted
## Guidance shaping shared by the ship brains and the overlays (05 s5.1, s5.3; R0 B.12 A-69, B.15 A-89; AI-13). Static
## and pure: functions of their arguments, no state, no allocation (Vector3 / float locals).
##   altitude band   vz = clamp(kp_alt (band_agl - agl), +-vz_max), never above `max_alt_m` (05 s5.3 band clamp);
##   terrain lift    A-69: the probe's drop-free lift (`TerrainProbe.drop_free_lift`) is added to the CURRENT radial
##                   speed (`v_cmd.radial = max(v_cmd.radial, v_r + lift)`), never on top of the band's own command;
##   PULL_UP trigger A-89: the 1.0 s ballistic re-sample below 0 OR the visible clearance (AGL or the probe's worst
##                   drop-free clearance) below `FlightController.pull_up_loss` (the pull-up budget). TTI / PULL_UP
##                   keep the ballistic probe; the budget is a second, earlier trigger, never a later one.


## 05 s5.3 band hold: the radial speed that brings `agl` to `band_agl`, clamped to +-`vz_max`; 0 or less at or above
## `max_alt` (altitude above the datum).
static func band_vz(agl: float, band_agl: float, alt: float, max_alt: float, kp: float, vz_max: float) -> float:
	var vz: float = clampf(kp * (band_agl - agl), -vz_max, vz_max)
	return minf(vz, 0.0) if alt >= max_alt else vz


## A level command: horizontal unit `dir_h` at `speed` with radial speed `vz`; the direction is taken from the current
## speed (so the vertical rate is met while the speed loop converges, the AI-05 rig's shape), the magnitude is `speed`.
static func level(dir_h: Vector3, speed: float, vz: float, u: float, up: Vector3) -> Vector3:
	return (dir_h * maxf(u, 1.0) + up * vz).normalized() * speed


## A-69: with a drop-free `lift` > 0 the command's radial speed becomes at least the current radial speed + lift.
static func lifted(v_cmd: Vector3, vel: Vector3, up: Vector3, lift: float) -> Vector3:
	if lift <= 0.0:
		return v_cmd
	var r: float = v_cmd.dot(up)
	return v_cmd + up * (maxf(r, vel.dot(up) + lift) - r)


## AI-13 generalisation of A-69 over every probe sample: the command's radial speed is at least the current radial
## speed + `need` (`ProbeResult.climb_need_mps`, capped by the caller): a positive need is the A-69 lift, a negative
## one the descent the samples still allow (the band hold may sink only that far; over open ground it never binds).
static func cleared(v_cmd: Vector3, vel: Vector3, up: Vector3, need: float) -> Vector3:
	var r: float = v_cmd.dot(up)
	return v_cmd + up * (maxf(r, vel.dot(up) + need) - r)


## Never command a sink below the deck: under `floor_agl` the radial command is at least the band climb back to it.
static func floored(v_cmd: Vector3, up: Vector3, agl: float, floor_agl: float, kp: float, vz_max: float) -> Vector3:
	if agl >= floor_agl:
		return v_cmd
	var r: float = v_cmd.dot(up)
	return v_cmd + up * (maxf(r, minf(kp * (floor_agl - agl), vz_max)) - r)


## Sink limit (AI-13, the pull-up budget applied to the command): when the command sinks and the height PULL_UP would
## lose from it (`FlightController.pull_up_loss` at the commanded velocity) exceeds `room` (the AGL less the required
## clearance), the sink is scaled by room / loss. One exact loss per call, none when the command does not sink; a
## residual excess is the act-time trigger's (05 s5.3) to catch.
static func sink_limited(v_cmd: Vector3, b: Basis, up: Vector3, g: FlightGains, room: float) -> Vector3:
	var r: float = v_cmd.dot(up)
	if r >= 0.0:
		return v_cmd
	var loss: float = FlightController.pull_up_loss(b, v_cmd, up, g)
	if loss <= room:
		return v_cmd
	var k: float = clampf(room / loss, 0.0, 1.0) if is_finite(loss) else 0.0
	return v_cmd - up * (r * (1.0 - k))


## The worst drop-free clearance of a filled probe result (the controller holds its path against gravity): c_w + 0.5 g t_w^2.
static func drop_free_clearance(r: ProbeResult, gravity: float) -> float:
	return r.min_clearance_m + 0.5 * gravity * r.worst_t_s * r.worst_t_s


## A-89 pull-up budget: true when `visible` (the smaller of the AGL and the worst drop-free clearance) is below the
## height PULL_UP loses before it arrests the sink (`FlightController.pull_up_loss`; 0 while climbing, so never then).
static func budget_low(visible: float, b: Basis, v: Vector3, up: Vector3, g: FlightGains) -> bool:
	if v.dot(up) >= 0.0:
		return false
	return visible < FlightController.pull_up_loss(b, v, up, g)


## 05 s5.3 act-time trigger (every `pull_up_check_ticks`): the ballistic re-sample at `sample_s` below 0, or the
## budget (`budget_low`). One height sample, plus one `pull_up_loss` while sinking (no conservative pre-bound exists:
## the loss is INF where the Newton-chosen elevation has no climb, and is not monotone in speed, sink or nose angle).
static func pull_up_due(terrain: Terrain, b: Basis, p: Vector3, v: Vector3, up: Vector3, g: FlightGains, sample_s: float,
		visible: float) -> bool:
	if TerrainProbe.sample_clearance(terrain, p, v, g.gravity, sample_s) < 0.0:
		return true
	return budget_low(visible, b, v, up, g)


## Unit horizontal direction from `p` toward `to` (any tangent when `to` is overhead).
static func toward(p: Vector3, to: Vector3, up: Vector3) -> Vector3:
	var d: Vector3 = to - p
	d -= up * d.dot(up)
	if d.length_squared() < 1e-6:
		return Sphere.tangent_frame(up).x
	return d.normalized()


## Great-circle ground distance between the points under `a` and `b` at the radius of `b`.
static func ground_dist(a: Vector3, b: Vector3) -> float:
	return a.angle_to(b) * b.length()
