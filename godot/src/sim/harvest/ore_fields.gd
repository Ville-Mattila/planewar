class_name OreFields extends RefCounted
## The Ore Fields of a match (GD-12; 02 s8.2): centre direction, `capacity`, `regen_per_s`, `radius_m`, `max_miners` and
## the Ore left in each, in packed arrays indexed by field (the file order of the map's `ore_field` nodes). The numbers are
## the map recipe's (02 s9), not constants. Only `amount` changes; the table is saved whole so a restored world needs no
## loader (S4). `miners` is derived by `Harvest` each step and never saved. No Nodes, no signals, no RNG.

const _MAX_FIELDS: int = 64                       ## sanity bound on a read table (a recipe has a handful)

var dirs: PackedVector3Array = PackedVector3Array()
var capacity: PackedInt32Array = PackedInt32Array()
var amount: PackedFloat32Array = PackedFloat32Array()      ## Ore left, 0..capacity
var regen_per_s: PackedFloat32Array = PackedFloat32Array()
var radius_m: PackedFloat32Array = PackedFloat32Array()
var max_miners: PackedInt32Array = PackedInt32Array()
var miners: PackedInt32Array = PackedInt32Array()          ## derived: Harvesters holding a mining slot (Harvest rebuilds it)

var _cos_r: PackedFloat32Array = PackedFloat32Array()      ## derived: cos(radius_m / R), the `field_at` threshold


## Appends a full field at unit direction `dir`; returns its index.
func add(dir: Vector3, cap: int, regen_rate: float, radius: float, miners_max: int) -> int:
	var i: int = dirs.size()
	var _a: bool = dirs.push_back(dir.normalized())
	var _b: bool = capacity.push_back(cap)
	var _c: bool = amount.push_back(float(cap))
	var _d: bool = regen_per_s.push_back(regen_rate)
	var _e: bool = radius_m.push_back(radius)
	var _f: bool = max_miners.push_back(miners_max)
	var _g: bool = miners.push_back(0)
	var _h: bool = _cos_r.push_back(cos(radius / Sphere.PLANET_RADIUS))
	return i


## Adds the `ore_field` entries of a map's `features.json` `nodes` array, in file order; returns how many.
func load_nodes(nodes: Array) -> int:
	var n: int = 0
	for item: Variant in nodes:
		var d: Dictionary = item if item is Dictionary else {}
		if d.get("kind", "") != "ore_field":
			continue
		var v: Array = d.get("dir", [])
		if v.size() != 3:
			continue
		var dir: Vector3 = Vector3(Def.num(v[0]), Def.num(v[1]), Def.num(v[2]))
		var _i: int = add(dir, roundi(Def.num(d.get("capacity", 0))), Def.num(d.get("regen_per_s", 0.0)),
				Def.num(d.get("radius_m", 0.0)), roundi(Def.num(d.get("max_miners", 1))))
		n += 1
	return n


func count() -> int:
	return dirs.size()


## Whole Ore left in field `i` (`SimView.field_remaining`); 0 for an index out of range.
func remaining(i: int) -> int:
	return roundi(amount[i]) if i >= 0 and i < amount.size() else 0


func capacity_of(i: int) -> int:
	return capacity[i]


func radius_of(i: int) -> float:
	return radius_m[i]


func max_miners_of(i: int) -> int:
	return max_miners[i]


func miners_of(i: int) -> int:
	return miners[i]


func dir_of(i: int) -> Vector3:
	return dirs[i]


## The nearest field (by great-circle distance to its centre) whose `radius_m` contains `dir`; -1 for none.
func field_at(dir: Vector3) -> int:
	var best: int = -1
	var best_dot: float = -2.0
	for i: int in dirs.size():
		var d: float = dirs[i].dot(dir)
		if d > best_dot and d >= _cos_r[i]:
			best = i
			best_dot = d
	return best


## 02 s8.2: each field below its capacity gains `regen_per_s * dt`, never past it. The caller skips this at Core Exposure.
func regen(dt: float) -> void:
	for i: int in amount.size():
		var a: float = amount[i]
		var c: float = float(capacity[i])
		if a < c:
			amount[i] = minf(c, a + regen_per_s[i] * dt)


func write_state(buf: StreamPeerBuffer) -> void:
	buf.put_var(dirs.size())
	buf.put_var(dirs)
	buf.put_var(capacity)
	buf.put_var(amount)
	buf.put_var(regen_per_s)
	buf.put_var(radius_m)
	buf.put_var(max_miners)


## Replaces the table; false (the table untouched) on missing bytes, a type mismatch or arrays of different lengths.
func read_state(buf: StreamPeerBuffer) -> bool:
	if buf.get_available_bytes() <= 0:
		return false
	var nv: Variant = buf.get_var()
	if typeof(nv) != TYPE_INT:
		return false
	var n: int = nv
	if n < 0 or n > _MAX_FIELDS:
		return false
	var got: Array = []
	for t: int in [TYPE_PACKED_VECTOR3_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_FLOAT32_ARRAY,
			TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_INT32_ARRAY]:
		if buf.get_available_bytes() <= 0:
			return false
		var v: Variant = buf.get_var()
		if typeof(v) != t or StateIO.size_of(v) != n:
			return false
		got.append(v)
	dirs = got[0]
	capacity = got[1]
	amount = got[2]
	regen_per_s = got[3]
	radius_m = got[4]
	max_miners = got[5]
	var _r: int = miners.resize(n)
	miners.fill(0)
	var _c: int = _cos_r.resize(n)
	for i: int in n:
		_cos_r[i] = cos(radius_m[i] / Sphere.PLANET_RADIUS)
	return true
