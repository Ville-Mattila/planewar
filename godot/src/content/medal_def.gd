class_name MedalDef extends Def
## medals.json entry (owner 02, R0 B.1). Fields stay in `raw` until ui names them.


static func from_dict(d: Dictionary) -> MedalDef:
	var r: MedalDef = MedalDef.new()
	r._read_common(d)
	return r
