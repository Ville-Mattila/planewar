class_name OpeningBook extends RefCounted
## An opening book (05 s7.3): the compiled form of one `build_orders.json` entry and the interpreter that runs it. Steps
## run in order; a step waits for its `when`, `skip_if_have` skips it, the host does the work and answers `Out`. A
## REJECTED_PLACEMENT makes the next think try the next candidate site and `max_rejects` of them skip the step; a due step
## that cannot complete for `stall_s` is skipped; an Outpost step waits for presence (the `order move` before it is
## re-issued every `presence_retry_s`); the book hands over to the reactive planner after the last step or at
## `book_end_s`. Compiled once (typed arrays per step); `think` allocates nothing. Run state lives in `BookRun`.

enum Do { BUILD, PRODUCE, SET_REPLENISH, ORDER, RAID }
enum Out { DONE, WAIT, REJECT, FAIL }

const MAX_UNITS_PER_STEP: int = 25

var id: StringName = &""
var doctrine: StringName = &""       ## "" for a campaign script (05 s7.10)
var mode: StringName = &"replace"    ## script books: `replace` | `prepend`
var reactive: bool = true            ## script books: false keeps the reactive managers off
var weight: float = 1.0              ## weighted pick among a doctrine's books
var n_steps: int = 0

var _do: PackedByteArray = PackedByteArray()
var _def: PackedInt32Array = PackedInt32Array()
var _count: PackedInt32Array = PackedInt32Array()
var _okind: PackedByteArray = PackedByteArray()
var _tok: Array[SiteToken] = []
var _when: Array[BookCondition] = []
var _skip: Array[BookCondition] = []
var _classes: Array[PackedInt32Array] = []
var _text: Array[PackedStringArray] = []     ## raid: [target, with]; produce: [then_order]


## Null with `errors` filled when the entry is not a valid book: unknown def / kind / token, a bad condition, no steps, or
## a `build outpost` that is not preceded by an `order move` to the same site and carries no `presence` (05 s7.3).
static func compile(e: Dictionary, content: ContentSet, errors: Array[String]) -> OpeningBook:
	var b: OpeningBook = OpeningBook.new()
	b.id = StringName(str(e.get("id", "")))
	if b.id == &"":
		errors.append("book without an id")
	b.doctrine = StringName(str(e["doctrine"])) if e.get("doctrine", null) != null else &""
	b.mode = StringName(str(e.get("mode", "replace")))
	b.reactive = Def.flag(e.get("reactive", true))
	b.weight = Def.num(e.get("weight", 1.0))
	var steps_v: Variant = e.get("steps", [])
	var steps: Array = steps_v if steps_v is Array else []
	if steps.is_empty():
		errors.append("%s: no steps" % b.id)
		return null
	if b.weight <= 0.0:
		errors.append("%s: weight must be positive" % b.id)
	var kinds: Dictionary = _kinds(content)
	for i: int in steps.size():
		var s: Variant = steps[i]
		var sd: Dictionary = s if s is Dictionary else {}
		if not (s is Dictionary) or not b._read_step(sd, i, content, kinds, errors):
			errors.append("%s step %d: unreadable" % [b.id, i])
	b._check_outposts(content, errors)
	return null if not errors.is_empty() else b


func kind_of(i: int) -> int:
	return _do[i]


func def_of(i: int) -> int:
	return _def[i]


func count_of(i: int) -> int:
	return _count[i]


func token_of(i: int) -> SiteToken:
	return _tok[i]


func classes_of(i: int) -> PackedInt32Array:
	return _classes[i]


func when_of(i: int) -> BookCondition:
	return _when[i]


func order_kind_of(i: int) -> int:
	return _okind[i]


## Runs the cursor step(s) of `run` against `host` until one waits, `budget` commands were issued or the book ends.
## `tick` is the sim tick, `hz` its rate; returns the commands issued (DONE outcomes).
func think(run: BookRun, ctx: BookContext, host: BookHost, tick: int, hz: int, p: BookParams, budget: int) -> int:
	if run.done:
		return 0
	if ctx.t_s >= p.book_end_s:
		run.done = true
		return 0
	var sent: int = 0
	while run.cursor < n_steps and sent < budget:
		var i: int = run.cursor
		if _skip[i] != null and _skip[i].eval(ctx):
			run.finish(BookRun.SKIPPED_HAVE)
			continue
		if not _due(i, ctx, host):
			if run.cursor == i and _when[i].uses_presence and _retry_move(i, run, host, tick, hz, p):
				sent += 1
			break
		if run.due_tick < 0:
			run.due_tick = tick
		elif float(tick - run.due_tick) >= p.stall_s * float(hz):
			run.finish(BookRun.SKIPPED_STALL)
			continue
		var out: int = _act(i, run, host)
		if out == Out.DONE:
			sent += 1
			continue
		if out == Out.FAIL:
			run.finish(BookRun.SKIPPED_FAIL)
		elif out == Out.REJECT:
			run.rejects += 1
			run.cand_k = host.next_k
			if run.rejects >= p.max_rejects:
				run.finish(BookRun.SKIPPED_REJECTS)
				continue
			break
		else:
			break
	if run.cursor >= n_steps:
		run.done = true
	return sent


# `when` of step i against the context (the host fills `presence` / `affordable` when the condition reads them).
func _due(i: int, ctx: BookContext, host: BookHost) -> bool:
	var w: BookCondition = _when[i]
	if w.uses_presence:
		ctx.presence = host.presence(_tok[i], _def[i])
	if w.uses_affordable:
		ctx.affordable = host.affordable(_do[i], _def[i], _count[i])
	return w.eval(ctx)


# An Outpost step with no unit in place after `presence_retry_s`: the `order move` before it goes out again.
func _retry_move(i: int, run: BookRun, host: BookHost, tick: int, hz: int, p: BookParams) -> bool:
	if run.wait_tick < 0:
		run.wait_tick = tick
		return false
	if float(tick - run.wait_tick) < p.presence_retry_s * float(hz) or i == 0 or _do[i - 1] != Do.ORDER:
		return false
	run.wait_tick = tick
	return host.order(_okind[i - 1], _classes[i - 1], _tok[i - 1]) == Out.DONE


# One attempt at step i; DONE advances the cursor (a build / produce step with n > 1 stays until all n are issued).
func _act(i: int, run: BookRun, host: BookHost) -> int:
	var out: int = Out.FAIL
	match _do[i]:
		Do.BUILD:
			out = host.build(_def[i], _tok[i], run.cand_k, run.issued)
			if out == Out.DONE:
				run.issued += 1
				run.rejects = 0
				run.cand_k = 0
				if run.issued < _count[i]:
					return out
		Do.PRODUCE:
			var n: int = mini(_count[i] - run.issued, 5)
			out = host.produce(_def[i], n)
			if out == Out.DONE:
				run.issued += n
				if run.issued < _count[i]:
					return out
		Do.SET_REPLENISH:
			out = host.replenish(_def[i], _count[i])
		Do.ORDER:
			out = host.order(_okind[i], _classes[i], _tok[i])
		Do.RAID:
			out = host.raid(StringName(_text[i][0]), StringName(_text[i][1]))
	if out == Out.DONE:
		run.finish(BookRun.DONE)
	return out


static func _kinds(c: ContentSet) -> Dictionary:
	var k: Dictionary = {}
	for sd: StructureDef in c.structures:
		k[sd.id] = EntityStore.K_STRUCTURE
	for sh: ShipDef in c.ships:
		k[sh.id] = EntityStore.K_SHIP
	for g: GroundUnitDef in c.ground_units:
		k[g.id] = EntityStore.K_GROUND
	return k


func _read_step(s: Dictionary, i: int, c: ContentSet, kinds: Dictionary, errors: Array[String]) -> bool:
	var tag: String = "%s step %d" % [id, i]
	var what: String = str(s.get("do", ""))
	var kind: int = ["build", "produce", "set_replenish", "order", "raid"].find(what)
	if kind < 0:
		errors.append("%s: unknown step kind '%s'" % [tag, what])
		return false
	var cond: BookCondition = BookCondition.compile(str(s.get("when", "")), c.entity_index)
	var skip: BookCondition = BookCondition.compile(str(s["skip_if_have"]), c.entity_index, true) if s.has("skip_if_have") else null
	if cond == null or (s.has("skip_if_have") and skip == null):
		errors.append("%s: bad condition" % tag)
		return false
	var def: int = -1
	var dname: StringName = StringName(str(s.get("def", "")))
	var n: int = roundi(Def.num(s.get("n", 1)))
	var ok: bool = true
	var tok: SiteToken = null
	var okind: int = 0
	var classes: PackedInt32Array = PackedInt32Array()
	var text: PackedStringArray = PackedStringArray(["", ""])
	if kind == Do.BUILD or kind == Do.PRODUCE or kind == Do.SET_REPLENISH:
		def = BookParams.def_of(c.entity_index, dname)
		var want: bool = kinds.get(dname, -1) == EntityStore.K_STRUCTURE
		if def < 0 or (kind == Do.BUILD) != want:
			errors.append("%s: def '%s' is not a %s" % [tag, dname, "structure" if kind == Do.BUILD else "unit"])
			ok = false
		if n < (0 if kind == Do.SET_REPLENISH else 1) or n > MAX_UNITS_PER_STEP:
			errors.append("%s: bad n %d" % [tag, n])
			ok = false
		text[0] = str(s.get("then_order", ""))
	if kind == Do.BUILD or kind == Do.ORDER:
		tok = SiteToken.parse(str(s.get("near" if kind == Do.BUILD else "to", "")))
		if tok == null:
			errors.append("%s: bad location '%s'" % [tag, str(s.get("near" if kind == Do.BUILD else "to", ""))])
			ok = false
	if kind == Do.ORDER:
		okind = OrderSpec.kind_from_name(str(s.get("kind", "")))
		if okind < 0:
			errors.append("%s: unknown order kind" % tag)
			ok = false
		for u: String in str(s.get("unit", "")).split("|", false):
			var d: int = BookParams.def_of(c.entity_index, StringName(u))
			if d < 0 or kinds.get(StringName(u), -1) == EntityStore.K_STRUCTURE:
				errors.append("%s: unknown unit class '%s'" % [tag, u])
				ok = false
			else:
				var _a: bool = classes.push_back(d)
		if classes.is_empty():
			errors.append("%s: order without units" % tag)
			ok = false
	if kind == Do.RAID:
		text[0] = str(s.get("target", ""))
		text[1] = str(s.get("with", ""))
		if text[0].is_empty():
			errors.append("%s: raid without a target" % tag)
			ok = false
	_append(kind, def, n, okind, tok, cond, skip, classes, text)
	return ok


func _append(kind: int, def: int, n: int, okind: int, tok: SiteToken, cond: BookCondition, skip: BookCondition,
		classes: PackedInt32Array, text: PackedStringArray) -> void:
	var _a: bool = _do.push_back(kind)
	var _b: bool = _def.push_back(def)
	var _c: bool = _count.push_back(n)
	var _d: bool = _okind.push_back(okind)
	_tok.append(tok)
	_when.append(cond)
	_skip.append(skip)
	_classes.append(classes)
	_text.append(text)
	n_steps += 1


# 05 s7.3: every `build outpost` follows an `order move` to the same site and carries `when: presence`.
func _check_outposts(c: ContentSet, errors: Array[String]) -> void:
	var outpost: int = BookParams.def_of(c.entity_index, &"outpost")
	for i: int in n_steps:
		if _do[i] != Do.BUILD or _def[i] != outpost or _tok[i] == null:
			continue
		if not _when[i].uses_presence:
			errors.append("%s step %d: build outpost needs when: presence" % [id, i])
		if i == 0 or _do[i - 1] != Do.ORDER or _okind[i - 1] != OrderSpec.Kind.MOVE or _tok[i - 1] == null or _tok[i - 1].src != _tok[i].src:
			errors.append("%s step %d: build outpost needs an order move to the same site just before it" % [id, i])
