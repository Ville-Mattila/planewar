# presentation - MODULE.md

Contract for `godot/src/presentation/**` except `planet/` (which has its own MODULE.md, R0 B.9 A-21). Entity views,
MultiMesh pools, pooled effects and the unit material cache (03 s7.9-7.10, s10; R0 C1-07, C1-17; 07 s3-s6;
TA-26, ART-03). A change to "Public API" or "Invariants" is a contract change: contract tests first, same PR (ADR-11);
`tools/gen_module_api.py --check` must pass.

| Field | Value |
|---|---|
| Responsibility | Draws the entities a `SimView` exposes: pooled `EntityView` meshes nearest-first up to the tier cap (200 / 400 / 800), `_Far` meshes through per-class MultiMesh pools past the cap or the `_Far` switch, icon glyphs past the icon band; the per-frame `set_local_override` pose of the possessed unit; projectile (six cube faces), trail and decal pools; `VfxRouter` mapping `SimEvent` kinds to pooled effects and the pre-warm list; the shared `unit_lit` material cache. Placeholder primitive meshes stand in until ART-04/05 deliver GLBs. Does not own the planet (`planet/`), the camera, HUD, audio, or any sim state. |
| Lane owner tier | Sonnet |
| May depend on | `core`, `content`; named sim types `SimView`, `SimEvent`, `Terrain`; net `NetSimView` (`tools/deps.json`) |
| Must never touch | the sim beyond `SimView` reads; `net`; `camera`; `ui`; no autoloads; no threads; no hard-coded 6,000 or 8,192 |
| Autoloads used | none |
| Status | implemented (TA-26 entity views, pools, VfxRouter; ART-03 `UnitMaterialCache`); placeholder meshes and effect looks |

## Public API

Anything not listed is private (`_` prefix). Caps and distances come from `quality_tiers.json` via `EntityViewConfig`.
`UnitMaterialCache` (ART-03): one shared `unit_lit` ShaderMaterial per (team 8 x state 5) = 40, created lazily.

```gdscript
class_name EntityClassTable extends RefCounted
const BIG_FOOTPRINT_CELLS: int = 3
static func from_content(c: ContentSet) -> EntityClassTable
func group_count() -> int
func group_name(group: int) -> StringName
func group_kind(group: int) -> int
func group_of(def_id: int) -> int

class_name EntityView extends MeshInstance3D
var id: int = 0
var group: int = -1
var team: int = -1
var state: int = -1
var linger_until: float = -1.0
var prev_pos: Vector3 = Vector3.ZERO
var cur_pos: Vector3 = Vector3.ZERO
var prev_q: Quaternion = Quaternion.IDENTITY
var cur_q: Quaternion = Quaternion.IDENTITY
var seen_tick: int = -1
var scale_m: float = 1.0

class_name EntityViewConfig extends RefCounted
const DEFAULT_FAR_PX: float = 24.0
const DEFAULT_LINGER_S: float = 2.0
const DEFAULT_VIEW_CAP: int = 200
const DEFAULT_ICON_BAND_M: float = 2500.0
var tier_id: StringName = &"low"
var view_cap: int = DEFAULT_VIEW_CAP
var icon_band_start_m: float = DEFAULT_ICON_BAND_M
var projectile_pool: int = 1024
var trails_enabled: bool = false
var trail_segments: int = 0
var far_px: float = DEFAULT_FAR_PX
var linger_s: float = DEFAULT_LINGER_S
static func from_dict(d: Dictionary) -> EntityViewConfig
static func from_def(def: QualityTierDef) -> EntityViewConfig
func bounded_by(profile_nodes: int) -> EntityViewConfig

class_name EntityViewPool extends Node3D
const MODE_VIEW: int = 0
const MODE_FAR: int = 1
const MODE_ICON: int = 2
const STATE_REFRESH_TICKS: int = 4
const DEFAULT_TICK_HZ: float = 30.0
const DEFAULT_PX_PER_M: float = 704.0
const FAR_CAPACITY: int = 1280
const WRECK_TINT: float = 0.35
var cam_pos: Vector3 = Vector3.ZERO
var px_per_m: float = DEFAULT_PX_PER_M
var viewer_team: int = 0
var tick_hz: float = DEFAULT_TICK_HZ
var far: FarPools = null
var icons: IconPool = null
var last_views: int = 0
var last_far: int = 0
var last_icons: int = 0
func setup(cfg: EntityViewConfig, classes: EntityClassTable, materials: UnitMaterialCache, far_capacity: int = FAR_CAPACITY) -> void
func set_local_override(id: int, p: Vector3, b: Basis) -> void
func clear_local_override() -> void
func invalidate() -> void
func view_capacity() -> int
func bound_count() -> int
func view_for(id: int) -> EntityView
func draw_calls() -> int
func sync(view: SimView, render_time: float) -> void

class_name PlaceholderMeshes extends RefCounted
const TEAM_PAINT_CELL: int = 18
const ATLAS_COLS: int = 16
const HEX_SIDES: int = 6
const FAR_TRI_BUDGET: int = 48
const QUAD_HALF: float = 0.5
static func mesh_for(kind: int) -> ArrayMesh
static func triangle_count(kind: int) -> int
static func icon_quad() -> QuadMesh
static func crossed_quads() -> ArrayMesh
static func flat_quad() -> ArrayMesh

class_name DecalPool extends MultiMeshPool
const CAPACITY: int = 256
const FADE_S: float = 60.0
const LIFT_M: float = 0.2
const SOOT: Color = Color(0.03, 0.03, 0.035, 0.85)
const UPDATE_INTERVAL_S: float = 0.25
func setup_decals(p_capacity: int = CAPACITY) -> void
func live_count() -> int
func add(pos: Vector3, up: Vector3, radius_m: float) -> void
func update(delta: float) -> void

class_name FarPools extends Node3D
var pools: Array[MultiMeshPool] = []
func setup(classes: EntityClassTable, capacity: int) -> void
func begin() -> void
func push(group: int, xf: Transform3D, color: Color) -> bool
func commit() -> void
func draw_calls() -> int
func instance_total() -> int

class_name IconPool extends MultiMeshPool
const MIN_SCREEN_PX: float = 14.0
const GLYPH_BY_KIND: PackedInt32Array = [0, 1, 2]
func setup_icons(capacity: int) -> void
static func icon_size(radius: float, dist: float, px_per_m: float) -> float
func add(pos: Vector3, size: float, color: Color, kind: int) -> bool

class_name MultiMeshPool extends MultiMeshInstance3D
var capacity: int = 0
var count: int = 0
func setup(mesh: Mesh, material: Material, p_capacity: int, use_custom: bool = false) -> void
func begin() -> void
func push(xf: Transform3D, color: Color, custom: Color = Color.BLACK) -> bool
func set_at(i: int, xf: Transform3D, color: Color) -> void
func commit() -> void
func draw_calls() -> int

class_name PoolMaterials extends RefCounted
const FAR_SHADER: String = "res://src/presentation/shaders/unit_far.gdshader"
const ICON_SHADER: String = "res://src/presentation/shaders/unit_icon.gdshader"
const DECAL_SHADER: String = "res://src/presentation/shaders/unit_decal.gdshader"
const ADDITIVE_SHADER: String = "res://src/presentation/shaders/vfx_additive.gdshader"
static func far_material() -> ShaderMaterial
static func icon_material() -> ShaderMaterial
static func additive_material() -> ShaderMaterial
static func decal_material() -> ShaderMaterial
static func make_additive() -> ShaderMaterial

class_name ProjectilePools extends Node3D
const FACES: int = 6
const TRACER_S: float = 0.02
const MIN_LENGTH_M: float = 0.6
const WIDTH_M: float = 0.3
const NEUTRAL: Color = Color(1.0, 0.91, 0.66)
var faces: Array[MultiMeshPool] = []
var dropped: int = 0
func setup(capacity_per_face: int) -> void
static func face_of(d: Vector3) -> int
func sync(view: SimView, ids: PackedInt32Array) -> void
func draw_calls() -> int
func instance_total() -> int

class_name TrailPool extends MultiMeshPool
const LIFE_S: float = 1.6
const WIDTH_M: float = 1.5
const UPDATE_INTERVAL_S: float = 0.0667
func setup_trails(segments: int) -> void
func enabled() -> bool
func add_segment(from: Vector3, to: Vector3, color: Color) -> bool
func update(delta: float) -> void

class_name UnitMaterialCache extends RefCounted
enum State { HEALTHY = 0, DAMAGED_1 = 1, DAMAGED_2 = 2, DAMAGED_3 = 3, WRECK = 4 }
const TEAM_COUNT: int = 8
const STATE_COUNT: int = 5
const TEAM_HEX: PackedStringArray = ["#E1A633", "#4C64ED", "#3BFAB2", "#17840E", "#B1369D", "#E9A1FD", "#D6F72C", "#F06867"]
const STATE_DAMAGE01: PackedFloat32Array = [0.0, 0.25, 0.5, 0.75, 1.0]
const DAMAGE_STEP_MIN: PackedFloat32Array = [0.25, 0.5, 0.75]
static func team_color(team: int) -> Color
static func state_for(damage01: float, is_wreck: bool) -> int
func get_material(team: int, state: int) -> ShaderMaterial
func build_material(team: int, build_progress: float) -> ShaderMaterial
func size() -> int
func clear() -> void

class_name VfxCatalog extends RefCounted
enum Shape { SPHERE, RING, CONE, QUAD }
const TABLE: Dictionary
static func ids() -> PackedStringArray
static func has(id: StringName) -> bool
static func shape(id: StringName) -> int
static func life_s(id: StringName) -> float
static func size_m(id: StringName) -> float
static func color(id: StringName) -> Color
static func intensity(id: StringName) -> float

class_name VfxPool extends Node3D
const DEFAULT_CAPACITY: int = 64
const SHRINK_FRACTION: float = 0.33
const RING_TUBE: float = 0.08
var spawned_total: int = 0
var last_id: StringName = &""
var counts: Dictionary = {}
func setup(max_effects: int = DEFAULT_CAPACITY) -> void
func capacity() -> int
func active_count() -> int
func material_for(id: StringName) -> ShaderMaterial
func spawn(id: StringName, pos: Vector3, scale_mult: float = 1.0, up: Vector3 = Vector3.ZERO) -> bool
func clear() -> void
func update(delta: float) -> void

class_name VfxPrewarm extends RefCounted
const LIST_PATH: String = "res://content/vfx_prewarm.json"
static func load_list(path: String = LIST_PATH) -> PackedStringArray
static func run(pool: VfxPool, ids: PackedStringArray, at: Vector3) -> int
static func finish(pool: VfxPool) -> void

class_name VfxRouter extends RefCounted
const SMOKE_HP01: PackedFloat32Array = [0.75, 0.5, 0.25]
const SMOKE_ID: StringName = &"vfx_smoke_trail"
const SMOKE_SCALE: PackedFloat32Array = [0.6, 1.0, 1.6]
const HIT_SCALE_PER_DAMAGE: float = 0.01
const HIT_SCALE_MAX: float = 3.0
const SCORCH_RADIUS_M: float = 14.0
var pool: VfxPool = null
var decals: DecalPool = null
var smoke_hp01: PackedFloat32Array = SMOKE_HP01
var handled: int = 0
static func route(kind: int) -> StringName
static func smoke_step(hp01: float, thresholds: PackedFloat32Array) -> int
func handle(ev: SimEvent, view: SimView) -> int
func drain(events: Array[SimEvent], view: SimView) -> int
```

## Invariants

- V1: `setup` pre-instantiates exactly `view_cap` `EntityView` nodes and never creates or frees view nodes afterwards; at most `view_cap` are bound (`bound_count()`), nearest first.
- V2: Every visible entity is drawn exactly once: as a view, a far-pool instance, or an icon (`last_views + last_far + last_icons` = visible ids, apart from pool-full drops).
- V3: Far pools hold one MultiMesh per class group (<= 8 for the shipped content); far plus icon draws stay <= 9 calls.
- V4: The possessed unit (`set_local_override`) is always drawn as a view and takes the override pose, not the sim sample (R0 C1-07).
- V5: `SimView` is read once per sim tick; frames between ticks interpolate the last two ticks with `render_time` (alpha = render_time x tick_hz - (tick - 1), clamped).
- V6: A view whose entity left the visible list lingers `linger_s` (2 s) before returning to the pool; lingering views are stolen first when the pool is full.
- V7: Team colour, damage step and wreck state come from the shared `UnitMaterialCache`; no per-view material is created.
- V8: `VfxRouter.route` is a pure table over `SimEvent.Kind`; kinds without an effect route to the empty id. HIT adds smoke when hp01 is below `smoke_hp01` (0.75 / 0.5 / 0.25).
- V9: Pools never allocate Nodes per frame; `VfxPool` recycles oldest-first when full.
- V10: Decals lie in the surface tangent plane (spec 7.10 says camera-facing; a flat scorch reads better on slopes).

## Data owned

Per-slot view cache (packed arrays) in `EntityViewPool`; the pooled nodes and MultiMeshes. Reads `quality_tiers.json` rows, def `presentation.far_mesh_node`, optional `content/vfx_prewarm.json` (07, hash-excluded; falls back to `VfxCatalog`).

## Events emitted / consumed

Consumes drained `SimEvent`s through `VfxRouter.drain`. Emits nothing.

## Performance budget

Entity sync 2.4 ms at 800 views PC-mid, 0.8 ms on 200 + far pools (03 s10.2); pools 1.0 ms. Measured with `scenes/presentation/entities/entity_demo.tscn` (see the TA-26 PR).

## Test entry points

`godot/test/unit/presentation/test_entity_view_pool.gd`, `godot/test/unit/presentation/test_vfx_router.gd`, `godot/test/unit/presentation/test_pools.gd`, `godot/test/unit/presentation/test_unit_material_cache.gd`, `godot/test/unit/presentation/test_shader_library.gd`. Demo: `godot/scenes/presentation/entities/entity_demo.tscn` (`-- --tier=low|medium|high --n=400 --cam=chase|base|wide --frames=N --shot=<png>`).

## How to add X

- A new effect: add its row to `VfxCatalog.TABLE`, route it in `VfxRouter.route`, list it in `content/vfx_prewarm.json`; extend `test_vfx_router.gd`.
- A new view class: give the def `presentation.far_mesh_node`, or extend `EntityClassTable._add` bucketing; keep the group count <= 8.
