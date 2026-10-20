class_name TerrainCellMax extends RefCounted
## Highest baked terrain height over one GRID_HASH cell (A-73 extraction from `Collision`, step 8b prefilter).


## Highest baked height (m) over every texel `Terrain.height_at` can read for a point of GRID_HASH `cell`, one texel of
## margin; 0 on the flat datum (before `Terrain.load_map`).
static func of_cell(terrain: Terrain, cell: int) -> float:
	var tn: int = terrain.face_resolution
	if tn == 0:
		return 0.0
	var n: int = Spatial.N
	var f: int = cell >> (Spatial.SHIFT + Spatial.SHIFT)
	var ci: int = cell & (n - 1)
	var cj: int = (cell >> Spatial.SHIFT) & (n - 1)
	var span: float = float(tn - 1) / float(n)
	var x0: int = maxi(int(float(ci) * span) - 1, 0)
	var x1: int = mini(int(float(ci + 1) * span) + 2, tn - 1)
	var y0: int = maxi(int(float(cj) * span) - 1, 0)
	var y1: int = mini(int(float(cj + 1) * span) + 2, tn - 1)
	var m: int = 0
	for y: int in range(y0, y1 + 1):
		for x: int in range(x0, x1 + 1):
			m = maxi(m, terrain.height_texel(f, x, y))
	return Sphere.RELIEF_MIN + float(m) * (Sphere.RELIEF_MAX - Sphere.RELIEF_MIN) / float(Terrain.U16_MAX)
