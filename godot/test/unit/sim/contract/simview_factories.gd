class_name SimViewFactories extends RefCounted
## Registry of the SimView implementations under contract (TEST-02): every script in `factories/` that extends
## SimViewFactory. Adding an implementation means adding a file there, not editing a test.

const DIR: String = "res://test/unit/sim/contract/factories"


## Paths in `factories/` that do not load as a SimViewFactory subclass; test_every_factory_file_loads asserts none.
static func unloadable() -> PackedStringArray:
	var bad: PackedStringArray = PackedStringArray()
	for f: String in _files():
		var script: GDScript = load("%s/%s" % [DIR, f]) as GDScript
		if script == null or not (script.new() is SimViewFactory):
			var _a: bool = bad.push_back(f)
	return bad


static func _files() -> PackedStringArray:
	var names: PackedStringArray = PackedStringArray()
	for f: String in DirAccess.get_files_at(DIR):
		if f.ends_with(".gd"):
			var _a: bool = names.push_back(f)
	names.sort()
	return names


static func all() -> Array[SimViewFactory]:
	var out: Array[SimViewFactory] = []
	for f: String in _files():
		var script: GDScript = load("%s/%s" % [DIR, f]) as GDScript
		var inst: SimViewFactory = script.new() as SimViewFactory if script != null else null
		if inst != null:
			out.append(inst)
	return out
