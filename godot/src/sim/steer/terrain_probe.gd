class_name TerrainProbe extends RefCounted
## Height-field lookahead of 05 s5.3 (AI-07). Predicts the ship's path ballistically (constant velocity in the
## tangent frame, carried along the great circle, plus a gravity drop 0.5 g t^2 along local down) and samples
## `Terrain.height_at` at the probe times. Clearance at sample k: c_k = (|p_k| - PLANET_RADIUS) - height_at(p_k).
## Pure (S8): static functions of their arguments, no state, no allocation (Vector3 and float locals only);
## `net` prediction may call them for the possessed unit. Cost: `probe_times_s.size()` height samples per
## call (6 at think, 05 s5.3 / s10), plus 1 for the t = 0 bracket and REFINE_STEPS on a hit in time_to_impact.
const REFINE_STEPS: int = 5   ## bisection steps inside the bracketing interval: <= 1 s / 32 = 0.03 s


## Seconds until the predicted path first reaches the terrain (clearance <= 0), refined by bisection inside the
## bracketing samples (REFINE_STEPS extra height samples, only on a hit); 0.0 if already at or under it; INF if
## no sample is below 0 inside the horizon.
static func time_to_impact(terrain: Terrain, p: Vector3, v: Vector3, probe: ProbeParams) -> float:
	var f: Basis = _frame(p, v)
	var ts: PackedFloat32Array = probe.probe_times_s
	var prev_t: float = 0.0
	if _clearance(terrain, f, p, v, probe.gravity, 0.0) <= 0.0:
		return 0.0
	for k: int in ts.size():
		var t: float = ts[k]
		var c: float = _clearance(terrain, f, p, v, probe.gravity, t)
		if c <= 0.0:
			return _refine(terrain, f, p, v, probe.gravity, prev_t, t)
		prev_t = t
	return INF


## (clearance m, time s) of the worst (lowest clearance) probe sample; ties keep the earliest.
static func min_clearance(terrain: Terrain, p: Vector3, v: Vector3, probe: ProbeParams) -> Vector2:
	var f: Basis = _frame(p, v)
	var ts: PackedFloat32Array = probe.probe_times_s
	var worst: Vector2 = Vector2(INF, 0.0)
	for k: int in ts.size():
		var c: float = _clearance(terrain, f, p, v, probe.gravity, ts[k])
		if c < worst.x:
			worst = Vector2(c, ts[k])
	return worst


## Extra climb rate in m/s to add to `v_cmd` along local up: for the worst sample
## `max(0, h_req - c_k) / max(t_k, lift_min_time_s)`, capped at `lift_max_frac * |v|`.
static func terrain_lift(terrain: Terrain, p: Vector3, v: Vector3, probe: ProbeParams, h_req: float) -> float:
	var w: Vector2 = min_clearance(terrain, p, v, probe)
	var lift: float = maxf(0.0, h_req - w.x) / maxf(w.y, probe.lift_min_time_s)
	return minf(lift, probe.lift_max_frac * v.length())


## Bisection on [lo, hi] where clearance(lo) > 0 and clearance(hi) <= 0; returns the upper end of the final interval.
static func _refine(terrain: Terrain, f: Basis, p: Vector3, v: Vector3, g: float, lo: float, hi: float) -> float:
	var a: float = lo
	var b: float = hi
	for _i: int in REFINE_STEPS:
		var m: float = 0.5 * (a + b)
		if _clearance(terrain, f, p, v, g, m) <= 0.0:
			b = m
		else:
			a = m
	return 0.5 * (a + b)


## Basis(x = radial n0, y = unit horizontal travel direction, z.x = ground speed). The travel direction is
## zero for a vertical or stationary ship (the path then stays over one point).
static func _frame(p: Vector3, v: Vector3) -> Basis:
	var n0: Vector3 = p.normalized()
	var vt: Vector3 = v - n0 * v.dot(n0)
	var s: float = vt.length()
	var tdir: Vector3 = vt / s if s > 0.0 else Vector3.ZERO
	return Basis(n0, tdir, Vector3(s, 0.0, 0.0))


## Clearance of the predicted position at time t (frame from `_frame`).
static func _clearance(terrain: Terrain, f: Basis, p: Vector3, v: Vector3, g: float, t: float) -> float:
	var n0: Vector3 = f.x
	var r0: float = p.length()
	var phi: float = f.z.x * t / r0
	var dir: Vector3 = n0 * cos(phi) + f.y * sin(phi)
	var r: float = r0 + v.dot(n0) * t - 0.5 * g * t * t
	return r - Sphere.PLANET_RADIUS - terrain.height_at(dir)
