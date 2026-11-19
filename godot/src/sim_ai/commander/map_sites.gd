class_name MapSites extends RefCounted
## The static geometry the location tokens resolve on: the map's start slots, Ore Fields and Cold Traps from
## `features.json` (02 s9, R0 B.2; public map data, known to every player in the lobby: not a vision matter). A node with
## `slot` = the player's slot is that player's home node (file order gives `home_N`); `slot` < 0 is neutral (R0 B.6,
## O-5: in 1v1 the slots are 0 and 2). Directions are unit vectors; `Vector3.ZERO` means "none". Session configuration.

var _slot_dir: PackedVector3Array = PackedVector3Array()
var _slot_ok: PackedByteArray = PackedByteArray()
var _field_dir: PackedVector3Array = PackedVector3Array()
var _field_slot: PackedInt32Array = PackedInt32Array()
var _trap_dir: PackedVector3Array = PackedVector3Array()
var _trap_slot: PackedInt32Array = PackedInt32Array()


## Null without a `start_slots` array.
static func from_features(d: Dictionary) -> MapSites:
	var slots: Variant = d.get("start_slots", null)
	if not (slots is Array):
		return null
	var slot_list: Array = slots
	if slot_list.is_empty():
		return null
	var m: MapSites = MapSites.new()
	for s: Variant in slot_list:
		var sd: Dictionary = s if s is Dictionary else {}
		var i: int = roundi(Def.num(sd.get("slot", -1)))
		if i < 0 or i >= PlayerTable.SLOTS:
			continue
		if m._slot_dir.size() <= i:
			var _a: int = m._slot_dir.resize(i + 1)
			var _b: int = m._slot_ok.resize(i + 1)
		m._slot_dir[i] = _vec(sd.get("dir", []))
		m._slot_ok[i] = 1
	var nodes: Variant = d.get("nodes", [])
	var node_list: Array = nodes if nodes is Array else []
	for n: Variant in node_list:
		var nd: Dictionary = n if n is Dictionary else {}
		var kind: String = str(nd.get("kind", ""))
		var dir: Vector3 = _vec(nd.get("dir", []))
		if dir == Vector3.ZERO:
			continue
		var slot: int = roundi(Def.num(nd.get("slot", -1)))
		if kind == "ore_field":
			var _c: bool = m._field_dir.push_back(dir)
			var _e: bool = m._field_slot.push_back(slot)
		elif kind == "cold_trap":
			var _f: bool = m._trap_dir.push_back(dir)
			var _g: bool = m._trap_slot.push_back(slot)
	return m


func slot_count() -> int:
	return _slot_dir.size()


func has_slot(slot: int) -> bool:
	return slot >= 0 and slot < _slot_ok.size() and _slot_ok[slot] != 0


## Start position (unit direction) of `slot`, ZERO when the map has none.
func slot_dir(slot: int) -> Vector3:
	return _slot_dir[slot] if has_slot(slot) else Vector3.ZERO


## The `nth` (from 1) Ore Field of `slot`'s home, in file order; ZERO when there are fewer.
func home_field(slot: int, nth: int) -> Vector3:
	var k: int = 0
	for i: int in _field_dir.size():
		if _field_slot[i] == slot:
			k += 1
			if k == nth:
				return _field_dir[i]
	return Vector3.ZERO


## The first Cold Trap of `slot`'s home; ZERO when none.
func home_trap(slot: int) -> Vector3:
	for i: int in _trap_dir.size():
		if _trap_slot[i] == slot:
			return _trap_dir[i]
	return Vector3.ZERO


## The neutral Ore Field nearest to `from`; ZERO when the map has none.
func contested(from: Vector3) -> Vector3:
	var best: Vector3 = Vector3.ZERO
	var best_d: float = INF
	for i: int in _field_dir.size():
		if _field_slot[i] >= 0:
			continue
		var a: float = from.angle_to(_field_dir[i])
		if a < best_d:
			best_d = a
			best = _field_dir[i]
	return best


static func _vec(a: Variant) -> Vector3:
	var l: Array = a if a is Array else []
	if l.size() != 3:
		return Vector3.ZERO
	var v: Vector3 = Vector3(Def.num(l[0]), Def.num(l[1]), Def.num(l[2]))
	return v.normalized() if v.length_squared() > 0.0 else Vector3.ZERO
