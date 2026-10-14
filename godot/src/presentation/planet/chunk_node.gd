class_name ChunkNode extends RefCounted
## One quadtree node of a cube face (03 s7.1): depth L covers 1/2^L of the face's (u, v) square starting at
## (ix, iy) * 2^-L. A record only; the quadtree, scheduler and pool own the behaviour. No parent pointer (a
## RefCounted cycle would leak); children are created on the first split and dropped after the merge grace.

const GRID: int = 32                         ## quads per chunk edge (33 x 33 vertices)

var face: int = 0
var depth: int = 0
var ix: int = 0
var iy: int = 0
var children: Array[ChunkNode] = []          ## empty or 4: (0,0), (1,0), (0,1), (1,1)
var center: Vector3 = Vector3.ZERO           ## bounding sphere centre (world)
var radius: float = 0.0                      ## bounding sphere radius (m)
var edge_m: float = 0.0                      ## chunk edge at the face centre, R * PI / 2 / 2^L (03 s7.1)
var h_min: float = Sphere.RELIEF_MIN         ## height range used for the bounds (tight after build)
var h_max: float = Sphere.RELIEF_MAX
var slot: int = -1                           ## ChunkPool slot holding the mesh, -1 = not built
var split: bool = false                      ## children are the rendered cut this frame
var merge_since_ms: int = -1                 ## time the node stopped being split (merge grace), -1 = n/a
var priority: float = 0.0                    ## scheduler priority (03 s7.4), set by the quadtree per frame
var queued_frame: int = -1                   ## frame number the node was last pushed to the queue
var wanted_since_ms: int = -1                ## start of the current uninterrupted run in the queue
var shown_frame: int = -1                    ## frame number the node was last part of the rendered cut
var build_ms: float = 0.0                    ## last measured build time


static func make(p_face: int, p_depth: int, p_ix: int, p_iy: int, h_lo: float, h_hi: float) -> ChunkNode:
	var n: ChunkNode = ChunkNode.new()
	n.face = p_face
	n.depth = p_depth
	n.ix = p_ix
	n.iy = p_iy
	n.edge_m = Sphere.PLANET_RADIUS * PI * 0.5 / float(1 << p_depth)
	n.set_height_range(h_lo, h_hi)
	return n


func is_built() -> bool:
	return slot >= 0


## Global vertex column of local vertex `a` at this depth (0 .. 32 * 2^depth).
func gx(a: int) -> int:
	return ix * GRID + a


func gy(b: int) -> int:
	return iy * GRID + b


## Recomputes the bounding sphere from the 4 corner and centre directions over [h_lo, h_hi] (03 s7.1).
func set_height_range(h_lo: float, h_hi: float) -> void:
	h_min = h_lo
	h_max = h_hi
	var w: float = 1.0 / float(1 << depth)
	var u0: float = float(ix) * w
	var v0: float = float(iy) * w
	var cdir: Vector3 = Sphere.face_uv_to_dir(face, u0 + 0.5 * w, v0 + 0.5 * w)
	var r_lo: float = Sphere.PLANET_RADIUS + h_lo
	var r_hi: float = Sphere.PLANET_RADIUS + h_hi
	center = cdir * (0.5 * (r_lo + r_hi))
	var r2: float = 0.0
	for k: int in 5:
		var d: Vector3 = cdir
		if k < 4:
			d = Sphere.face_uv_to_dir(face, u0 + w * float(k & 1), v0 + w * float(k >> 1))
		r2 = maxf(r2, maxf(center.distance_squared_to(d * r_lo), center.distance_squared_to(d * r_hi)))
	radius = sqrt(r2)


## The 4 children (created once, bounds from this node's height range widened by the skirt margin).
func ensure_children(margin_m: float) -> Array[ChunkNode]:
	if children.is_empty():
		var lo: float = maxf(Sphere.RELIEF_MIN, h_min - margin_m)
		var hi: float = minf(Sphere.RELIEF_MAX, h_max + margin_m)
		for k: int in 4:
			children.append(make(face, depth + 1, ix * 2 + (k & 1), iy * 2 + (k >> 1), lo, hi))
	return children


func children_built() -> bool:
	if children.is_empty():
		return false
	for c: ChunkNode in children:
		if not c.is_built():
			return false
	return true
