class_name MapRelays extends RefCounted
## GD-51 (R0 B.30 A-150): the Relay Stations a baked map carries, spawned as finished neutral structures by `SimWorld.load_map`.
## Keys read from `<map_dir>/features.json`, in this order and each in file order: `nodes[]` entries with `kind` "relay_station"
## (the 02 s9.1 template `ring_features`, field `dir`), then `neutral_structures[]` entries with `def` "relay_station"
## (`dir`, optional `facing_dir`). Load time only: no state of its own, nothing runs per tick, no new saved section.

const RELAY: StringName = &"relay_station"
const NEUTRAL: int = 255


## Spawns one Relay Station (owner and team 255, F_BUILDING clear, `up` = radial `dir` (A-157), resting on the surface) per
## entry; returns how many. 0 when the file is missing, malformed, the def is unknown or the map has none.
static func spawn(map_dir: String, defs: WorldDefs, terrain: Terrain, store: EntityStore, applier: CommandApplier, tick: int) -> int:
	var def: int = defs.content.entity_index.get(RELAY, -1)
	if def < 0:
		return 0
	var n: int = 0
	for e: Dictionary in _entries(map_dir):
		var dir: Vector3 = _vec(e.get("dir", null))
		if dir.length_squared() == 0.0:
			continue
		dir = dir.normalized()
		var up: Vector3 = dir   # A-157: radial, as Build.stamp (sim/build B10), not the terrain normal
		var face: Vector3 = _vec(e.get("facing_dir", null))
		var fwd: Vector3 = face - up * face.dot(up)
		if fwd.is_zero_approx():
			fwd = Sphere.tangent_frame(dir).x
		var s: int = applier.spawn(def, NEUTRAL, NEUTRAL, terrain.surface_point(dir), Vector3.ZERO, fwd, tick)
		if s < 0:
			break
		store.up[s] = up
		store.fwd[s] = (fwd - up * fwd.dot(up)).normalized()
		n += 1
	return n


# The relay entries of both blocks as one list, file order.
static func _entries(map_dir: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var f: FileAccess = FileAccess.open(map_dir + "/features.json", FileAccess.READ)
	if f == null:
		return out
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if not (parsed is Dictionary):
		return out
	var d: Dictionary = parsed
	_collect(d.get("nodes", null), "kind", out)
	_collect(d.get("neutral_structures", null), "def", out)
	return out


static func _collect(block: Variant, key: String, out: Array[Dictionary]) -> void:
	if not (block is Array):
		return
	var list: Array = block
	for item: Variant in list:
		if item is Dictionary:
			var e: Dictionary = item
			if e.get(key, "") == String(RELAY):
				out.append(e)


static func _vec(v: Variant) -> Vector3:
	if not (v is Array):
		return Vector3.ZERO
	var a: Array = v
	if a.size() != 3:
		return Vector3.ZERO
	return Vector3(Def.num(a[0]), Def.num(a[1]), Def.num(a[2]))
