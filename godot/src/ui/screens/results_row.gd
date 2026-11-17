class_name ResultsRow extends RefCounted
## One player's row of the Results screen: the per-player `MATCH_END` fields of 04 s2.3 / R0 C2-17 plus kills and manual
## landings from the score events (06 s8). Plain data; `from_dict` reads the keys of the decoded payload.

const CLASS_IDS: PackedStringArray = ["dart", "lancer", "bomber", "scout", "hauler"]   ## pilot_time_s order (04 s2.3)

var slot: int = 0
var team: int = 0
var player_name: String = ""
var score_pilot: int = 0
var score_commander: int = 0
var kills: int = 0
var manual_landings: int = 0
var structures_destroyed: int = 0
var sorties: int = 0
var ore_mined: int = 0
var ore_spent: int = 0
var ice_delivered: int = 0
var pilot_time_s: PackedInt32Array = PackedInt32Array()   ## seconds possessed per class, CLASS_IDS order
var medals: PackedByteArray = PackedByteArray()           ## medals.json order; non-zero = earned


static func from_dict(d: Dictionary) -> ResultsRow:
	var r: ResultsRow = ResultsRow.new()
	r.slot = _int(d, "slot")
	r.team = _int(d, "team")
	r.player_name = str(d.get("name", ""))
	r.score_pilot = _int(d, "score_pilot")
	r.score_commander = _int(d, "score_commander")
	r.kills = _int(d, "kills")
	r.manual_landings = _int(d, "manual_landings")
	r.structures_destroyed = _int(d, "structures_destroyed")
	r.sorties = _int(d, "sorties")
	r.ore_mined = _int(d, "ore_mined")
	r.ore_spent = _int(d, "ore_spent")
	r.ice_delivered = _int(d, "ice_delivered")
	var times: Array = _arr(d, "pilot_time_s")
	var _e: int = times.resize(CLASS_IDS.size())
	r.pilot_time_s = PackedInt32Array(times)
	r.medals = PackedByteArray(_arr(d, "medals"))
	return r


static func _int(d: Dictionary, key: String) -> int:
	var v: Variant = d.get(key, 0)
	if v is int:
		var i: int = v
		return i
	if v is float:
		var f: float = v
		return int(f)
	return 0


static func _flag(d: Dictionary, key: String) -> bool:
	var v: Variant = d.get(key, false)
	if v is bool:
		var b: bool = v
		return b
	return false


static func _dict(d: Dictionary, key: String) -> Dictionary:
	var v: Variant = d.get(key, {})
	if v is Dictionary:
		var out: Dictionary = v
		return out
	return {}


static func _arr(d: Dictionary, key: String) -> Array:
	var v: Variant = d.get(key, [])
	if v is Array:
		var a: Array = v
		return a
	return []
