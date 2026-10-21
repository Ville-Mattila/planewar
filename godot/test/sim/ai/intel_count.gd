class_name IntelCount extends RefCounted
## AI-22 brute-force expectations of `ThreatMap.update`'s work counters from a refreshed `Perception`: one spread per
## distinct (side, cell, range class) - a profile's air bands at its air class, GROUND at its ground class - and the
## ring lengths of those keys (contacts counted whether fresh or ghost; the delay must be 0).


static func bins(t: ThreatParams, p: Perception) -> int:
	return _keys(t, p).size()


static func cells(t: ThreatParams, p: Perception) -> int:
	var n: int = 0
	for key: Variant in _keys(t, p).keys():
		var k: int = key
		var ck: int = MathX.floori_div(k, 2)
		var cell: int = MathX.floori_div(ck, t.classes)
		var base: int = (ck - cell * t.classes) * (ThreatParams.CELLS + 1) + cell
		n += t.ring_start[base + 1] - t.ring_start[base]
	return n


static func _keys(t: ThreatParams, p: Perception) -> Dictionary:
	var keys: Dictionary = {}
	for i: int in p.n_known:
		var s: int = p.known[i]
		_add(t, keys, p.k_cell[s], p.k_def[s], 0)
	for i: int in p.n_own:
		_add(t, keys, p.own_cell[i], p.own_def[i], 1)
	return keys


static func _add(t: ThreatParams, keys: Dictionary, cell: int, def: int, side: int) -> void:
	var pr: int = t.profile_by_def[def]
	if pr == 0:
		return
	for k: int in [t.prof_class[pr], t.prof_gclass[pr]]:
		if k != 0:
			keys[(cell * t.classes + k) * 2 + side] = true
