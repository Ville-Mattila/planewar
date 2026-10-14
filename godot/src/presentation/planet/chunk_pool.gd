class_name ChunkPool extends RefCounted
## Fixed pool of MeshInstance3D + ArrayMesh pairs (03 s7.3): all allocated up front under `parent`, never
## freed while the pool lives, handed out by slot index. A released slot is hidden and its mesh cleared only
## when it is rebuilt, so acquire/release never allocate Nodes or resources.

var parent: Node3D
var instances: Array[MeshInstance3D] = []
var meshes: Array[ArrayMesh] = []
var allocated: int = 0                       ## Nodes created by this pool (== capacity after _init)
var acquires: int = 0
var _free: PackedInt32Array = PackedInt32Array()


func _init(p_parent: Node3D, slots: int, material: Material) -> void:
	parent = p_parent
	for k: int in slots:
		var mesh: ArrayMesh = ArrayMesh.new()
		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.name = "Chunk%03d" % k
		mi.mesh = mesh
		mi.material_override = material
		mi.visible = false
		parent.add_child(mi)
		instances.append(mi)
		meshes.append(mesh)
		allocated += 1
	for k: int in slots:
		var _a: bool = _free.push_back(slots - 1 - k)


func capacity() -> int:
	return instances.size()


func free_count() -> int:
	return _free.size()


func in_use() -> int:
	return instances.size() - _free.size()


## A free slot (lowest index first), or -1 when the pool is exhausted.
func acquire() -> int:
	if _free.is_empty():
		return -1
	var slot: int = _free[_free.size() - 1]
	_free.remove_at(_free.size() - 1)
	acquires += 1
	return slot


## Hides the slot's instance and returns it to the free list.
func release(slot: int) -> void:
	instances[slot].visible = false
	var _a: bool = _free.push_back(slot)


func set_visible(slot: int, on: bool) -> void:
	instances[slot].visible = on
