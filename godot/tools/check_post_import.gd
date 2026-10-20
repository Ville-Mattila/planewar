extends SceneTree
# ART-05: loads an imported glb (res:// path after `--`) and asserts what post_import_asset.gd promises (docs/07 s4.6):
# every HP_* node is a Marker3D, Far meshes cast no shadows and have visibility ranges, the root is a Node3D.
# Run (after --import): godot --headless --path <project> -s res://tools/check_post_import.gd -- res://ship_dart.glb
# Prints "check_post_import: OK <n> markers" and exits 0, or prints each failure to stderr and exits 1.

var _markers: int = 0


func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		printerr("check_post_import: usage: -- res://path/to/asset.glb")
		quit(2)
		return
	var packed: PackedScene = load(args[0]) as PackedScene
	if packed == null:
		printerr("%s: not importable (run --import first)" % args[0])
		quit(1)
		return
	var root: Node = packed.instantiate()
	var failures: Array[String] = []
	if not (root is Node3D):
		failures.append("root is %s, expected Node3D" % root.get_class())
	var far_name: String = _pascal(args[0].get_file().get_basename()) + "Far"
	_walk(root, far_name, failures)
	for f: String in failures:
		printerr("%s: %s" % [args[0], f])
	if failures.is_empty():
		print("check_post_import: OK %d markers" % _markers)
	root.free()
	quit(1 if not failures.is_empty() else 0)


func _walk(node: Node, far_name: String, failures: Array[String]) -> void:
	var n: String = String(node.name)
	if n.begins_with("HP_"):
		if node is Marker3D:
			_markers += 1
		else:
			failures.append("%s is %s, expected Marker3D" % [n, node.get_class()])
	if node is MeshInstance3D:
		var mi: MeshInstance3D = node as MeshInstance3D
		if n == far_name:
			if mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				failures.append("%s still casts shadows" % n)
			if mi.visibility_range_begin <= 0.0 or mi.visibility_range_end <= mi.visibility_range_begin:
				failures.append("%s has no visibility range (%f..%f)" % [n, mi.visibility_range_begin, mi.visibility_range_end])
		elif mi.visibility_range_end <= 0.0:
			failures.append("%s has no visibility_range_end" % n)
	for child: Node in node.get_children():
		_walk(child, far_name, failures)


func _pascal(asset_id: String) -> String:
	var out: String = ""
	for part: String in asset_id.split("_"):
		out += part.capitalize()
	return out
