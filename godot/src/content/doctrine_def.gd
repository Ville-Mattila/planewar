class_name DoctrineDef extends Def
## doctrines.json entry (R0 B.1, 02 s7). Modifier = {select {ids | tags_any | weapon_mount}, field, op, value}.

const OPS: PackedStringArray = ["mul", "add", "set"]

var modifiers: Array = []  ## Array of Dictionary, in file order
var rules: Dictionary = {}  ## flip_cooldown_s_override, hangar_blocks_rockets, reactor_unlock_s

const SPEC: Dictionary = {
	"l": "modifiers",
	"d": "rules",
	"req": "modifiers rules",
}


static func from_dict(d: Dictionary) -> DoctrineDef:
	var r: DoctrineDef = DoctrineDef.new()
	r._read_common(d)
	r._fill(d, SPEC)
	for m: Variant in r.modifiers:
		if typeof(m) != TYPE_DICTIONARY:
			r.errors.append("modifier is not an object")
			continue
		var md: Dictionary = m
		if typeof(md.get("select")) != TYPE_DICTIONARY or typeof(md.get("field")) != TYPE_STRING \
				or not md.has("value") or not OPS.has(str(md.get("op", ""))):
			r.errors.append("modifier needs select, field, op (mul|add|set), value")
	return r
