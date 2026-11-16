class_name HarvesterBrain extends AiBrain
## The Harvester autopilot (05 s6.6, s5.7; AI-16). It drives the sim's mining cycle (`sim/harvest`, GD-12) and decides
## nothing the sim decides: it takes the unit to a mining spot inside a field (the sim claims a miner slot when the unit
## stands still there), to the dock stop beside a Refinery (the sim unloads), and picks the next field. AiTag modes:
## PICK_FIELD -> TO_FIELD -> MINE -> TO_REFINERY -> QUEUE / UNLOAD -> PICK_FIELD (sticky to the same field), FLEE, and for
## orders HOLD / MOVE (HARVEST_HERE = the cycle on the field nearest the order's point, AUTO when it runs dry).
## Think (every `think_period_ticks`, staggered): the order, the threat (a hull loss within `hit_window_s`, or an armed enemy
## ship the team sees within `flee_radius_m`), then the mode's transitions and the route health (ticket timeout = a stuck
## strike, `NO_PATH`, a path-grid face of the route changed, off the route, no progress for 10 s: repath, then another
## destination, then give up to PICK_FIELD). Act (every tick): poll the ticket, then `GroundFollower.drive`; a unit without a
## route waits (BRAKE, then still). State is `AiState` only: mode, `aux_id` = field + 1, `target` = Refinery or flee site,
## `goal`, `bflags`, `hp_mark` / `mark_tick`, `order_tick`, `path`, `ground`. Vision only: ships come from `TeamPicture`,
## structures of the own team, fields from the map.

const B_ARRIVED: int = 1   ## bflags: the act reached the goal (cleared by the think that takes the next step)
const B_MINED: int = 2     ## bflags: the unit has been MINING on this arrival
const B_NOPATH: int = 4    ## bflags: the sim proved the last request has no route
const B_DRY: int = 8       ## bflags: the HARVEST_HERE field ran dry: the order is AUTO from then on (cleared by a new order)
const HP_EPS: float = 0.0001

var prm: HarvesterParams
var sites: HarvestSites
var picture: TeamPicture = TeamPicture.new()
var stats_thinks: int = 0
var stats_picks: int = 0
var stats_strikes: int = 0
var stats_gave_up: int = 0       ## destinations given up after three strikes (05 s5.7: ORDER_FAILED(STUCK) has no sink call yet)
var stats_flees: int = 0
var _inp: PilotInput = PilotInput.new()


## The Harvester brain from content (`ap` = the `ap_harvester` dictionary); null when a key is missing.
static func create(c: ContentSet, ap: Dictionary, def: GroundUnitDef) -> HarvesterBrain:
	var p: HarvesterParams = HarvesterParams.from_content(c, ap, def)
	if p == null:
		return null
	var b: HarvesterBrain = HarvesterBrain.new()
	b.prm = p
	var def_id: int = c.entity_index.get(def.id, -1)
	b.sites = HarvestSites.new(p, def_id)
	b.picture.period = p.vision_period
	return b


## Copies the map's field geometry (call after the map load and again after a restore, like the class table).
func bind_fields(f: OreFields) -> void:
	sites.bind_fields(f)


func bind_rng(_rng: Rng) -> void:
	picture.reset()


func think_batch(ids: PackedInt32Array, n: int, view: SimView, st: AiState, sink: CommandSink, tick: int) -> void:
	for i: int in n:
		think_one(ids[i], view, st, sink, tick)


func act_batch(ids: PackedInt32Array, view: SimView, st: AiState, sink: CommandSink) -> void:
	var tick: int = view.tick()
	for id: int in ids:
		_act(id, EntityId.slot(id), view, st, sink, tick)


# --- act -------------------------------------------------------------------------------------------------------------

## True for the modes that follow a route.
static func moving(m: int) -> bool:
	return m == AiTag.Tag.TO_FIELD or m == AiTag.Tag.TO_REFINERY or m == AiTag.Tag.FLEE or m == AiTag.Tag.MOVE


func _act(id: int, s: int, view: SimView, st: AiState, sink: CommandSink, tick: int) -> void:
	_inp.pitch = 0.0
	_inp.roll = 0.0
	if not moving(st.mode[s]):
		GroundFollower.stop(_inp)
	else:
		if GroundFollower.poll(s, st, sink, view) == GroundFollower.Poll.NO_PATH:
			st.bflags[s] |= B_NOPATH
		if GroundFollower.has_route(s, st):
			var fwd: Vector3 = -view.basis(id).z
			if GroundFollower.drive(s, view.pos(id), fwd, tick, st, prm.ground, _inp) == GroundFollower.Drive.ARRIVED:
				st.bflags[s] |= B_ARRIVED
		else:
			GroundFollower.wait(s, tick, st, prm.ground, _inp)
	var _ok: bool = sink.drive(id, _inp)
	if _ok and st.overlay[s] == Overlays.NONE:   # an overlay overrides this drive and books its own; a refused one is the pilot's
		GroundFollower.book_brake(s, _inp.buttons, st)


# --- think -----------------------------------------------------------------------------------------------------------

## One think of `id` (rigs, perf).
func think_one(id: int, view: SimView, st: AiState, sink: CommandSink, tick: int) -> void:
	stats_thinks += 1
	var s: int = EntityId.slot(id)
	var p: Vector3 = view.pos(id)
	var head: OrderSpec = view.order_head(id)
	if _order(id, s, head, p, view, st, sink, tick):
		return
	if _flee(id, s, head, p, view, st, sink, tick):
		return
	match st.mode[s]:
		AiTag.Tag.TO_FIELD, AiTag.Tag.TO_REFINERY:
			_travel(id, s, p, view, st, sink, tick)
		AiTag.Tag.MINE:
			_mine(id, s, p, view, st, sink, tick)
		AiTag.Tag.QUEUE, AiTag.Tag.UNLOAD:
			_dock(id, s, p, view, st, sink, tick)
		_:
			_pick(id, s, p, -1, view, st, sink, tick)


func _mode(id: int, s: int, m: int, st: AiState, sink: CommandSink, tick: int) -> void:
	if st.mode[s] != m:
		sink.set_ai_tag(id, m)
		st.set_mode(id, m, tick)


# A new head order restarts the cycle; HOLD stops, MOVE drives to its point (stays there). True when the order took the think.
func _order(id: int, s: int, head: OrderSpec, p: Vector3, view: SimView, st: AiState, sink: CommandSink, tick: int) -> bool:
	var kind: int = head.kind if head != null else -1
	var issued: int = head.issue_tick if head != null else -1
	var point: Vector3 = head.point if head != null else Vector3.ZERO
	if issued != st.order_tick[s]:
		st.order_tick[s] = issued
		_reset(s, st, sink)
		st.bflags[s] = 0
		_mode(id, s, AiTag.Tag.PICK_FIELD, st, sink, tick)
	if kind == OrderSpec.Kind.HOLD:
		_mode(id, s, AiTag.Tag.HOLD, st, sink, tick)
		return true
	if kind != OrderSpec.Kind.MOVE:
		return false
	if st.mode[s] != AiTag.Tag.MOVE:
		_mode(id, s, AiTag.Tag.MOVE, st, sink, tick)
		_start(s, p, point, st, sink, tick)
	elif (st.bflags[s] & B_ARRIVED) == 0:
		_route_health(id, s, p, view, st, sink, tick)
	return true


func _reset(s: int, st: AiState, sink: CommandSink) -> void:
	GroundFollower.clear(s, st, sink)
	st.ground.strikes[s] = 0
	st.bflags[s] &= B_DRY
	st.aux_id[s] = 0
	st.set_target(s, 0)


# Asks for a route to `goal`; the unit waits (BRAKE) until it arrives.
func _start(s: int, p: Vector3, goal: Vector3, st: AiState, sink: CommandSink, tick: int) -> void:
	st.bflags[s] &= ~(B_ARRIVED | B_NOPATH)
	var _ok: bool = GroundFollower.request(s, p, goal, prm.mask, st, sink, tick)


# --- threat ----------------------------------------------------------------------------------------------------------

func _threat(id: int, s: int, p: Vector3, view: SimView, st: AiState, tick: int) -> bool:
	var hp: float = view.hp01(id)
	var hit: bool = false
	hit = hp < st.hp_mark[s] - HP_EPS   # compare first: a loss in the think that re-bases the window still counts
	if tick - st.mark_tick[s] >= prm.hit_ticks:
		st.mark_tick[s] = tick
		st.hp_mark[s] = hp
	else:
		st.hp_mark[s] = maxf(st.hp_mark[s], hp)
	var armed: bool = _armed(id, p, view, tick) != 0
	if hit or armed:
		st.ground.threat[s] = tick
	return hit or armed


# The first armed enemy ship the team sees within `flee_radius_m` (ascending ids), 0 for none.
func _armed(id: int, p: Vector3, view: SimView, tick: int) -> int:
	var n: int = picture.near(view, view.team(id), tick, p, prm.flee_radius_m)
	for k: int in n:
		var e: int = picture.near_ids()[k]
		if prm.is_armed(view.def_id(e)):
			return e
	return 0


# FLEE: start on a threat, hold while one was seen within `quiet_s`, then resume the cycle. True when FLEE took the think.
func _flee(id: int, s: int, head: OrderSpec, p: Vector3, view: SimView, st: AiState, sink: CommandSink, tick: int) -> bool:
	var ordered: bool = head != null and (head.kind == OrderSpec.Kind.HOLD or head.kind == OrderSpec.Kind.MOVE)
	var seen: bool = _threat(id, s, p, view, st, tick) and not ordered
	if st.mode[s] != AiTag.Tag.FLEE:
		if seen:
			_start_flee(id, s, p, view, st, sink, tick)
		return seen
	if st.ground.threat[s] != 0 and tick - st.ground.threat[s] < prm.quiet_ticks:
		var site: int = st.target[s]
		if site != 0 and not view.alive(site):
			_start_flee(id, s, p, view, st, sink, tick)   # the site was destroyed
		elif (st.bflags[s] & B_ARRIVED) == 0:
			_route_health(id, s, p, view, st, sink, tick)
		return true
	_reset(s, st, sink)
	if view.cargo(id) > 0.0:
		_go_refinery(id, s, p, 0, view, st, sink, tick)
	else:
		_mode(id, s, AiTag.Tag.PICK_FIELD, st, sink, tick)
	return true


func _start_flee(id: int, s: int, p: Vector3, view: SimView, st: AiState, sink: CommandSink, tick: int) -> void:
	stats_flees += 1
	var team: int = view.team(id)
	var foe: int = _armed(id, p, view, tick)
	var threat: Vector3 = view.pos(foe) if foe != 0 else p
	var site: int = sites.flee_site(view, team, p, threat)
	st.set_target(s, site)
	_mode(id, s, AiTag.Tag.FLEE, st, sink, tick)
	var goal: Vector3 = sites.dock_stop(view, site, p) if site != 0 else HarvestSites.toward(p, threat, -prm.flee_radius_m)
	_start(s, p, goal, st, sink, tick)


# --- the cycle -------------------------------------------------------------------------------------------------------

func _pick(id: int, s: int, p: Vector3, avoid: int, view: SimView, st: AiState, sink: CommandSink, tick: int) -> void:
	if view.cargo(id) >= prm.cargo_ore - 0.5:
		_go_refinery(id, s, p, 0, view, st, sink, tick)
		return
	stats_picks += 1
	var head: OrderSpec = view.order_head(id)
	var f: int = -1
	if head != null and head.kind == OrderSpec.Kind.HARVEST_HERE and (st.bflags[s] & B_DRY) == 0:
		var o: int = sites.nearest_field(head.point)
		f = o if o >= 0 and view.field_remaining(o) > 0 else -1
		if f < 0:
			st.bflags[s] |= B_DRY   # the ordered field is dry: the order falls back to AUTO (05 s3.2), for good
	if f < 0:
		f = sites.pick_field(view, view.team(id), p, avoid, st.aux_id[s] - 1)
	if f < 0:
		_mode(id, s, AiTag.Tag.PICK_FIELD, st, sink, tick)
		GroundFollower.clear(s, st, sink)
		return
	st.aux_id[s] = f + 1
	_mode(id, s, AiTag.Tag.TO_FIELD, st, sink, tick)
	_start(s, p, sites.spot(f, s), st, sink, tick)


func _go_refinery(id: int, s: int, p: Vector3, avoid: int, view: SimView, st: AiState, sink: CommandSink, tick: int) -> void:
	var r: int = sites.best_refinery(view, view.team(id), p, tick, avoid)
	st.set_target(s, r)
	_mode(id, s, AiTag.Tag.TO_REFINERY, st, sink, tick)
	if r == 0:
		GroundFollower.clear(s, st, sink)   # none yet: wait, ask again next think
		return
	_start(s, p, sites.dock_stop(view, r, p), st, sink, tick)


func _travel(id: int, s: int, p: Vector3, view: SimView, st: AiState, sink: CommandSink, tick: int) -> void:
	var m: int = st.mode[s]
	if (st.bflags[s] & B_ARRIVED) != 0:
		st.bflags[s] &= ~(B_ARRIVED | B_MINED)
		st.ground.strikes[s] = 0
		GroundFollower.clear(s, st, sink)
		_mode(id, s, AiTag.Tag.MINE if m == AiTag.Tag.TO_FIELD else AiTag.Tag.QUEUE, st, sink, tick)
	elif m == AiTag.Tag.TO_REFINERY and not sites.usable(view, view.team(id), st.target[s]):
		_go_refinery(id, s, p, 0, view, st, sink, tick)   # gone, captured or none yet
	elif m == AiTag.Tag.TO_FIELD and view.field_remaining(st.aux_id[s] - 1) <= 0:
		st.bflags[s] |= B_DRY
		_pick(id, s, p, st.aux_id[s] - 1, view, st, sink, tick)   # drained on the way
	else:
		_route_health(id, s, p, view, st, sink, tick)


func _mine(id: int, s: int, p: Vector3, view: SimView, st: AiState, sink: CommandSink, tick: int) -> void:
	var dry: bool = view.field_remaining(st.aux_id[s] - 1) <= 0   # empty (regen's trickle never refills a unit's load)
	if dry:
		st.bflags[s] |= B_DRY   # a HARVEST_HERE field that ran dry: the order is AUTO from now on
	elif Harvest.state_of(view.link(id)) == Harvest.State.MINING:
		st.bflags[s] |= B_MINED
		return
	elif (st.bflags[s] & B_MINED) == 0 and tick - st.mode_since[s] < prm.claim_wait_ticks:
		return   # just arrived: the sim claims a miner slot while the unit stands still in the field
	if view.cargo(id) > 0.0:
		_go_refinery(id, s, p, 0, view, st, sink, tick)   # full, or the field ran dry: a partial load is delivered (02 s8.2)
	else:
		_pick(id, s, p, st.aux_id[s] - 1, view, st, sink, tick)   # nothing mined here (no slot, dry): another field


func _dock(id: int, s: int, p: Vector3, view: SimView, st: AiState, sink: CommandSink, tick: int) -> void:
	if view.cargo(id) <= 0.0:
		_pick(id, s, p, -1, view, st, sink, tick)   # unloaded: the same field unless its utility fell (sticky)
		return
	var state: int = Harvest.state_of(view.link(id))
	if state == Harvest.State.UNLOADING:
		_mode(id, s, AiTag.Tag.UNLOAD, st, sink, tick)
	elif state == Harvest.State.WAITING:
		_mode(id, s, AiTag.Tag.QUEUE, st, sink, tick)
	elif tick - st.mode_since[s] >= prm.unload_wait_ticks or not sites.usable(view, view.team(id), st.target[s]):
		_go_refinery(id, s, p, st.target[s], view, st, sink, tick)   # out of the sim's reach or the Refinery is gone


# --- route health (05 s5.7) ------------------------------------------------------------------------------------------

func _route_health(id: int, s: int, p: Vector3, view: SimView, st: AiState, sink: CommandSink, tick: int) -> void:
	var g: AiGround = st.ground
	if (st.bflags[s] & B_NOPATH) != 0:
		st.bflags[s] &= ~B_NOPATH
		g.strikes[s] = maxi(g.strikes[s], 1)
		_strike(id, s, p, view, st, sink, tick)
	elif st.path_ticket[s] >= 0:
		if tick - g.req[s] >= prm.ground.path_wait_ticks:
			_strike(id, s, p, view, st, sink, tick)   # a ticket not answered in time
	elif not GroundFollower.has_route(s, st):
		_start(s, p, st.goal[s], st, sink, tick)       # refused (no free ticket) or cleared: ask again
	elif GroundFollower.changed(s, st, view) or GroundFollower.off_route(s, p, st, prm.ground):
		_start(s, p, st.goal[s], st, sink, tick)       # the world or the unit changed: repath, no strike
	elif GroundFollower.stuck(s, p, tick, st, prm.ground):
		_strike(id, s, p, view, st, sink, tick)


# Strike 1: repath. Strike 2: another destination (another field / Refinery). Strike 3: give up the destination.
func _strike(id: int, s: int, p: Vector3, view: SimView, st: AiState, sink: CommandSink, tick: int) -> void:
	stats_strikes += 1
	var n: int = st.ground.strikes[s] + 1
	st.ground.strikes[s] = n
	var m: int = st.mode[s]
	if n == 1 or ((m == AiTag.Tag.FLEE or m == AiTag.Tag.MOVE) and n == 2):
		_start(s, p, st.goal[s], st, sink, tick)
	elif n == 2 and m == AiTag.Tag.TO_FIELD:
		_pick(id, s, p, st.aux_id[s] - 1, view, st, sink, tick)
	elif n == 2 and m == AiTag.Tag.TO_REFINERY:
		_go_refinery(id, s, p, st.target[s], view, st, sink, tick)
	else:
		stats_gave_up += 1
		st.ground.strikes[s] = 0
		_reset(s, st, sink)
		_mode(id, s, AiTag.Tag.MOVE if m == AiTag.Tag.MOVE else AiTag.Tag.PICK_FIELD, st, sink, tick)
