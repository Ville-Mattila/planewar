class_name BookCondition extends RefCounted
## One `when` / `skip_if_have` condition of an opening book (05 s7.3), compiled once into flat atom arrays; `eval` reads a
## `BookContext` and allocates nothing. Grammar: atoms `t>=60`, `ore>=X`, `ice>=X`, `have:<def>>=N`, `power01<1.1`,
## `enemy_seen`, `affordable`, `presence`; `&` (and) binds tighter than `|` (or); comparisons `>= > <= < =`; spaces ignored.
## An empty source is always true. `skip_if_have` sources are `<def>>=N` and count sites too (`have_all`).

enum Atom { T, ORE, ICE, HAVE, POWER01, ENEMY_SEEN, AFFORDABLE, PRESENCE }
enum Cmp { GE, GT, LE, LT, EQ }

var src: String = ""
var uses_presence: bool = false
var uses_affordable: bool = false
var _all: bool = false                       ## `have` reads `have_all` (sites included)
var _atom: PackedByteArray = PackedByteArray()
var _cmp: PackedByteArray = PackedByteArray()
var _def: PackedInt32Array = PackedInt32Array()
var _val: PackedFloat64Array = PackedFloat64Array()
var _clause_end: PackedInt32Array = PackedInt32Array()   ## index one past the last atom of each and-clause


## Null when `src` is not in the grammar or names a def that is not in `def_index` (StringName -> def id).
static func compile(text: String, def_index: Dictionary, count_sites: bool = false) -> BookCondition:
	var c: BookCondition = BookCondition.new()
	c.src = text
	c._all = count_sites
	var clean: String = text.replace(" ", "")
	if clean.is_empty():
		return c
	for clause: String in clean.split("|", true):
		if clause.is_empty():
			return null
		for atom: String in clause.split("&", true):
			if not c._add(atom, def_index, count_sites):
				return null
		var _a: bool = c._clause_end.push_back(c._atom.size())
	return c


func eval(c: BookContext) -> bool:
	if _clause_end.is_empty():
		return true
	var i: int = 0
	for e: int in _clause_end:
		var ok: bool = true
		while i < e:
			if ok and not _holds(i, c):
				ok = false
			i += 1
		if ok:
			return true
	return false


## True when this condition is false at `c` only because of the clock (R0 B.33 A-163; SC-41's verdict on a step left pending
## at the hand-over): advancing `t_s` alone would make it true (`t_s` = +INF, the other terms kept), or it stays false at this
## `t_s` even with every other term true. Pure: reads `c`, writes nothing.
func waits_on_clock(c: BookContext) -> bool:
	if eval(c):
		return false
	return _eval_clock(c, true) or not _eval_clock(c, false)


# `later`: t at +INF, the other atoms as in `c`; otherwise t as in `c`, every other atom true.
func _eval_clock(c: BookContext, later: bool) -> bool:
	var i: int = 0
	for e: int in _clause_end:
		var ok: bool = true
		while i < e:
			if ok:
				if _atom[i] == Atom.T:
					ok = _cmp_holds(i, INF if later else c.t_s)
				elif later:
					ok = _holds(i, c)
			i += 1
		if ok:
			return true
	return _clause_end.is_empty()


func _holds(i: int, c: BookContext) -> bool:
	var a: int = _atom[i]
	if a == Atom.ENEMY_SEEN:
		return c.enemy_seen
	if a == Atom.AFFORDABLE:
		return c.affordable
	if a == Atom.PRESENCE:
		return c.presence
	var x: float = 0.0
	match a:
		Atom.T:
			x = c.t_s
		Atom.ORE:
			x = c.ore
		Atom.ICE:
			x = c.ice
		Atom.POWER01:
			x = c.power01
		_:
			var d: int = _def[i]
			var arr: PackedInt32Array = c.have_all if _all else c.have_done
			x = float(arr[d]) if d >= 0 and d < arr.size() else 0.0
	return _cmp_holds(i, x)


func _cmp_holds(i: int, x: float) -> bool:
	var v: float = _val[i]
	match _cmp[i]:
		Cmp.GE:
			return x >= v
		Cmp.GT:
			return x > v
		Cmp.LE:
			return x <= v
		Cmp.LT:
			return x < v
	return is_equal_approx(x, v)


func _add(atom: String, def_index: Dictionary, count_sites: bool) -> bool:
	var kind: int = -1
	var rest: String = ""
	var def: int = -1
	match atom:
		"enemy_seen":
			return _push(Atom.ENEMY_SEEN, Cmp.GE, -1, 0.0)
		"affordable":
			uses_affordable = true
			return _push(Atom.AFFORDABLE, Cmp.GE, -1, 0.0)
		"presence":
			uses_presence = true
			return _push(Atom.PRESENCE, Cmp.GE, -1, 0.0)
	if atom.begins_with("have:") or count_sites:
		kind = Atom.HAVE
		rest = atom.substr(5) if atom.begins_with("have:") else atom
		var at: int = _op_at(rest)
		if at <= 0:
			return false
		var name: StringName = StringName(rest.substr(0, at))
		if not def_index.has(name):
			return false
		def = BookParams.def_of(def_index, name)
		rest = rest.substr(at)
	else:
		for pair: Array in [["t", Atom.T], ["ore", Atom.ORE], ["ice", Atom.ICE], ["power01", Atom.POWER01]]:
			var key: String = pair[0]
			if atom.begins_with(key) and _op_at(atom) == key.length():
				kind = pair[1]
				rest = atom.substr(key.length())
				break
		if kind < 0:
			return false
	return _push_cmp(kind, rest, def)


# Index of the first comparison character, -1 when none.
func _op_at(s: String) -> int:
	for i: int in s.length():
		if "<>=".contains(s[i]):
			return i
	return -1


func _push_cmp(kind: int, rest: String, def: int) -> bool:
	var cmp: int = -1
	var num: String = ""
	for pair: Array in [[">=", Cmp.GE], ["<=", Cmp.LE], [">", Cmp.GT], ["<", Cmp.LT], ["=", Cmp.EQ]]:
		var op: String = pair[0]
		if rest.begins_with(op):
			cmp = pair[1]
			num = rest.substr(op.length())
			break
	if cmp < 0 or not num.is_valid_float():
		return false
	return _push(kind, cmp, def, num.to_float())


func _push(kind: int, cmp: int, def: int, v: float) -> bool:
	var _a: bool = _atom.push_back(kind)
	var _b: bool = _cmp.push_back(cmp)
	var _c: bool = _def.push_back(def)
	var _d: bool = _val.push_back(v)
	return true
