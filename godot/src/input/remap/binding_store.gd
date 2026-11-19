class_name BindingStore extends RefCounted
## Remappable bindings of the flight actions (06 s2.5, A11Y-06, UX-09), persisted to `user://settings/input_map.cfg`.
## Defaults come from `content/ui/remap.json`. Conflicts (one code on two actions of a device) are flagged, never
## refused: the player may keep them. Codes are physical keycodes (kbm, `slots` per action) or JoyButtons (pad,
## one per action); Glyphs.UNBOUND (-1) is an empty slot.

const PARAMS_PATH: String = "res://content/ui/remap.json"
const KBM: StringName = &"kbm"
const PAD: StringName = &"pad"
const UNBOUND: int = Glyphs.UNBOUND
## input_map.cfg format version ([meta] version); a newer file is ignored, older ones load (missing = 0).
const FILE_VERSION: int = 1

var path: String = ""

var _kbm: Dictionary[StringName, PackedInt32Array] = {}
var _pad: Dictionary[StringName, int] = {}
var _params: Dictionary = {}


## `p_path` overrides the settings file (tests); empty reads it from remap.json.
func _init(p_path: String = "") -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PARAMS_PATH))
	_params = Glyphs.as_dict(parsed)
	path = p_path if p_path != "" else str(_params.get("settings_path", ""))
	reset(KBM)
	reset(PAD)


func slots() -> int:
	var v: Variant = _params.get("slots", 2)
	return v if v is int else 2


func actions(device: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for id: Variant in Glyphs.as_array(Glyphs.as_dict(_params.get("actions", {})).get(String(device), [])):
		out.append(StringName(str(id)))
	return out


## Code in `slot` of `action` (pad ignores `slot`); UNBOUND when empty or unknown.
func code(device: StringName, action: StringName, slot: int = 0) -> int:
	if device == PAD:
		return _pad.get(action, UNBOUND)
	var arr: PackedInt32Array = _kbm.get(action, PackedInt32Array())
	return arr[slot] if slot >= 0 and slot < arr.size() else UNBOUND


## Every bound code of `action`, empty slots skipped.
func codes_of(device: StringName, action: StringName) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	if device == PAD:
		var c: int = code(PAD, action)
		if c != UNBOUND:
			var _n: bool = out.append(c)
		return out
	for c: int in _kbm.get(action, PackedInt32Array()):
		if c != UNBOUND:
			var _n: bool = out.append(c)
	return out


## Every bound code of a device (for polling).
func all_codes(device: StringName) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for a: StringName in actions(device):
		for c: int in codes_of(device, a):
			var _n: bool = out.append(c)
	return out


## Binds `new_code`; returns the first OTHER action already holding it (a conflict flag), or &"".
func bind(device: StringName, action: StringName, slot: int, new_code: int) -> StringName:
	if not actions(device).has(action):
		return &""
	if device == PAD:
		_pad[action] = new_code
	else:
		var arr: PackedInt32Array = _kbm.get(action, PackedInt32Array())
		if slot < 0 or slot >= arr.size():
			return &""
		arr[slot] = new_code
		_kbm[action] = arr
	return conflict_of(device, action, slot)


func clear(device: StringName, action: StringName, slot: int = 0) -> void:
	var _c: StringName = bind(device, action, slot, UNBOUND)


## Another action holding the same code as (action, slot); &"" when none or empty.
func conflict_of(device: StringName, action: StringName, slot: int = 0) -> StringName:
	var c: int = code(device, action, slot)
	if c == UNBOUND:
		return &""
	for other: StringName in actions(device):
		if other != action and codes_of(device, other).has(c):
			return other
	return &""


## Actions of `device` that share a code with another action.
func conflicted(device: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for a: StringName in actions(device):
		for s: int in (1 if device == PAD else slots()):
			if conflict_of(device, a, s) != &"":
				out.append(a)
				break
	return out


func reset(device: StringName) -> void:
	var defaults: Dictionary = _params.get(String(device), {})
	if device == PAD:
		_pad.clear()
		for a: StringName in actions(PAD):
			_pad[a] = Glyphs.button_from_id(str(defaults.get(String(a), "")))
		return
	_kbm.clear()
	for a: StringName in actions(KBM):
		var arr: PackedInt32Array = PackedInt32Array()
		var _r: int = arr.resize(slots())
		arr.fill(UNBOUND)
		var names: Array = Glyphs.as_array(defaults.get(String(a), []))
		for i: int in mini(names.size(), slots()):
			arr[i] = Glyphs.key_from_name(str(names[i]))
		_kbm[a] = arr


func save() -> Error:
	var cf: ConfigFile = ConfigFile.new()
	cf.set_value("meta", "version", FILE_VERSION)
	for a: StringName in actions(KBM):
		var list: Array = []
		for c: int in _kbm.get(a, PackedInt32Array()):
			list.append(c)
		cf.set_value(String(KBM), String(a), list)
	for a: StringName in actions(PAD):
		cf.set_value(String(PAD), String(a), code(PAD, a))
	var dir: String = path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		var _e: Error = DirAccess.make_dir_recursive_absolute(dir)
	return cf.save(path)


## Loads the saved map over the defaults; unknown actions and malformed values are ignored. OK when the file is absent.
func load_file() -> Error:
	if not FileAccess.file_exists(path):
		return OK
	var cf: ConfigFile = ConfigFile.new()
	var err: Error = cf.load(path)
	if err != OK:
		return err
	var ver: Variant = cf.get_value("meta", "version", 0)
	if ver is int and ver > FILE_VERSION:
		return ERR_FILE_UNRECOGNIZED   # written by a newer build: keep the defaults
	for a: StringName in actions(KBM):
		var v: Variant = cf.get_value(String(KBM), String(a), [])
		var list: Array = Glyphs.as_array(v)
		if list.size() == slots():
			var arr: PackedInt32Array = PackedInt32Array()
			for x: Variant in list:
				var n: int = UNBOUND
				if x is int:
					n = x
				var _ok: bool = arr.append(n)
			_kbm[a] = arr
	for a: StringName in actions(PAD):
		var v: Variant = cf.get_value(String(PAD), String(a), "") if cf.has_section_key(String(PAD), String(a)) else ""
		if v is int:
			_pad[a] = v
	return OK
