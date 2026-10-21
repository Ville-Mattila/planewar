class_name ShieldDomes extends RefCounted
## Shield domes (02 s4.3 rule 6, s5.1, s5.2; R0 C3-05; GD-10): every finished Shield Projector and every Core is a sphere of
## `dome_radius` around its position. `absorb(tick)` (step 9, before Combat's contacts) sweeps the live projectiles whose
## def has `shield_absorbed` against the active domes of other teams: one that enters from outside is freed when
## `charge >= damage` (charge -= damage, the weapon's resolved `damage_max`, no dice), else it flies on and the dome
## collapses to 0 for `collapse_s` (SHIELD_COLLAPSE). A projectile that starts inside is never absorbed; ships are
## not projectiles. `step(tick)` (step 10, after the supply pass) ages collapses and recharges: a Projector (not
## collapsed, supplied, power ratio at or above `tower_offline_ratio`) gains `recharge_per_s` x ratio after
## `recharge_delay_s` without an absorb, paying 1 Ice per `1 / recharge_ice_per_point` points from the team pool and
## waiting while the pool is empty. After Core Exposure a Projector whose dome covers a Core has its charge cap and
## recharge halved. The Core's integrated shield costs no Ice and no power, starts full, and is removed for good at
## `core_shield_until_s` or at Exposure (ALERT CORE_SHIELD_DOWN). No Nodes, no signals, no RNG.
## State (S4) is per entity slot in packed arrays, canonical for the live structures; the dome list and the cover flags
## are derived and rebuilt from the store when `Economy.structure_epoch` or the structure count moves.

const NEVER: int = -(1 << 30)    ## `_last_hit` of a dome that has not been hit
const REMOVED: int = -1          ## `_down_until` of a Core shield that is gone for good
const _K_PROJECTOR: int = ShieldTables.K_PROJECTOR
const _K_CORE: int = ShieldTables.K_CORE
const _STATE: PackedStringArray = ["_charge", "_credit", "_last_hit", "_down_until", "_bound"]

var absorbed_total: int = 0      ## projectiles absorbed so far (diagnostic for tests and perf notes, not state)

var _store: EntityStore
var _proj: ProjectileStore
var _defs: WorldDefs
var _rules: MatchRules
var _events: SimEvents
var _hz: int
var _econ: Economy = null
var _supply: SupplyNet = null
var _core_until: int = 0                                  ## first tick without the Core shield
# By def_id: kind, dome radius, charge cap, recharge per s, exposure multipliers, points per Ice (0 = free), ticks.
var _kind: PackedByteArray = PackedByteArray()
var _radius: PackedFloat64Array = PackedFloat64Array()
var _cmax: PackedFloat64Array = PackedFloat64Array()
var _rate: PackedFloat64Array = PackedFloat64Array()
var _xc: PackedFloat64Array = PackedFloat64Array()
var _xr: PackedFloat64Array = PackedFloat64Array()
var _pts_per_ice: PackedFloat64Array = PackedFloat64Array()
var _delay: PackedInt32Array = PackedInt32Array()
var _collapse: PackedInt32Array = PackedInt32Array()
var _absorbs: PackedByteArray = PackedByteArray()         ## by projectile local def: shield_absorbed
# State, per entity slot (saved).
var _charge: PackedFloat64Array = PackedFloat64Array()
var _credit: PackedFloat64Array = PackedFloat64Array()    ## prepaid recharge points (a part of the last Ice paid)
var _last_hit: PackedInt32Array = PackedInt32Array()      ## tick of the last absorb or collapse
var _down_until: PackedInt32Array = PackedInt32Array()    ## 0 up; > 0 collapsed until that tick; REMOVED
var _bound: PackedInt32Array = PackedInt32Array()         ## EntityId the slot's state belongs to, 0 = none
# Derived.
var _list: PackedInt32Array = PackedInt32Array()          ## dome slots in store order
var _next: PackedInt32Array = PackedInt32Array()
var _covers: PackedByteArray = PackedByteArray()          ## per slot: a Projector whose dome covers a Core
var _epoch: int = -1
var _n_struct: int = -1
var _exposed: bool = false
var _a_n: int = 0
var _a_slot: PackedInt32Array = PackedInt32Array()
var _a_pos: PackedVector3Array = PackedVector3Array()
var _a_r: PackedFloat64Array = PackedFloat64Array()
var _a_lim2: PackedFloat64Array = PackedFloat64Array()   ## (2 r)^2: a projectile step is shorter than a dome radius
var _a_team: PackedByteArray = PackedByteArray()
var _shell_lo2: float = 0.0                               ## squared radius range around the planet centre that holds every active dome
var _shell_hi2: float = 0.0
var _due: PackedInt32Array = PackedInt32Array()


func _init(store: EntityStore, projectiles: ProjectileStore, defs: WorldDefs, rules: MatchRules, events: SimEvents) -> void:
	_store = store
	_proj = projectiles
	_defs = defs
	_rules = rules
	_events = events
	_hz = maxi(rules.tick_hz, 1)
	var n: int = InputSlots.ENTITY_SLOTS
	var e: int = _charge.resize(n) | _credit.resize(n) | _last_hit.resize(n) | _down_until.resize(n) | _bound.resize(n)
	e |= _covers.resize(n)
	assert(e == OK)
	_charge.fill(0.0)
	_credit.fill(0.0)
	_last_hit.fill(0)
	_down_until.fill(0)
	_bound.fill(0)
	_covers.fill(0)
	var t: ShieldTables = ShieldTables.new(defs, _hz)
	_kind = t.kind
	_radius = t.radius
	_cmax = t.cmax
	_rate = t.rate
	_xc = t.xc
	_xr = t.xr
	_pts_per_ice = t.pts_per_ice
	_delay = t.delay
	_collapse = t.collapse
	_absorbs = t.absorbs
	_core_until = t.core_until


## The economy and supply network whose power ratio, Ice pool and supplied flags the recharge reads (`SimWorld._wire`).
func bind(economy: Economy, supply: SupplyNet) -> void:
	_econ = economy
	_supply = supply


## Step 9, before the contacts of this tick: rule 6 over the live projectiles. Returns the number absorbed.
func absorb(tick: int) -> int:
	if _econ == null:
		return 0
	_prepare(tick)
	_activate(tick)
	if _a_n == 0:
		return 0
	var _r: int = _due.resize(0)
	var pdef: PackedByteArray = _proj.projectile_def
	var pos: PackedVector3Array = _proj.pos
	var lo2: float = _shell_lo2
	var hi2: float = _shell_hi2
	for i: int in _proj.live:
		if _absorbs[pdef[i]] != 0:
			var l2: float = pos[i].length_squared()
			if l2 >= lo2 and l2 <= hi2 and _intercept(i, tick):
				var _p: bool = _due.push_back(i)
	for i: int in _due:
		var _f: bool = _proj.free_slot(i, tick)
	absorbed_total += _due.size()
	return _due.size()


## Step 10 (after construction, production and the supply pass): ends collapses, removes the Core shield, recharges.
func step(tick: int) -> void:
	if _econ == null:
		return
	_prepare(tick)
	for s: int in _list:
		if _store.hp[s] <= 0.0:
			continue
		if _kind[_store.def_id[s]] == _K_CORE:
			_step_core(s, tick)
		else:
			_step_projector(s, tick)


## Charge of the dome at `slot`; 0 for a slot without one.
func charge_of(slot: int) -> float:
	return _charge[slot] if _has(slot) else 0.0


## True while the dome at `slot` is not collapsed, not removed and (a Projector) powered at `tick`.
func is_up(slot: int, tick: int) -> bool:
	if not _has(slot):
		return false
	var d: int = _down_until[slot]
	if d == REMOVED or (d > 0 and tick < d):
		return false
	return _powered(slot, tick, _econ.tower_rates() if _econ != null else PackedFloat32Array())


## Collapse ticks left of the dome at `slot` at `tick` (0 when not collapsed).
func collapse_left(slot: int, tick: int) -> int:
	return maxi(_down_until[slot] - tick, 0) if _has(slot) else 0


## Dome radius in metres (0 for a slot without a dome).
func dome_radius(slot: int) -> float:
	return _radius[_store.def_id[slot]] if _has(slot) else 0.0


## True while a Core of `team` has its integrated shield up (not collapsed, not removed).
func core_up(team: int) -> bool:
	for s: int in _list:
		if _kind[_store.def_id[s]] == _K_CORE and _store.team[s] == team and _down_until[s] == 0:
			return true
	return false


## Charge / effective cap (0..1) of the dome at `slot`: 0 for no dome, a collapsed or removed one, an unpowered Projector.
## The cap is `charge_max`, times `exposure_charge_mult` for a Projector covering a Core during Exposure (SH7, SH11).
func charge01(slot: int, tick: int) -> float:
	if not _has(slot):
		return 0.0
	var d: int = _store.def_id[slot]
	var up: bool = _down_until[slot] == 0 if _kind[d] == _K_CORE else is_up(slot, tick)   # a Core by `core_up`'s rule
	if not up:
		return 0.0
	var cap: float = _cmax[d] * (_xc[d] if _exposed and _covers[slot] != 0 else 1.0)
	return clampf(_charge[slot] / cap, 0.0, 1.0) if cap > 0.0 else 0.0


func write_state(buf: StreamPeerBuffer) -> void:
	StateIO.put_props(buf, self, _STATE)


## Refuses the wrong sizes, non-finite or negative charges and a collapse marker below REMOVED; the derived list and
## the canonical form of the state (dead slots cleared, charges capped) are rebuilt from the restored store.
func read_state(buf: StreamPeerBuffer) -> bool:
	if not StateIO.get_props(buf, self, _STATE):
		return false
	var n: int = InputSlots.ENTITY_SLOTS
	if not StateIO.sizes_ok(self, ["_charge", "_credit"], n) or not StateIO.sizes_ok(self, ["_last_hit", "_down_until", "_bound"], n):
		return false
	for s: int in n:
		if not (_charge[s] >= 0.0 and _charge[s] < INF and _credit[s] >= 0.0 and _credit[s] < INF) or _down_until[s] < REMOVED:
			return false
	_epoch = -1
	if _econ != null:
		_scan(true)
	return true


# The dome at `slot` is neither collapsed nor removed (checked by the caller); a Core by its timer, a Projector by `rates`.
func _powered(slot: int, tick: int, rates: PackedFloat32Array) -> bool:
	if _kind[_store.def_id[slot]] == _K_CORE:
		return tick < _core_until and not _exposed
	return rates.is_empty() or rates[_store.team[slot]] > 0.0


func _has(slot: int) -> bool:
	return slot >= 0 and slot < _bound.size() and _bound[slot] != 0 and _bound[slot] == _store.id_of(slot)


# Sync the derived list with the store and apply the Exposure cap (idempotent within a tick).
func _prepare(tick: int) -> void:
	if _econ.structure_epoch != _epoch or _store.structures.size() != _n_struct:
		_scan(false)
	_exposed = _rules.phase(tick) != MatchRules.Phase.PLAYING
	if _exposed:
		for s: int in _list:
			if _covers[s] != 0:
				_charge[s] = minf(_charge[s], _cmax[_store.def_id[s]] * _xc[_store.def_id[s]])


# Rebuilds the dome list from the finished living structures, binds new ones (Core full, Projector empty), unbinds the
# ones gone and recomputes the cover flags. `full` also clears every slot that holds no dome (a restored world).
func _scan(full: bool) -> void:
	_epoch = _econ.structure_epoch
	_n_struct = _store.structures.size()
	var _r: int = _next.resize(0)
	for s: int in _store.structures:
		var d: int = _store.def_id[s]
		if (_store.flags[s] & EntityStore.F_BUILDING) != 0 or _store.hp[s] <= 0.0 or _kind[d] == 0:
			continue
		var id: int = _store.id_of(s)
		if _bound[s] != id:
			_unbind(s)
			_bound[s] = id
			_charge[s] = _cmax[d] if _kind[d] == _K_CORE else 0.0
			_last_hit[s] = NEVER
		_charge[s] = minf(_charge[s], _cmax[d])
		var _p: bool = _next.push_back(s)
	var keep: PackedInt32Array = _next
	for s: int in (InputSlots.ENTITY_SLOTS if full else 0):
		if _bound[s] != 0 and not keep.has(s):
			_unbind(s)
	for s: int in _list:
		if _bound[s] != 0 and not keep.has(s):
			_unbind(s)
	_list = _next.duplicate()
	_cover_flags()


func _unbind(s: int) -> void:
	_bound[s] = 0
	_charge[s] = 0.0
	_credit[s] = 0.0
	_last_hit[s] = 0
	_down_until[s] = 0
	_covers[s] = 0


# A Projector covers a Core when a finished Core of any team is within its dome radius (centre distance).
func _cover_flags() -> void:
	for s: int in _list:
		_covers[s] = 0
		if _kind[_store.def_id[s]] != _K_PROJECTOR:
			continue
		var r2: float = _radius[_store.def_id[s]] * _radius[_store.def_id[s]]
		for c: int in _list:
			if _kind[_store.def_id[c]] == _K_CORE and _store.pos[s].distance_squared_to(_store.pos[c]) <= r2:
				_covers[s] = 1


# The domes that can absorb at `tick`, as flat scratch arrays, and the shell of radii around the planet centre they fill.
func _activate(tick: int) -> void:
	_a_n = 0
	var e: int = _a_slot.resize(_list.size()) | _a_pos.resize(_list.size()) | _a_r.resize(_list.size()) | _a_lim2.resize(_list.size()) | _a_team.resize(_list.size())
	assert(e == OK)
	var rates: PackedFloat32Array = _econ.tower_rates()
	var lo: float = INF
	var hi: float = 0.0
	var slack: float = 0.0
	for s: int in _list:
		var d: int = _down_until[s]
		if _store.hp[s] > 0.0 and d != REMOVED and (d <= 0 or tick >= d) and _powered(s, tick, rates):
			var c: Vector3 = _store.pos[s]
			var r: float = _radius[_store.def_id[s]]
			_a_slot[_a_n] = s
			_a_pos[_a_n] = c
			_a_r[_a_n] = r
			_a_lim2[_a_n] = (r + r) * (r + r)
			_a_team[_a_n] = _store.team[s]
			_a_n += 1
			var cl: float = c.length()
			lo = minf(lo, cl - r)
			hi = maxf(hi, cl + r)
			slack = maxf(slack, r)
	_shell_lo2 = maxf(lo - slack, 0.0) * maxf(lo - slack, 0.0)
	_shell_hi2 = (hi + slack) * (hi + slack)


# Rule 6 for projectile `i`: the first active enemy dome its last step enters from outside. True when absorbed.
func _intercept(i: int, tick: int) -> bool:
	var a: Vector3 = _proj.prev_pos[i]
	var b: Vector3 = _proj.pos[i]
	var team: int = _proj.team[i]
	var best: float = 2.0
	var hit: int = -1
	for k: int in _a_n:
		if _a_team[k] == team or _a_slot[k] < 0 or b.distance_squared_to(_a_pos[k]) > _a_lim2[k]:
			continue
		var r: float = _a_r[k]
		if a.distance_squared_to(_a_pos[k]) <= r * r:
			continue
		var t: float = Collision.sweep_sphere(a, b, _a_pos[k], r)
		if t >= 0.0 and t < best:
			best = t
			hit = k
	if hit < 0:
		return false
	var res: ResolvedDefs = _defs.resolved(_proj.owner[i])
	var wi: int = _proj.weapon_def[i]
	if wi >= res.weapons.size():
		return false
	var s: int = _a_slot[hit]
	var dmg: float = float(res.weapons[wi].damage_max)
	_last_hit[s] = tick
	if _charge[s] >= dmg:
		_charge[s] -= dmg
		return true
	_collapse_dome(s, hit, tick)
	return false


# The shot was too big for the charge: the dome drops to 0 and is down for `collapse_s`.
func _collapse_dome(s: int, k: int, tick: int) -> void:
	var d: int = _store.def_id[s]
	_charge[s] = 0.0
	_down_until[s] = tick + _collapse[d]
	_a_slot[k] = -1
	var id: int = _store.id_of(s)
	var _e: SimEvent = _events.emit(SimEvent.Kind.SHIELD_COLLAPSE, id, 0, _store.pos[s], float(_collapse[d]) / float(_hz), _store.team[s])
	if _kind[d] == _K_CORE:
		var _a: SimEvent = _events.emit(SimEvent.Kind.ALERT, AlertKind.Kind.CORE_SHIELD_DOWN, id, _store.pos[s], 0.0, _store.team[s])


func _step_core(s: int, tick: int) -> void:
	var down: int = _down_until[s]
	if down == REMOVED:
		return
	if tick >= _core_until or _exposed:
		_down_until[s] = REMOVED
		_charge[s] = 0.0
		if down == 0 or tick >= down:   # a collapse already told the player
			var _a: SimEvent = _events.emit(SimEvent.Kind.ALERT, AlertKind.Kind.CORE_SHIELD_DOWN, _store.id_of(s), _store.pos[s], 0.0, _store.team[s])
		return
	if down > 0:
		if tick < down:
			return
		_down_until[s] = 0
	var d: int = _store.def_id[s]
	if tick - _last_hit[s] >= _delay[d]:
		_charge[s] = minf(_charge[s] + _rate[d] / float(_hz), _cmax[d])


func _step_projector(s: int, tick: int) -> void:
	var down: int = _down_until[s]
	if down > 0:
		if tick < down:
			return
		_down_until[s] = 0
	var d: int = _store.def_id[s]
	var team: int = _store.team[s]
	var mult: float = _econ.shield_recharge_mult(team)
	if mult <= 0.0 or not _supply.is_supplied(s) or tick - _last_hit[s] < _delay[d]:
		return
	var cap: float = _cmax[d] * (_xc[d] if _exposed and _covers[s] != 0 else 1.0)
	var rate: float = _rate[d] * mult * (_xr[d] if _exposed and _covers[s] != 0 else 1.0)
	var dq: float = minf(rate / float(_hz), cap - _charge[s])
	if dq <= 0.0:
		return
	if _pts_per_ice[d] > 0.0 and _credit[s] < dq:
		if not _econ.try_spend(team, 0, 1):
			return                                   # waiting for Ice
		_credit[s] += _pts_per_ice[d]
	_credit[s] = maxf(_credit[s] - dq, 0.0)
	_charge[s] += dq
