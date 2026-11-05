class_name OrderClassRules extends RefCounted
## Which order kinds a class accepts, read from order_rules.json (`enabled_kinds` x `allowed_kinds`), the same
## data the sim's OrderRules checks. The sim rejects a whole ORDER if any id's class disallows the kind, so
## the resolver filters with this before it builds a command. Class key = def id; towers share &"tower".

var _enabled: int = 0
var _by_class: Dictionary = {}   # StringName -> kind bitmask
var _rally: Array[StringName] = []


## `raw` is OrderRulesDef.raw.
static func from_raw(raw: Dictionary) -> OrderClassRules:
	var r: OrderClassRules = OrderClassRules.new()
	r._enabled = _mask_of(raw.get("enabled_kinds", []))
	var allowed: Dictionary = raw.get("allowed_kinds", {})
	for key: Variant in allowed.keys():
		r._by_class[StringName(str(key))] = _mask_of(allowed[key])
	for c: Variant in RtsParams.list("rally_classes"):
		r._rally.append(StringName(str(c)))
	return r


static func from_content() -> OrderClassRules:
	return from_raw(ContentDB.order_rules.raw if ContentDB.order_rules != null else {})


func allows(kind: int, class_key: StringName) -> bool:
	if kind < 0 or kind >= OrderSpec.KIND_COUNT or not _by_class.has(class_key):
		return false
	var m: int = _by_class[class_key]
	return (_enabled & m & (1 << kind)) != 0


func is_rally_class(class_key: StringName) -> bool:
	return _rally.has(class_key)


static func _mask_of(names: Variant) -> int:
	var m: int = 0
	if names is Array:
		var arr: Array = names
		for n: Variant in arr:
			var k: int = OrderSpec.kind_from_name(str(n))
			if k >= 0:
				m |= 1 << k
	return m
