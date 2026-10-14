class_name NavTestKit extends RefCounted
## S-NAV-1 (TA-20) helpers shared by the spike harness and the pathing tests: an independent path validator
## (Sphere.neighbours8, not PathGrid), an independent Dijkstra over the path grid (brute force) and a deterministic
## rough weight map. Not sim code: runs in tools and tests only.

const N: int = Sphere.GRID_PATH


## "" when `cells` is a valid route from `s` to `g` for `mask` on `p` (8-adjacent steps by Sphere.neighbours8,
## passable cells except the start, no diagonal cutting a blocked corner), else the first failure.
static func validate(p: Pathing, cells: PackedInt32Array, s: int, g: int, mask: int) -> String:
	if cells.is_empty():
		return "empty"
	if cells[0] != s or cells[cells.size() - 1] != g:
		return "endpoints %d..%d, want %d..%d" % [cells[0], cells[cells.size() - 1], s, g]
	var lq: int = PathGrid.limit_q_of(mask)
	for k: int in range(1, cells.size()):
		var a: int = cells[k - 1]
		var b: int = cells[k]
		if not p.grid.passable(b, lq):
			return "cell %d impassable at step %d" % [b, k]
		var nb: PackedInt32Array = Sphere.neighbours8(a, N)
		var at: int = nb.find(b)
		if at < 0:
			return "cells %d -> %d not adjacent at step %d" % [a, b, k]
		if at >= 4:
			var q: int = at - 4
			if not p.grid.passable(nb[q & 1], lq) or not p.grid.passable(nb[2 + (q >> 1)], lq):
				return "diagonal %d -> %d cuts a blocked corner" % [a, b]
	return ""


## Route cost with the Pathing cost model computed independently (Sphere centres, angle_to in doubles).
static func cost_of(p: Pathing, cells: PackedInt32Array) -> float:
	var c: float = 0.0
	for k: int in range(1, cells.size()):
		var a: Vector3 = Sphere.cell_center_dir(cells[k - 1], N)
		var b: Vector3 = Sphere.cell_center_dir(cells[k], N)
		c += Sphere.PLANET_RADIUS * a.angle_to(b) * float(p.weight(cells[k - 1]) + p.weight(cells[k])) * 0.5
	return c


## Route length in metres along the cell centres.
static func length_of(cells: PackedInt32Array) -> float:
	var m: float = 0.0
	for k: int in range(1, cells.size()):
		m += Sphere.great_circle(Sphere.cell_center_dir(cells[k - 1], N), Sphere.cell_center_dir(cells[k], N))
	return m


## Brute-force Dijkstra (O(V^2) selection over the cells in `region`, no heap, no heuristic) from s to g; returns
## the optimal cost or -1 when unreachable. `region` lists every cell the search may enter (small grids).
static func dijkstra(p: Pathing, region: PackedInt32Array, s: int, g: int, mask: int) -> float:
	var lq: int = PathGrid.limit_q_of(mask)
	var dist: Dictionary[int, float] = {}
	var done: Dictionary[int, bool] = {}
	var inside: Dictionary[int, bool] = {}
	for c: int in region:
		inside[c] = true
	dist[s] = 0.0
	while true:
		var best: int = -1
		var bd: float = INF
		for c: int in dist:
			if not done.has(c) and dist[c] < bd:
				bd = dist[c]
				best = c
		if best < 0:
			return -1.0
		if best == g:
			return bd
		done[best] = true
		var nb: PackedInt32Array = Sphere.neighbours8(best, N)
		for at: int in nb.size():
			var n: int = nb[at]
			if not inside.has(n) or not p.grid.passable(n, lq):
				continue
			if at >= 4:
				var q: int = at - 4
				if not p.grid.passable(nb[q & 1], lq) or not p.grid.passable(nb[2 + (q >> 1)], lq):
					continue
			var a: Vector3 = Sphere.cell_center_dir(best, N)
			var b: Vector3 = Sphere.cell_center_dir(n, N)
			var nd: float = bd + Sphere.PLANET_RADIUS * a.angle_to(b) * float(p.weight(best) + p.weight(n)) * 0.5
			if not dist.has(n) or nd < dist[n]:
				dist[n] = nd
	return -1.0


## Reachability flood (BFS over Sphere.neighbours8 with the same rules) from s; true when g is reached.
static func reachable(p: Pathing, s: int, g: int, mask: int) -> bool:
	var lq: int = PathGrid.limit_q_of(mask)
	var seen: PackedByteArray = PackedByteArray()
	var _r: int = seen.resize(PathGrid.CELLS)
	var q: PackedInt32Array = PackedInt32Array([s])
	seen[s] = 1
	var head: int = 0
	while head < q.size():
		var c: int = q[head]
		head += 1
		if c == g:
			return true
		var nb: PackedInt32Array = Sphere.neighbours8(c, N)
		for at: int in nb.size():
			var n: int = nb[at]
			if seen[n] != 0 or not p.grid.passable(n, lq):
				continue
			if at >= 4:
				var k: int = at - 4
				if not p.grid.passable(nb[k & 1], lq) or not p.grid.passable(nb[2 + (k >> 1)], lq):
					continue
			seen[n] = 1
			var _a: bool = q.push_back(n)
	return false


## Every cell within `half` cells (Chebyshev, through Sphere.neighbours8 steps) of `centre`.
static func region_around(centre: int, half: int) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array([centre])
	var depth: Dictionary[int, int] = {centre: 0}
	var head: int = 0
	while head < out.size():
		var c: int = out[head]
		head += 1
		if depth[c] >= half:
			continue
		for n: int in Sphere.neighbours8(c, N):
			if not depth.has(n):
				depth[n] = depth[c] + 1
				var _a: bool = out.push_back(n)
	return out


## Deterministic rough weights: base noise 1..5, `craters` impassable rims (radius 3..14 cells) with 1-2 gaps, and
## `walls` straight impassable walls 10..60 cells long. Weights only; slopes come from the map's terrain.
static func rough_weights(seed_v: int, craters: int, walls: int) -> PackedByteArray:
	var rng: Rng = Rng.new(seed_v)
	var w: PackedByteArray = PackedByteArray()
	var _r: int = w.resize(PathGrid.CELLS)
	for c: int in PathGrid.CELLS:
		var u: int = rng.range_i(0, 9)
		w[c] = 1 if u < 6 else u - 4
	for k: int in craters:
		var centre: Vector3 = _rand_dir(rng)
		var rad: float = rng.range_f(3.0, 14.0) * Sphere.PLANET_RADIUS * PI * 0.5 / float(N)
		var gap: float = rng.range_f(-PI, PI)
		for c: int in Sphere.cells_in_radius(centre, rad + 40.0, N):
			var d: Vector3 = Sphere.cell_center_dir(c, N)
			var gc: float = Sphere.great_circle(centre, d)
			if absf(gc - rad) < 30.0 and absf(angle_difference(Sphere.bearing(centre, d), gap)) > 0.5:
				w[c] = PathGrid.W_BLOCKED
	for k: int in walls:
		var a: Vector3 = _rand_dir(rng)
		var b: Vector3 = Sphere.slerp_dir(a, _rand_dir(rng), rng.range_f(0.002, 0.01))
		for t: int in 200:
			w[Sphere.cell_of(Sphere.slerp_dir(a, b, float(t) / 199.0), N)] = PathGrid.W_BLOCKED
	return w


static func _rand_dir(rng: Rng) -> Vector3:
	while true:
		var v: Vector3 = Vector3(rng.range_f(-1.0, 1.0), rng.range_f(-1.0, 1.0), rng.range_f(-1.0, 1.0))
		if v.length_squared() > 0.01 and v.length_squared() <= 1.0:
			return v.normalized()
	return Vector3.UP
