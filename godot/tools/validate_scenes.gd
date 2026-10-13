extends SceneTree
# TEST-01 (docs/03 s1.4, 01 ADR-11, 01:563): every .tscn under res://scenes must load and instantiate headless.
# Run: godot --headless --path godot -s res://tools/validate_scenes.gd
# For each scene: every [ext_resource] path must exist (catches a missing script or resource explicitly),
# the file must load as a PackedScene, and it must instantiate. Each failing file is printed to stderr;
# exit 0 when all pass, 1 otherwise (0 scenes found is a failure).

const SCENE_ROOT: String = "res://scenes"

var _failures: Array[String] = []
var _checked: int = 0
var _ext_path_re: RegEx = RegEx.new()


func _init() -> void:
	var _compile_err: Error = _ext_path_re.compile("path=\"(res://[^\"]+)\"")
	var files: Array[String] = []
	_collect(SCENE_ROOT, files)
	files.sort()
	if files.is_empty():
		_failures.append("%s: no .tscn files found" % SCENE_ROOT)
	for scene_path: String in files:
		_check_scene(scene_path)
	for failure: String in _failures:
		printerr("validate_scenes FAIL: %s" % failure)
	print("validate_scenes: %d scene(s) checked, %d failure(s)" % [_checked, _failures.size()])
	quit(1 if not _failures.is_empty() else 0)


func _collect(dir_path: String, out: Array[String]) -> void:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		_failures.append("%s: cannot open directory" % dir_path)
		return
	for file_name: String in dir.get_files():
		if file_name.ends_with(".tscn"):
			out.append(dir_path.path_join(file_name))
	for sub_dir: String in dir.get_directories():
		_collect(dir_path.path_join(sub_dir), out)


func _check_scene(scene_path: String) -> void:
	_checked += 1
	var text: String = FileAccess.get_file_as_string(scene_path)
	if text.is_empty():
		_fail(scene_path, "empty or unreadable file")
		return
	for line: String in text.split("\n"):
		if not line.begins_with("[ext_resource"):
			continue
		var hit: RegExMatch = _ext_path_re.search(line)
		if hit == null:
			continue
		var ref_path: String = hit.get_string(1)
		if not ResourceLoader.exists(ref_path):
			_fail(scene_path, "missing ext_resource %s" % ref_path)
	var packed: PackedScene = load(scene_path) as PackedScene
	if packed == null:
		_fail(scene_path, "does not load as PackedScene")
		return
	var instance: Node = packed.instantiate()
	if instance == null:
		_fail(scene_path, "instantiate() returned null")
		return
	instance.free()


func _fail(scene_path: String, reason: String) -> void:
	_failures.append("%s: %s" % [scene_path, reason])
