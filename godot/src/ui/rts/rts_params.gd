class_name RtsParams extends RefCounted
## Numbers for selection, picking, groups and rally lines (docs/06 s7.2); from res://content/ui/rts.json.

const PARAMS_PATH: String = "res://content/ui/rts.json"

static var _params: Dictionary = {}


static func _load() -> void:
	if not _params.is_empty():
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PARAMS_PATH))
	var d: Dictionary = {}
	if parsed is Dictionary:
		d = parsed
	_params = d
	if _params.is_empty():
		push_error("RtsParams: %s missing or invalid" % PARAMS_PATH)


static func param(key: String) -> float:
	_load()
	var v: Variant = _params.get(key, null)
	if v is float or v is int:
		return v
	push_error("RtsParams: no number '%s' in %s" % [key, PARAMS_PATH])
	return 0.0


static func list(key: String) -> Array:
	_load()
	var v: Variant = _params.get(key, [])
	var out: Array = []
	if v is Array:
		out = v
	return out
