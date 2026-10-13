class_name AssistDef extends Def
## assists.json (owner 06, R0 B.1; in the content hash). Singleton file; tier numbers stay in `raw`
## until input/camera name them.


static func from_dict(d: Dictionary) -> AssistDef:
	var r: AssistDef = AssistDef.new()
	r._read_singleton(d, &"assists")
	return r
