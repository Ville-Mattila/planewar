class_name CallsignDef extends Def
## callsigns.json (08 SL-3 rule 1, FEAT-01). Singleton file. callsigns: team slot -> class key -> word list.

var number_count: int = 0  ## n = 1 + (hash(entity_id) mod number_count) (08 SL-3 rule 1)
var callsigns: Dictionary = {}

const SPEC: Dictionary = {
	"i": "number_count",
	"d": "callsigns",
	"req": "number_count callsigns",
}


static func from_dict(d: Dictionary) -> CallsignDef:
	var c: CallsignDef = CallsignDef.new()
	c._read_singleton(d, &"callsigns")
	c._fill(d, SPEC)
	return c
