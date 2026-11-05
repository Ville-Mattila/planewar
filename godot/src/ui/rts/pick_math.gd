class_name PickMath extends RefCounted
## Pure picking maths (docs/06 s7.2). Candidates are given in screen du; the caller projects them.
## Nearest centre inside the class radius wins; candidates within pick_tie_du of the nearest are tied and
## break by category (own unit > own structure > other), then by camera depth.

enum PickDevice { POINTER, TOUCH, GAMEPAD }
enum Category { OWN_UNIT, OWN_STRUCTURE, OTHER }


static func radius_du(input: PickDevice) -> float:
	match input:
		PickDevice.TOUCH:
			return RtsParams.param("pick_radius_touch_du")
		PickDevice.GAMEPAD:
			return RtsParams.param("pick_radius_gamepad_du")
	return RtsParams.param("pick_radius_pointer_du")


## Index into `screen` of the picked candidate, -1 if none within `input`'s radius.
static func pick(cursor: Vector2, screen: PackedVector2Array, category: PackedInt32Array, depth: PackedFloat32Array, input: PickDevice) -> int:
	var rad: float = radius_du(input)
	var best_d: float = INF
	for i: int in screen.size():
		var d: float = cursor.distance_to(screen[i])
		if d <= rad and d < best_d:
			best_d = d
	if best_d == INF:
		return -1
	var limit: float = minf(best_d + RtsParams.param("pick_tie_du"), rad)
	var best: int = -1
	for i: int in screen.size():
		if cursor.distance_to(screen[i]) > limit:
			continue
		if best < 0 or _better(i, best, category, depth):
			best = i
	return best


static func _better(a: int, b: int, category: PackedInt32Array, depth: PackedFloat32Array) -> bool:
	if category[a] != category[b]:
		return category[a] < category[b]
	return depth[a] < depth[b]


## Paint-circle radius in du after `held_s` seconds of holding: paint_min -> paint_max over paint_grow_s.
static func paint_radius_du(held_s: float) -> float:
	var t: float = clampf(held_s / RtsParams.param("paint_grow_s"), 0.0, 1.0)
	return lerpf(RtsParams.param("paint_min_du"), RtsParams.param("paint_max_du"), t)


## Box select: units only; structures only when the box holds no unit. `is_unit[i]` flags ids[i].
static func box_filter(ids: PackedInt32Array, is_unit: PackedByteArray) -> PackedInt32Array:
	var units: PackedInt32Array = PackedInt32Array()
	var structs: PackedInt32Array = PackedInt32Array()
	for i: int in ids.size():
		if is_unit[i] != 0:
			var _a: bool = units.append(ids[i])
		else:
			var _b: bool = structs.append(ids[i])
	return units if not units.is_empty() else structs


## Same-type select: ids whose def equals `def_id`.
static func same_type(ids: PackedInt32Array, defs: PackedInt32Array, def_id: int) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for i: int in ids.size():
		if defs[i] == def_id:
			var _a: bool = out.append(ids[i])
	return out
