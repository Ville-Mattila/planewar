class_name Config
## Static configuration access: project settings plus command-line overrides.
## Overrides: `--name=value` or `--name` (flag, value "true") in the engine args or after `--`.
## Project setting keys live under `planewar/<name>`.


static func get_flag(name: StringName) -> bool:
	var v: String = get_str(name, "")
	return v == "true" or v == "1" or v == "yes"


static func get_int(name: StringName, default: int) -> int:
	var v: String = get_str(name, "")
	if v.is_empty() or not v.is_valid_int():
		return default
	return v.to_int()


static func get_str(name: StringName, default: String) -> String:
	var key: String = String(name)
	var found: PackedStringArray = parse_override(OS.get_cmdline_user_args(), key)
	if found.is_empty():
		found = parse_override(OS.get_cmdline_args(), key)
	if not found.is_empty():
		return found[0]
	var setting: Variant = ProjectSettings.get_setting("planewar/" + key, default)
	return str(setting)


## Returns [value] if `--key` or `--key=value` is in args, else an empty array.
## A bare `--key` yields ["true"].
static func parse_override(args: PackedStringArray, key: String) -> PackedStringArray:
	var bare: String = "--" + key
	for arg: String in args:
		if arg == bare:
			return PackedStringArray(["true"])
		if arg.begins_with(bare + "="):
			return PackedStringArray([arg.substr(bare.length() + 1)])
	return PackedStringArray()


static func is_server() -> bool:
	return get_flag(&"server")


static func is_web() -> bool:
	return OS.has_feature("web")


static func is_mobile() -> bool:
	return OS.has_feature("android") or OS.has_feature("ios")


## "standard" on native PC/Deck; "lite" on web and mobile (03 s2 API; flipped by data later).
static func default_offline_caps_profile() -> StringName:
	return &"lite" if (is_web() or is_mobile()) else &"standard"
