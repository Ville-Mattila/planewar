class_name SiteToken extends RefCounted
## A location token of an opening book (05 s7.3): `core`, `approach:nearest_enemy`, `toward:<token>`, `cold_trap:home`,
## `ore_field:home_N` (N from 1), `outpost_site:home_trap`, `contested_field`, `refinery`, `outpost`. Parsed once when the
## book compiles; `BuildPlanner` resolves it to a point on the map.

enum Kind { CORE, APPROACH, TOWARD, COLD_TRAP, ORE_FIELD, OUTPOST_SITE, CONTESTED, REFINERY, OUTPOST }

var src: String = ""
var kind: Kind = Kind.CORE
var arg: String = ""            ## `nearest_enemy`, `home`, `home_trap`
var nth: int = 1                ## `ore_field:home_N`
var inner: SiteToken = null     ## the target of a `toward:` token


## Null for text outside the grammar.
static func parse(text: String) -> SiteToken:
	var t: SiteToken = SiteToken.new()
	t.src = text
	match text:
		"core":
			t.kind = Kind.CORE
		"contested_field":
			t.kind = Kind.CONTESTED
		"refinery":
			t.kind = Kind.REFINERY
		"outpost":
			t.kind = Kind.OUTPOST
		"cold_trap:home":
			t.kind = Kind.COLD_TRAP
			t.arg = "home"
		"outpost_site:home_trap":
			t.kind = Kind.OUTPOST_SITE
			t.arg = "home_trap"
		"approach:nearest_enemy":
			t.kind = Kind.APPROACH
			t.arg = "nearest_enemy"
		_:
			return _parse_prefixed(t, text)
	return t


static func _parse_prefixed(t: SiteToken, text: String) -> SiteToken:
	if text.begins_with("toward:"):
		t.kind = Kind.TOWARD
		t.inner = parse(text.substr(7))
		return t if t.inner != null and t.inner.kind != Kind.TOWARD else null
	if text.begins_with("ore_field:home_"):
		var n: String = text.substr(15)
		if not n.is_valid_int() or n.to_int() < 1:
			return null
		t.kind = Kind.ORE_FIELD
		t.arg = "home"
		t.nth = n.to_int()
		return t
	return null
