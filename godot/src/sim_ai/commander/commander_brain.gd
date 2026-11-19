class_name CommanderBrain extends AiBrain
## The Commander bot's think (05 s7.2-7.3; AI-23: the opening book; the reactive managers follow in AI-25..AI-27): one
## instance serves every bot slot of a session (`AiDriver.set_brain(cls, brain, true)` + `schedule_bot`). On the slot's
## staggered tick it reads the team's `Perception` (never an entity the team does not see), fills a `BookContext`, and runs
## the slot's `BookRun` for at most the tier's command cap (05 s7.8; `CommandGovernor`, AI-28, replaces the stand-in).
## The book of a slot is picked once, by weighted draw among its doctrine's books on the driver's AI RNG. S4 state: the
## slots, their book ids and runs (`serialize`).

const FORMAT: int = 1

var st_thinks: int = 0
var host: CommanderHost                ## the actions and their counters (`st_*`)

var _c: ContentSet
var _p: BookParams
var _sites: MapSites
var _hz: int
var _planner: BuildPlanner
var _ctx: BookContext = BookContext.new()
var _books: Array[OpeningBook] = []
var _rng: Rng = null
var _intel: TeamIntel = null
var _slots: PackedInt32Array = PackedInt32Array()
var _teams: PackedInt32Array = PackedInt32Array()
var _runs: Array[BookRun] = []


func _init(content: ContentSet, params: BookParams, sites: MapSites, tick_hz: int) -> void:
	_c = content
	_p = params
	_sites = sites
	_hz = tick_hz
	_planner = BuildPlanner.new(content, params, sites)
	host = CommanderHost.new(content, params, _planner, tick_hz)
	_ctx.size_defs(DefRanges.END)


## The books a doctrine's bots may open with (session configuration: from `ContentSet.build_orders` once compiled).
func set_books(books: Array[OpeningBook]) -> void:
	_books = books


func bind_rng(rng: Rng) -> void:
	_rng = rng


func bind_intel(intel: TeamIntel) -> void:
	_intel = intel


## Bot `slot`'s run (null before its first think, or when no book fits its doctrine).
func run_of(slot: int) -> BookRun:
	var i: int = _slots.find(slot)
	return _runs[i] if i >= 0 else null


func book_of(slot: int) -> OpeningBook:
	var r: BookRun = run_of(slot)
	return r.book if r != null else null


func think_bot(slot: int, tier: int, tick: int, view: SimView, sink: CommandSink) -> void:
	st_thinks += 1
	var i: int = _slots.find(slot)
	if i < 0:
		i = _register(slot, view)
	var run: BookRun = _runs[i]
	if run == null or run.done or _intel == null:
		return
	var perc: Perception = _intel.perception(_teams[i])
	if perc == null:
		return
	_planner.load_view(perc, view)
	_planner.enemy_hint = _enemy_hint(perc, view, slot, _teams[i])
	_fill(perc, view, _teams[i], tick)
	var cap: int = _p.cmds_per_think[clampi(tier, 0, _p.cmds_per_think.size() - 1)]
	host.bind_think(view, sink, perc, slot, tick, cap, _ctx.have_done)
	var _n: int = run.book.think(run, _ctx, host, tick, _hz, _p, cap)


## `{slot, book, cursor, done, outcomes}` for the bot inspector and tests.
func debug_state(slot: int) -> Dictionary:
	var r: BookRun = run_of(slot)
	if r == null:
		return {"slot": slot, "book": &"", "cursor": 0, "done": false}
	return {"slot": slot, "book": r.book.id, "cursor": r.cursor, "done": r.done, "outcomes": r.outcome.duplicate(),
			"commands": host.st_cmds, "accepted": host.st_accepted}


func _register(slot: int, view: SimView) -> int:
	var ps: PlayerStateView = view.player_state(slot)
	var team: int = ps.team
	var pick: OpeningBook = pick_book(ps.doctrine)
	var _a: bool = _slots.push_back(slot)
	var _b: bool = _teams.push_back(team)
	_runs.append(BookRun.new(pick) if pick != null else null)
	return _slots.size() - 1


## Weighted draw among the doctrine's books on the AI RNG (the first one without an RNG); null without a book.
func pick_book(doctrine: StringName) -> OpeningBook:
	var total: float = 0.0
	for b: OpeningBook in _books:
		if b.doctrine == doctrine:
			total += b.weight
	if total <= 0.0:
		return null
	var r: float = _rng.range_f(0.0, total) if _rng != null else 0.0
	for b: OpeningBook in _books:
		if b.doctrine == doctrine:
			r -= b.weight
			if r < 0.0:
				return b
	return null


func _fill(perc: Perception, view: SimView, team: int, tick: int) -> void:
	var sp: Vector3 = view.stockpile(team)
	_ctx.t_s = float(tick) / float(_hz)
	_ctx.ore = sp.x
	_ctx.ice = sp.y
	_ctx.power01 = sp.z
	_ctx.enemy_seen = perc.n_known > 0
	_ctx.have_done.fill(0)
	_ctx.have_all.fill(0)
	for i: int in perc.n_own:
		var d: int = perc.own_def[i]
		_ctx.have_all[d] += 1
		if (view.flags(perc.own_id[i]) & EntityStore.F_BUILDING) == 0:
			_ctx.have_done[d] += 1


# 05 s7.3 `approach:nearest_enemy`: the nearest known enemy structure, else the nearest start slot of another team's
# player (the lobby is public), else the nearest other start slot of the map.
func _enemy_hint(perc: Perception, view: SimView, slot: int, team: int) -> Vector3:
	var home: Vector3 = _sites.slot_dir(slot)
	var best: Vector3 = Vector3.ZERO
	var best_a: float = INF
	for i: int in _planner.foe_n:
		var a: float = home.angle_to(_planner.foe_dir[i])
		if a < best_a:
			best_a = a
			best = _planner.foe_dir[i]
	if best != Vector3.ZERO:
		return best
	for pass_other: int in 2:
		for s: int in _sites.slot_count():
			if s == slot or not _sites.has_slot(s):
				continue
			if pass_other == 0:
				var ps: PlayerStateView = view.player_state(s)
				if ps.team == team or ps.kind == PlayerTable.KIND_OPEN:
					continue
			var a2: float = home.angle_to(_sites.slot_dir(s))
			if a2 < best_a:
				best_a = a2
				best = _sites.slot_dir(s)
		if best != Vector3.ZERO:
			return best
	return perc.own_pos[0].normalized() * -1.0 if perc.n_own > 0 else Vector3.ZERO


func serialize() -> PackedByteArray:
	if _slots.is_empty():
		return PackedByteArray()
	var b: StreamPeerBuffer = StreamPeerBuffer.new()
	b.put_u8(FORMAT)
	b.put_u32(_slots.size())
	for i: int in _slots.size():
		b.put_32(_slots[i])
		b.put_u8(_teams[i])
		var rb: PackedByteArray = _runs[i].serialize() if _runs[i] != null else PackedByteArray()
		b.put_u32(rb.size())
		var _e: Error = b.put_data(rb)
	return b.data_array


## Empty bytes clear the slots; false for bytes that are malformed or name a book this session does not have.
func deserialize(bytes: PackedByteArray) -> bool:
	_slots.clear()
	_teams.clear()
	_runs.clear()
	if bytes.is_empty():
		return true
	var b: StreamPeerBuffer = StreamPeerBuffer.new()
	b.data_array = bytes
	if b.get_available_bytes() < 5 or b.get_u8() != FORMAT:
		return false
	var n: int = b.get_u32()
	for _i: int in n:
		if b.get_available_bytes() < 9:
			return _fail()
		var slot: int = b.get_32()
		var team: int = b.get_u8()
		var len_r: int = b.get_u32()
		if b.get_available_bytes() < len_r:
			return _fail()
		var rb: PackedByteArray = b.get_data(len_r)[1]
		var run: BookRun = null
		if len_r > 0:
			run = _run_from(rb)
			if run == null:
				return _fail()
		var _a: bool = _slots.push_back(slot)
		var _t: bool = _teams.push_back(team)
		_runs.append(run)
	return true


# The run in `rb`: its book is the session book whose id the bytes name.
func _run_from(rb: PackedByteArray) -> BookRun:
	if rb.size() < 8:
		return null
	var h: StreamPeerBuffer = StreamPeerBuffer.new()
	h.data_array = rb
	var _fmt: int = h.get_u8()
	var bid: String = h.get_utf8_string()
	for bk: OpeningBook in _books:
		if String(bk.id) == bid:
			var r: BookRun = BookRun.new(bk)
			return r if r.deserialize(rb) else null
	return null


func _fail() -> bool:
	_slots.clear()
	_teams.clear()
	_runs.clear()
	return false
