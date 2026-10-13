class_name ProgressionDef extends Def
## progression.json (owner 02, R0 B.1). Singleton file; fields stay in `raw` until ui names them.


static func from_dict(d: Dictionary) -> ProgressionDef:
	var r: ProgressionDef = ProgressionDef.new()
	r._read_singleton(d, &"progression")
	return r
