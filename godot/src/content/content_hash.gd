class_name ContentHash extends RefCounted
## Content hash (N1): reproduces tools/content_hash.py byte for byte. Canonical form rules are in that
## file's docstring (sorted keys, no whitespace, integral numbers without ".0", shortest round-trip decimals,
## `presentation` and `_doc` keys dropped at any depth). GDScript's JSON.stringify does not match, hence this.

const EXCLUDED_FILES: PackedStringArray = ["sfx.json", "vfx_prewarm.json", "chat_filter.json"]
const STRIPPED_KEYS: PackedStringArray = ["presentation", "_doc"]
const MAX_SAFE: float = 9007199254740992.0  # 2^53


## files: file name -> raw JSON text. Applies the exclusion list; names are sorted byte-wise.
## Returns the 32 SHA-256 bytes, or an empty array when a file does not parse or holds an unsupported number.
static func hash_texts(files: Dictionary) -> PackedByteArray:
	var names: PackedStringArray = included_names(files.keys())
	var parts: Array[String] = []
	for n: String in names:
		var text: String = str(files[n])
		if text.begins_with("﻿"):
			text = text.substr(1)
		var parsed: Variant = JSON.parse_string(text)
		if parsed == null:
			return PackedByteArray()
		var c: String = canonical(parsed)
		if c.is_empty():
			return PackedByteArray()
		parts.append(c)
	var ctx: HashingContext = HashingContext.new()
	var _s: int = ctx.start(HashingContext.HASH_SHA256)
	var _u: int = ctx.update("\n".join(PackedStringArray(parts)).to_utf8_buffer())
	return ctx.finish()


static func included_names(names: Array) -> PackedStringArray:
	var out: Array[String] = []
	for n: Variant in names:
		var s: String = str(n)
		if s.ends_with(".json") and not EXCLUDED_FILES.has(s):
			out.append(s)
	out.sort()
	return PackedStringArray(out)


## Canonical text of one parsed JSON value; "" on an unsupported value (NaN, inf, |int| >= 2^53, non-JSON type).
static func canonical(v: Variant) -> String:
	var out: Array[String] = []
	if not _write(v, out):
		return ""
	return "".join(PackedStringArray(out))


static func _write(v: Variant, out: Array[String]) -> bool:
	match typeof(v):
		TYPE_NIL:
			out.append("null")
		TYPE_BOOL:
			out.append("true" if v else "false")
		TYPE_INT, TYPE_FLOAT:
			var n: String = number_text(Def.num(v))
			if n.is_empty():
				return false
			out.append(n)
		TYPE_STRING:
			out.append(_string(str(v)))
		TYPE_ARRAY:
			var arr: Array = v
			out.append("[")
			for i: int in arr.size():
				if i > 0:
					out.append(",")
				if not _write(arr[i], out):
					return false
			out.append("]")
		TYPE_DICTIONARY:
			var obj: Dictionary = v
			return _write_object(obj, out)
		_:
			return false
	return true


static func _write_object(d: Dictionary, out: Array[String]) -> bool:
	var keys: Array[String] = []
	for k: Variant in d.keys():
		if not STRIPPED_KEYS.has(str(k)):
			keys.append(str(k))
	keys.sort()
	out.append("{")
	for i: int in keys.size():
		if i > 0:
			out.append(",")
		out.append(_string(keys[i]))
		out.append(":")
		if not _write(d[keys[i]], out):
			return false
	out.append("}")
	return true


static func _string(s: String) -> String:
	var out: Array[String] = []
	out.append("\"")
	for i: int in s.length():
		var cp: int = s.unicode_at(i)
		match cp:
			34: out.append("\\\"")
			92: out.append("\\\\")
			8: out.append("\\b")
			9: out.append("\\t")
			10: out.append("\\n")
			12: out.append("\\f")
			13: out.append("\\r")
			_:
				if cp < 32:
					out.append("\\u%04x" % cp)
				else:
					out.append(char(cp))
	out.append("\"")
	return "".join(PackedStringArray(out))


## Integral values print as integers (-0 -> 0); others as the shortest decimal that round-trips, never
## with an exponent. "" for NaN, infinity or |integral value| >= 2^53.
static func number_text(x: float) -> String:
	if is_nan(x) or is_inf(x):
		return ""
	if x == floorf(x):
		if absf(x) >= MAX_SAFE:
			return ""
		return str(int(x))
	return _plain(String.num_scientific(x))


## Expands "d.ddde-05" / "d.ddde+20" / plain forms into plain decimal notation.
static func _plain(sci: String) -> String:
	var e_at: int = sci.find("e")
	if e_at < 0:
		return sci
	var mantissa: String = sci.substr(0, e_at)
	var exp10: int = int(sci.substr(e_at + 1))
	var sign: String = ""
	if mantissa.begins_with("-"):
		sign = "-"
		mantissa = mantissa.substr(1)
	var dot: int = mantissa.find(".")
	var digits: String = mantissa.replace(".", "")
	var point: int = (dot if dot >= 0 else mantissa.length()) + exp10
	if point <= 0:
		return sign + "0." + "0".repeat(-point) + digits
	if point >= digits.length():
		return sign + digits + "0".repeat(point - digits.length())
	return sign + digits.substr(0, point) + "." + digits.substr(point)
