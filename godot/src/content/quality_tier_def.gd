class_name QualityTierDef extends Def
## quality_tiers.json entry (owner 03, TA-31): LOW / MEDIUM / HIGH knobs. Fields stay in `raw` until TA-31.


static func from_dict(d: Dictionary) -> QualityTierDef:
	var r: QualityTierDef = QualityTierDef.new()
	r._read_common(d)
	return r
