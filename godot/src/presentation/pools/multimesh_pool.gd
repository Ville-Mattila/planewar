class_name MultiMeshPool
extends MultiMeshInstance3D
## A fixed-capacity MultiMesh (03 s7.10): preallocated at setup, refilled with begin / push / commit each frame,
## drawn as one call. MultiMesh has no per-instance culling in Compatibility (R2 s2.2), so the AABB is the whole
## simulation volume and callers split pools where whole-pool culling pays (projectiles per cube face).

var capacity: int = 0
var count: int = 0   ## instances pushed since begin(), or the live ring size for set_at users


func setup(mesh: Mesh, material: Material, p_capacity: int, use_custom: bool = false) -> void:
	capacity = p_capacity
	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = use_custom
	mm.mesh = mesh
	mm.instance_count = p_capacity
	mm.visible_instance_count = 0
	var half: float = Sphere.MAX_SIM_MAGNITUDE
	mm.custom_aabb = AABB(Vector3(-half, -half, -half), Vector3(half, half, half) * 2.0)
	multimesh = mm
	material_override = material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func begin() -> void:
	count = 0


## False when the pool is full (the instance is dropped).
func push(xf: Transform3D, color: Color, custom: Color = Color.BLACK) -> bool:
	if count >= capacity:
		return false
	multimesh.set_instance_transform(count, xf)
	multimesh.set_instance_color(count, color)
	if multimesh.use_custom_data:
		multimesh.set_instance_custom_data(count, custom)
	count += 1
	return true


## Random-access write for ring users (trails, decals); the caller maintains `count` and calls commit().
func set_at(i: int, xf: Transform3D, color: Color) -> void:
	multimesh.set_instance_transform(i, xf)
	multimesh.set_instance_color(i, color)


func commit() -> void:
	multimesh.visible_instance_count = count


## 1 draw call while anything is visible, else 0.
func draw_calls() -> int:
	return 1 if count > 0 else 0
