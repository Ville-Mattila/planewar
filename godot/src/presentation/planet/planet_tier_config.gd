class_name PlanetTierConfig extends RefCounted
## Planet renderer knobs of one quality tier (03 s7.2, s7.4, s13), read from a `quality_tiers.json` entry.
## Budgets and caps are data, never constants (ADR-04): every field below comes from the tier def. The
## optional keys `chunk_starvation_frames`, `chunk_merge_hysteresis`, `chunk_merge_grace_s` and
## `chunk_pool_size` are read when present and otherwise default to the 03 s7 values.

const DEFAULT_STARVATION_FRAMES: int = 2    ## R0 C1-06: one forced build after 2 frames without a build
const DEFAULT_MERGE_HYSTERESIS: float = 0.5 ## 03 s7.2: merge at d > (K + 0.5) * edge
const DEFAULT_MERGE_GRACE_S: float = 1.0    ## 03 s7.4: merged children return to the pool after 1 s
const DEFAULT_POOL_SIZE: int = 220          ## 03 s7.3: MeshInstance3D + ArrayMesh pairs allocated at load
const DEFAULT_DETAIL_RANGE_M: float = 500.0 ## 03 s13 detail displacement range (MEDIUM)

var tier_id: StringName = &"high"
var split_k: float = 2.5
var max_depth: int = 6
var builds_per_frame: int = 6
var build_ms_cap: float = 4.0
var visible_chunks_cap: int = 150
var starvation_frames: int = DEFAULT_STARVATION_FRAMES
var merge_hysteresis: float = DEFAULT_MERGE_HYSTERESIS
var merge_grace_s: float = DEFAULT_MERGE_GRACE_S
var pool_size: int = DEFAULT_POOL_SIZE
var detail_range_m: float = DEFAULT_DETAIL_RANGE_M   ## moon_terrain vertex detail fades to 0 here (`detail_displacement_m`)


## From one parsed `quality_tiers.json` entry (a `QualityTierDef.raw` or the JSON dictionary itself).
static func from_dict(d: Dictionary) -> PlanetTierConfig:
	var c: PlanetTierConfig = PlanetTierConfig.new()
	c.tier_id = StringName(str(d.get("id", "high")))
	c.split_k = _f(d, "planet_split_k", c.split_k)
	c.max_depth = int(_f(d, "planet_max_depth", float(c.max_depth)))
	c.builds_per_frame = int(_f(d, "chunk_builds_per_frame", float(c.builds_per_frame)))
	c.build_ms_cap = _f(d, "chunk_build_ms_cap", c.build_ms_cap)
	c.visible_chunks_cap = int(_f(d, "visible_chunks_cap", float(c.visible_chunks_cap)))
	c.starvation_frames = int(_f(d, "chunk_starvation_frames", float(c.starvation_frames)))
	c.merge_hysteresis = _f(d, "chunk_merge_hysteresis", c.merge_hysteresis)
	c.merge_grace_s = _f(d, "chunk_merge_grace_s", c.merge_grace_s)
	c.pool_size = int(_f(d, "chunk_pool_size", float(c.pool_size)))
	c.detail_range_m = _f(d, "detail_displacement_m", c.detail_range_m)
	return c


static func from_def(def: QualityTierDef) -> PlanetTierConfig:
	return from_dict(def.raw)


static func _f(d: Dictionary, key: String, fallback: float) -> float:
	var v: Variant = d.get(key, fallback)
	if v is float:
		var f: float = v
		return f
	if v is int:
		var i: int = v
		return float(i)
	return fallback
