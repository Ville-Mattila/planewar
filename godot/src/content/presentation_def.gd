class_name PresentationDef extends RefCounted
## 07-owned presentation block of a def (03 s15.3). Stripped from the content hash.

var mesh: String = ""
var far_mesh_node: StringName = &""
var vfx: PackedStringArray = PackedStringArray()
var sfx: Dictionary = {}
var pool: int = 0
var budget_tris: int = 0
## The whole source block, for keys this class does not name (smoke_hp01, camera, icon, ...).
var raw: Dictionary = {}


static func from_dict(d: Variant) -> PresentationDef:
	var p: PresentationDef = PresentationDef.new()
	if typeof(d) != TYPE_DICTIONARY:
		return p
	var src: Dictionary = d
	p.raw = src.duplicate(true)
	p.mesh = str(src.get("mesh", ""))
	p.far_mesh_node = StringName(str(src.get("far_mesh_node", "")))
	p.vfx = Def._strings(src.get("vfx", []))
	var sfx_src: Variant = src.get("sfx", {})
	if typeof(sfx_src) == TYPE_DICTIONARY:
		var sd: Dictionary = sfx_src
		p.sfx = sd.duplicate(true)
	p.pool = roundi(Def.num(src.get("pool", 0)))
	p.budget_tris = roundi(Def.num(src.get("budget_tris", 0)))
	return p
