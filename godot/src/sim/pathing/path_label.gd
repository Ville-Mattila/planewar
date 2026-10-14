class_name PathLabel extends PathSearch
## Region labelling for the path hierarchy (PathRegions), on the grid's own arrays so the loops make no
## cross-object calls: label_cluster flood-fills the passable cells of one 16 x 16 cluster (8-connectivity with the
## corner rule; a cluster never spans a cube edge, so in-cluster steps are integer offsets) into labels 0..MAX_REG-1
## (fragments past MAX_REG - 1 fold into the last label; a region's centre is the cell at its mean (i, j), weighted
## by size when fragments fold), and link_cluster collects, per region, the bits of the
## neighbour-cluster regions its ring cells touch. Results stay in small scratch arrays read through accessors.

const CS: int = 16                         ## cells per cluster edge
const _DX: PackedInt32Array = [-1, 1, 0, 0, -1, 1, -1, 1]   ## PathGrid.neighbours order: -u, +u, -v, +v, diagonals
const _DY: PackedInt32Array = [0, 0, -1, 1, -1, -1, 1, 1]

var _pm: PackedByteArray = PackedByteArray()          ## CS * CS passability of the cluster being labelled
var _fq: PackedInt32Array = PackedInt32Array()        ## flood queue, local indices
var _rsum: PackedVector3Array = PackedVector3Array()  ## per label: sum of cell centre dirs
var _rwt: PackedFloat32Array = PackedFloat32Array()   ## per label: sum of weights, then the mean
var _rcnt: PackedInt32Array = PackedInt32Array()
var _adj_out: PackedByteArray = PackedByteArray()     ## MAX_REG * 8 link_cluster output


func _init() -> void:
	super()
	var _r: int = _pm.resize(CS * CS)
	_r = _fq.resize(CS * CS)
	_r = _rsum.resize(MAX_REG)
	_r = _rwt.resize(MAX_REG)
	_r = _rcnt.resize(MAX_REG)
	_r = _adj_out.resize(MAX_REG * 8)


## First cell (i, j lowest) of cluster `c`.
static func cell0(c: int) -> int:
	return ((c >> 8) * N + ((c >> 4) & 15) * CS) * N + (c & 15) * CS


## Labels cluster `c` in mask slot `sl` under slope limit `lq`; returns the number of fragments found (labels in
## use = min(result, MAX_REG)). Region means: reg_dir / reg_weight.
func label_cluster(sl: int, c: int, lq: int) -> int:
	var off: int = sl * CELLS
	var c0: int = cell0(c)
	for y: int in CS:
		for x: int in CS:
			var cell: int = c0 + y * N + x
			label[off + cell] = NO_REGION
			_pm[y * CS + x] = 1 if passable(cell, lq) else 0
	for k: int in MAX_REG:
		_rsum[k] = Vector3.ZERO
		_rwt[k] = 0.0
		_rcnt[k] = 0
	var nreg: int = 0
	for li: int in CS * CS:
		if _pm[li] == 0 or label[off + c0 + (li >> 4) * N + (li & 15)] != NO_REGION:
			continue
		_flood(off, c0, li, mini(nreg, MAX_REG - 1))
		nreg += 1
	for k: int in mini(nreg, MAX_REG):
		_rsum[k] = _rsum[k].normalized()
		_rwt[k] = _rwt[k] / float(maxi(1, _rcnt[k]))
	return nreg


func _flood(off: int, c0: int, seed: int, lab: int) -> void:
	label[off + c0 + (seed >> 4) * N + (seed & 15)] = lab
	_fq[0] = seed
	var head: int = 0
	var tail: int = 1
	var sx: int = 0
	var sy: int = 0
	var sw: int = 0
	while head < tail:
		var li: int = _fq[head]
		head += 1
		var x: int = li & 15
		var y: int = li >> 4
		sx += x
		sy += y
		sw += weights[c0 + y * N + x]
		for k: int in 8:
			var nx: int = x + _DX[k]
			var ny: int = y + _DY[k]
			if nx < 0 or nx >= CS or ny < 0 or ny >= CS:
				continue
			var nl: int = ny * CS + nx
			if _pm[nl] == 0 or (k >= 4 and (_pm[y * CS + nx] == 0 or _pm[ny * CS + x] == 0)):
				continue
			var nc: int = off + c0 + ny * N + nx
			if label[nc] == NO_REGION:
				label[nc] = lab
				_fq[tail] = nl
				tail += 1
	_rcnt[lab] += tail
	_rwt[lab] += float(sw)
	var mid: int = c0 + roundi(float(sy) / float(tail)) * N + roundi(float(sx) / float(tail))
	_rsum[lab] += center_dir(mid) * float(tail)


## Adjacency of cluster `c`'s regions (labels current for c and its neighbours) toward each cluster neighbour
## `nbr8[k]`: bit r of adj_out(lab * 8 + k) = region lab touches region r of nbr8[k]. Returns orphan pairs (cells
## adjacent across the border whose cluster is not in nbr8; 0 unless the neighbour tables disagree).
func link_cluster(sl: int, c: int, lq: int, nbr8: PackedInt32Array) -> int:
	var off: int = sl * CELLS
	var c0: int = cell0(c)
	var orphans: int = 0
	_adj_out.fill(0)
	for y: int in CS:
		var step: int = 1 if y == 0 or y == CS - 1 else CS - 1
		for x: int in range(0, CS, step):
			var cell: int = c0 + y * N + x
			var lab: int = label[off + cell]
			if lab == NO_REGION:
				continue
			neighbours(cell)
			var open: int = 0
			for k: int in 8:
				var n: int = nb[k]
				if n < 0 or not passable(n, lq):
					continue
				if k < 4:
					open |= 1 << k
				elif ((open >> (k & 1)) & 1) == 0 or ((open >> (2 + ((k >> 1) & 1))) & 1) == 0:
					continue
				var b: int = cluster_of(n)
				if b == c:
					continue
				var m: int = nbr8.find(b)
				var nl: int = label[off + n]
				if m < 0 or nl >= MAX_REG:
					orphans += 1
					continue
				_adj_out[lab * 8 + m] = _adj_out[lab * 8 + m] | (1 << nl)
	return orphans


func reg_dir(k: int) -> Vector3:
	return _rsum[k]


func reg_weight(k: int) -> float:
	return _rwt[k]


func adj_out(i: int) -> int:
	return _adj_out[i]
