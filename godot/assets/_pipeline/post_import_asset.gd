@tool
extends EditorScenePostImport
# ART-05 (docs/07 s4.6): runs on every committed .glb (the .glb.import names it in import_script/path).
#  - HP_* Node3Ds become Marker3D (hardpoints; presentation reads them by name).
#  - Hull meshes hide at 3 px and swap to the <PascalId>Far mesh under 24 px (07 s1.4); Far meshes show between.
#  - Props, wrecks, projectiles and every Far mesh cast no shadows.
#  - The shared unit_lit.tres is assigned when it exists (the v1 path is UnitMaterialCache, ART-03; harmless otherwise).
#  - Prints the triangle count and warns above the class budget of tools/art/asset_budgets.json (the validator is
#    the gate; this is the editor-time heads-up).
# No class_name: an EditorScenePostImport script is referenced by path from every .glb.import.
# Test: python tools/tests/test_art_import.py (needs GODOT_BIN), godot/tools/check_post_import.gd.

const UNIT_LIT_PATH: String = "res://assets/materials/unit_lit.tres"
# 07 s1.4: px = 935 * S / d at 1080p / 60 degrees; swap to Far under 24 px, hide at 3 px.
const PX_PER_M_AT_1M: float = 935.0
const FAR_PX: float = 24.0
const HIDE_PX: float = 3.0
const NO_SHADOW_CLASSES: PackedStringArray = ["prop", "proj", "wreck"]


func _post_import(scene: Node) -> Object:
	var asset_id: String = get_source_file().get_file().get_basename()
	var cls: String = asset_id.get_slice("_", 0)
	_convert_hardpoints(scene, scene)
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(scene, meshes)
	var far_name: String = _pascal(asset_id) + "Far"
	var length_m: float = _body_length(meshes, far_name)
	var material: Material = null
	if ResourceLoader.exists(UNIT_LIT_PATH):
		material = load(UNIT_LIT_PATH) as Material
	var tris: int = 0
	for mi: MeshInstance3D in meshes:
		tris += _triangles(mi)
		var is_far: bool = String(mi.name) == far_name
		if is_far or NO_SHADOW_CLASSES.has(cls):
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if length_m > 0.0:
			var far_m: float = PX_PER_M_AT_1M * length_m / FAR_PX
			var hide_m: float = PX_PER_M_AT_1M * length_m / HIDE_PX
			mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			if is_far:
				mi.visibility_range_begin = far_m
				mi.visibility_range_end = hide_m
			else:
				mi.visibility_range_end = far_m if _has_far(meshes, far_name) else hide_m
		if material != null:
			mi.material_override = material
	_warn_budget(asset_id, cls, tris)
	print("post_import_asset: %s %d tris, body length %.1f m" % [asset_id, tris, length_m])
	return scene


func _convert_hardpoints(node: Node, scene: Node) -> void:
	for child: Node in node.get_children():
		_convert_hardpoints(child, scene)
		var n: String = String(child.name)
		if n.begins_with("HP_") and child is Node3D and not (child is Marker3D) and not (child is MeshInstance3D):
			var src: Node3D = child as Node3D
			var marker: Marker3D = Marker3D.new()
			node.add_child(marker)
			marker.owner = scene
			marker.transform = src.transform
			node.remove_child(src)
			src.free()
			marker.name = StringName(n)


func _collect_meshes(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		out.append(node as MeshInstance3D)
	for child: Node in node.get_children():
		_collect_meshes(child, out)


func _has_far(meshes: Array[MeshInstance3D], far_name: String) -> bool:
	for mi: MeshInstance3D in meshes:
		if String(mi.name) == far_name:
			return true
	return false


## S of 07 s1.4: the longest horizontal extent of the non-Far meshes, in the glTF (Y-up) frame.
func _body_length(meshes: Array[MeshInstance3D], far_name: String) -> float:
	var box: AABB = AABB()
	var first: bool = true
	for mi: MeshInstance3D in meshes:
		if String(mi.name) == far_name or mi.mesh == null:
			continue
		var b: AABB = mi.transform * mi.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return 0.0 if first else maxf(box.size.x, box.size.z)


func _triangles(mi: MeshInstance3D) -> int:
	if mi.mesh == null:
		return 0
	var total: int = 0
	for s: int in mi.mesh.get_surface_count():
		var arrays: Array = mi.mesh.surface_get_arrays(s)
		var idx: PackedInt32Array = PackedInt32Array()
		var raw_idx: Variant = arrays[Mesh.ARRAY_INDEX]
		if raw_idx is PackedInt32Array:
			idx = raw_idx
		var count: int = idx.size()
		if count == 0:
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			count = verts.size()
		total += int(floorf(float(count) / 3.0))
	return total


func _warn_budget(asset_id: String, cls: String, tris: int) -> void:
	var path: String = ProjectSettings.globalize_path("res://").path_join("../tools/art/asset_budgets.json")
	var text: String = FileAccess.get_file_as_string(path)
	if text.is_empty():
		return  # exported builds and CI checkouts without tools/ skip the heads-up
	var root: Dictionary = _dict(JSON.parse_string(text))
	var assets: Dictionary = _dict(root.get("assets", {}))
	var classes: Dictionary = _dict(root.get("classes", {}))
	var limit: int = 0
	if assets.has(asset_id):
		limit = _max_tris(_dict(assets[asset_id]))
	elif classes.has(cls):
		limit = _max_tris(_dict(classes[cls]))
	if limit > 0 and tris > limit:
		push_warning("%s: %d triangles exceed the budget %d (tools/art/validate_glb.py is the gate)" % [asset_id, tris, limit])


func _dict(v: Variant) -> Dictionary:
	if v is Dictionary:
		var d: Dictionary = v
		return d
	return {}


func _max_tris(entry: Dictionary) -> int:
	var v: Variant = entry.get("max_tris", 0)
	if v is float:
		var f: float = v
		return roundi(f)
	if v is int:
		var i: int = v
		return i
	return 0


func _pascal(asset_id: String) -> String:
	var out: String = ""
	for part: String in asset_id.split("_"):
		out += part.capitalize()
	return out
