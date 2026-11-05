class_name ControlGroups extends RefCounted
## Client-side control groups, per match; they hold entity ids only, so they survive possession (06 s7.2).

var _groups: Array[PackedInt32Array] = []


func _init() -> void:
	for _i: int in int(RtsParams.param("group_count")):
		_groups.append(PackedInt32Array())


func count() -> int:
	return _groups.size()


func get_group(slot: int) -> PackedInt32Array:
	return _groups[slot] if slot >= 0 and slot < _groups.size() else PackedInt32Array()


func assign(slot: int, ids: PackedInt32Array) -> void:
	if slot >= 0 and slot < _groups.size():
		_groups[slot] = ids.duplicate()


func add_to(slot: int, ids: PackedInt32Array) -> void:
	if slot < 0 or slot >= _groups.size():
		return
	var g: PackedInt32Array = _groups[slot]
	for id: int in ids:
		if not g.has(id):
			var _a: bool = g.append(id)
	_groups[slot] = g


## Recall: living members of the group (dead ids are dropped from the group too).
func recall(slot: int, alive: Callable) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for id: int in get_group(slot):
		if alive.call(id):
			var _a: bool = out.append(id)
	if slot >= 0 and slot < _groups.size():
		_groups[slot] = out.duplicate()
	return out


func clear() -> void:
	for i: int in _groups.size():
		_groups[i] = PackedInt32Array()
