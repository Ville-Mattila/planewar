class_name Fmt extends RefCounted
## Locale-aware number, distance and time formatting (docs/06 s11, UX-29).
## en "12,400" / "92.5" / "1.2 km"; fi "12 400" (U+202F) / "92,5" / "1,2 km"; 24 h time everywhere.
## Pure statics: the locale is an explicit argument; separators and units come from content/ui/i18n.json.

const PARAMS_PATH: String = "res://content/ui/i18n.json"

static var _params: Dictionary = {}


static func _load() -> Dictionary:
	if _params.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PARAMS_PATH))
		var d: Dictionary = {}
		if parsed is Dictionary:
			d = parsed
		_params = d
	return _params


static func param_str(key: String) -> String:
	return str(_load().get(key, ""))


static func param_num(key: String) -> float:
	var v: Variant = _load().get(key, 0.0)
	return v if v is float or v is int else 0.0


static func supported() -> Array:
	var v: Variant = _load().get("supported", [])
	var out: Array = []
	if v is Array:
		out = v
	return out


## Language part of any locale name: "fi_FI" -> "fi". Unsupported languages map to the default.
static func normalize(locale: String) -> String:
	var lang: String = locale.substr(0, 2).to_lower() if locale.length() >= 2 else ""
	if supported().has(lang):
		return lang
	return param_str("default_locale")


static func separator(locale: String, key: String) -> String:
	var formats: Dictionary = {}
	var f: Variant = _load().get("formats", {})
	if f is Dictionary:
		formats = f
	var fmt: Dictionary = {}
	var g: Variant = formats.get(normalize(locale), {})
	if g is Dictionary:
		fmt = g
	return str(fmt.get(key, ""))


## 12400 -> "12,400" (en) / "12 400" (fi).
static func integer(n: int, locale: String) -> String:
	var digits: String = str(absi(n))
	var group: String = separator(locale, "group")
	var out: String = ""
	var count: int = 0
	for i: int in range(digits.length() - 1, -1, -1):
		if count > 0 and count % 3 == 0:
			out = group + out
		out = digits[i] + out
		count += 1
	return ("-" + out) if n < 0 else out


## 92.5 -> "92.5" (en) / "92,5" (fi), rounded half away from zero to `digits` places.
static func decimal(x: float, digits: int, locale: String) -> String:
	var scale: float = pow(10.0, float(digits))
	var scaled: int = roundi(absf(x) * scale)
	var whole: int = MathX.floori_div(scaled, int(scale))
	var frac: int = scaled % int(scale)
	var sign_text: String = "-" if x < 0.0 and scaled > 0 else ""
	var text: String = sign_text + integer(whole, locale)
	if digits > 0:
		text += separator(locale, "decimal") + str(frac).pad_zeros(digits)
	return text


## Metres below 1 km as "850 m", otherwise "1.2 km".
static func distance_m(metres: float, locale: String) -> String:
	if absf(metres) < param_num("km_from_m"):
		return integer(roundi(metres), locale) + " " + param_str("unit_m")
	var digits: int = int(param_num("km_digits"))
	return decimal(metres / param_num("km_from_m"), digits, locale) + " " + param_str("unit_km")


## Seconds since midnight -> "HH:MM" (24 h, both locales).
static func clock_24h(seconds_of_day: int) -> String:
	var s: int = MathX.posmod_i(seconds_of_day, 86400)
	return "%02d:%02d" % [MathX.floori_div(s, 3600), MathX.floori_div(s % 3600, 60)]


## A duration in seconds -> "m:ss" (or "h:mm:ss" from one hour).
static func duration(seconds: int) -> String:
	var s: int = maxi(seconds, 0)
	if s >= 3600:
		return "%d:%02d:%02d" % [MathX.floori_div(s, 3600), MathX.floori_div(s % 3600, 60), s % 60]
	return "%d:%02d" % [MathX.floori_div(s, 60), s % 60]
