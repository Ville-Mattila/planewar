class_name WeaponFire extends RefCounted
## Step 9 weapon fire (02 s4.4 "Fire pipeline", R0 C2-23, GD-36), run by `Combat.step` before the contacts. Every
## live ship, ground unit and tower with a weapon reads its input slot: FIRE1 = primary (ship gun, tower or ground
## weapon), FIRE2 = ship secondary (bomb or rocket). Rules CB10-CB13 of sim/combat/MODULE.md: due within half a tick
## of 0, `1 / rof` or `reload_s` per shot / salvo with the remainder carried, no banked shots; `burst` windows on
## `cd_secondary` (burst weapons are primary-only); unsupplied towers at `economy.unsupplied_rate_mult`; ammo / bombs /
## rockets spent per projectile; lock held `lock_time_s` in cone and range; spread on the world Rng; flak fused for
## the closest approach + the projectile's `fuse_delay_s` (burst tick in `ProjectileStore.target`). Lane-internal. Tower aim,
## envelopes, AGL floor, flip lock break, target priority: GD-09; supply graph and refill: GD-18 (writes `unsupplied`).

const _BLOCKED: int = EntityStore.F_DOCKED | EntityStore.F_BUILDING
const _STATE: PackedStringArray = ["lock_target", "lock_time", "unsupplied"]

var lock_target: PackedInt32Array = PackedInt32Array()   ## per main-range slot: seeker candidate EntityId, 0 = none
var lock_time: PackedFloat32Array = PackedFloat32Array()   ## per slot: seconds the candidate has been held
var unsupplied: PackedByteArray = PackedByteArray()        ## per slot: 1 = tower outside the supply network (GD-18 writes)
var tower_power: PackedFloat32Array = PackedFloat32Array() ## per team tower rate multiplier, 0 = offline (GD-13; SimWorld sets it each tick, not state)

var _store: EntityStore
var _proj: ProjectileStore
var _inputs: InputSlots
var _defs: WorldDefs
var _events: SimEvents
var _hz: int = 30
var _dt: float = 0.0
var _half: float = 0.0
# Swapped out of the store for one fire pass so per-slot writes never copy a shared array (03 s12.2 rule 11).
var _cd1: PackedFloat32Array = PackedFloat32Array()
var _cd2: PackedFloat32Array = PackedFloat32Array()
var _ammo: PackedInt32Array = PackedInt32Array()
var _bombs: PackedByteArray = PackedByteArray()
var _rockets: PackedByteArray = PackedByteArray()
var _dirty: PackedByteArray = PackedByteArray()
var _dice: Rng = null
var _tick: int = 0
# Read for one fire pass, released by _give (03 s12.2: a cross-object property fetch per entity costs more than the
# shot); then the FireTables arrays (rows re-read after a `bind`).
var _own: PackedByteArray = PackedByteArray()
var _did: PackedInt32Array = PackedInt32Array()
var _tm: PackedByteArray = PackedByteArray()
var _pos: PackedVector3Array = PackedVector3Array()
var _vel: PackedVector3Array = PackedVector3Array()
var _fwd: PackedVector3Array = PackedVector3Array()
var _up: PackedVector3Array = PackedVector3Array()
var _rad: PackedFloat32Array = PackedFloat32Array()
var _prim: PackedInt32Array
var _sec: PackedInt32Array
var _tower: PackedByteArray
var _mask: PackedByteArray
var _wk: PackedByteArray
var _wp: PackedInt32Array
var _nw: int = 0
var _t: FireTables
var _iv: PackedFloat64Array
var _lock: PackedFloat64Array
var _bn: PackedInt32Array
var _bs: PackedFloat64Array
var _ss: PackedFloat64Array
var _salvo: PackedInt32Array
var _cost: PackedInt32Array
var _spread: PackedFloat64Array
var _r2: PackedFloat64Array
var _cone: PackedFloat64Array


func _init(store: EntityStore, projectiles: ProjectileStore, inputs: InputSlots, defs: WorldDefs, events: SimEvents,
		tick_hz: int) -> void:
	_store = store
	_proj = projectiles
	_inputs = inputs
	_defs = defs
	_events = events
	_hz = maxi(tick_hz, 1)
	_dt = 1.0 / float(_hz)
	_half = _dt * 0.5
	var n: int = InputSlots.ENTITY_SLOTS
	var e: int = lock_target.resize(n) | lock_time.resize(n) | unsupplied.resize(n)
	assert(e == OK)
	lock_target.fill(0)
	lock_time.fill(0.0)
	unsupplied.fill(0)
	_t = FireTables.new(defs.content)
	_prim = _t.prim
	_sec = _t.sec
	_tower = _t.tower
	_mask = _t.mask
	_wk = _t.w_kind
	_wp = _t.w_proj
	_nw = _t.weapon_count


## Fires every armed entity whose trigger is held this tick; `dice` is the world Rng (S7, spread draws).
func step(tick: int, dice: Rng) -> void:
	_tick = tick
	_dice = dice
	_take()
	_list(_store.ships)
	_list(_store.ground)
	_list(_store.structures)
	_give()
	_dice = null


## Clears the per-slot lock and supply state of a slot that is being freed (called for every death of the tick).
func forget(s: int) -> void:
	if s >= 0 and s < lock_target.size():
		lock_target[s] = 0
		lock_time[s] = 0.0
		unsupplied[s] = 0


func write_state(buf: StreamPeerBuffer) -> void:
	StateIO.put_props(buf, self, _STATE)


func read_state(buf: StreamPeerBuffer) -> bool:
	return StateIO.get_props(buf, self, _STATE) and lock_target.size() == InputSlots.ENTITY_SLOTS


func _list(slots: PackedInt32Array) -> void:
	var did: PackedInt32Array = _did
	var fl: PackedByteArray = _store.flags
	var ib: PackedByteArray = _inputs.e_buttons
	var prim: PackedInt32Array = _prim
	var sec: PackedInt32Array = _sec
	var n: int = prim.size()
	for s: int in slots:
		var d: int = did[s]
		if d < 0 or d >= n:
			continue
		var wp: int = prim[d]
		var ws: int = sec[d]
		if wp < 0 and ws < 0:
			continue
		var b: int = ib[s] if (fl[s] & _BLOCKED) == 0 else 0
		if (b & (PilotInput.FIRE1 | PilotInput.FIRE2)) == 0 and _cd1[s] == 0.0 and _cd2[s] == 0.0 \
				and lock_target[s] == 0:
			continue
		if wp >= 0:
			_weapon(s, wp, 0, (b & PilotInput.FIRE1) != 0)
		if ws >= 0:
			_weapon(s, ws, 1, (b & PilotInput.FIRE2) != 0)


# One weapon of slot `s` (`which` 0 primary on cd_primary, 1 secondary on cd_secondary) for this tick.
func _weapon(s: int, wi: int, which: int, held: bool) -> void:
	var k: int = mini(_own[s], WorldDefs.NEUTRAL) * _nw + wi
	var target: int = 0
	var trigger: bool = held
	if _lock[k] > 0.0:
		target = _seek(s, k, held)
		trigger = held and target != 0
	var slow: float = _defs.unsupplied_rate_mult if _tower[_did[s]] != 0 and unsupplied[s] != 0 else 1.0
	if _tower[_did[s]] != 0 and _tm[s] < tower_power.size():
		slow *= tower_power[_tm[s]]                       # 02 s8.4: x power ratio, offline (0) below tower_offline_ratio
		if slow <= 0.0:
			return
	if _bn[k] > 0 and which == 0:
		_burst(s, wi, k, trigger, slow)
		return
	var iv: float = _iv[k]
	var c: float = _due_in(_cd1[s] if which == 0 else _cd2[s])
	var fired: bool = false
	if trigger and iv > 0.0 and c < _half and _rounds(s, wi, which) >= _cost[k] and _room():
		if _wk[wi] == ProjectileStore.FLAK:                # aim pick only for a salvo that can leave
			target = _pick(s, k, _mask[_did[s]], -1.0)
		for _n: int in _salvo[k]:
			if not _shoot(s, wi, k, which, target):
				break
			fired = true
	c = c + iv / slow if fired else maxf(c, 0.0)
	if which == 0:
		_cd1[s] = c
	else:
		_cd2[s] = c


# Burst weapon: shots `1 / rof` apart while the window (`cd_secondary`) is younger than `burst - 0.5` shot spacings;
# a shot with the window closed (<= half a tick left) opens the next one, `burst_interval_s` long.
func _burst(s: int, wi: int, k: int, trigger: bool, slow: float) -> void:
	var shot_iv: float = _ss[k] / slow
	var window: float = _bs[k] / slow
	var c1: float = _due_in(_cd1[s])
	var c2: float = _due_in(_cd2[s])
	var fired: bool = false
	var opens: bool = c2 < _half
	if trigger and shot_iv > 0.0 and c1 < _half:
		if opens or window - c2 < (float(_bn[k]) - 0.5) * shot_iv:
			fired = _shoot(s, wi, k, 0, 0)
	if fired:
		c1 += shot_iv
		if opens:
			c2 += window
	else:
		c1 = maxf(c1, 0.0)
	_cd1[s] = c1
	_cd2[s] = maxf(c2, 0.0) if not (fired and opens) else c2


# Cooldown left after this tick's dt; a weapon at rest (0) is due now with no carry (no banked shots).
func _due_in(cd: float) -> float:
	return cd - _dt if cd > 0.0 else 0.0


# One projectile of weapon `wi` from slot `s`: ammo check and draw, spread, spawn. False when out of ammo or the pool
# is full (rung 3 cap: the weapon refuses to fire, nothing is spent).
func _shoot(s: int, wi: int, k: int, which: int, target: int) -> bool:
	var kind: int = _wk[wi]
	var pi: int = _wp[wi]
	var cost: int = _cost[k]
	var have: int = _rounds(s, wi, which)
	if pi < 0 or have < cost or not _room():
		return false                                     # no rounds, or the pool is at its cap: no draw, no spend
	var speed: float = _t.p_speed[pi]
	var p: Vector3 = _pos[s]
	var dir: Vector3 = FireTables.aim(_fwd[s], _up[s], _spread[k], _dice)
	var v: Vector3 = _vel[s] + dir * speed
	var at: Vector3 = p + dir * _rad[s]
	var flags: int = 0
	if kind == ProjectileStore.BOMB:
		at = p
		v = _vel[s] - p.normalized() * _t.p_eject[pi]
	elif kind == ProjectileStore.ROCKET:
		v = dir * speed
		flags = ProjectileStore.F_GUIDED if target != 0 else 0
	elif kind == ProjectileStore.FLAK:
		var t: int = EntityId.slot(target) if target != 0 and _store.alive(target) else -1
		var rp: Vector3 = _pos[t] - at if t >= 0 else Vector3.ZERO      # no target: the end of the shell's life
		var rv: Vector3 = _vel[t] - v if t >= 0 else Vector3.ZERO
		target = _tick + FireTables.fuse_ticks(rp, rv, _defs.content.projectiles[pi], _hz, _defs.fuse_delay_s[pi])
	var id: int = _proj.spawn(kind, _tick, at, v, _t.p_life[pi], pi, wi, _own[s], _tm[s], _store.id_of(s),
		target, flags)
	if id == EntityId.NULL_ID:
		return false
	_spend(s, which, kind, have - cost)
	return true


func _rounds(s: int, wi: int, which: int) -> int:
	return _ammo[s] if which == 0 else (_bombs[s] if _wk[wi] == ProjectileStore.BOMB else _rockets[s])


func _room() -> bool:
	return _proj.live.size() < _proj.live_cap


func _spend(s: int, which: int, kind: int, left: int) -> void:
	if which == 0:
		_ammo[s] = left
	elif kind == ProjectileStore.BOMB:
		_bombs[s] = left
	else:
		_rockets[s] = left
	_dirty[s] = _dirty[s] | EntityStore.DIRTY_VITALS


# Lock seeker (02 s4.4): keeps the held candidate while it stays lockable, else picks the hostile nearest the
# boresight; returns the target once held `lock_time_s` (half-tick tolerance), else 0. Released trigger drops it.
func _seek(s: int, k: int, held: bool) -> int:
	var need: float = _lock[k] - _half
	var t: int = lock_target[s]
	if not held:
		lock_target[s] = 0
		lock_time[s] = 0.0
		return 0
	var mask: int = _mask[_did[s]]
	var cone: float = _cone[k]
	if t != 0 and _lockable(s, t, mask, _r2[k], cone):
		lock_time[s] += _dt
	else:
		if t != 0 and lock_time[s] >= need:
			_lock_event(SimEvent.Kind.LOCK_BROKEN, s, t)
		t = _pick(s, k, mask, cone)
		lock_target[s] = t
		lock_time[s] = 0.0
	if t == 0 or lock_time[s] < need:
		return 0
	if lock_time[s] - _dt < need:
		_lock_event(SimEvent.Kind.LOCK_ACQUIRED, s, t)
	return t


func _lock_event(kind: SimEvent.Kind, s: int, t: int) -> void:
	var _e: SimEvent = _events.emit(kind, _store.id_of(s), t, _pos[EntityId.slot(t)], 0.0, _tm[s])


func _pick(s: int, k: int, mask: int, cone: float) -> int:
	return SeekerScan.pick(_store, _pos, _tm, s, _fwd[s], mask, _r2[k], cone)


func _score(s: int, t: int, r2: float, cone: float) -> float:
	return SeekerScan.score(_pos, _tm, s, _fwd[s], t, r2, cone)


func _lockable(s: int, t: int, mask: int, r2: float, cone: float) -> bool:
	if not _store.alive(t):
		return false
	var ts: int = EntityId.slot(t)
	return (mask & (1 << _store.kind[ts])) != 0 and _score(s, ts, r2, cone) > -2.0


func _take() -> void:
	_own = _store.owner
	_did = _store.def_id
	_tm = _store.team
	_pos = _store.pos
	_vel = _store.vel
	_fwd = _store.fwd
	_up = _store.up
	_rad = _store.radius
	var fresh: bool = _iv.is_empty()
	for o: int in WorldDefs.NEUTRAL + 1:
		fresh = _t.bind(o, _defs.resolved(o)) or fresh
	if fresh:
		_iv = _t.interval
		_lock = _t.lock_s
		_bn = _t.burst_n
		_bs = _t.burst_s
		_ss = _t.shot_s
		_salvo = _t.salvo
		_cost = _t.cost
		_spread = _t.spread
		_r2 = _t.range2
		_cone = _t.cone
	_cd1 = _store.cd_primary
	_store.cd_primary = PackedFloat32Array()
	_cd2 = _store.cd_secondary
	_store.cd_secondary = PackedFloat32Array()
	_ammo = _store.ammo
	_store.ammo = PackedInt32Array()
	_bombs = _store.bombs
	_store.bombs = PackedByteArray()
	_rockets = _store.rockets
	_store.rockets = PackedByteArray()
	_dirty = _store.dirty
	_store.dirty = PackedByteArray()


func _give() -> void:
	_store.cd_primary = _cd1
	_store.cd_secondary = _cd2
	_store.ammo = _ammo
	_store.bombs = _bombs
	_store.rockets = _rockets
	_store.dirty = _dirty
	_cd1 = PackedFloat32Array()
	_cd2 = PackedFloat32Array()
	_ammo = PackedInt32Array()
	_bombs = PackedByteArray()
	_rockets = PackedByteArray()
	_dirty = PackedByteArray()
	_own = PackedByteArray()
	_did = PackedInt32Array()
	_tm = PackedByteArray()
	_pos = PackedVector3Array()
	_vel = PackedVector3Array()
	_fwd = PackedVector3Array()
	_up = PackedVector3Array()
	_rad = PackedFloat32Array()
