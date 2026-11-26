class_name LocaleSelect extends RefCounted
## Locale registration and selection (docs/06 s11, UX-29).
## Order: command line `--ui_locale=fi`, saved override (user settings), OS language. Anything but "fi" is English.
## Translations are the PO files built by tools/locale/build_po.py; untranslated strings fall back to English.


## `override_code` is a supported code to force, or "auto" / "" / anything unknown to follow the OS language.
static func resolve(os_locale: String, override_code: String) -> String:
	var forced: String = override_code.strip_edges().to_lower()
	if Fmt.supported().has(forced):
		return forced
	return Fmt.normalize(os_locale)


## Loads `<dir>/<code>.po` for each supported code and adds it to the TranslationServer. Returns the count added.
static func register_translations(dir: String) -> int:
	var added: int = 0
	for code: Variant in Fmt.supported():
		var path: String = "%s/%s.po" % [dir, str(code)]
		var res: Translation = load(path) as Translation
		if res != null:
			TranslationServer.add_translation(res)
			added += 1
		else:
			push_warning("LocaleSelect: cannot load " + path)
	return added


static func saved_override(path: String) -> String:
	var cfg: ConfigFile = _load_cfg(path)
	return str(cfg.get_value(Fmt.param_str("settings_section"), Fmt.param_str("settings_key"), ""))


## Persists the Settings / age-screen choice ("auto" clears the override). Returns OK, ERR_UNAVAILABLE when
## user:// storage is blocked (the choice then lasts for the session only), or another Godot error code.
static func save_override(path: String, code: String) -> Error:
	var cfg: ConfigFile = _load_cfg(path)
	cfg.set_value(Fmt.param_str("settings_section"), Fmt.param_str("settings_key"), code)
	var dir: Result = Saves.try_make_dir(path.get_base_dir())
	var wr: Result = dir if not dir.ok else Saves.try_write_text(path, cfg.encode_to_text())
	if wr.ok:
		return OK
	return ERR_UNAVAILABLE if wr.error == Saves.ERR_UNAVAILABLE else ERR_CANT_CREATE


## The settings file through Saves.try_*; an empty ConfigFile when absent, unreadable or storage is unavailable.
static func _load_cfg(path: String) -> ConfigFile:
	var cfg: ConfigFile = ConfigFile.new()
	var rd: Result = Saves.try_read_text(path)
	if rd.ok:
		var _e: Error = cfg.parse(str(rd.value))
	return cfg


## Switches the active locale and returns the resolved code.
static func apply(code: String) -> String:
	TranslationServer.set_locale(code)
	return code


## Pseudolocalisation (accents; expansion ratio is the project setting, 0.4) for UI lint and the Settings golden.
static func set_pseudo(enabled: bool) -> void:
	TranslationServer.pseudolocalization_enabled = enabled


## Startup: register PO files, pick the locale, honour `--pseudo_locale`. Returns the active code.
static func setup() -> String:
	var _n: int = register_translations(Fmt.param_str("po_dir"))
	var cli: String = Config.get_str(&"ui_locale", "")
	var saved: String = saved_override(Fmt.param_str("settings_path"))
	var code: String = resolve(OS.get_locale(), cli if not cli.is_empty() else saved)
	set_pseudo(Config.get_flag(&"pseudo_locale"))
	return apply(code)
