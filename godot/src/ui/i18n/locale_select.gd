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
	var cfg: ConfigFile = ConfigFile.new()
	if cfg.load(path) != OK:
		return ""
	return str(cfg.get_value(Fmt.param_str("settings_section"), Fmt.param_str("settings_key"), ""))


## Persists the Settings / age-screen choice ("auto" clears the override). Returns OK or a Godot error code.
static func save_override(path: String, code: String) -> Error:
	var cfg: ConfigFile = ConfigFile.new()
	var _loaded: Error = cfg.load(path)
	cfg.set_value(Fmt.param_str("settings_section"), Fmt.param_str("settings_key"), code)
	return cfg.save(path)


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
