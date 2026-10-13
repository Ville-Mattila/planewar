class_name BotProfileDef extends Def
## bot_profiles.json entry (owner 05, R0 B.1). Fields stay in `raw` until sim_ai (TA-4x) names them;
## adding typed fields later is an append.


static func from_dict(d: Dictionary) -> BotProfileDef:
	var r: BotProfileDef = BotProfileDef.new()
	r._read_common(d)
	return r
