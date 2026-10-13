class_name AutopilotDef extends Def
## autopilots.json entry (owner 05, R0 B.1). Fields stay in `raw` until sim_ai names them.


static func from_dict(d: Dictionary) -> AutopilotDef:
	var r: AutopilotDef = AutopilotDef.new()
	r._read_common(d)
	return r
