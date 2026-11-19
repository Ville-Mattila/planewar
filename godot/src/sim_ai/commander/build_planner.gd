class_name BuildPlanner extends RefCounted
## Site resolution of the Commander (05 s7.3, AI-23): a location token -> an anchor on the map (features.json and the slot
## layout through `MapSites`, the team's own structures, the enemy ones it knows) -> the k-th placement candidate that
## passes the pre-check of 02 s6.2, so the bot does not spend a command on a site the sim would refuse. Every structure
## gets the ADR-05 rule: footprint centre inside a finished friendly build radius, outside every known enemy build radius,
## clear of own footprints; an anchor outside every radius is pulled to the edge of the nearest one (a structure on a
## node, the Ice Extractor, and a `toward:` chain step are never moved: they wait, BLOCKED, for the radius to reach them). Outposts get 02 AR-1 instead: no radius, >= `outpost_spacing_friendly_m`
## from every friendly Core / Outpost (sites included), >= `outpost_spacing_enemy_m` from every known enemy one, outside
## enemy radii; their candidates stay inside the presence radius of the anchor. Candidates are a deterministic spiral (8
## per ring; every radius test keeps one build cell of margin, because the sim snaps a footprint centre to its cell); the sim stays the judge (Build.can_place), a REJECTED_PLACEMENT moves the caller to the next index.
## Reads only what the caller loads (Perception lists); a pure function of them. 05 s10: one call examines at most
## `scan_cap` candidates against the own / known structure lists (tens of entries).

enum Status { OK, UNRESOLVED, BLOCKED }   ## UNRESOLVED: the map has no such site (skip the step); BLOCKED: no valid candidate now

const R: float = Sphere.PLANET_RADIUS
const R2: float = R * R
const RING: int = 8
const RING_SHIFT: int = 3                 ## log2(RING)

var status: Status = Status.UNRESOLVED
var last_k: int = 0                       ## index of the candidate the last OK call returned
var enemy_hint: Vector3 = Vector3.ZERO    ## unit direction of the nearest enemy (known structure, else its start slot)
var own_n: int = 0
var own_def: PackedInt32Array = PackedInt32Array()
var own_dir: PackedVector3Array = PackedVector3Array()
var own_done: PackedByteArray = PackedByteArray()
var foe_n: int = 0
var foe_def: PackedInt32Array = PackedInt32Array()
var foe_dir: PackedVector3Array = PackedVector3Array()

var _p: BookParams
var _sites: MapSites
var _is_struct: PackedByteArray = PackedByteArray()
var _fp_r: PackedFloat32Array = PackedFloat32Array()      ## half diagonal of the footprint, m
var _build_r: PackedFloat32Array = PackedFloat32Array()
var _on_node: PackedByteArray = PackedByteArray()
var _core: int = -1
var _outpost: int = -1
var _refinery: int = -1
var _spacing_friendly: float = 0.0
var _spacing_enemy: float = 0.0
var _presence: float = 0.0
var _cell_m: float = 0.0


func _init(content: ContentSet, params: BookParams, sites: MapSites) -> void:
	_p = params
	_sites = sites
	_core = BookParams.def_of(content.entity_index, &"core")
	_outpost = BookParams.def_of(content.entity_index, &"outpost")
	_refinery = BookParams.def_of(content.entity_index, &"refinery")
	var n: int = DefRanges.END
	var _r: Array[int] = [_is_struct.resize(n), _fp_r.resize(n), _build_r.resize(n), _on_node.resize(n)]
	_is_struct.fill(0)
	_fp_r.fill(0.0)
	_build_r.fill(0.0)
	_on_node.fill(0)
	_cell_m = PI * 0.5 * R / float(Sphere.GRID_BUILD)
	for sd: StructureDef in content.structures:
		if sd.def_id < 0 or sd.def_id >= n or sd.footprint.size() != 2:
			continue
		_is_struct[sd.def_id] = 1
		_fp_r[sd.def_id] = 0.5 * _cell_m * sqrt(float(sd.footprint[0] * sd.footprint[0] + sd.footprint[1] * sd.footprint[1]))
		_build_r[sd.def_id] = sd.build_radius
		_on_node[sd.def_id] = 1 if sd.on_node != &"" else 0
	var eco: EconomyDef = content.economy
	_spacing_friendly = eco.outpost_spacing_friendly_m if eco != null else 0.0
	_spacing_enemy = eco.outpost_spacing_enemy_m if eco != null else 0.0
	_presence = eco.outpost_presence_radius_m if eco != null else 0.0


func is_outpost_def(def_id: int) -> bool:
	return def_id == _outpost


func is_structure(def_id: int) -> bool:
	return def_id >= 0 and def_id < _is_struct.size() and _is_struct[def_id] != 0


func clear_view() -> void:
	own_n = 0
	foe_n = 0


func add_own(def_id: int, dir: Vector3, done: bool) -> void:
	if own_n >= own_def.size():
		var _a: int = own_def.resize(own_n + 32)
		var _b: int = own_dir.resize(own_n + 32)
		var _c: int = own_done.resize(own_n + 32)
	own_def[own_n] = def_id
	own_dir[own_n] = dir
	own_done[own_n] = 1 if done else 0
	own_n += 1


func add_foe(def_id: int, dir: Vector3) -> void:
	if foe_n >= foe_def.size():
		var _a: int = foe_def.resize(foe_n + 32)
		var _b: int = foe_dir.resize(foe_n + 32)
	foe_def[foe_n] = def_id
	foe_dir[foe_n] = dir
	foe_n += 1


## Fills the own / known structure lists from the team's perception (the bot's only source of positions).
func load_view(perc: Perception, v: SimView) -> void:
	clear_view()
	for i: int in perc.n_own:
		var d: int = perc.own_def[i]
		if is_structure(d):
			add_own(d, perc.own_pos[i].normalized(), (v.flags(perc.own_id[i]) & EntityStore.F_BUILDING) == 0)
	for i: int in perc.n_known:
		var s: int = perc.known[i]
		if is_structure(perc.k_def[s]):
			add_foe(perc.k_def[s], perc.k_pos[s].normalized())


## The point `token` names for `slot` (unit direction), ZERO when it has none; `status` says why. `issued` = how many
## structures of this step the bot already placed (the `toward:` chain step).
func anchor(tok: SiteToken, slot: int, issued: int) -> Vector3:
	status = Status.UNRESOLVED
	var core: Vector3 = _own_core(slot)
	if core == Vector3.ZERO:
		return Vector3.ZERO
	var a: Vector3 = Vector3.ZERO
	match tok.kind:
		SiteToken.Kind.CORE:
			a = core
		SiteToken.Kind.APPROACH:
			a = _toward(core, enemy_hint, _p.approach_m) if enemy_hint != Vector3.ZERO else Vector3.ZERO
		SiteToken.Kind.TOWARD:
			var t: Vector3 = _target_of(tok.inner, slot, core)
			a = _toward(core, t, _p.toward_first_m + _p.toward_step_m * float(issued)) if t != Vector3.ZERO else Vector3.ZERO
		SiteToken.Kind.COLD_TRAP, SiteToken.Kind.ORE_FIELD, SiteToken.Kind.CONTESTED:
			a = _target_of(tok, slot, core)
		SiteToken.Kind.OUTPOST_SITE:
			a = _outpost_site(slot, core)
		SiteToken.Kind.REFINERY:
			a = _latest(_refinery)
			status = Status.BLOCKED
		SiteToken.Kind.OUTPOST:
			a = _latest(_outpost)
			status = Status.BLOCKED
	if a != Vector3.ZERO:
		status = Status.OK
	return a


## The k-th (or a later) valid candidate for `def_id` at `tok`: a unit direction; ZERO with `status` UNRESOLVED / BLOCKED.
## On OK, `last_k` is the candidate's index (the caller retries from `last_k + 1` after a REJECTED_PLACEMENT).
func resolve_site(def_id: int, tok: SiteToken, slot: int, k: int, issued: int) -> Vector3:
	var a: Vector3 = anchor(tok, slot, issued)
	if a == Vector3.ZERO:
		return Vector3.ZERO
	var is_outpost: bool = def_id == _outpost
	var on_node: bool = _on_node[def_id] != 0 if def_id < _on_node.size() else false
	var open: bool = tok.kind != SiteToken.Kind.CORE and tok.kind != SiteToken.Kind.REFINERY and tok.kind != SiteToken.Kind.OUTPOST
	if not is_outpost and not on_node and tok.kind != SiteToken.Kind.TOWARD and not _covered(a):
		a = _pull_inside(a, def_id)
		open = true
		if a == Vector3.ZERO:
			status = Status.BLOCKED
			return Vector3.ZERO
	var last: int = k + _p.scan_cap
	if is_outpost:
		last = mini(last, 1 + RING * _outpost_rings())
	for i: int in range(k, last):
		var c: Vector3 = _candidate(a, i, open, on_node, is_outpost, slot)
		if _valid(def_id, c, is_outpost):
			last_k = i
			status = Status.OK
			return c
	status = Status.BLOCKED
	return Vector3.ZERO


# The anchor's target for map tokens (a trap, a field, the contested field).
func _target_of(tok: SiteToken, slot: int, core: Vector3) -> Vector3:
	match tok.kind:
		SiteToken.Kind.COLD_TRAP:
			return _sites.home_trap(slot)
		SiteToken.Kind.ORE_FIELD:
			return _sites.home_field(slot, tok.nth)
		SiteToken.Kind.CONTESTED:
			return _sites.contested(core)
	return Vector3.ZERO


# 02 AR-1: >= the friendly spacing from the Core and `outpost_cover` of the Outpost radius short of the trap, so the
# Extractor ends inside the new Outpost's build radius.
func _outpost_site(slot: int, core: Vector3) -> Vector3:
	var trap: Vector3 = _sites.home_trap(slot)
	if trap == Vector3.ZERO:
		return Vector3.ZERO
	var d_trap: float = core.angle_to(trap) * R
	var d: float = maxf(_spacing_friendly + _p.gap_m, d_trap - _p.outpost_cover * _build_r[_outpost])
	return _toward(core, trap, minf(d, d_trap))


func _toward(from: Vector3, to: Vector3, metres: float) -> Vector3:
	var ang: float = from.angle_to(to) * R
	if ang < 1.0:
		return from
	return Sphere.slerp_dir(from, to, clampf(metres / ang, 0.0, 1.0))


func _own_core(slot: int) -> Vector3:
	var best: Vector3 = Vector3.ZERO
	var best_a: float = INF
	var home: Vector3 = _sites.slot_dir(slot)
	for i: int in own_n:
		if own_def[i] == _core:
			var a: float = home.angle_to(own_dir[i]) if home != Vector3.ZERO else 0.0
			if a < best_a:
				best_a = a
				best = own_dir[i]
	return best


func _latest(def_id: int) -> Vector3:
	for i: int in range(own_n - 1, -1, -1):
		if own_def[i] == def_id:
			return own_dir[i]
	return Vector3.ZERO


func _covered(a: Vector3) -> bool:
	for i: int in own_n:
		var r: float = _build_r[own_def[i]]
		if r > 0.0 and own_done[i] != 0 and _within(a, own_dir[i], r - _cell_m):
			return true
	return false


# The anchor moved to the edge of the nearest finished friendly build radius, toward it.
func _pull_inside(a: Vector3, def_id: int) -> Vector3:
	var best: int = -1
	var best_gap: float = INF
	for i: int in own_n:
		var r: float = _build_r[own_def[i]]
		if r > 0.0 and own_done[i] != 0:
			var gap: float = a.angle_to(own_dir[i]) * R - r
			if gap < best_gap:
				best_gap = gap
				best = i
	if best < 0:
		return Vector3.ZERO
	var edge: float = _build_r[own_def[best]] - _fp_r[def_id] - _p.gap_m - _p.ring_step_m
	return _toward(own_dir[best], a, maxf(edge, 0.0))


# Candidate `i` of a spiral around `a`: open anchors: 0 is the anchor, then rings of 8; structure anchors: rings from 0.
func _candidate(a: Vector3, i: int, open: bool, on_node: bool, is_outpost: bool, slot: int) -> Vector3:
	if open and i == 0:
		return a
	var j: int = (i - 1) if open else i
	var ring: int = j >> RING_SHIFT
	var step: float = _p.outpost_ring_m if is_outpost else (_cell_m if on_node else _p.ring_step_m)
	var dist: float = step * float(ring + 1) if open else _p.core_ring_m + _p.ring_step_m * float(ring)
	var theta: float = TAU * float(j % RING) / float(RING) + _p.slot_phase_rad * float(slot)
	var ref: Vector3 = Vector3.UP if absf(a.y) < 0.9 else Vector3.RIGHT
	var e1: Vector3 = ref.cross(a).normalized()
	var t: Vector3 = e1 * cos(theta) + a.cross(e1) * sin(theta)
	var ang: float = dist / R
	return (a * cos(ang) + t * sin(ang)).normalized()


## The pre-check alone: would `resolve_site` accept the unit direction `c` for `def_id` (radius or Outpost rule)?
func accepts(def_id: int, c: Vector3) -> bool:
	return _valid(def_id, c, def_id == _outpost)


func _valid(def_id: int, c: Vector3, is_outpost: bool) -> bool:
	if is_outpost:
		return _valid_outpost(c)
	var covered: bool = false
	for i: int in own_n:
		var d: int = own_def[i]
		if _within(c, own_dir[i], _fp_r[def_id] + _fp_r[d] + _p.gap_m):
			return false
		if not covered and own_done[i] != 0 and _build_r[d] > 0.0 and _within(c, own_dir[i], _build_r[d] - _cell_m):
			covered = true
	if not covered:
		return false
	return not _in_foe_radius(c)


func _valid_outpost(c: Vector3) -> bool:
	for i: int in own_n:
		var d: int = own_def[i]
		if (d == _core or d == _outpost) and _within(c, own_dir[i], _spacing_friendly + _cell_m):
			return false
	for i: int in foe_n:
		var d: int = foe_def[i]
		if (d == _core or d == _outpost) and _within(c, foe_dir[i], _spacing_enemy + _cell_m):
			return false
	return not _in_foe_radius(c)


func _in_foe_radius(c: Vector3) -> bool:
	for i: int in foe_n:
		var r: float = _build_r[foe_def[i]]
		if r > 0.0 and _within(c, foe_dir[i], r + _cell_m):
			return true
	return false


# Presence radius of an Outpost candidate ring count: rings stay within half the horizontal reach of the 300 m radius.
func _outpost_rings() -> int:
	var reach: float = sqrt(maxf(_presence * _presence - _p.move_agl_m * _p.move_agl_m, 0.0))
	return maxi(int(0.5 * reach / maxf(_p.outpost_ring_m, 1.0)), 1)


# Arc distance <= r_m between unit vectors, by chord (monotone in the arc; no trigonometry in the loops).
static func _within(a: Vector3, b: Vector3, r_m: float) -> bool:
	var chord: float = r_m - r_m * r_m * r_m / (24.0 * R2)
	return a.distance_squared_to(b) * R2 <= chord * chord
