class_name Def extends RefCounted
## Base of every typed def (03 s15.3, R0 B.1). Subclasses declare typed fields plus a SPEC and fill
## them with `_fill`. Content defs are immutable by convention after ContentDB emits loaded(true) (N4).
## Parsing never logs: problems land in `errors` (fatal, N3) and `unknown` (warn-only), the loader reports.

var id: StringName = &""
var def_id: int = -1
var status: StringName = &"core"
var tags: PackedStringArray = PackedStringArray()
var doc: String = ""
var presentation: PresentationDef = null
## Source dictionary as parsed (deep copy). Doctrine resolution edits copies of this and re-parses.
var raw: Dictionary = {}
var errors: Array[String] = []
var unknown: Array[String] = []

const COMMON_KEYS: PackedStringArray = ["id", "status", "tags", "_doc", "presentation"]

## Base parse; overridden per class (return type narrows).
static func from_dict(d: Dictionary) -> Def:
	var r: Def = Def.new()
	r._read_common(d)
	return r


func _read_common(d: Dictionary) -> void:
	raw = d.duplicate(true)
	id = StringName(str(d.get("id", "")))
	status = StringName(str(d.get("status", "core")))
	tags = _strings(d.get("tags", []))
	doc = str(d.get("_doc", ""))
	presentation = PresentationDef.from_dict(d.get("presentation", {}))
	if id == &"":
		errors.append("missing id")


## Singleton files (rules, economy, match_rules, scoring, ...) have no id/status/tags: the id is fixed.
func _read_singleton(d: Dictionary, fixed_id: StringName) -> void:
	raw = d.duplicate(true)
	id = fixed_id
	doc = str(d.get("_doc", ""))
	presentation = PresentationDef.new()


## SPEC keys: f float, i int, b bool, s String, n StringName, a PackedStringArray, p PackedInt32Array,
## l Array (copied), d Dictionary (copied); each a space separated name list. `req` names must be present.
## `extra` names are known keys that the class parses by hand. Names absent from `d` keep the field default.
func _fill(d: Dictionary, spec: Dictionary) -> void:
	for kind: String in ["f", "i", "b", "s", "n", "a", "p", "l", "d"]:
		for key: String in str(spec.get(kind, "")).split(" ", false):
			if d.has(key):
				_assign(key, kind, d[key])
	for key: String in str(spec.get("req", "")).split(" ", false):
		if not d.has(key):
			errors.append("missing field '%s'" % key)
	var known: PackedStringArray = COMMON_KEYS.duplicate()
	for kind: String in ["f", "i", "b", "s", "n", "a", "p", "l", "d", "req", "extra"]:
		known.append_array(str(spec.get(kind, "")).split(" ", false))
	for k: Variant in d.keys():
		if not known.has(str(k)):
			unknown.append(str(k))


func _assign(key: String, kind: String, v: Variant) -> void:
	var t: int = typeof(v)
	if t == TYPE_NIL:
		return  # JSON null: keep the field default (the class documents the sentinel)
	var is_num: bool = t == TYPE_FLOAT or t == TYPE_INT
	match kind:
		"f":
			if is_num:
				set(key, Def.num(v))
				return
		"i":
			if is_num:
				set(key, roundi(Def.num(v)))
				return
		"b":
			if t == TYPE_BOOL:
				set(key, v)
				return
		"s":
			if t == TYPE_STRING:
				set(key, v)
				return
		"n":
			if t == TYPE_STRING:
				set(key, StringName(str(v)))
				return
		"a":
			if t == TYPE_ARRAY:
				set(key, _strings(v))
				return
		"p":
			if t == TYPE_ARRAY:
				set(key, _ints(v))
				return
		"l":
			if t == TYPE_ARRAY:
				var src: Array = v
				set(key, src.duplicate(true))
				return
		"d":
			if t == TYPE_DICTIONARY:
				var srcd: Dictionary = v
				set(key, srcd.duplicate(true))
				return
	errors.append("field '%s' has the wrong type" % key)


## Variant -> float without the unsafe `float(Variant)` constructor; 0.0 for non-numbers.
static func num(v: Variant) -> float:
	var f: float = 0.0
	if typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT:
		f = v
	return f


static func flag(v: Variant) -> bool:
	var b: bool = false
	if typeof(v) == TYPE_BOOL:
		b = v
	return b


static func _strings(v: Variant) -> PackedStringArray:
	var out: Array[String] = []
	if typeof(v) == TYPE_ARRAY:
		var src: Array = v
		for e: Variant in src:
			out.append(str(e))
	return PackedStringArray(out)


static func _ints(v: Variant) -> PackedInt32Array:
	var out: Array[int] = []
	if typeof(v) == TYPE_ARRAY:
		var src: Array = v
		for e: Variant in src:
			out.append(roundi(Def.num(e)))
	return PackedInt32Array(out)


## Nullable `{weapon, <count_key>}` block (ship primary/secondary): returns [weapon, count] or ["", 0].
static func _weapon_slot(v: Variant, count_key: String) -> Array:
	if typeof(v) != TYPE_DICTIONARY:
		return [&"", 0]
	var b: Dictionary = v
	return [StringName(str(b.get("weapon", ""))), roundi(Def.num(b.get(count_key, 0)))]
