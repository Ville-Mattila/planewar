class_name FarPools
extends Node3D
## One `_Far` MultiMesh per view class (07 ART-A1, R0 C1-17, 03 s7.9-7.10): entities beyond the individually drawn
## view cap or beyond the `_Far` switch distance draw here, flat team colour from the per-instance colour. About one
## draw per class (<= 8 in the shipped content). Refilled on `EntityViewPool.sync`.

var pools: Array[MultiMeshPool] = []


func setup(classes: EntityClassTable, capacity: int) -> void:
	var mat: ShaderMaterial = PoolMaterials.far_material()
	for g: int in classes.group_count():
		var p: MultiMeshPool = MultiMeshPool.new()
		p.name = String(classes.group_name(g))
		p.setup(PlaceholderMeshes.mesh_for(classes.group_kind(g)), mat, capacity)
		add_child(p)
		pools.append(p)


func begin() -> void:
	for p: MultiMeshPool in pools:
		p.begin()


func push(group: int, xf: Transform3D, color: Color) -> bool:
	return pools[group].push(xf, color)


func commit() -> void:
	for p: MultiMeshPool in pools:
		p.commit()


## Draw calls this frame (pools with at least one instance).
func draw_calls() -> int:
	var n: int = 0
	for p: MultiMeshPool in pools:
		n += p.draw_calls()
	return n


func instance_total() -> int:
	var n: int = 0
	for p: MultiMeshPool in pools:
		n += p.count
	return n
