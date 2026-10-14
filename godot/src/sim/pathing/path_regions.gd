class_name PathRegions extends RefCounted
## Region graph of the path grid (03 s3.6 hierarchy): 6 x 16^2 clusters of 16 x 16 cells, each split into its
## connected passable regions (8-connectivity with the corner rule, inside the cluster) per request-mask slot.
## Region node = cluster * MAX_REG + label; adjacency = bit r of _adj[(region) * 8 + k] when the region touches
## region r of cluster neighbour k across the border (corner rule applied). A cluster with more than MAX_REG
## fragments folds the rest into label OVERFLOW (a superset). Labels live in PathSearch.label and are computed by
## PathLabel on its own arrays (no cross-object packed writes). Built lazily per (slot, cluster) against a per-cluster version that a
## passability flip bumps for the cell's cluster and its 8 neighbours. Base of PathClusters (the region search).

const CN: int = 16                          ## clusters per face edge
const CS: int = 16                          ## cells per cluster edge (PathGrid.N / CN)
const CLUSTERS: int = PathSearch.CLUSTERS
const MAX_REG: int = PathSearch.MAX_REG
const REGIONS: int = PathSearch.REGIONS
const OVERFLOW: int = MAX_REG - 1
const MASK_SLOTS: int = PathSearch.MASK_SLOTS
const BUILD_COST: int = 40                  ## expansion units charged per cluster label build (S-NAV-1 calibration)
const LINK_COST: int = 20                   ## expansion units charged per cluster link build (S-NAV-1 calibration)
const _REGION_STATE: PackedStringArray = ["builds", "overflows", "orphans", "_slot_mask", "_slot_next", "_cver", "_ever",
	"_lab_ver", "_edge_ver", "_nreg"]

var grid: PathLabel
var builds: int = 0                         ## label + link builds so far
var overflows: int = 0                      ## label builds that folded fragments into OVERFLOW
var orphans: int = 0                        ## adjacent cells whose clusters are not cluster neighbours (must stay 0)
var _slot_mask: PackedInt32Array = PackedInt32Array()
var _slot_next: int = 0
var _nbr: PackedInt32Array = PackedInt32Array()     ## CLUSTERS * 8 cluster neighbours, -1 = missing (cube corner)
var _cver: PackedInt32Array = PackedInt32Array()    ## per cluster: bumped by a flip inside it (labels)
var _ever: PackedInt32Array = PackedInt32Array()    ## per cluster: bumped by a flip inside it or a neighbour (links)
var _lab_ver: PackedInt32Array = PackedInt32Array() ## MASK_SLOTS * CLUSTERS: _cver at label build, -1 none
var _edge_ver: PackedInt32Array = PackedInt32Array()
var _nreg: PackedByteArray = PackedByteArray()      ## MASK_SLOTS * CLUSTERS
var _adj: PackedByteArray = PackedByteArray()       ## MASK_SLOTS * REGIONS * 8
var _rdir: PackedVector3Array = PackedVector3Array()   ## MASK_SLOTS * REGIONS, sum of cell centre dirs
var _rw: PackedFloat32Array = PackedFloat32Array()     ## MASK_SLOTS * REGIONS, mean weight
var _nbr8: PackedInt32Array = PackedInt32Array()    ## link_cluster argument scratch
var _rev: int = 0                                   ## bumped by every _adj / _rdir / _rw write; keys the S4 blocks
var _blob_rev: int = -1
var _blobs: PackedByteArray = PackedByteArray()     ## compressed _adj, _rdir, _rw, concatenated as written


func _init(g: PathLabel) -> void:
	grid = g
	var _r: int = _slot_mask.resize(MASK_SLOTS)
	_slot_mask.fill(-1)
	_r = _nbr.resize(CLUSTERS * 8)
	_nbr.fill(-1)
	_r = _cver.resize(CLUSTERS)
	_r = _ever.resize(CLUSTERS)
	_r = _lab_ver.resize(MASK_SLOTS * CLUSTERS)
	_lab_ver.fill(-1)
	_r = _edge_ver.resize(MASK_SLOTS * CLUSTERS)
	_edge_ver.fill(-1)
	_r = _nreg.resize(MASK_SLOTS * CLUSTERS)
	_r = _adj.resize(MASK_SLOTS * REGIONS * 8)
	_r = _rdir.resize(MASK_SLOTS * REGIONS)
	_r = _rw.resize(MASK_SLOTS * REGIONS)
	_r = _nbr8.resize(8)
	for c: int in CLUSTERS:
		var nb: PackedInt32Array = Sphere.neighbours8(c, CN)
		for k: int in nb.size():
			_nbr[c * 8 + k] = nb[k]


## Drops every built region graph (new weights or terrain).
func invalidate() -> void:
	_lab_ver.fill(-1)
	_edge_ver.fill(-1)


## Mask slot for `mask` (assigned round-robin; a reused slot drops its graph).
func slot_for(mask: int) -> int:
	for s: int in MASK_SLOTS:
		if _slot_mask[s] == mask:
			return s
	var s2: int = _slot_next
	_slot_next = (_slot_next + 1) % MASK_SLOTS
	_slot_mask[s2] = mask
	for c: int in CLUSTERS:
		_lab_ver[s2 * CLUSTERS + c] = -1
		_edge_ver[s2 * CLUSTERS + c] = -1
	return s2


## Builds every cluster of `mask`'s slot now (map load), so queries pay no lazy builds.
func prepare(mask: int) -> void:
	var s: int = slot_for(mask)
	for c: int in CLUSTERS:
		var _u: int = ensure_links(s, c)


## A passability flip at `cell`: its cluster relabels on next use; it and its 8 neighbours relink (labels of the
## flipped cluster may renumber, and the neighbours' adjacency bits name them).
func on_flip(cell: int) -> void:
	var c: int = PathGrid.cluster_of(cell)
	_cver[c] += 1
	_ever[c] += 1
	for k: int in 8:
		var n: int = _nbr[c * 8 + k]
		if n >= 0:
			_ever[n] += 1


## Region node of `cell` in slot `sl` (labels built if needed), or -1 for a blocked cell.
func region_of(cell: int, sl: int) -> int:
	var c: int = PathGrid.cluster_of(cell)
	var _u: int = ensure_labels(sl, c)
	var lab: int = grid.label_at(sl * PathGrid.CELLS + cell)
	return -1 if lab == PathSearch.NO_REGION else c * MAX_REG + lab


func region_count(c: int, sl: int) -> int:
	var _u: int = ensure_links(sl, c)
	return _nreg[sl * CLUSTERS + c]


## Bits of the regions of cluster neighbour k that `region` touches (tests and tools).
func adjacency(region: int, k: int, sl: int) -> int:
	var _u: int = ensure_links(sl, region >> 3)
	return _adj[(sl * REGIONS + region) * 8 + k]


func neighbour(c: int, k: int) -> int:
	return _nbr[c * 8 + k]


## Labels of cluster `c` current for slot `sl`; returns the units spent (0 or BUILD_COST).
func ensure_labels(sl: int, c: int) -> int:
	if _lab_ver[sl * CLUSTERS + c] == _cver[c]:
		return 0
	var n: int = grid.label_cluster(sl, c, PathGrid.limit_q_of(_slot_mask[sl]))
	if n > MAX_REG:
		overflows += 1
	_nreg[sl * CLUSTERS + c] = mini(n, MAX_REG)
	for k: int in mini(n, MAX_REG):
		_rdir[sl * REGIONS + c * MAX_REG + k] = grid.reg_dir(k)
		_rw[sl * REGIONS + c * MAX_REG + k] = grid.reg_weight(k)
	_lab_ver[sl * CLUSTERS + c] = _cver[c]
	_rev += 1
	return BUILD_COST


## Labels of `c` and its neighbours plus c's adjacency current for slot `sl`; returns the units spent.
func ensure_links(sl: int, c: int) -> int:
	var cost: int = ensure_labels(sl, c)
	if _edge_ver[sl * CLUSTERS + c] == _ever[c]:
		return cost
	for k: int in 8:
		if _nbr[c * 8 + k] >= 0:
			cost += ensure_labels(sl, _nbr[c * 8 + k])
	for k: int in 8:
		_nbr8[k] = _nbr[c * 8 + k]
	orphans += grid.link_cluster(sl, c, PathGrid.limit_q_of(_slot_mask[sl]), _nbr8)
	var base: int = (sl * REGIONS + c * MAX_REG) * 8
	for i: int in MAX_REG * 8:
		_adj[base + i] = grid.adj_out(i)
	_edge_ver[sl * CLUSTERS + c] = _ever[c]
	_rev += 1
	builds += 1
	return cost + LINK_COST


## S4 (TA-50): build versions and counters as they are, the region data (_adj, _rdir, _rw) zstd-compressed and
## cached until the next build. The labels are PathSearch's (grid.write_state).
func write_state(buf: StreamPeerBuffer) -> void:
	StateIO.put_props(buf, self, _REGION_STATE)
	if _blob_rev != _rev:
		var b: StreamPeerBuffer = StreamPeerBuffer.new()
		PathGrid.put_z(b, _adj)
		PathGrid.put_z(b, _rdir.to_byte_array())
		PathGrid.put_z(b, _rw.to_byte_array())
		_blobs = b.data_array
		_blob_rev = _rev
	buf.put_var(_blobs)


## Inverse of write_state; false on malformed bytes.
func read_state(buf: StreamPeerBuffer) -> bool:
	if not StateIO.get_props(buf, self, _REGION_STATE) or _slot_mask.size() != MASK_SLOTS or _cver.size() != CLUSTERS:
		return false
	if _ever.size() != CLUSTERS or _lab_ver.size() != MASK_SLOTS * CLUSTERS or _edge_ver.size() != MASK_SLOTS * CLUSTERS:
		return false
	var bv: Variant = buf.get_var()
	if typeof(bv) != TYPE_PACKED_BYTE_ARRAY or _nreg.size() != MASK_SLOTS * CLUSTERS:
		return false
	var b: StreamPeerBuffer = StreamPeerBuffer.new()
	b.data_array = bv
	var adj: PackedByteArray = PathGrid.get_z(b, MASK_SLOTS * REGIONS * 8)
	var rdir: PackedByteArray = PathGrid.get_z(b, MASK_SLOTS * REGIONS * 12)
	var rw: PackedByteArray = PathGrid.get_z(b, MASK_SLOTS * REGIONS * 4)
	if adj.is_empty() or rdir.is_empty() or rw.is_empty():
		return false
	_adj = adj
	_rdir = rdir.to_vector3_array()
	_rw = rw.to_float32_array()
	_rev += 1
	return true
