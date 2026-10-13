class_name OrderRulesDef extends Def
## order_rules.json (owner 05, R0 B.1). Singleton file; fields stay in `raw` until sim_ai names them.


static func from_dict(d: Dictionary) -> OrderRulesDef:
	var r: OrderRulesDef = OrderRulesDef.new()
	r._read_singleton(d, &"order_rules")
	return r
