class_name SelectionSet extends RefCounted
## Ordered set of selected entity ids (client-side). Commands go out in chunks of OrderSpec.WIRE_MAX_IDS.

signal changed

var _ids: PackedInt32Array = PackedInt32Array()


func ids() -> PackedInt32Array:
	return _ids


func size() -> int:
	return _ids.size()


func has(id: int) -> bool:
	return _ids.has(id)


func set_ids(v: PackedInt32Array) -> void:
	_ids = PackedInt32Array()
	for id: int in v:
		if not _ids.has(id):
			var _a: bool = _ids.append(id)
	changed.emit()


func add(id: int) -> void:
	if not _ids.has(id):
		var _a: bool = _ids.append(id)
		changed.emit()


func toggle(id: int) -> void:
	var i: int = _ids.find(id)
	if i >= 0:
		_ids.remove_at(i)
	else:
		var _a: bool = _ids.append(id)
	changed.emit()


func clear() -> void:
	if not _ids.is_empty():
		_ids = PackedInt32Array()
		changed.emit()


## Drop ids that are no longer alive.
func prune(alive: Callable) -> void:
	var keep: PackedInt32Array = PackedInt32Array()
	for id: int in _ids:
		if alive.call(id):
			var _a: bool = keep.append(id)
	if keep.size() != _ids.size():
		_ids = keep
		changed.emit()


## Chunks of at most OrderSpec.WIRE_MAX_IDS for issuing commands.
func chunks() -> Array[PackedInt32Array]:
	var out: Array[PackedInt32Array] = []
	var i: int = 0
	while i < _ids.size():
		out.append(_ids.slice(i, i + OrderSpec.WIRE_MAX_IDS))
		i += OrderSpec.WIRE_MAX_IDS
	return out
