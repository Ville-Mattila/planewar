class_name TerrainProbe extends RefCounted
## Height-field lookahead of 05 s5.3 (AI-07). Predicts the ship's path ballistically (constant velocity in the
## tangent frame, carried along the great circle, plus a gravity drop 0.5 g t^2 along local down) and samples
## `Terrain.height_at` at the probe times. Clearance at sample k: c_k = (|p_k| - PLANET_RADIUS) - height_at(p_k).
## Pure (S8): static functions of their arguments, no state; the only write is to the caller's `out`.
## Cost (05 s5.3 / s10): `probe` = one pass of `probe_times_s.size()` (6) height samples per think and nothing
## else; `sample_clearance` = 1 sample (the 1.0 s re-check at act, every 3rd tick).


## One sampling pass fills `out`: TTI (the first sample with clearance <= 0, linearly refined between it and the
## previous sample, so a dip between two samples is missed by design, 05 s5.3; if the very first sample is
## already <= 0 the crossing is extrapolated back through the first two samples, clamped to [0, t_0]), the worst
## sample (clearance, time, direction) and the lift `max(0, h_req - c_w) / max(t_w, lift_min_time_s)` capped at
## `lift_max_frac * |v|`. The path is sampled from the start state; there is no separate t = 0 sample.
static func probe(terrain: Terrain, p: Vector3, v: Vector3, probe_params: ProbeParams, h_req: float,
		out: ProbeResult) -> void:
	var n0: Vector3 = p.normalized()
	var vt: Vector3 = v - n0 * v.dot(n0)
	var s: float = vt.length()
	var tdir: Vector3 = vt / s if s > 0.0 else Vector3.ZERO
	var r0: float = p.length()
	var vr: float = v.dot(n0)
	var g: float = probe_params.gravity
	var ts: PackedFloat32Array = probe_params.probe_times_s
	out.tti_s = INF
	out.min_clearance_m = INF
	out.worst_t_s = 0.0
	out.worst_dir = n0
	var prev_t: float = 0.0
	var prev_c: float = 0.0
	var first_c: float = 0.0
	var pending_first: bool = false
	for k: int in ts.size():
		var t: float = ts[k]
		var phi: float = s * t / r0
		var dir: Vector3 = n0 * cos(phi) + tdir * sin(phi)
		var c: float = r0 + vr * t - 0.5 * g * t * t - Sphere.PLANET_RADIUS - terrain.height_at(dir)
		if c < out.min_clearance_m:
			out.min_clearance_m = c
			out.worst_t_s = t
			out.worst_dir = dir
		if is_inf(out.tti_s) and not pending_first:
			if c <= 0.0:
				if k == 0:
					pending_first = true
					first_c = c
				else:
					out.tti_s = prev_t + (t - prev_t) * prev_c / (prev_c - c)
		elif pending_first and k == 1:
			out.tti_s = _first_hit(ts[0], first_c, t, c)
			pending_first = false
		prev_t = t
		prev_c = c
	if pending_first:
		out.tti_s = ts[0]
	var lift: float = maxf(0.0, h_req - out.min_clearance_m) / maxf(out.worst_t_s, probe_params.lift_min_time_s)
	out.lift_mps = minf(lift, probe_params.lift_max_frac * v.length())


## Clearance of the predicted position at time `t` (one height sample): the 1.0 s re-check at act time.
static func sample_clearance(terrain: Terrain, p: Vector3, v: Vector3, gravity: float, t: float) -> float:
	var n0: Vector3 = p.normalized()
	var vt: Vector3 = v - n0 * v.dot(n0)
	var s: float = vt.length()
	var tdir: Vector3 = vt / s if s > 0.0 else Vector3.ZERO
	var r0: float = p.length()
	var phi: float = s * t / r0
	var dir: Vector3 = n0 * cos(phi) + tdir * sin(phi)
	return r0 + v.dot(n0) * t - 0.5 * gravity * t * t - Sphere.PLANET_RADIUS - terrain.height_at(dir)


## R0 B.12 A-69 lift: the worst sample's clearance without the gravity drop, c' = c_w + 0.5 g t_w^2 (the controller
## holds the commanded path against gravity), `max(0, h_req - c') / max(t_w, lift_min_time_s)` capped at
## `lift_max_frac * speed`. Read from a filled `ProbeResult`: no extra sample (the worst sample is the ballistic one).
static func drop_free_lift(r: ProbeResult, probe_params: ProbeParams, h_req: float, speed: float) -> float:
	var t: float = r.worst_t_s
	var c: float = r.min_clearance_m + 0.5 * probe_params.gravity * t * t
	var lift: float = maxf(0.0, h_req - c) / maxf(t, probe_params.lift_min_time_s)
	return minf(lift, probe_params.lift_max_frac * speed)


## Crossing time when sample 0 (t0, c0 <= 0) is already under the surface: extrapolate back through sample 1,
## clamped to [0, t0]; a path not rising towards the surface gives t0.
static func _first_hit(t0: float, c0: float, t1: float, c1: float) -> float:
	if c1 >= c0:
		return t0
	return clampf(t0 - (t1 - t0) * c0 / (c1 - c0), 0.0, t0)
