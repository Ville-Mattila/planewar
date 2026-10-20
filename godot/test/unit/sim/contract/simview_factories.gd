class_name SimViewFactories extends RefCounted
## Registry of the SimView implementations under contract (TEST-02): every script in `factories/` that extends
## SimViewFactory. Adding an implementation means adding a file there, not editing a test.

const DIR: String = "res://test/unit/sim/contract/factories"


static func all() -> Array[SimViewFactory]:
	var out: Array[SimViewFactory] = []
	var names: PackedStringArray = DirAccess.get_files_at(DIR)
	names.sort()
	for f: String in names:
		if f.ends_with(".gd"):
			var script: GDScript = load("%s/%s" % [DIR, f]) as GDScript
			var inst: SimViewFactory = script.new() as SimViewFactory if script != null else null
			if inst != null:
				out.append(inst)
	return out
