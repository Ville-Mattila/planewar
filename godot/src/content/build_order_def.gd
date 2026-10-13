class_name BuildOrderDef extends Def
## build_orders.json entry (opening books, owner 05, R0 B.1). Fields stay in `raw` until sim_ai names them.


static func from_dict(d: Dictionary) -> BuildOrderDef:
	var r: BuildOrderDef = BuildOrderDef.new()
	r._read_common(d)
	return r
