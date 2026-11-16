class_name IceNodes extends RefCounted
## The Cold Traps of a match (GD-14; 02 s8.3, s9): centre direction, `capacity`, `rate_per_s`, `radius_m` and the Ice left
## in each, in packed arrays indexed by node (the file order of the map's `cold_trap` nodes). The numbers are the map
## recipe's, not constants. Ice does not regenerate: only `amount` changes, and only through `IceExtract.step`. The table is
## saved whole so a restored world needs no loader (S4). No Nodes, no signals, no RNG.

const _MAX_NODES: int = 64                        ## sanity bound on a read table (a recipe has about twenty)

var dirs: PackedVector3Array = PackedVector3Array()
var capacity: PackedInt32Array = PackedInt32Array()
var amount: PackedFloat32Array = PackedFloat32Array()      ## Ice left, 0..capacity
var rate_per_s: PackedFloat32Array = PackedFloat32Array()
var radius_m: PackedFloat32Array = PackedFloat32Array()

var _cos_r: PackedFloat32Array = PackedFloat32Array()      ## derived: cos(radius_m / R), the `node_at` threshold


## Appends a full node at unit direction `dir`; returns its index.
func add(dir: Vector3, cap: int, rate: float, radius: float) -> int:
	var i: int = dirs.size()
	var _a: bool = dirs.push_back(dir.normalized())
	var _b: bool = capacity.push_back(cap)
	var _c: bool = amount.push_back(float(cap))
	var _d: bool = rate_per_s.push_back(rate)
	var _e: bool = radius_m.push_back(radius)
	var _f: bool = _cos_r.push_back(cos(radius / Sphere.PLANET_RADIUS))
	return i


## Replaces the table with the `cold_trap` nodes of `<map_dir>/features.json` (a second call never doubles it); returns
## how many, -1 when the file is missing or is not a JSON object with a `nodes` array.
func load_map_dir(map_dir: String) -> int:
	clear()
	var f: FileAccess = FileAccess.open(map_dir + "/features.json", FileAccess.READ)
	if f == null:
		return -1
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if not (parsed is Dictionary):
		return -1
	var d: Dictionary = parsed
	var nodes: Variant = d.get("nodes", null)
	if not (nodes is Array):
		return -1
	var list: Array = nodes
	return load_nodes(list)


func clear() -> void:
	dirs.clear()
	capacity.clear()
	amount.clear()
	rate_per_s.clear()
	radius_m.clear()
	_cos_r.clear()


## Adds the `cold_trap` entries of a map's `features.json` `nodes` array, in file order; returns how many.
func load_nodes(nodes: Array) -> int:
	var n: int = 0
	for item: Variant in nodes:
		var d: Dictionary = item if item is Dictionary else {}
		if d.get("kind", "") != "cold_trap":
			continue
		var v: Array = d.get("dir", [])
		if v.size() != 3:
			continue
		var dir: Vector3 = Vector3(Def.num(v[0]), Def.num(v[1]), Def.num(v[2]))
		var _i: int = add(dir, roundi(Def.num(d.get("capacity", 0))), Def.num(d.get("rate_per_s", 0.0)),
				Def.num(d.get("radius_m", 0.0)))
		n += 1
	return n


func count() -> int:
	return dirs.size()


## Whole Ice left in node `i`; 0 for an index out of range.
func remaining(i: int) -> int:
	return roundi(amount[i]) if i >= 0 and i < amount.size() else 0


func capacity_of(i: int) -> int:
	return capacity[i]


func rate_of(i: int) -> float:
	return rate_per_s[i]


func radius_of(i: int) -> float:
	return radius_m[i]


func dir_of(i: int) -> Vector3:
	return dirs[i]


## The nearest node (by great-circle distance to its centre) whose `radius_m` contains `dir`; -1 for none.
func node_at(dir: Vector3) -> int:
	var best: int = -1
	var best_dot: float = 0.0
	for i: int in dirs.size():
		var d: float = dirs[i].dot(dir)
		if (best < 0 or d > best_dot) and d >= _cos_r[i]:
			best = i
			best_dot = d
	return best


func write_state(buf: StreamPeerBuffer) -> void:
	buf.put_var(dirs.size())
	buf.put_var(dirs)
	buf.put_var(capacity)
	buf.put_var(amount)
	buf.put_var(rate_per_s)
	buf.put_var(radius_m)


## Replaces the table; false (the table untouched) on missing bytes, a type mismatch or arrays of different lengths.
func read_state(buf: StreamPeerBuffer) -> bool:
	if buf.get_available_bytes() <= 0:
		return false
	var nv: Variant = buf.get_var()
	if typeof(nv) != TYPE_INT:
		return false
	var n: int = nv
	if n < 0 or n > _MAX_NODES:
		return false
	var got: Array = []
	for t: int in [TYPE_PACKED_VECTOR3_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_FLOAT32_ARRAY,
			TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT32_ARRAY]:
		if buf.get_available_bytes() <= 0:
			return false
		var v: Variant = buf.get_var()
		if typeof(v) != t or StateIO.size_of(v) != n:
			return false
		got.append(v)
	dirs = got[0]
	capacity = got[1]
	amount = got[2]
	rate_per_s = got[3]
	radius_m = got[4]
	var _c: int = _cos_r.resize(n)
	for i: int in n:
		_cos_r[i] = cos(radius_m[i] / Sphere.PLANET_RADIUS)
	return true
