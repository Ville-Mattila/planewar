class_name PlanetRenderer extends Node3D
## The planet renderer (03 s7): six face quadtrees, the per-frame build scheduler, the texel-index mesher
## (variant A) and the chunk pool. Reads only `Terrain` and the camera (`PlanetView`); writes nothing to the
## sim (D1). The only Nodes it owns are the pooled MeshInstance3D children (no Node per quadtree node).
## Call `setup` once (behind the loading screen: builds depth 0-2 synchronously), then either set `camera`
## and let `_process` drive it or call `update_view` yourself.

## Emitted after every chunk build (03 s7.4 "build ms logged per chunk"); the ring below keeps the numbers.
signal chunk_built(face: int, depth: int, ix: int, iy: int, ms: float)

const SHADER: Shader = preload("res://src/presentation/planet/shaders/planet_chunk.gdshader")
const PREBUILD_DEPTH: int = 2                ## 03 s7.4: depth 0-2 (126 chunks) at load
const BUILD_LOG_SIZE: int = 512              ## ring of per-chunk build times
const NEAR_M: float = 400.0                  ## hole statistic radius (R0 C1-06 boost-path criterion)
const POOL_RESERVE: int = 8                  ## below this many free slots pending merges are released early

var terrain: Terrain
var config: PlanetTierConfig
var scheduler: ChunkScheduler
var quadtree: PlanetQuadtree
var mesher: ChunkMesher
var pool: ChunkPool
var material: Material
var camera: Camera3D = null                  ## when set, _process updates from it every frame
var prebuilt: int = 0
var plan_ms: float = 0.0                     ## last update: selection + queue
var build_log_ms: PackedFloat32Array = PackedFloat32Array()   ## ring, BUILD_LOG_SIZE entries
var build_log_depth: PackedInt32Array = PackedInt32Array()
var build_log_count: int = 0
var pool_exhausted: int = 0                  ## builds refused for lack of a slot
var worst_near_wait_ms: int = 0              ## longest queue wait of a chunk built within NEAR_M of the camera
var _now_ms: int = 0
var _view: PlanetView = null
var _shown: Array[ChunkNode] = []


## Creates the pool, mesher, scheduler and quadtree for `p_terrain` at tier `p_config` and builds depth
## 0..PREBUILD_DEPTH synchronously. `p_material` defaults to the interim chunk shader.
func setup(p_terrain: Terrain, p_config: PlanetTierConfig, p_material: Material = null) -> void:
	terrain = p_terrain
	config = p_config
	if p_material == null:
		var sm: ShaderMaterial = ShaderMaterial.new()
		sm.shader = SHADER
		sm.render_priority = -1              # 03 s7.6: planet -1, structures 0
		material = sm
	else:
		material = p_material
	var _r: int = build_log_ms.resize(BUILD_LOG_SIZE)
	_r = build_log_depth.resize(BUILD_LOG_SIZE)
	mesher = ChunkMesher.new(terrain, config.max_depth)
	pool = ChunkPool.new(self, config.pool_size, material)
	scheduler = ChunkScheduler.new()
	scheduler.configure(config)
	quadtree = PlanetQuadtree.new(config, scheduler, _release)
	prebuilt = quadtree.prebuild(mini(PREBUILD_DEPTH, config.max_depth), _build)


func _process(_delta: float) -> void:
	if camera != null and quadtree != null:
		update_view(PlanetView.from_camera(camera), Time.get_ticks_msec())


## One frame: select the cut, refill the queue, run the budgeted builds, update visibility.
func update_view(view: PlanetView, now_ms: int) -> void:
	_view = view
	_now_ms = now_ms
	while pool.free_count() < POOL_RESERVE and quadtree.reclaim_one():
		pass
	quadtree.slot_budget = pool.free_count()
	var t0: int = Time.get_ticks_usec()
	quadtree.update(view, now_ms)
	plan_ms = float(Time.get_ticks_usec() - t0) * 0.001
	var _n: int = scheduler.run(_build)
	for n: ChunkNode in quadtree.cut:
		pool.set_visible(n.slot, true)
	for n: ChunkNode in _shown:
		if n.shown_frame != quadtree.frame and n.is_built():
			pool.set_visible(n.slot, false)
	_shown.assign(quadtree.cut)


func visible_chunks() -> int:
	return quadtree.cut.size()


## Percentile (0..1) of the logged per-chunk build times in ms; 0 when nothing was built.
func build_ms_percentile(p: float) -> float:
	var count: int = mini(build_log_count, BUILD_LOG_SIZE)
	if count == 0:
		return 0.0
	var tmp: PackedFloat32Array = build_log_ms.slice(0, count)
	tmp.sort()
	return tmp[clampi(int(p * float(count - 1) + 0.5), 0, count - 1)]


func _build(node: ChunkNode) -> float:
	var slot: int = pool.acquire()
	if slot < 0 and quadtree != null and quadtree.reclaim_one():
		slot = pool.acquire()
	if slot < 0:
		pool_exhausted += 1
		return -1.0
	var t0: int = Time.get_ticks_usec()
	mesher.build_into(node, pool.meshes[slot], material)
	node.slot = slot
	node.build_ms = float(Time.get_ticks_usec() - t0) * 0.001
	if _view != null and node.wanted_since_ms >= 0 and PlanetQuadtree.bounds_distance(_view.position, node) < NEAR_M:
		worst_near_wait_ms = maxi(worst_near_wait_ms, _now_ms - node.wanted_since_ms)
	var k: int = build_log_count % BUILD_LOG_SIZE
	build_log_ms[k] = node.build_ms
	build_log_depth[k] = node.depth
	build_log_count += 1
	chunk_built.emit(node.face, node.depth, node.ix, node.iy, node.build_ms)
	return node.build_ms


func _release(node: ChunkNode) -> void:
	pool.release(node.slot)
