# presentation/planet - MODULE.md

Contract for `godot/src/presentation/planet/**` (03 s7.1-7.5, R0 C1-06; TA-23), a sub-module of `presentation`
(R0 B.9 A-21). A change to "Public API" or "Invariants" is a contract change: update the contract tests first,
in the same PR (ADR-11); `tools/gen_module_api.py --check` must pass; <= 300 lines.

| Field | Value |
|---|---|
| Responsibility | Draws the moon: six face quadtrees (depth 0..MAX_DEPTH), the split metric with hysteresis, best-first cut selection under the visible-chunk cap, the per-frame build scheduler with the starvation rule, the texel-index CPU mesher (variant A) with the per-depth direction table, shared index pattern and skirts, horizon and frustum culling, and the fixed MeshInstance3D/ArrayMesh pool. Does not own gameplay height (`Terrain.height_at` is the only gameplay sampler), the camera rig and the near-plane formula (`camera`: `CamMath.near_plane`) or variant B (TA-25). Since TA-24 it owns the terrain material, the sky hookup and the flatten sites API. |
| Lane owner tier | Opus |
| May depend on | `core`, `content`; named sim type `Terrain` (read-only) (`tools/deps.json`) |
| Must never touch | the sim (writes nothing, reads only `Terrain`), `net`, `camera`, `ui`; no Node per quadtree node (only the pooled MeshInstance3D); no autoloads; no threads; no hard-coded 6,000 or 8,192 (D6) |
| Autoloads used | none |
| Status | implemented (TA-23); `moon_terrain` material, `sky_moon` hookup, near-plane hook and flatten sites (TA-24); Z1-Z5 and Z8 harness `test/golden/world/z_scene.tscn` |

## Public API

Anything not listed is private (prefix `_`). Budgets, caps and K come from `quality_tiers.json` via
`PlanetTierConfig`; nothing tier-dependent is a constant.

```gdscript
class_name PlanetTierConfig extends RefCounted   # planet knobs of one quality tier (03 s13)
const DEFAULT_STARVATION_FRAMES: int; const DEFAULT_MERGE_HYSTERESIS: float; const DEFAULT_MERGE_GRACE_S: float; const DEFAULT_POOL_SIZE: int
var tier_id: StringName; var split_k: float; var max_depth: int; var builds_per_frame: int; var build_ms_cap: float
var visible_chunks_cap: int; var detail_range_m: float; var starvation_frames: int; var merge_hysteresis: float; var merge_grace_s: float; var pool_size: int
static func from_dict(d: Dictionary) -> PlanetTierConfig          # one quality_tiers.json entry; optional chunk_* keys
static func from_def(def: QualityTierDef) -> PlanetTierConfig

class_name ChunkNode extends RefCounted          # quadtree node record (03 s7.1)
const GRID: int
var face: int; var depth: int; var ix: int; var iy: int; var children: Array[ChunkNode]; var center: Vector3; var radius: float
var edge_m: float; var h_min: float; var h_max: float; var slot: int; var split: bool; var merge_since_ms: int; var priority: float
var queued_frame: int; var wanted_since_ms: int; var shown_frame: int; var build_ms: float
static func make(p_face: int, p_depth: int, p_ix: int, p_iy: int, h_lo: float, h_hi: float) -> ChunkNode
func is_built() -> bool
func gx(a: int) -> int;  func gy(b: int) -> int                    # global vertex column / row at this depth
func set_height_range(h_lo: float, h_hi: float) -> void            # bounding sphere from 4 corners + centre
func ensure_children(margin_m: float) -> Array[ChunkNode]
func children_built() -> bool

class_name PlanetView extends RefCounted         # camera input of one frame (03 s7.5)
var position: Vector3; var forward: Vector3; var frustum: Array[Plane]; var near_m: float   # near_m = Camera3D.near (ViewState.near), 0 = unknown
static func make(p_position: Vector3, p_forward: Vector3, p_frustum: Array[Plane]) -> PlanetView
static func from_camera(cam: Camera3D) -> PlanetView
static func perspective_planes(xf: Transform3D, fov_y_deg: float, aspect: float, near: float, far: float) -> Array[Plane]
func sphere_in_frustum(center: Vector3, radius: float) -> bool
func is_ahead(center: Vector3) -> bool

class_name HorizonCull extends RefCounted        # all static (03 s7.5)
static func r_low() -> float
static func theta_up_for(h_max: float) -> float
static func theta_up() -> float
static func horizon_angle(cam: Vector3) -> float
static func is_culled_angle(cam_dir: Vector3, horizon: float, center: Vector3, radius: float, h_max: float) -> bool
static func is_culled(cam: Vector3, center: Vector3, radius: float) -> bool

class_name ChunkScheduler extends RefCounted     # per-frame build budget + starvation rule (03 s7.4)
const EST_BLEND: float
var budget_builds_per_frame: int; var budget_ms_per_frame: float; var starvation_frames: int; var frames_since_build: int
var queue: Array[ChunkNode]; var est_build_ms: float; var last_builds: int; var last_ms: float; var last_forced: bool; var total_builds: int
func configure(cfg: PlanetTierConfig) -> void
func begin_plan() -> void
func push(node: ChunkNode, frame: int, now_ms: int) -> void
func run(build: Callable) -> int                                   # build: func(node) -> float ms, < 0 = no slot

class_name ChunkPool extends RefCounted          # fixed MeshInstance3D + ArrayMesh pairs (03 s7.3)
var parent: Node3D; var instances: Array[MeshInstance3D]; var meshes: Array[ArrayMesh]; var allocated: int; var acquires: int
func capacity() -> int;  func free_count() -> int;  func in_use() -> int
func acquire() -> int                                              # -1 when exhausted
func release(slot: int) -> void
func set_visible(slot: int, on: bool) -> void

class_name ChunkMesher extends RefCounted        # texel-index mesher, variant A (03 s7.3, R0 C1-06)
const GRID: int; const VERTS: int; const RING: int; const GRID_VERTS: int; const SKIRT_VERTS: int; const VERTEX_COUNT: int
const INDEX_COUNT: int; const SKIRT_FACTOR: float; const MAX_SLOPE_TAN: float; const ARRAY_FLAGS: int
var terrain: Terrain; var max_depth: int; var indices: PackedInt32Array; var last_heights: PackedFloat64Array; var flatten: FlattenSites
var last_h_min: float; var last_h_max: float
static func segments(depth: int) -> int
static func skirt_depth(depth: int) -> float
static func edge_vertex(e: int, k: int) -> int
func vertex_dir(face: int, depth: int, gx: int, gy: int) -> Vector3
func vertex_height(face: int, depth: int, gx: int, gy: int) -> float
func texel_index(g: int, depth: int) -> int
func texel_frac(g: int, segs: int, depth: int) -> float
func build_arrays(node: ChunkNode) -> Array
func build_into(node: ChunkNode, mesh: ArrayMesh, material: Material) -> void

class_name PlanetQuadtree extends RefCounted     # six face trees, cut selection (03 s7.2, s7.4)
var config: PlanetTierConfig; var scheduler: ChunkScheduler; var roots: Array[ChunkNode]; var cut: Array[ChunkNode]; var frame: int
var splits_refused_by_cap: int; var splits_refused_by_pool: int; var visited: int; var slot_budget: int
static func bounds_distance(cam: Vector3, node: ChunkNode) -> float
static func wants_split(d: float, edge: float, k: float, depth: int, max_depth: int) -> bool
static func wants_merge(d: float, edge: float, k: float, hysteresis: float) -> bool
static func priority_of(d: float, edge: float, k: float, in_frustum: bool, ahead: bool) -> float
func prebuild(depth: int, build: Callable) -> int
func update(view: PlanetView, now_ms: int) -> void
func reclaim_one() -> bool
func release_children(n: ChunkNode) -> void
func leaf_at(dir: Vector3) -> ChunkNode
func built_nodes() -> Array[ChunkNode]

class_name FlattenSites extends RefCounted       # cosmetic footprint flattening (03 s7.6, R0 C2-31)
const OUTER_FACTOR: float; const MAX_SHADER_SITES: int; const CHUNK_MARGIN_M: float
var dirs: PackedVector3Array; var heights: PackedFloat64Array; var radii: PackedFloat32Array
func size() -> int;  func is_empty() -> bool
func set_sites(terrain: Terrain, positions: PackedVector3Array, p_radii: PackedFloat32Array) -> void
func affects(node: ChunkNode) -> bool
func select_for(node: ChunkNode) -> int                            # sites near the chunk about to be built
func apply(d: Vector3, h: float) -> float                          # pure function of the unit direction (seamless)
func shader_sites(cam: Vector3) -> PackedVector4Array             # nearest MAX_SHADER_SITES as (x, y, z, radius)

class_name MoonTerrain extends RefCounted        # the planet material (07 s3.1); all static
const SHADER_PATH: String; const RAMP_PATH: String; const MAX_SITES: int; const DEFAULT_DETAIL_RANGE_M: float; const MEASURE_RAMP_V: float
static func base_material() -> ShaderMaterial                      # ramp + 1 x 1 mare biome array (no map)
static func make_material(terrain: Terrain, cfg: PlanetTierConfig) -> ShaderMaterial
static func measure_material() -> ShaderMaterial                   # mare mid, no detail: measurement plates
static func biome_images(terrain: Terrain) -> Array[Image]
static func biome_array(terrain: Terrain) -> Texture2DArray
static func flat_biome_array(id: int) -> Texture2DArray
static func set_sites(m: ShaderMaterial, sites: PackedVector4Array) -> void

class_name MoonDetail extends RefCounted         # CPU mirror of moon_terrain.gdshader's detail constants; all static
const CELLS_M: PackedFloat32Array; const AMPLITUDES_M: PackedFloat32Array; const TOTAL_M: float; const FOOTPRINT_KEEP: float
const FOOTPRINT_OUTER: float; const FOOTPRINT_MAX_M: float
static func profile(t: float) -> float
static func footprint_scale(dist: float, radius: float) -> float
static func max_displacement(dist: float, radius: float) -> float
static func range_fade(dist: float, range_m: float) -> float

class_name SkyMoon extends RefCounted            # sky_moon.gdshader hookup (07 s1.5); all static
const SHADER_PATH: String; const EARTH_DIAMETER_DEG: float; const SUN_DIAMETER_DEG: float
static func earth_dir() -> Vector3                                 # -Z
static func make_sky() -> Sky
static func apply(env: Environment) -> void                        # BG_SKY; ambient stays 0

class_name MoonLight extends RefCounted          # shared light model, CPU side (07 s1.5; ART-01); all static
const SUN_DIR_PARAM: StringName; const DEFAULT_SUN_DIR: Vector3; const SUN_COLOR: Color; const SUN_ENERGY: float; const SPACE_COLOR: Color
const MOON_SHADER_PATH: String; const UNIT_SHADER_PATH: String; const UNIT_INSTANCED_SHADER_PATH: String; const ATLAS_PATH: String
const INCLUDE_PATH: String; const WRAP: float; const AMB_LOW: Vector3; const AMB_HIGH: Vector3; const EARTH: Vector3; const EARTH_GAIN: float
const EARTH_BASE: float; const NIGHT_LO: float; const NIGHT_HI: float; const RIM: Vector3; const RIM_NEAR: float; const RIM_FAR: float
const NIGHT_TARGET: Vector3; const NIGHT_TOLERANCE: float
static func ensure_globals() -> void                               # registers global uniform sun_dir once
static func set_sun_dir(dir: Vector3, sun: DirectionalLight3D = null) -> void
static func sun_basis(dir: Vector3) -> Basis
static func make_sun() -> DirectionalLight3D
static func make_environment() -> Environment
static func moon_material() -> ShaderMaterial                       # MoonTerrain.base_material (no map)
static func unit_material(instanced: bool = false) -> ShaderMaterial
static func day_factor(up: Vector3, sun: Vector3) -> float
static func earth_k(up: Vector3, sun: Vector3) -> float
static func shade_linear(albedo: Vector3, n: Vector3, up: Vector3, sun: Vector3) -> Vector3   # CPU mirror of the include
static func night_pole_ratio() -> Vector3

class_name PlanetRenderer extends Node3D         # the Node: owns pool, mesher, scheduler, quadtree (03 s7)
signal chunk_built(face: int, depth: int, ix: int, iy: int, ms: float)
const PREBUILD_DEPTH: int; const SITE_REFRESH_FRAMES: int; const BUILD_LOG_SIZE: int; const NEAR_M: float; const POOL_RESERVE: int
var terrain: Terrain; var config: PlanetTierConfig; var scheduler: ChunkScheduler; var quadtree: PlanetQuadtree; var mesher: ChunkMesher
var pool: ChunkPool; var material: Material; var camera: Camera3D; var debug_depth_tint: bool; var prebuilt: int; var plan_ms: float
var build_log_ms: PackedFloat32Array; var build_log_depth: PackedInt32Array; var build_log_count: int; var pool_exhausted: int
var worst_near_wait_ms: int; var flatten_rebuilds: int
func setup(p_terrain: Terrain, p_config: PlanetTierConfig, p_material: Material = null) -> void   # null = MoonTerrain.make_material
func set_flatten_sites(sites: PackedVector3Array, radii: PackedFloat32Array) -> void          # EntityViewPool, on BUILD_STARTED / STRUCTURE_LOST
func flatten_site_count() -> int
func camera_height_agl(pos: Vector3) -> float                                                 # h_cam for CamMath.near_plane (ViewState.near)
func update_view(view: PlanetView, now_ms: int) -> void
func visible_chunks() -> int
func build_ms_percentile(p: float) -> float
```

## Invariants

- P1: No hole. Every direction above the horizon is covered by exactly one shown leaf; a node whose 4 children are
  not all built keeps rendering itself; a merged subtree stays resident for `merge_grace_s` before its slots return.
- P2: Mesher heights (without flatten sites) are bit-identical to the texel-space reference of `height_at` (03 s6.2 bilinear at
  x = (n - 1) g / segs) and agree with `Terrain.height_at(vertex_dir)` to < 2 mm (float32 direction quantisation).
  Vertex directions are bit-identical to `Sphere.face_uv_to_dir`. Vertex heights never round-trip through
  `face_uv_to_dir -> height_at`; only ring samples outside a cube face (edge normals) use `height_at`.
- P3: Every chunk shares one index pattern: 2,048 grid + 256 skirt triangles, clockwise front faces seen from
  outside; skirts hang `skirt_depth(depth)` (2.5 x 0.5 x vertex spacing) below their edge and carry custom.a = 255.
- P4: The cut never exceeds `visible_chunks_cap` nor `max_depth`; when the cap binds, the lowest-priority
  (farthest) splits are refused first; no split is taken that the free pool slots cannot hold.
- P5: Per frame at most `builds_per_frame` builds run, and a build whose estimate would overrun `build_ms_cap`
  waits, except that after `starvation_frames` frames without a build exactly one runs (R0 C1-06).
- P6: Horizon culling is conservative: nothing a straight line of sight can reach over the R + RELIEF_MIN sphere
  is culled; the node's own `h_max` replaces RELIEF_MAX in theta_up.
- P7: The pool allocates `pool_size` instance + mesh pairs in `setup` and never creates or frees Nodes afterwards.
- P8: The renderer writes nothing to the sim and reads only `Terrain` and `PlanetView`.
- P10 (TA-24): Footprint flattening and shader detail are cosmetic. `Terrain.height_at` is never changed; the
  flatten height is a pure function of the unit direction (chunk seams and cube edges stay closed, skirts follow);
  shader displacement is <= 1.2 m (3 layers 0.6 / 0.4 / 0.2 m, mean zero), 0 on skirts and beyond the tier's
  `detail_displacement_m`, and <= 0.6 m inside a footprint (FOOTPRINT_KEEP 0.5). `MoonDetail` mirrors the shader's
  constants (`test_moon_terrain.gd`). Biome id is read per pixel from an R8 Texture2DArray of the baked faces
  (`Terrain.biome_face`), custom.b = cube face; the result equals `Terrain.biome_at`.
- P11 (TA-24): The Earth is a 6 degree disc exactly at -Z and the sun disc 2 degrees at `sun_dir` (`SkyMoon`).
- P9: Every spatial material includes `src/presentation/shaders/moon_light.gdshaderinc` and works in linear light:
  inputs through `ml_to_linear`, ALBEDO / EMISSION through `ml_encode` (Godot 4.7.2 Compatibility decodes them with
  a polynomial; ART-01 REPORT s3). `MoonLight` constants equal the include's (`test_moon_light.gd`). `sun_dir` is
  registered by `MoonLight.ensure_globals()` before any such material is created.

## Data owned

Quadtree records (`ChunkNode`, RefCounted, no parent pointers), the scheduler queue, the per-depth tan table
(sum over depths of 32 * 2^L + 3 doubles), the shared index buffer, the pool's MeshInstance3D + ArrayMesh pairs
and the build-time ring. Reads `content/defs/quality_tiers.json` through `PlanetTierConfig` and the baked faces
through `Terrain.height_texel` / `height_at`.

## Events emitted / consumed

Signal `PlanetRenderer.chunk_built(face, depth, ix, iy, ms)` after every chunk build (the per-chunk build log).
Consumes no `SimEvent`.

## Performance budget

Per frame: selection (`plan_ms`) + builds <= `build_ms_cap` of the tier (2.0 / 3.0 / 4.0 ms) except one starvation
build. Chunk build (arrays + upload) measured by `godot/test/perf/bench_planet.gd`: ~1.0-1.3 ms at depth 4-6,
~1.8 ms at depth 0-1 on the dev PC headless (s_world1_r6000, n = 128). Selection ~0.5-2 ms in GDScript for
120-220 visited nodes. Prebuild of depth 0-2 (126 chunks) ~200 ms behind the loading screen.
TA-24: the flatten override adds ~0.4 ms (typical, 4-9 sites in a chunk) to ~0.9 ms (20 sites in one depth-6 chunk,
worst case) to a chunk build (`BENCH_PLANET_FLATTEN`); rebuilds after `set_flatten_sites` take the frame's leftover
build budget (at least one per frame). The 32-site loop and 3 crater layers run in the vertex shader of the
chunks inside the tier's detail range only; the pool holds 150 / 220 / 300 pairs (LOW / MEDIUM / HIGH).

## Test entry points

- `godot/test/unit/presentation/planet/test_split_metric.gd` (split metric, hysteresis, priority, tier knobs)
- `godot/test/unit/presentation/planet/test_planet_quadtree.gd` (caps, no hole while flying, merge grace, skirts close cracks)
- `godot/test/unit/presentation/planet/test_chunk_scheduler.gd` (count / ms budget, starvation rule)
- `godot/test/unit/presentation/planet/test_chunk_pool.gd` (pool reuse, no Node churn)
- `godot/test/unit/presentation/planet/test_horizon_cull.gd` (conservative horizon, frustum planes)
- `godot/test/unit/presentation/planet/test_chunk_mesher.gd` (bit-identical heights, direction table, winding, skirts, seams)
- `godot/test/unit/presentation/planet/test_chunk_mesher_1024.gd` (1,024 map with 370 m single-texel cliffs: vertices == `height_at` at every depth, no skirt vertex above the surface)
- `godot/test/perf/bench_planet.gd` (build ms per depth, flatten cost, boost path per tier)
- `godot/test/unit/presentation/planet/test_moon_terrain.gd` (shader constants == `MoonDetail`, 1.2 m / 0.6 m caps, mean-zero crater, biome array == `Terrain.biome_at`, ramp rows, sites uniform)
- `godot/test/unit/presentation/planet/test_flatten_sites.gd` (flat inside / untouched outside, seamless over a cube edge, in-place rebuilds)
- `godot/test/unit/presentation/planet/test_sky_moon.gd` (Earth at -Z, 6 and 2 degree discs, `apply`)
- `godot/test/golden/world/z_scene.tscn` (Z1-Z5 and Z8 harness, `Z_RESULT` flicker metric, `--control` negative control; Xvfb + llvmpipe)
- `godot/test/unit/presentation/planet/test_moon_light.gd` (include == CPU mirror, 07 hex derivation, night target, atlas import)
- `godot/test/perf/bench_instance_uniforms.gd` (instance-uniform capacity and cost; windowed)
- Goldens: `godot/test/golden/world/goldens.json` (look-dev scene `lookdev_shot.tscn` with `LOOKDEV_MEASURE` probes; TA-24 terrain, Earth probe and Z entries)
- Demo: `godot/scenes/presentation/planet/planet_demo.tscn` (free camera; `--autofly`, `--lod`, `--frames`, `--shot`,
  `--lat/--lon/--yaw`, `--sun=<deg>`, `--sky=0`, `--earth-probe`, `--hud=0`)

## How to add X (recipes for the cheapest tier)

- A new tier knob: add the key to `quality_tiers.json` and its schema (content lane), read it in
  `PlanetTierConfig.from_dict` with a 03 default, assert it in `test_split_metric.gd`.
- A new per-vertex attribute: extend `ChunkMesher._fill_grid` / `_fill_skirts` and `build_arrays`, keep
  `VERTEX_COUNT` and the shared index pattern, extend `test_chunk_mesher.gd`.

## Open items

- ART-15 owns the final Earth / star look of `sky_moon.gdshader`; TA-24 ships a working version under the same
  contract (6 degree disc at -Z, 2 degree sun disc). The sky colour space in Compatibility is unmeasured on device.
- The camera lane feeds `ViewState.near` = `CamMath.near_plane(PlanetRenderer.camera_height_agl(pos))`; the planet
  lane only exposes h_cam and carries the camera's near in `PlanetView.near_m` (planet may not depend on `camera`).
- `EntityViewPool` (TA-26) calls `set_flatten_sites` with the full structure list on BUILD_STARTED / STRUCTURE_LOST.
- ART-03 / TA-24: `ml_encode` costs two pows + two Newton steps per output; measure on Android-mid (HUM-06) and
  fall back to one Newton step or a 256-entry LUT if fill-bound.
- TA-25: variant B, three radii, device numbers; confirm `chunk_pool_size` 150 / 220 / 300 and `detail_displacement_m`
  on Android-mid and web (the 3-layer vertex detail and the 32-site loop are the new vertex cost).
- `ViewState` (06) will hand `PlanetView` over; until then `PlanetView.from_camera`.
