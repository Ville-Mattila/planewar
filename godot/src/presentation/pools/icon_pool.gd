class_name IconPool
extends MultiMeshPool
## Billboard icon layer (03 s7.9-7.10, 07 P4): one MultiMesh for every entity past the icon band start (2,500 m on
## MEDIUM/HIGH, 1,800 m on LOW). Per instance: scale = world size (clamped so the glyph keeps a minimum screen
## size), colour = team, custom data x = glyph index (kind-coded; 06/07 own the final glyphs).

## Smallest on-screen glyph, in pixels (placeholder until 06 fixes the icon size).
const MIN_SCREEN_PX: float = 14.0
## Glyph index per DefRanges kind: ship triangle, ground unit disc, structure square.
const GLYPH_BY_KIND: PackedInt32Array = [0, 1, 2]


func setup_icons(capacity: int) -> void:
	setup(PlaceholderMeshes.icon_quad(), PoolMaterials.icon_material(), capacity, true)


## World size of an icon at `dist` metres so it spans at least MIN_SCREEN_PX (px_per_m = pixels per metre at 1 m).
static func icon_size(radius: float, dist: float, px_per_m: float) -> float:
	return maxf(radius * 2.0, dist * MIN_SCREEN_PX / maxf(px_per_m, 1.0))


func add(pos: Vector3, size: float, color: Color, kind: int) -> bool:
	var glyph: float = float(GLYPH_BY_KIND[clampi(kind, 0, GLYPH_BY_KIND.size() - 1)])
	return push(Transform3D(Basis.IDENTITY * size, pos), color, Color(glyph, 0.0, 0.0, 0.0))
