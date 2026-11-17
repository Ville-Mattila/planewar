class_name ScreenParams extends RefCounted
## Numbers of the match overlays (06 s8, UX-27) from res://content/ui/screens.json.

const PARAMS_PATH: String = "res://content/ui/screens.json"

static var _params: Dictionary = {}


static func param(key: String) -> float:
	if _params.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PARAMS_PATH))
		var d: Dictionary = {}
		if parsed is Dictionary:
			d = parsed
		_params = d
	var v: Variant = _params.get(key, 0.0)
	return v if v is float or v is int else 0.0
