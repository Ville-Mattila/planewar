class_name Glyphs extends RefCounted
## Glyph sets (06 s2.4, s9.4, UX-09): joypad name -> set, and the label a binding shows in the active set. Data is
## `content/ui/glyphs.json`; read directly (input may not use ContentDB). Pure statics; a change of the active set
## is one `DeviceMonitor.feed`, so labels swap in the same frame the next `binding_label` call is made.

const PATH: String = "res://content/ui/glyphs.json"
const UNBOUND: int = -1

## glyphs.json button id -> JoyButton.
const BUTTON_IDS: Dictionary[StringName, int] = {
	&"a": JOY_BUTTON_A, &"b": JOY_BUTTON_B, &"x": JOY_BUTTON_X, &"y": JOY_BUTTON_Y,
	&"lb": JOY_BUTTON_LEFT_SHOULDER, &"rb": JOY_BUTTON_RIGHT_SHOULDER,
	&"l3": JOY_BUTTON_LEFT_STICK, &"r3": JOY_BUTTON_RIGHT_STICK,
	&"view": JOY_BUTTON_BACK, &"menu": JOY_BUTTON_START,
	&"dpad_up": JOY_BUTTON_DPAD_UP, &"dpad_down": JOY_BUTTON_DPAD_DOWN,
	&"dpad_left": JOY_BUTTON_DPAD_LEFT, &"dpad_right": JOY_BUTTON_DPAD_RIGHT,
}

static var _data: Dictionary = {}


static func _load() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		var d: Dictionary = {}
		if parsed is Dictionary:
			d = parsed
		_data = d
	return _data


static func as_dict(v: Variant) -> Dictionary:
	if v is Dictionary:
		return v
	return {}


static func as_array(v: Variant) -> Array:
	if v is Array:
		return v
	return []


## Glyph set for a joypad name (`Input.get_joy_name`); first matching entry wins.
static func set_for_joy_name(joy_name: String) -> StringName:
	var n: String = joy_name.to_lower()
	for e: Variant in as_array(_load().get("match", [])):
		var entry: Dictionary = as_dict(e)
		for sub: Variant in as_array(entry.get("contains", [])):
			if str(sub) != "" and n.contains(str(sub)):
				return StringName(str(entry.get("set", "")))
	return fallback_set()


static func fallback_set() -> StringName:
	return StringName(str(_load().get("fallback_set", "generic")))


static func set_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for k: Variant in as_dict(_load().get("layout", {})).keys():
		out.append(StringName(str(k)))
	return out


static func button_id_of(joy_button: int) -> StringName:
	for id: StringName in BUTTON_IDS:
		if BUTTON_IDS[id] == joy_button:
			return id
	return &""


## JoyButton for a glyphs.json id; UNBOUND for "" or an unknown id.
static func button_from_id(id: String) -> int:
	return BUTTON_IDS.get(StringName(id), UNBOUND)


static func unbound_label() -> String:
	return str(_load().get("unbound", "-"))


static func pad_label(glyph_set: StringName, joy_button: int) -> String:
	if joy_button < 0:
		return unbound_label()
	var layout: Dictionary = as_dict(_load().get("layout", {}))
	var set_map: Dictionary = as_dict(layout.get(String(glyph_set), layout.get(String(fallback_set()), {})))
	var id: String = String(button_id_of(joy_button))
	if set_map.has(id):
		return str(set_map[id])
	return "#%d" % joy_button


static func key_from_name(key_name: String) -> int:
	if key_name == "":
		return UNBOUND
	var k: Key = OS.find_keycode_from_string(key_name)
	return UNBOUND if k == KEY_NONE else int(k)


static func key_label(keycode: int) -> String:
	if keycode <= 0:
		return unbound_label()
	return OS.get_keycode_string(keycode as Key)


## Label of one binding for the active glyph set: keys ignore the set, pad buttons follow it.
static func binding_label(glyph_set: StringName, device: StringName, code: int) -> String:
	if device == &"pad":
		return pad_label(glyph_set, code)
	return key_label(code)


## No keyboard-and-mouse glyphs while a gamepad is active (06 s2.4, I8): the set a device class shows.
static func set_for_class(kind: int, joy_set: StringName) -> StringName:
	if kind == InputClass.Kind.GAMEPAD:
		return joy_set if joy_set != &"kbm" else fallback_set()
	return &"kbm"
