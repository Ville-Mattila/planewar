class_name EntityViewConfig
extends RefCounted
## Entity-view knobs of one quality tier (03 s10.1, s13; R0 C1-17). `view_cap` is the number of individually
## drawn meshes (200 / 400 / 800); entities past it, or past the `_Far` switch, draw through the far pools.
## All numbers come from `quality_tiers.json`; the consts below are presentation defaults 07 owns.

## 07 ART-A1: a body under this many screen pixels draws as its `_Far` mesh.
const DEFAULT_FAR_PX: float = 24.0
## 03 s10.1: a released view lingers this long so the death effect has a body to play on.
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


## One `quality_tiers.json` entry.
static func from_dict(d: Dictionary) -> EntityViewConfig:
	var c: EntityViewConfig = EntityViewConfig.new()
	c.tier_id = StringName(str(d.get("id", "low")))
	c.view_cap = roundi(Def.num(d.get("entity_views_cap", DEFAULT_VIEW_CAP)))
	c.icon_band_start_m = Def.num(d.get("icon_band_start_m", DEFAULT_ICON_BAND_M))
	c.projectile_pool = roundi(Def.num(d.get("projectile_pool", c.projectile_pool)))
	c.trails_enabled = Def.flag(d.get("trails_enabled", false))
	c.trail_segments = roundi(Def.num(d.get("trail_segments", 0)))
	return c


static func from_def(def: QualityTierDef) -> EntityViewConfig:
	return from_dict(def.raw)


## The tier cap bounded by the caps profile's "visible entity mesh nodes" (01 s8.1; 0 = no profile bound).
func bounded_by(profile_nodes: int) -> EntityViewConfig:
	if profile_nodes > 0:
		view_cap = mini(view_cap, profile_nodes)
	return self
