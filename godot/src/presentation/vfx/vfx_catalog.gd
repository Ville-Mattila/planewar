class_name VfxCatalog
extends RefCounted
## Placeholder look of every `vfx_*` id of the 07 s6 table (until ART-VFX delivers the real effects): shape, life,
## size, colour. The id set is the source of the pre-warm fallback list (`VfxPrewarm`). Looks are presentation
## data of 07, not sim constants. All static.

enum Shape { SPHERE, RING, CONE, QUAD }

## id -> [Shape, life_s, size_m, colour hex, intensity]
const TABLE: Dictionary = {
	&"vfx_exhaust_cone": [Shape.CONE, 0.2, 8.0, "#CFEBFF", 1.0],
	&"vfx_exhaust_burst": [Shape.SPHERE, 0.3, 3.0, "#CFEBFF", 1.0],
	&"vfx_muzzle_flash": [Shape.QUAD, 0.06, 2.0, "#FFE9A8", 1.5],
	&"vfx_tracer": [Shape.QUAD, 0.1, 6.0, "#FFE9A8", 1.0],
	&"vfx_hit_spark": [Shape.SPHERE, 0.25, 3.0, "#FFD27F", 1.5],
	&"vfx_smoke_trail": [Shape.SPHERE, 1.6, 4.0, "#8C8F99", 0.6],
	&"vfx_rocket_flame": [Shape.CONE, 0.3, 5.0, "#FFB060", 1.2],
	&"vfx_flak_burst": [Shape.SPHERE, 0.4, 25.0, "#3A3D46", 0.8],
	&"vfx_rail_beam": [Shape.QUAD, 0.2, 40.0, "#9DE0FF", 1.5],
	&"vfx_bomb_impact_s": [Shape.SPHERE, 0.8, 18.0, "#FF9A3C", 1.4],
	&"vfx_bomb_impact_l": [Shape.SPHERE, 0.8, 36.0, "#FF9A3C", 1.4],
	&"vfx_debris": [Shape.SPHERE, 1.2, 2.0, "#6E7686", 0.6],
	&"vfx_explosion_ship": [Shape.SPHERE, 0.9, 20.0, "#FFB060", 1.5],
	&"vfx_explosion_structure": [Shape.SPHERE, 1.2, 40.0, "#FF8A30", 1.5],
	&"vfx_explosion_reactor": [Shape.RING, 1.5, 100.0, "#FFE0A0", 1.6],
	&"vfx_shield_dome": [Shape.SPHERE, 1.0, 60.0, "#7FD6FF", 0.5],
	&"vfx_shield_hit": [Shape.RING, 0.5, 12.0, "#7FD6FF", 1.4],
	&"vfx_dock_beam": [Shape.CONE, 1.0, 12.0, "#6FD08C", 0.9],
	&"vfx_pad_lights": [Shape.RING, 0.8, 10.0, "#FFF0A0", 1.0],
	&"vfx_build_scaffold": [Shape.QUAD, 1.0, 20.0, "#5CC8FF", 0.8],
	&"vfx_possess_pulse": [Shape.RING, 0.5, 14.0, "#F0E442", 1.4],
	&"vfx_alert_ring": [Shape.RING, 1.0, 60.0, "#FF5A5A", 1.4],
	&"vfx_dust_plume": [Shape.SPHERE, 1.2, 10.0, "#B1ACA1", 0.5],
	&"vfx_ice_steam": [Shape.SPHERE, 1.5, 8.0, "#B5D8EC", 0.5],
	&"vfx_tether": [Shape.QUAD, 0.5, 25.0, "#9AA2B1", 0.8],
	&"vfx_wreck_smoke": [Shape.SPHERE, 1.6, 5.0, "#3A3D46", 0.6],
	&"vfx_spawn_in": [Shape.RING, 0.6, 10.0, "#5CC8FF", 1.2],
}


static func ids() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for k: StringName in TABLE:
		var _a: bool = out.push_back(String(k))
	return out


static func has(id: StringName) -> bool:
	return TABLE.has(id)


static func shape(id: StringName) -> int:
	var row: Array = TABLE[id]
	var v: int = row[0]
	return v


static func life_s(id: StringName) -> float:
	var row: Array = TABLE[id]
	var v: float = row[1]
	return v


static func size_m(id: StringName) -> float:
	var row: Array = TABLE[id]
	var v: float = row[2]
	return v


static func color(id: StringName) -> Color:
	var row: Array = TABLE[id]
	var v: String = row[3]
	return Color(v)


static func intensity(id: StringName) -> float:
	var row: Array = TABLE[id]
	var v: float = row[4]
	return v
