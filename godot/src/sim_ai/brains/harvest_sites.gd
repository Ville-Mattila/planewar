class_name HarvestSites extends RefCounted
## What the Harvester brain knows about where to go (05 s6.6; AI-16): the map's Ore Fields (static geometry copied from
## `OreFields` once; Ore left is read live through `SimView.field_remaining`, the sim's own count), the team's finished
## Refineries and towers (`SimView.structures()` scans, a Refinery list cached per team for `scan_ticks`, a tower scan only
## when a Harvester starts to flee), and the points to drive to: a mining spot inside a field, the dock stop beside a Refinery.
## Crowding (`assigned`, free miner slots) is counted from the Harvesters near a field (`ids_near`, the team's own plus the
## enemy's it sees); every read is `SimView` only. Runs at choice points (once per trip), never per tick.

const GOLDEN_RAD: float = 2.3999632297286533   ## the golden angle: spreads the mining spots of different slots

var prm: HarvesterParams = null
var harvester_def: int = -1
var scans: int = 0                              ## structure-list scans made (tests, perf)
var _dir: PackedVector3Array = PackedVector3Array()
var _radius: PackedFloat32Array = PackedFloat32Array()
var _max_miners: PackedInt32Array = PackedInt32Array()
var _cap: PackedFloat32Array = PackedFloat32Array()
var _rem: PackedFloat32Array = PackedFloat32Array()
var _free: PackedInt32Array = PackedInt32Array()
var _asg: PackedInt32Array = PackedInt32Array()
var _ref: Array[PackedInt32Array] = []
var _ref_tick: PackedInt32Array = PackedInt32Array()


func _init(params: HarvesterParams, def_id: int) -> void:
	prm = params
	harvester_def = def_id
	var _r: int = _ref_tick.resize(PlayerTable.TEAMS)
	_ref_tick.fill(-1000000)
	for t: int in PlayerTable.TEAMS:
		_ref.append(PackedInt32Array())


## Copies the static geometry of the map's fields (session configuration, like the class table: call again after a load).
func bind_fields(f: OreFields) -> void:
	_dir = f.dirs.duplicate()
	_radius = f.radius_m.duplicate()
	var n: int = f.count()
	var _r: Array[int] = [_max_miners.resize(n), _cap.resize(n), _rem.resize(n), _free.resize(n), _asg.resize(n)]
	for i: int in n:
		_max_miners[i] = f.max_miners[i]
		_cap[i] = float(f.capacity[i])


func field_count() -> int:
	return _dir.size()


## The field nearest to the world point `p` (HARVEST_HERE's point), -1 without fields.
func nearest_field(p: Vector3) -> int:
	var best: int = -1
	var best_d: float = INF
	var d: Vector3 = p.normalized()
	for i: int in _dir.size():
		var a: float = 1.0 - d.dot(_dir[i])
		if a < best_d:
			best_d = a
			best = i
	return best


## 05 s6.6 PICK_FIELD for a Harvester of `team` at `from`: the field with the best utility among those with Ore left and a
## free miner slot, skipping `avoid`, sticking to `last` (-1: none) unless its utility fell by more than `sticky_drop`.
func pick_field(view: SimView, team: int, from: Vector3, avoid: int, last: int) -> int:
	for i: int in _dir.size():
		_rem[i] = float(view.field_remaining(i)) / _cap[i] if _cap[i] > 0.0 else 0.0
		_free[i] = _max_miners[i]
		_asg[i] = 0
		if _rem[i] > 0.0:
			_count(view, team, i)
	return HarvestPicker.pick_sticky(from.normalized(), _dir, _rem, _free, _asg, prm.assigned_weight, avoid, last, prm.sticky_drop)


# Harvesters within the field's radius (+ margin): the team's own are `assigned`; every one that mines takes a slot.
func _count(view: SimView, team: int, i: int) -> void:
	var centre: Vector3 = _dir[i] * (Sphere.PLANET_RADIUS + view.terrain_height(_dir[i]))
	for id: int in view.ids_near(centre, _radius[i] + prm.count_margin_m, Spatial.MASK_GROUND):
		if view.def_id(id) != harvester_def:
			continue
		var mine: bool = view.team(id) == team
		if mine:
			_asg[i] += 1
		if Harvest.state_of(view.link(id)) == Harvest.State.MINING and (mine or view.visible_to(team, id)):
			_free[i] -= 1


## A mining spot of field `i` for slot `s`: `spot_frac` of the radius from the centre, at the slot's golden-angle bearing.
func spot(i: int, s: int) -> Vector3:
	var fr: Basis = Sphere.tangent_frame(_dir[i])
	var th: float = float(s) * GOLDEN_RAD
	return arc_point(_dir[i], fr.x * cos(th) + fr.y * sin(th), _radius[i] * prm.spot_frac)


## Point `dist` m of arc from direction `from` toward tangent direction `along` (a unit vector in the tangent plane); on the datum.
static func arc_point(from: Vector3, along: Vector3, dist: float) -> Vector3:
	var a: float = dist / Sphere.PLANET_RADIUS
	return (from * cos(a) + along * sin(a)).normalized() * Sphere.PLANET_RADIUS


## The point `dist` m from `site` toward `toward` (negative: away from it), both world points.
static func toward(site: Vector3, toward_p: Vector3, dist: float) -> Vector3:
	var n: Vector3 = site.normalized()
	var h: Vector3 = toward_p.normalized()
	var t: Vector3 = h - n * h.dot(n)
	t = Sphere.tangent_frame(n).x if t.is_zero_approx() else t.normalized()
	return arc_point(n, t, dist)


## The dock stop of Refinery `id`: just inside the sim's delivery reach (radius + `dock_frac` x `salvage_deliver_m`), on the
## side the Harvester comes from.
func dock_stop(view: SimView, id: int, from: Vector3) -> Vector3:
	return toward(view.pos(id), from, view.radius(id) + prm.dock_frac * prm.deliver_m)


## The team's Refinery ids (finished or not: the caller checks), rebuilt at most every `scan_ticks`.
func refineries(view: SimView, team: int, tick: int) -> PackedInt32Array:
	if team < 0 or team >= PlayerTable.TEAMS:
		return PackedInt32Array()
	if tick - _ref_tick[team] >= prm.scan_ticks:
		_ref_tick[team] = tick
		scans += 1
		var out: PackedInt32Array = PackedInt32Array()
		for id: int in view.structures():
			if view.team(id) == team and prm.is_dock(view.def_id(id)):
				var _a: bool = out.push_back(id)
		_ref[team] = out
	return _ref[team]


## True when structure `id` is a finished Refinery-like structure of `team` still standing.
func usable(view: SimView, team: int, id: int) -> bool:
	return id != 0 and view.alive(id) and view.team(id) == team and prm.is_dock(view.def_id(id)) \
		and (view.flags(id) & EntityStore.F_BUILDING) == 0


## 05 s6.6 TO_REFINERY: the finished Refinery with the least `flat distance + queue_len x queue_m` (queue: Harvesters of the
## team waiting or unloading at it), skipping `avoid`; 0 for none.
func best_refinery(view: SimView, team: int, p: Vector3, tick: int, avoid: int) -> int:
	var best: int = 0
	var best_c: float = INF
	for id: int in refineries(view, team, tick):
		if id == avoid or not usable(view, team, id):
			continue
		var c: float = GroundFollower.flat(p, view.pos(id)) + float(_queued(view, team, id)) * prm.queue_m
		if c < best_c:
			best_c = c
			best = id
	return best


func _queued(view: SimView, team: int, id: int) -> int:
	var n: int = 0
	var reach: float = view.radius(id) + prm.deliver_m + prm.count_margin_m
	for h: int in view.ids_near(view.pos(id), reach, Spatial.MASK_GROUND):
		if view.def_id(h) == harvester_def and view.team(h) == team and Harvest.state_of(view.link(h)) >= Harvest.State.WAITING:
			n += 1
	return n


## 05 s6.6 FLEE: the nearest finished tower of `team` whose envelope covers a threat at `threat` (h_rel and AGL by its def), else
## the nearest finished Refinery; 0 for neither. One `structures()` scan, made when a Harvester starts to flee.
func flee_site(view: SimView, team: int, p: Vector3, threat: Vector3) -> int:
	scans += 1
	var agl: float = threat.length() - Sphere.PLANET_RADIUS - view.terrain_height(threat.normalized())
	var tower: int = 0
	var tower_d: float = INF
	var dock: int = 0
	var dock_d: float = INF
	for id: int in view.structures():
		if view.team(id) != team or (view.flags(id) & EntityStore.F_BUILDING) != 0:
			continue
		var d: float = GroundFollower.flat(p, view.pos(id))
		var def: int = view.def_id(id)
		if prm.covers(def, threat.length() - view.pos(id).length(), agl):
			if d < tower_d:
				tower_d = d
				tower = id
		elif prm.is_dock(def) and d < dock_d:
			dock_d = d
			dock = id
	return tower if tower != 0 else dock
