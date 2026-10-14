class_name FlattenSites extends RefCounted
## Cosmetic footprint flattening (03 s7.6, R0 C2-31): the mesher lowers/raises terrain under a structure
## footprint to the height at the footprint centre (full inside `radius`, smoothstep to the terrain at
## OUTER_FACTOR x radius). A client-side look only: gameplay height stays `Terrain.height_at` (ADR-04). The
## result is a pure function of the unit direction, so chunk seams and skirts stay consistent. The sites come
## from `SimView` through `PlanetRenderer.set_flatten_sites`; this class holds no sim state.

const OUTER_FACTOR: float = 1.5               ## blend ends at 1.5 x radius (the shader's FOOTPRINT_OUTER)
const MAX_SHADER_SITES: int = 32              ## the shader's sites[] capacity (nearest to the camera win)
const CHUNK_MARGIN_M: float = 24.0            ## slack on the chunk-vs-site test (ring samples, skirts)

var dirs: PackedVector3Array = PackedVector3Array()      ## unit directions of the footprint centres
var heights: PackedFloat64Array = PackedFloat64Array()   ## metres above the datum at each centre
var radii: PackedFloat32Array = PackedFloat32Array()     ## footprint radius in metres
var _world: PackedVector3Array = PackedVector3Array()    ## centre positions on the surface
var _loc_dirs: PackedVector3Array = PackedVector3Array() ## sites relevant to the chunk being built
var _loc_h: PackedFloat64Array = PackedFloat64Array()
var _loc_in: PackedFloat64Array = PackedFloat64Array()   ## inner / outer radius as unit-sphere arc
var _loc_out: PackedFloat64Array = PackedFloat64Array()
var _loc_out2: PackedFloat64Array = PackedFloat64Array()   ## outer radius squared (cheap reject)
var _loc_n: int = 0


func size() -> int:
	return dirs.size()


func is_empty() -> bool:
	return dirs.is_empty()


## Replaces the sites. `positions` are world positions (only the direction is used); the plane height is
## `terrain.height_at` at the centre, the same sample the build system places the structure at.
func set_sites(terrain: Terrain, positions: PackedVector3Array, p_radii: PackedFloat32Array) -> void:
	dirs.clear()
	heights.clear()
	radii.clear()
	_world.clear()
	var n: int = mini(positions.size(), p_radii.size())
	for i: int in n:
		if positions[i].length_squared() < 1e-6 or p_radii[i] <= 0.0:
			continue
		var d: Vector3 = positions[i].normalized()
		var h: float = terrain.height_at(d)
		var _a: bool = dirs.push_back(d)
		_a = heights.push_back(h)
		_a = radii.push_back(p_radii[i])
		_a = _world.push_back(d * (Sphere.PLANET_RADIUS + h))


## True when any site's blend disc can touch `node` (its bounding sphere plus a margin).
func affects(node: ChunkNode) -> bool:
	for i: int in dirs.size():
		if _near(node, i):
			return true
	return false


## Collects the sites relevant to `node` for the following `apply` calls; returns how many.
func select_for(node: ChunkNode) -> int:
	_loc_n = 0
	var _r: int = _loc_dirs.resize(dirs.size())
	_r = _loc_h.resize(dirs.size())
	_r = _loc_in.resize(dirs.size())
	_r = _loc_out.resize(dirs.size())
	_r = _loc_out2.resize(dirs.size())
	for i: int in dirs.size():
		if not _near(node, i):
			continue
		_loc_dirs[_loc_n] = dirs[i]
		_loc_h[_loc_n] = heights[i]
		_loc_in[_loc_n] = float(radii[i]) / Sphere.PLANET_RADIUS
		_loc_out[_loc_n] = float(radii[i]) * OUTER_FACTOR / Sphere.PLANET_RADIUS
		_loc_out2[_loc_n] = _loc_out[_loc_n] * _loc_out[_loc_n]
		_loc_n += 1
	return _loc_n


## Height at unit direction `d` whose unflattened height is `h`, over the sites chosen by `select_for`.
func apply(d: Vector3, h: float) -> float:
	var out: float = h
	for i: int in _loc_n:
		var d2: float = d.distance_squared_to(_loc_dirs[i])
		if d2 >= _loc_out2[i]:
			continue
		var w: float = 1.0 - smoothstep(_loc_in[i], _loc_out[i], sqrt(d2))
		out = lerpf(out, _loc_h[i], w)
	return out


## Up to MAX_SHADER_SITES sites nearest `cam` as (x, y, z, radius) for the material's sites[] uniform.
func shader_sites(cam: Vector3) -> PackedVector4Array:
	var order: Array[int] = []
	for i: int in dirs.size():
		order.append(i)
	if order.size() > MAX_SHADER_SITES:
		order.sort_custom(func(a: int, b: int) -> bool: return _world[a].distance_squared_to(cam) < _world[b].distance_squared_to(cam))
	var out: PackedVector4Array = PackedVector4Array()
	for k: int in mini(order.size(), MAX_SHADER_SITES):
		var i: int = order[k]
		var _a: bool = out.push_back(Vector4(_world[i].x, _world[i].y, _world[i].z, radii[i]))
	return out


func _near(node: ChunkNode, i: int) -> bool:
	var reach: float = node.radius + float(radii[i]) * OUTER_FACTOR + CHUNK_MARGIN_M
	return _world[i].distance_squared_to(node.center) <= reach * reach
