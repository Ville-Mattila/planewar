class_name BarrelReadoutData extends RefCounted
## Plain data of the barrel elevation readout (UX-49; 06 s3.2, s6.1; R0 B.31 A-155) for a possessed ground unit with a
## barrel. `shown` is false for a def without a barrel and while the view does not receive the field.

var shown: bool = false
var deg: int = 0           ## whole degrees above the local horizontal, clamped to the def's limits
var min_deg: int = 0
var max_deg: int = 0
var fill01: float = 0.0


## True when the def has a barrel (the BarrelSlew rule: a slew rate or a non-zero limit).
static func has_barrel(g: GroundUnitDef) -> bool:
	return g != null and (g.barrel_slew_dps > 0.0 or g.barrel_min_deg != 0.0 or g.barrel_max_deg != 0.0)


## Pure builder: `rad` = SimView.barrel_elevation(id), `received` = false hides the readout.
static func from_def(g: GroundUnitDef, rad: float, received: bool) -> BarrelReadoutData:
	var d: BarrelReadoutData = BarrelReadoutData.new()
	if not received or not has_barrel(g):
		return d
	d.shown = true
	d.min_deg = roundi(minf(g.barrel_min_deg, g.barrel_max_deg))
	d.max_deg = roundi(maxf(g.barrel_min_deg, g.barrel_max_deg))
	d.deg = HudMath.barrel_deg(rad, g.barrel_min_deg, g.barrel_max_deg)
	d.fill01 = HudMath.barrel_fill01(rad_to_deg(rad), g.barrel_min_deg, g.barrel_max_deg)
	return d


## `g` = ContentDB.ground_unit(v.def_id(id)), looked up by the host. Reads only SimView. A view that reports `field_unknown(id, &"barrel_elevation")` (NetSimView) counts as not received.
static func from_view(v: SimView, id: int, g: GroundUnitDef) -> BarrelReadoutData:
	var unknown: bool = false
	if v.has_method(&"field_unknown"):
		var r: Variant = v.call(&"field_unknown", id, &"barrel_elevation")
		unknown = r is bool and r
	var received: bool = not unknown
	return from_def(g, v.barrel_elevation(id), received)
