class_name PlanetQuadtree extends RefCounted
## Six face quadtrees and the per-frame cut selection (03 s7.2, s7.4, s7.5). Node-free so tests run it
## headless with a fake builder. Each frame `update` refines the trees best-first: a built node inside its
## split radius (and inside the frustum, not beyond the horizon, below MAX_DEPTH) is split when all 4
## children are built, else it keeps rendering and its missing children are queued (never a hole). Split
## candidates are taken by priority while the visible-chunk cap allows (+3 per split), so the farthest
## nodes stay merged first. Merged subtrees go back to the pool after the merge grace.

var config: PlanetTierConfig
var scheduler: ChunkScheduler
var roots: Array[ChunkNode] = []
var cut: Array[ChunkNode] = []               ## rendered leaves of the last update (built, above the horizon)
var frame: int = 0
var splits_refused_by_cap: int = 0           ## last update
var splits_refused_by_pool: int = 0          ## last update
var visited: int = 0                         ## nodes classified by the last update
var slot_budget: int = 1 << 30               ## free pool slots this frame; queued children reserve them
var _release: Callable                       ## func(node: ChunkNode) -> void: return node.slot to the pool
var _level: Array[ChunkNode] = []
var _next: Array[ChunkNode] = []
var _heap: Array[ChunkNode] = []
var _view: PlanetView = null
var _cam_dir: Vector3 = Vector3.ZERO
var _horizon: float = PI
var _now_ms: int = 0
var _merging: Array[ChunkNode] = []


func _init(p_config: PlanetTierConfig, p_scheduler: ChunkScheduler, release: Callable) -> void:
	config = p_config
	scheduler = p_scheduler
	_release = release
	for f: int in Terrain.FACE_COUNT:
		roots.append(ChunkNode.make(f, 0, 0, 0, Sphere.RELIEF_MIN, Sphere.RELIEF_MAX))


# region split metric (03 s7.2)
## Distance from `cam` to the surface of the node's bounding sphere, >= 0.
static func bounds_distance(cam: Vector3, node: ChunkNode) -> float:
	return maxf(0.0, cam.distance_to(node.center) - node.radius)


## Split when d < K * edge and below MAX_DEPTH.
static func wants_split(d: float, edge: float, k: float, depth: int, max_depth: int) -> bool:
	return depth < max_depth and d < k * edge


## A split node merges only when d > (K + hysteresis) * edge.
static func wants_merge(d: float, edge: float, k: float, hysteresis: float) -> bool:
	return d > (k + hysteresis) * edge


## (K * edge - d) / edge + 2 inside the frustum + 1 ahead of the camera (03 s7.4).
static func priority_of(d: float, edge: float, k: float, in_frustum: bool, ahead: bool) -> float:
	return (k * edge - d) / edge + (2.0 if in_frustum else 0.0) + (1.0 if ahead else 0.0)
# endregion


## Builds every node down to `depth` synchronously with `build` (`func(node) -> float`), parents first so
## children inherit tight height ranges (load screen, 03 s7.4: depth 0-2 = 126 chunks). Returns the count.
func prebuild(depth: int, build: Callable) -> int:
	var count: int = 0
	_level.assign(roots)
	for d: int in depth + 1:
		_next.clear()
		for n: ChunkNode in _level:
			if not n.is_built():
				var ms: float = build.call(n)
				count += 1 if ms >= 0.0 else 0
			if d < depth and n.is_built():
				_next.append_array(n.ensure_children(ChunkMesher.skirt_depth(n.depth)))
		_level.assign(_next)
	return count


## Selects this frame's cut and refills the scheduler queue. `now_ms` drives the merge grace. Best-first:
## split candidates of every depth go through one max-heap on priority, so when the visible-chunk cap
## binds it is the farthest (lowest priority) splits that are refused, never the ones under the camera.
func update(view: PlanetView, now_ms: int) -> void:
	frame += 1
	scheduler.begin_plan()
	cut.clear()
	splits_refused_by_cap = 0
	splits_refused_by_pool = 0
	_view = view
	_now_ms = now_ms
	_cam_dir = view.position.normalized()
	_horizon = HorizonCull.horizon_angle(view.position)
	_heap.clear()
	visited = 0
	var count: int = 0
	for r: ChunkNode in roots:
		count += 0 if _culled(r) else 1
		_classify(r)
	while not _heap.is_empty():
		count = _try_split(_heap_pop(), count)
	_expire_merges(now_ms)


func _culled(n: ChunkNode) -> bool:
	return HorizonCull.is_culled_angle(_cam_dir, _horizon, n.center, n.radius, n.h_max)


func _classify(n: ChunkNode) -> void:
	visited += 1
	if _culled(n):
		_leaf(n, false, _now_ms)
		return
	var d: float = bounds_distance(_view.position, n)
	var inside: bool = _view.sphere_in_frustum(n.center, n.radius)
	n.priority = priority_of(d, n.edge_m, config.split_k, inside, _view.is_ahead(n.center))
	var want: bool
	if n.split:
		want = not wants_merge(d, n.edge_m, config.split_k, config.merge_hysteresis)
	else:
		want = inside and wants_split(d, n.edge_m, config.split_k, n.depth, config.max_depth)
	if want and n.depth < config.max_depth and n.is_built():
		_heap_push(n)
	else:
		_leaf(n, true, _now_ms)


func _try_split(n: ChunkNode, count: int) -> int:
	var kids: Array[ChunkNode] = n.ensure_children(ChunkMesher.skirt_depth(n.depth))
	var visible: int = 0
	for c: ChunkNode in kids:
		visible += 0 if _culled(c) else 1
	if count + visible - 1 > config.visible_chunks_cap:
		splits_refused_by_cap += 1
		_leaf(n, true, _now_ms)
		return count
	if n.children_built():
		n.split = true
		n.merge_since_ms = -1
		for c: ChunkNode in kids:
			_classify(c)
		return count + visible - 1
	var missing: int = 0
	for c: ChunkNode in kids:
		missing += 0 if c.is_built() else 1
	if missing > slot_budget:
		splits_refused_by_pool += 1
		_leaf(n, true, _now_ms)
		return count
	slot_budget -= missing
	for c: ChunkNode in kids:
		if not c.is_built():
			c.priority = n.priority          # siblings build back to back: no partial sets hogging slots
			scheduler.push(c, frame, _now_ms)
	n.split = false
	n.merge_since_ms = -1                    # children are wanted: never released while they build
	_show(n)
	return count


# region max-heap on ChunkNode.priority
func _heap_push(n: ChunkNode) -> void:
	_heap.append(n)
	var i: int = _heap.size() - 1
	while i > 0:
		var p: int = (i - 1) >> 1
		if _heap[p].priority >= n.priority:
			break
		_heap[i] = _heap[p]
		i = p
	_heap[i] = n


func _heap_pop() -> ChunkNode:
	var top: ChunkNode = _heap[0]
	var last: ChunkNode = _heap.pop_back()
	var size: int = _heap.size()
	if size == 0:
		return top
	var i: int = 0
	while true:
		var c: int = 2 * i + 1
		if c >= size:
			break
		if c + 1 < size and _heap[c + 1].priority > _heap[c].priority:
			c += 1
		if _heap[c].priority <= last.priority:
			break
		_heap[i] = _heap[c]
		i = c
	_heap[i] = last
	return top
# endregion


func _leaf(n: ChunkNode, shown: bool, now_ms: int) -> void:
	n.split = false
	if not n.children.is_empty() and n.merge_since_ms < 0:
		n.merge_since_ms = now_ms
		_merging.append(n)
	if shown:
		_show(n)


func _show(n: ChunkNode) -> void:
	if n.is_built():
		n.shown_frame = frame
		cut.append(n)


func _expire_merges(now_ms: int) -> void:
	var grace_ms: int = int(config.merge_grace_s * 1000.0)
	var k: int = 0
	while k < _merging.size():
		var n: ChunkNode = _merging[k]
		if n.split or n.merge_since_ms < 0 or n.children.is_empty():
			_merging.remove_at(k)
		elif now_ms - n.merge_since_ms >= grace_ms:
			release_children(n)
			_merging.remove_at(k)
		else:
			k += 1


## Releases the oldest pending merge early (pool pressure). Returns false when nothing was pending.
func reclaim_one() -> bool:
	while not _merging.is_empty():
		var n: ChunkNode = _merging.pop_front()
		if not n.split and n.merge_since_ms >= 0 and not n.children.is_empty():
			release_children(n)
			return true
	return false


## Returns every descendant's pool slot and drops the children.
func release_children(n: ChunkNode) -> void:
	for c: ChunkNode in n.children:
		release_children(c)
		if c.is_built():
			_release.call(c)
			c.slot = -1
	n.children.clear()
	n.merge_since_ms = -1
	n.split = false


## The leaf of the last cut containing direction `dir` (null when the cut does not cover it: beyond the
## horizon). Walks the face quadtree by (u, v).
func leaf_at(dir: Vector3) -> ChunkNode:
	var fuv: Vector3 = Sphere.dir_to_face_uv(dir)
	var n: ChunkNode = roots[int(fuv.x)]
	while n.split:
		var s: float = float(1 << (n.depth + 1))
		var cx: int = clampi(int(fuv.y * s), n.ix * 2, n.ix * 2 + 1) - n.ix * 2
		var cy: int = clampi(int(fuv.z * s), n.iy * 2, n.iy * 2 + 1) - n.iy * 2
		n = n.children[cy * 2 + cx]
	return n if n.shown_frame == frame else null


## Every node currently holding a pool slot (tests, stats).
func built_nodes() -> Array[ChunkNode]:
	var out: Array[ChunkNode] = []
	for r: ChunkNode in roots:
		_collect_built(r, out)
	return out


func _collect_built(n: ChunkNode, out: Array[ChunkNode]) -> void:
	if n.is_built():
		out.append(n)
	for c: ChunkNode in n.children:
		_collect_built(c, out)

