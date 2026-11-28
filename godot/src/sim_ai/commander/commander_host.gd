class_name CommanderHost extends BookHost
## The Commander's side of an opening book (05 s7.3): turns each book action into `Command`s through the `CommandSink` and
## the sim's verdict into an `OpeningBook.Out`. Everything it knows comes from the team's `Perception` lists, `SimView`
## reads of own entities and the planner; `bind_think` is called once per think. Verdicts: ACCEPTED -> DONE; a placement
## the sim refused for geometry (occupied, slope, node, radius, spacing, enemy radius) -> REJECT (the planner moves to the
## next candidate); funds, prerequisites, caps, locks, presence, vision and queue space -> WAIT; malformed -> FAIL.

const WAIT_REJECTS: PackedInt32Array = [Build.Reject.ELIMINATED, Build.Reject.PREREQ, Build.Reject.CAP,
		Build.Reject.NOT_VISIBLE, Build.Reject.NO_PRESENCE, Build.Reject.FUNDS, Build.Reject.SPEND_LOCKED]

const WAIT_FUNDS: int = 0
const WAIT_SITE: int = 1
const WAIT_CMDS: int = 2
const WAIT_PRESENCE: int = 3

var planner: BuildPlanner
var cmds_left: int = 0                 ## commands this think may still submit (the tier cap)
var st_cmds: int = 0
var st_accepted: int = 0
var st_placement_rejects: int = 0
var st_repeat_rejects: int = 0         ## a placement refused twice for the same def at the same cell
var st_locked: int = 0                 ## REJECTED_LOCKED / SPEND_LOCKED (the early share lock)
var st_by_reject: PackedInt32Array = PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])   ## REJECTED_PLACEMENT by Build.Reject
var st_by_code: PackedInt32Array = PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])   ## every verdict by CommandResult.Code
var st_waits: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])   ## WAIT answers of `build` by cause: WAIT_FUNDS, WAIT_SITE, WAIT_CMDS, WAIT_PRESENCE
var st_raids: int = 0                  ## `raid` steps handed to the military manager (AI-27)

var _c: ContentSet
var _p: BookParams
var _v: SimView
var _sink: CommandSink
var _perc: Perception
var _slot: int = 0
var _tick: int = 0
var _hz: int = 30
var _presence_m: float = 0.0
var _cost_ore: PackedInt32Array = PackedInt32Array()
var _cost_ice: PackedInt32Array = PackedInt32Array()
var _tbl_ore: Dictionary = {}                            ## slot -> doctrine-resolved Ore costs by def (02 s5; built at the slot's first think)
var _tbl_ice: Dictionary = {}
var _made_at: PackedInt32Array = PackedInt32Array()      ## unit def -> factory structure def (-1: none)
var _unit_defs: PackedInt32Array = PackedInt32Array()    ## every ship / ground def id
var _requires: Array[PackedInt32Array] = []              ## def -> the structure defs it needs finished (tech, 02 s5)
var _have_done: PackedInt32Array = PackedInt32Array()    ## the think's finished counts by def (BookContext.have_done)
var _ore: float = 0.0
var _ice: float = 0.0
var _last_rej_def: int = -1
var _last_rej_cell: int = -1
var _spec: OrderSpec = OrderSpec.make(OrderSpec.Kind.MOVE)
var _one: PackedInt32Array = PackedInt32Array([0])


func _init(content: ContentSet, params: BookParams, plan: BuildPlanner, tick_hz: int) -> void:
	_c = content
	_p = params
	planner = plan
	_hz = tick_hz
	_presence_m = content.economy.outpost_presence_radius_m if content.economy != null else 0.0
	var n: int = DefRanges.END
	var _r: Array[int] = [_cost_ore.resize(n), _cost_ice.resize(n), _made_at.resize(n)]
	_cost_ore.fill(0)
	_cost_ice.fill(0)
	_made_at.fill(-1)
	for _i: int in n:
		_requires.append(PackedInt32Array())
	for sd: StructureDef in content.structures:
		_cost_ore[sd.def_id] = sd.cost_ore
		_cost_ice[sd.def_id] = sd.cost_ice
		_requires[sd.def_id] = _ids(content, sd.requires)
	for sh: ShipDef in content.ships:
		_cost_ore[sh.def_id] = sh.cost_ore
		_cost_ice[sh.def_id] = sh.cost_ice
		_made_at[sh.def_id] = BookParams.def_of(content.entity_index, sh.produced_at)
		_requires[sh.def_id] = _ids(content, sh.requires)
		var _a: bool = _unit_defs.push_back(sh.def_id)
	for g: GroundUnitDef in content.ground_units:
		_cost_ore[g.def_id] = g.cost_ore
		_cost_ice[g.def_id] = g.cost_ice
		_made_at[g.def_id] = BookParams.def_of(content.entity_index, g.produced_at)
		_requires[g.def_id] = _ids(content, g.requires)
		var _b: bool = _unit_defs.push_back(g.def_id)


static func _ids(content: ContentSet, names: PackedStringArray) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for nm: String in names:
		var _a: bool = out.push_back(BookParams.def_of(content.entity_index, StringName(nm)))
	return out


## `have_done` = the think's finished-entity counts by def (the tech check reads them; the array is shared, not copied).
## The slot's costs under its doctrine (the sim charges the resolved ones): built once per slot from the content.
func bind_doctrine(slot: int, doctrine: StringName) -> void:
	var dd: DoctrineDef = null
	for d: DoctrineDef in _c.doctrines:
		if d.id == doctrine:
			dd = d
	var rd: ResolvedDefs = DoctrineResolver.resolve(dd, _c.ships, _c.ground_units, _c.structures, _c.weapons, _c.projectiles)
	var ore: PackedInt32Array = PackedInt32Array()
	var ice: PackedInt32Array = PackedInt32Array()
	var _r: Array[int] = [ore.resize(DefRanges.END), ice.resize(DefRanges.END)]
	for sd: StructureDef in rd.structures:
		ore[sd.def_id] = sd.cost_ore
		ice[sd.def_id] = sd.cost_ice
	for sh: ShipDef in rd.ships:
		ore[sh.def_id] = sh.cost_ore
		ice[sh.def_id] = sh.cost_ice
	for g: GroundUnitDef in rd.ground_units:
		ore[g.def_id] = g.cost_ore
		ice[g.def_id] = g.cost_ice
	_tbl_ore[slot] = ore
	_tbl_ice[slot] = ice


func bind_think(v: SimView, sink: CommandSink, perc: Perception, slot: int, tick: int, cap: int, have_done: PackedInt32Array) -> void:
	_have_done = have_done
	if not _tbl_ore.has(slot):
		bind_doctrine(slot, v.player_state(slot).doctrine)
	_cost_ore = _tbl_ore[slot]
	_cost_ice = _tbl_ice[slot]
	var sp: Vector3 = v.stockpile(v.player_state(slot).team)
	_ore = sp.x
	_ice = sp.y
	_v = v
	_sink = sink
	_perc = perc
	_slot = slot
	_tick = tick
	cmds_left = cap


func presence(tok: SiteToken, _def_id: int) -> bool:
	var dir: Vector3 = planner.anchor(tok, _slot, 0)
	return dir != Vector3.ZERO and _present_at(dir)


# An own, undocked unit inside the presence radius of the ground point under `dir` (current positions of own entities).
func _present_at(dir: Vector3) -> bool:
	var site: Vector3 = _ground(dir)
	var reach: float = _p.reach_m(_presence_m)   # presence_slack_cells of slack: the sim snaps the centre to its cell
	var r: float = reach * reach
	for i: int in _perc.n_own:
		var id: int = _perc.own_id[i]
		if planner.is_structure(_perc.own_def[i]) or _v.owner(id) != _slot or (_v.flags(id) & EntityStore.F_DOCKED) != 0:
			continue
		if _v.pos(id).distance_squared_to(site) <= r:
			return true
	return false


func affordable(_kind: int, def_id: int, n: int) -> bool:
	return float(_cost_ore[def_id] * n) <= _ore and float(_cost_ice[def_id] * n) <= _ice


# Not worth a command: the sim would answer COST or PREREQ (every think the same). The sim stays the judge otherwise.
func _can_try(def_id: int, n: int) -> bool:
	if not affordable(0, def_id, n):
		return false
	for r: int in _requires[def_id]:
		if r >= 0 and _have_done[r] == 0:
			return false
	return true


func build(def_id: int, tok: SiteToken, k: int, issued: int) -> int:
	if not _can_try(def_id, 1):
		st_waits[WAIT_FUNDS] += 1
		return OpeningBook.Out.WAIT
	var dir: Vector3 = planner.resolve_site(def_id, tok, _slot, k, issued)
	if planner.status == BuildPlanner.Status.UNRESOLVED:
		return OpeningBook.Out.FAIL
	if dir == Vector3.ZERO or cmds_left <= 0:
		st_waits[WAIT_SITE if dir == Vector3.ZERO else WAIT_CMDS] += 1
		return OpeningBook.Out.WAIT
	if tok.kind != SiteToken.Kind.CORE and planner.is_outpost_def(def_id) and not _present_at(dir):
		st_waits[WAIT_PRESENCE] += 1
		return OpeningBook.Out.WAIT
	var cell: int = Sphere.cell_of(dir, Sphere.GRID_BUILD)
	var r: CommandResult = _submit(Command.build(_slot, def_id, cell, 0))
	next_k = planner.last_k + 1
	if r.code == CommandResult.Code.ACCEPTED:
		planner.add_own(def_id, dir, false)
		return OpeningBook.Out.DONE
	if r.code != CommandResult.Code.REJECTED_PLACEMENT:
		return _wait_or_fail(r.code)
	st_by_reject[r.reject] += 1
	if r.reject == Build.Reject.SPEND_LOCKED:
		st_locked += 1
	if WAIT_REJECTS.has(r.reject):
		return OpeningBook.Out.WAIT
	st_placement_rejects += 1
	if def_id == _last_rej_def and cell == _last_rej_cell:
		st_repeat_rejects += 1
	_last_rej_def = def_id
	_last_rej_cell = cell
	return OpeningBook.Out.REJECT


func produce(def_id: int, count: int) -> int:
	var factory: int = _factory_for(def_id)
	if factory == 0 or cmds_left <= 0 or not _can_try(def_id, count):
		return OpeningBook.Out.WAIT
	var r: CommandResult = _submit(Command.produce(_slot, factory, def_id, count))
	return OpeningBook.Out.DONE if r.code == CommandResult.Code.ACCEPTED else _wait_or_fail(r.code)


func replenish(def_id: int, n: int) -> int:
	var factory: int = _factory_for(def_id)
	if factory == 0 or cmds_left <= 0:
		return OpeningBook.Out.WAIT
	var roster: PackedInt32Array = PackedInt32Array()   # the command replaces the player's targets: keep the others
	for u: int in _unit_defs:
		var t: int = n if u == def_id else _v.auto_replenish_target(_slot, u)
		if t > 0 and roster.size() < 16:
			var _a: bool = roster.push_back(u)
			var _b: bool = roster.push_back(t)
	var r: CommandResult = _submit(Command.toggle_auto_replenish(_slot, factory, true, roster))
	return OpeningBook.Out.DONE if r.code == CommandResult.Code.ACCEPTED else _wait_or_fail(r.code)


func order(kind: int, classes: PackedInt32Array, tok: SiteToken) -> int:
	if kind != OrderSpec.Kind.MOVE:
		return OpeningBook.Out.FAIL   # the other kinds are the military manager's (AI-27)
	var dir: Vector3 = planner.anchor(tok, _slot, 0)
	if dir == Vector3.ZERO:
		return OpeningBook.Out.FAIL if planner.status == BuildPlanner.Status.UNRESOLVED else OpeningBook.Out.WAIT
	var site: Vector3 = _ground(dir)
	var id: int = _pick_unit(classes, site)
	if id == 0 or cmds_left <= 0:
		return OpeningBook.Out.WAIT
	_one[0] = id
	_spec.point = site + dir * _p.move_agl_m
	var r: CommandResult = _submit(Command.order(_slot, _one, _spec))
	return OpeningBook.Out.DONE if r.code == CommandResult.Code.ACCEPTED else _wait_or_fail(r.code)


func raid(_target: StringName, _with: StringName) -> int:
	st_raids += 1
	return OpeningBook.Out.DONE


func _submit(cmd: Command) -> CommandResult:
	cmds_left -= 1
	st_cmds += 1
	var r: CommandResult = _sink.submit(cmd)
	st_by_code[r.code] += 1
	if r.code == CommandResult.Code.ACCEPTED:
		st_accepted += 1
	elif r.code == CommandResult.Code.REJECTED_LOCKED:
		st_locked += 1
	return r


func _wait_or_fail(code: int) -> int:
	return OpeningBook.Out.FAIL if code == CommandResult.Code.REJECTED_MALFORMED else OpeningBook.Out.WAIT


func _ground(dir: Vector3) -> Vector3:
	return dir * (Sphere.PLANET_RADIUS + _v.terrain_height(dir))


# The first finished own factory that makes `unit_def` (the team shares its queues).
func _factory_for(unit_def: int) -> int:
	var f: int = _made_at[unit_def] if unit_def < _made_at.size() else -1
	if f < 0:
		return 0
	for i: int in _perc.n_own:
		if _perc.own_def[i] == f and (_v.flags(_perc.own_id[i]) & EntityStore.F_BUILDING) == 0:
			return _perc.own_id[i]
	return 0


# The own unit of `classes` nearest to `site` that is free: not POSSESSED, not under a human's order inside the lock. An
# undocked unit is preferred (a docked one waits for SERVICED, 05 s6 DOCKED row); a docked one only when none else exists.
func _pick_unit(classes: PackedInt32Array, site: Vector3) -> int:
	var best: int = 0
	var best_d: float = INF
	var dock: int = 0
	var dock_d: float = INF
	for i: int in _perc.n_own:
		var id: int = _perc.own_id[i]
		if not classes.has(_perc.own_def[i]) or _v.owner(id) != _slot or _v.possessor(id) != -1:
			continue
		var h: OrderSpec = _v.order_head(id)
		if h != null and h.issuer != -1 and h.issuer != _slot and float(_tick - h.issue_tick) < _p.lock_s * float(_hz):
			continue
		var d: float = _perc.own_pos[i].distance_squared_to(site)
		if (_v.flags(id) & EntityStore.F_DOCKED) != 0:
			if d < dock_d:
				dock_d = d
				dock = id
		elif d < best_d:
			best_d = d
			best = id
	return best if best != 0 else dock
