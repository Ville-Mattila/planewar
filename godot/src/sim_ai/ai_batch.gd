class_name AiBatch extends RefCounted
## The AI-driven entity ids of one class (05 s4.3), kept sorted by slot so iteration order is a function of state alone.
## `due` is the preallocated scratch the driver fills with the ids that think this tick.

var ids: PackedInt32Array = PackedInt32Array()
var due: PackedInt32Array = PackedInt32Array()


## Inserts `id` keeping slot order; false if its slot is already present.
func add(id: int) -> bool:
	var s: int = EntityId.slot(id)
	var lo: int = 0
	var hi: int = ids.size()
	while lo < hi:
		var mid: int = (lo + hi) >> 1
		if EntityId.slot(ids[mid]) < s:
			lo = mid + 1
		else:
			hi = mid
	if lo < ids.size() and EntityId.slot(ids[lo]) == s:
		return false
	var _r: int = ids.insert(lo, id)
	var _e: int = due.resize(ids.size())
	return true


## Removes the entry in `id`'s slot; false if absent.
func remove(id: int) -> bool:
	var s: int = EntityId.slot(id)
	for i: int in ids.size():
		if EntityId.slot(ids[i]) == s:
			ids.remove_at(i)
			var _e: int = due.resize(ids.size())
			return true
	return false
