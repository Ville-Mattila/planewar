class_name PadService extends RefCounted
## Step-10 service of a ship DOCKED on a finished service pad (02 s2.3, 03 s6.4; GD-15). Three parallel timers, each a
## function of the ship's own state, so the only saved state is the per-ship record below:
##   refuel  `fuel_s / refuel_time_s` fuel-seconds per second until `fuel_s` (time scales with fuel missing); Ice drawn
##           so that a whole refuel costs `ceil(refuel_ice * fuel_missing01)`: tick cost = ceil(m0 * ice / fuel_s) -
##           ceil(m1 * ice / fuel_s) for the missing fuel before (m0) and after (m1) the tick;
##   rearm   a fill line (`EntityStore.timer_a`, 0..1 of a full load) rising `1 / rearm_time_s` per second from the
##           fullest-missing slot's share; every slot holds max(own count, floor(line * capacity)), so the most-missing
##           slot sets the time; a round loaded costs its weapon's `rearm_ice` (gun rounds are free: rearm_ice 0);
##   repair  `hp / (repair_time_s * m)` HP per second, m = `repair_time_mult` (0.9) after a manual FAIR+ landing
##           (LandingLog), else 1; Ore as SelfRepair (E7): tick cost = ceil(m0 * repair_ore_per_hp) - ceil(m1 * ...).
## A timer whose tick cost the team pool cannot pay (`Economy.try_spend`, all or nothing) does not advance that tick
## (02: "the corresponding service pauses"); the others go on. Each whole Ice / Ore is paid as the missing amount
## crosses it (E7's rule), so an empty pool stops a timer at its next whole unit. ALERT WAITING_FOR_ICE /
## WAITING_FOR_ORE fires once when a pause starts. SERVICED (a ship, b pad, extra[0] = bit0 fuel, bit1 ammo, bit2
## repair given) fires once per stay when all three are full. A timer within half a tick of its end completes
## (float32 storage, exact totals). A pass (`open` .. `close`) writes the store arrays through local handles.

const BIT_FUEL: int = 1
const BIT_AMMO: int = 2
const BIT_REPAIR: int = 4
const BIT_WAIT_ICE: int = 8
const BIT_WAIT_ORE: int = 16
const BIT_FAST: int = 32           ## the stay repairs in repair_time_s x repair_time_mult (manual FAIR+, set at begin)
const BIT_DONE: int = 128

var svc_gen: PackedInt32Array = PackedInt32Array()   ## per entity slot: generation of the ship whose stay `svc_bits` describes, -1 none
var svc_bits: PackedByteArray = PackedByteArray()    ## per entity slot: BIT_* of that stay
var serviced: int = 0                                ## ships given service in the last pass (perf counter, not state)

const _STATE: PackedStringArray = ["svc_gen", "svc_bits"]

var _store: EntityStore
var _defs: WorldDefs
var _economy: Economy
var _events: SimEvents
var _log: LandingLog
var _grade: LandingGrade
var _prim_wd: PackedInt32Array = PackedInt32Array()   ## by ship local index: primary weapon def_id, -1 none
var _sec_wd: PackedInt32Array = PackedInt32Array()    ## ... secondary weapon def_id, -1 none
var _sec_bomb: PackedByteArray = PackedByteArray()    ## ... 1 when the secondary loads into `bombs`, else `rockets`
var _ice_p: PackedInt32Array = PackedInt32Array()     ## by owner * ship_count + local: rearm_ice of a primary round
var _ice_s: PackedInt32Array = PackedInt32Array()     ## ... of a secondary round (doctrine-resolved, filled on first use)
var _ice_ok: PackedByteArray = PackedByteArray()      ## by owner: 1 once its row is filled
var _ships: Array[ShipDef] = []                       ## WorldDefs.ship_table (shared): owner-resolved ShipDef by owner * _ns + local
var _ns: int = 0
var _open: bool = false                               ## between `open` and `close` the store arrays below are ours
var _fuel: PackedFloat32Array = PackedFloat32Array()  ## pass handles of EntityStore fuel, hp, timer_a, ammo, bombs,
var _hp: PackedFloat32Array = PackedFloat32Array()    ## rockets, dirty: one copy-on-write per pass, then in place
var _line: PackedFloat32Array = PackedFloat32Array()
var _ammo: PackedInt32Array = PackedInt32Array()
var _bombs: PackedByteArray = PackedByteArray()
var _rockets: PackedByteArray = PackedByteArray()
var _dirty: PackedByteArray = PackedByteArray()


func _init(store: EntityStore, defs: WorldDefs, economy: Economy, events: SimEvents, landings: LandingLog, grade: LandingGrade) -> void:
	_store = store
	_defs = defs
	_economy = economy
	_events = events
	_log = landings
	_grade = grade
	var n: int = InputSlots.ENTITY_SLOTS
	var ns: int = defs.ship_count
	var e: int = svc_gen.resize(n) | svc_bits.resize(n) | _prim_wd.resize(ns) | _sec_wd.resize(ns) | _sec_bomb.resize(ns)
	e |= _ice_p.resize((WorldDefs.NEUTRAL + 1) * ns) | _ice_s.resize((WorldDefs.NEUTRAL + 1) * ns) | _ice_ok.resize(WorldDefs.NEUTRAL + 1)
	assert(e == OK)
	_ice_ok.fill(0)
	svc_gen.fill(-1)
	svc_bits.fill(0)
	_ships = defs.ship_table
	_ns = defs.ship_count
	for i: int in ns:
		var sd: ShipDef = defs.content.ships[i]
		var pw: int = defs.content.weapon_index.get(sd.primary_weapon, -1)
		var sw: int = defs.content.weapon_index.get(sd.secondary_weapon, -1)
		_prim_wd[i] = pw if sd.primary_weapon != &"" else -1
		_sec_wd[i] = sw if sd.secondary_weapon != &"" else -1
		var w: WeaponDef = defs.base.weapon(_sec_wd[i])
		_sec_bomb[i] = 1 if w != null and w.kind == &"bomb" else 0


## A new stay of ship slot `s` (landing): fresh record, the rearm line at its fullest-missing slot's share, the repair
## bonus from the ship's last landing grade (LandingLog).
func begin(s: int) -> void:
	svc_gen[s] = _store.generation[s]
	svc_bits[s] = BIT_FAST if LandingGrade.repair_bonus(_log.grade_of(_store.id_of(s))) else 0
	if _open:
		_line[s] = _line_start(s)
	else:
		_store.timer_a[s] = _line_start(s)


## Starts a service pass (step 10): takes the store arrays the timers write as local handles (03 s12.2 rule 11: no
## per-write copy of a packed array another object holds). `close` hands them back; `serve` runs only in between.
func open() -> void:
	if _open:
		return
	_open = true
	_fuel = _store.fuel
	_hp = _store.hp
	_line = _store.timer_a
	_ammo = _store.ammo
	_bombs = _store.bombs
	_rockets = _store.rockets
	_dirty = _store.dirty


func close() -> void:
	if not _open:
		return
	_open = false
	_store.fuel = _fuel
	_store.hp = _hp
	_store.timer_a = _line
	_store.ammo = _ammo
	_store.bombs = _bombs
	_store.rockets = _rockets
	_store.dirty = _dirty
	_fuel = PackedFloat32Array()          # drop the second reference: the store's next writer does not copy
	_hp = PackedFloat32Array()
	_line = PackedFloat32Array()
	_ammo = PackedInt32Array()
	_bombs = PackedByteArray()
	_rockets = PackedByteArray()
	_dirty = PackedByteArray()


## One tick of service for ship slot `s` docked on pad slot `pad` (between `open` and `close`).
func serve(s: int, pad: int, dt: float) -> void:
	if svc_gen[s] != _store.generation[s]:
		begin(s)
	var bits: int = svc_bits[s]
	if (bits & BIT_DONE) != 0:
		return
	serviced += 1
	var owner: int = _store.owner[s]
	var sd: ShipDef = _ships[(owner if owner < WorldDefs.NEUTRAL else WorldDefs.NEUTRAL) * _ns + _store.def_id[s] - DefRanges.SHIP_BASE]
	var team: int = _store.team[s]
	var ran: int = 0
	if _fuel[s] < sd.fuel_s:
		ran = _refuel(s, sd, team, dt)
	if _line[s] < 1.0:
		ran |= _rearm(s, owner, sd, team, dt)
	if _hp[s] < float(sd.hp):
		ran |= _repair(s, sd, team, dt, (bits & BIT_FAST) != 0)
	var waits: int = ran & (BIT_WAIT_ICE | BIT_WAIT_ORE)
	var fresh: int = waits & ~bits
	bits = (bits & ~(BIT_WAIT_ICE | BIT_WAIT_ORE)) | ran
	if (fresh & BIT_WAIT_ICE) != 0:
		_alert(AlertKind.Kind.WAITING_FOR_ICE, s, pad)
	if (fresh & BIT_WAIT_ORE) != 0:
		_alert(AlertKind.Kind.WAITING_FOR_ORE, s, pad)
	if _fuel[s] >= sd.fuel_s and _line[s] >= 1.0 and _hp[s] >= float(sd.hp):
		bits |= BIT_DONE
		var e: SimEvent = _events.emit(SimEvent.Kind.SERVICED, _store.id_of(s), _store.id_of(pad), _store.pos[pad], 0.0, team)
		e.extra = PackedByteArray([bits & (BIT_FUEL | BIT_AMMO | BIT_REPAIR)])
	svc_bits[s] = bits
	_dirty[s] |= EntityStore.DIRTY_VITALS


## (fuel01, rearm line, hp01) of docked ship slot `s`: the fill of each timer, 1 when that slot has nothing to load.
func progress(s: int) -> Vector3:
	var sd: ShipDef = _defs.ship(_store.owner[s], _store.def_id[s])
	if sd == null:
		return Vector3.ZERO
	var hm: float = float(sd.hp)
	var fuel01: float = clampf(_store.fuel[s] / sd.fuel_s, 0.0, 1.0) if sd.fuel_s > 0.0 else 1.0
	var missing: bool = _missing(s, sd, _store.ammo, _store.bombs, _store.rockets)
	var line: float = clampf(_store.timer_a[s], 0.0, 1.0) if missing else 1.0
	return Vector3(fuel01, line, clampf(_store.hp[s] / hm, 0.0, 1.0) if hm > 0.0 else 1.0)


func write_state(buf: StreamPeerBuffer) -> void:
	StateIO.put_props(buf, self, _STATE)


func read_state(buf: StreamPeerBuffer) -> bool:
	return StateIO.get_props(buf, self, _STATE) and StateIO.sizes_ok(self, _STATE, InputSlots.ENTITY_SLOTS)


# Refuel: 0 when full, else BIT_FUEL, | BIT_WAIT_ICE when the tick's Ice could not be paid.
func _refuel(s: int, sd: ShipDef, team: int, dt: float) -> int:
	var full: float = sd.fuel_s
	var f0: float = _fuel[s]
	if f0 >= full:
		return 0
	var add: float = full * dt / sd.refuel_time_s if sd.refuel_time_s > 0.0 else full
	var f1: float = full if full - (f0 + add) < add * 0.5 else f0 + add
	_fuel[s] = f1
	f1 = _fuel[s]                                           # the stored float32: costs telescope exactly
	var cost: int = ceili((full - f0) * float(sd.refuel_ice) / full) - ceili((full - f1) * float(sd.refuel_ice) / full)
	if cost > 0 and not _economy.try_spend(team, 0, cost):
		_fuel[s] = f0
		return BIT_FUEL | BIT_WAIT_ICE
	return BIT_FUEL


# Repair: 0 when whole, else BIT_REPAIR, | BIT_WAIT_ORE when the tick's Ore could not be paid. Full HP is the
# doctrine-resolved ShipDef.hp (= WorldDefs.hp_max of a ship).
func _repair(s: int, sd: ShipDef, team: int, dt: float, fast: bool) -> int:
	var full: float = float(sd.hp)
	var h0: float = _hp[s]
	if h0 >= full or h0 <= 0.0:
		return 0
	var t_rep: float = sd.repair_time_s * (_grade.repair_time_mult if fast else 1.0)
	var add: float = full * dt / t_rep if t_rep > 0.0 else full
	var h1: float = full if full - (h0 + add) < add * 0.5 else h0 + add
	_hp[s] = h1
	h1 = _hp[s]
	var rate: float = _defs.economy.repair_ore_per_hp
	var cost: int = ceili((full - h0) * rate) - ceili((full - h1) * rate)
	if cost > 0 and not _economy.try_spend(team, cost, 0):
		_hp[s] = h0
		return BIT_REPAIR | BIT_WAIT_ORE
	return BIT_REPAIR


# Rearm (line below 1, i.e. a slot is missing): BIT_AMMO, | BIT_WAIT_ICE when the rounds of this tick could not be
# paid. begin() puts the line at 1 exactly when nothing is missing, and rounds never leave a docked ship.
func _rearm(s: int, owner: int, sd: ShipDef, team: int, dt: float) -> int:
	var line: float = _line[s]
	if line < 0.0:
		line = _line_start(s)
	var i: int = _store.def_id[s] - DefRanges.SHIP_BASE
	var step: float = dt / sd.rearm_time_s if sd.rearm_time_s > 0.0 else 1.0
	var l1: float = 1.0 if 1.0 - (line + step) < step * 0.5 else line + step
	var a0: int = _ammo[s]
	var a1: int = maxi(a0, floori(l1 * float(sd.primary_ammo)))
	var sec0: int = _bombs[s] if _sec_bomb[i] != 0 else _rockets[s]
	var sec1: int = maxi(sec0, floori(l1 * float(sd.secondary_count)))
	var row: int = _ice_row(owner) + i
	var cost: int = (a1 - a0) * _ice_p[row] + (sec1 - sec0) * _ice_s[row]
	if cost > 0 and not _economy.try_spend(team, 0, cost):
		return BIT_AMMO | BIT_WAIT_ICE
	_ammo[s] = a1
	if _sec_bomb[i] != 0:
		_bombs[s] = clampi(sec1, 0, 255)
	else:
		_rockets[s] = clampi(sec1, 0, 255)
	_line[s] = l1
	return BIT_AMMO


# First index of owner's row of rearm_ice per round (doctrine-resolved), filled on first use.
func _ice_row(owner: int) -> int:
	var o: int = owner if owner >= 0 and owner < WorldDefs.NEUTRAL else WorldDefs.NEUTRAL
	var ns: int = _defs.ship_count
	if _ice_ok[o] == 0:
		_ice_ok[o] = 1
		var r: ResolvedDefs = _defs.resolved(o)
		for k: int in ns:
			_ice_p[o * ns + k] = _ice(r, _prim_wd[k])
			_ice_s[o * ns + k] = _ice(r, _sec_wd[k])
	return o * ns


static func _ice(r: ResolvedDefs, wd: int) -> int:
	var w: WeaponDef = r.weapon(wd)
	return w.rearm_ice if w != null else 0


func _missing(s: int, sd: ShipDef, ammo: PackedInt32Array, bombs: PackedByteArray, rockets: PackedByteArray) -> bool:
	var i: int = _store.def_id[s] - DefRanges.SHIP_BASE
	var sec: int = bombs[s] if _sec_bomb[i] != 0 else rockets[s]
	return ammo[s] < sd.primary_ammo or sec < sd.secondary_count


# The rearm line a stay starts from: the smallest fill share among the slots with a capacity, 1 with none.
func _line_start(s: int) -> float:
	var sd: ShipDef = _defs.ship(_store.owner[s], _store.def_id[s])
	if sd == null:
		return 1.0
	var i: int = _store.def_id[s] - DefRanges.SHIP_BASE
	var ammo: PackedInt32Array = _ammo if _open else _store.ammo
	var sec_arr: PackedByteArray = (_bombs if _open else _store.bombs) if _sec_bomb[i] != 0 else (_rockets if _open else _store.rockets)
	var line: float = 1.0
	if sd.primary_ammo > 0:
		line = minf(line, float(ammo[s]) / float(sd.primary_ammo))
	if sd.secondary_count > 0:
		line = minf(line, float(sec_arr[s]) / float(sd.secondary_count))
	return clampf(line, 0.0, 1.0)


func _alert(kind: AlertKind.Kind, s: int, pad: int) -> void:
	var _e: SimEvent = _events.emit(SimEvent.Kind.ALERT, kind, _store.id_of(s), _store.pos[pad], 0.0, _store.team[s],
		_store.owner[s])
