class_name VfxPrewarm
extends RefCounted
## Pre-warm list loader (07 s6, ADR-02: no shader baker on Compatibility). `load_list` reads
## `content/vfx_prewarm.json` ({"effects": [vfx ids]}, owned by 07 / task ART-VFX, hash-excluded) and falls back to
## every id of `VfxCatalog` while the file is absent. `run` spawns one of each effect at `at` (the loading screen
## puts a point in front of the camera) so every material and mesh is drawn once; `finish` hides them again.

const LIST_PATH: String = "res://content/vfx_prewarm.json"


## Effect ids to pre-warm; unknown ids (not in the catalog) are dropped.
static func load_list(path: String = LIST_PATH) -> PackedStringArray:
	if FileAccess.file_exists(path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary:
			var d: Dictionary = parsed
			var out: PackedStringArray = PackedStringArray()
			for e: Variant in d.get("effects", []):
				if VfxCatalog.has(StringName(str(e))):
					var _a: bool = out.push_back(str(e))
			if not out.is_empty():
				return out
	return VfxCatalog.ids()


## Spawns one instance of every listed effect at `at`; returns how many spawned. Needs pool capacity >= list size.
static func run(pool: VfxPool, ids: PackedStringArray, at: Vector3) -> int:
	var n: int = 0
	for id: String in ids:
		if pool.spawn(StringName(id), at):
			n += 1
	pool.update(0.0)
	return n


static func finish(pool: VfxPool) -> void:
	pool.clear()
