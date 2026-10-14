class_name Economy extends RefCounted
## Economy core of tick-order step 10 (02 s8, R0 C2-14, C3-08): the team stockpiles (the `PlayerTable` pools),
## storage caps, power ratio, payment with the early share lock, refunds, the Core trickle and the STORAGE_FULL /
## LOW_POWER notices. Caps, power and Core counts are cached and refreshed only when the structure set changes
## (`mark_dirty`, or a different live-structure count), so the per-tick cost is a handful of array reads.
## Harvester, Refinery dock, Extractor, salvage and Core shield logic are GD-xx tasks; this class has the seam
## (`credit(..., player)` for deliveries). No RNG, no clock but `step`'s tick: deterministic.

enum Pay { OK, LOCKED, SHORT }   ## `try_pay` outcomes

const _STATE: PackedStringArray = ["_power", "_cap_ore", "_cap_ice", "_cores", "_acc", "_low", "_full", "_n_struct", "_dirty"]

var _store: EntityStore
var _players: PlayerTable
var _defs: WorldDefs
var _events: SimEvents
var _build: Build
var _hz: int
var _econ: EconomyDef
var _power: PackedFloat32Array = PackedFloat32Array()    ## per team, min(1, supply / demand)
var _cap_ore: PackedInt32Array = PackedInt32Array()      ## per team, summed storage_ore of live structures
var _cap_ice: PackedInt32Array = PackedInt32Array()
var _cores: PackedInt32Array = PackedInt32Array()        ## per player slot, finished Cores owned
var _acc: PackedFloat64Array = PackedFloat64Array()      ## per player slot, trickle in Ore-ticks (Ore x tick_hz) not yet credited
var _low: PackedByteArray = PackedByteArray()            ## per team, 1 while LOW_POWER is active
var _full: PackedByteArray = PackedByteArray()           ## per team, bit0 Ore / bit1 Ice STORAGE_FULL already reported
var _n_struct: int = -1
var _dirty: bool = true
var _core_def: int = -1


func _init(store: EntityStore, players: PlayerTable, defs: WorldDefs, hz: int, events: SimEvents, build: Build) -> void:
	_store = store
	_players = players
	_defs = defs
	_events = events
	_build = build
	_hz = hz
	_econ = defs.economy if defs.economy != null else EconomyDef.new()
	var e: int = _power.resize(PlayerTable.TEAMS) | _cap_ore.resize(PlayerTable.TEAMS) | _cap_ice.resize(PlayerTable.TEAMS)
	e |= _cores.resize(PlayerTable.SLOTS) | _acc.resize(PlayerTable.SLOTS) | _low.resize(PlayerTable.TEAMS) | _full.resize(PlayerTable.TEAMS)
	assert(e == OK)
	_power.fill(1.0)
	_cap_ore.fill(0)
	_cap_ice.fill(0)
	_cores.fill(0)
	_acc.fill(0.0)
	_low.fill(0)
	_full.fill(0)
	_core_def = defs.content.entity_index.get(&"core", -1)


## 02 s8.4: clamp((elev + band) / (2 band), 0, 1), times the Plateau multiplier on the Plateau. `up` is the structure's
## up vector, `sun_dir` the unit sun direction (fixed +Z), so `elev_deg` is the latitude with the fixed sun.
static func solar_factor(up: Vector3, sun_dir: Vector3, on_plateau: bool, band_deg: float, plateau_mult: float) -> float:
	var elev: float = rad_to_deg(asin(clampf(up.dot(sun_dir), -1.0, 1.0)))
	var f: float = 1.0 if elev >= 0.0 else 0.0
	if band_deg > 0.0:
		f = clampf((elev + band_deg) / (2.0 * band_deg), 0.0, 1.0)
	return f * plateau_mult if on_plateau else f


## 02 s8.2: d / v + cargo_ore / mine_rate + d / v_loaded + unload_time_s (the dock queue wait is the caller's).
static func harvest_trip_time(d: float, def: GroundUnitDef) -> float:
	if def.ground_speed <= 0.0 or def.ground_speed_loaded <= 0.0 or def.mine_rate <= 0.0:
		return INF
	return d / def.ground_speed + float(def.cargo_ore) / def.mine_rate + d / def.ground_speed_loaded + def.unload_time_s


func power_ratio(team: int) -> float:
	if team < 0 or team >= PlayerTable.TEAMS:
		return 1.0
	_ensure()
	return _power[team]


## (Ore, Ice) in the team pool.
func stockpile(team: int) -> Vector2i:
	if team < 0 or team >= PlayerTable.TEAMS:
		return Vector2i.ZERO
	return Vector2i(_players.team_ore[team], _players.team_ice[team])


## (Ore, Ice) storage caps of the team.
func caps(team: int) -> Vector2i:
	if team < 0 or team >= PlayerTable.TEAMS:
		return Vector2i.ZERO
	_ensure()
	return Vector2i(_cap_ore[team], _cap_ice[team])


func try_spend(team: int, ore: int, ice: int) -> bool:
	if team < 0 or team >= PlayerTable.TEAMS or ore < 0 or ice < 0:
		return false
	if ore > _players.team_ore[team] or ice > _players.team_ice[team]:
		return false
	_players.team_ore[team] -= ore
	_players.team_ice[team] -= ice
	return true


## Adds to the pool, clamped to the storage caps; the first overflow of a kind raises ALERT STORAGE_FULL. A `player` >= 0
## books the Ore actually stored as that player's delivery (early share lock ledger, `Build.delivered_ore`).
func credit(team: int, ore: int, ice: int, player: int = -1) -> void:
	if team < 0 or team >= PlayerTable.TEAMS:
		return
	_ensure()
	var ore_in: int = clampi(_cap_ore[team] - _players.team_ore[team], 0, maxi(ore, 0))
	var ice_in: int = clampi(_cap_ice[team] - _players.team_ice[team], 0, maxi(ice, 0))
	_players.team_ore[team] += ore_in
	_players.team_ice[team] += ice_in
	if player >= 0 and player < PlayerTable.SLOTS:
		_build.delivered_ore[player] += ore_in
	_report_full(team, ore > ore_in, 1)
	_report_full(team, ice > ice_in, 2)


## Pays `ore` / `ice` for `player` out of the team pool: SHORT when the pool lacks it, LOCKED while the early share lock
## (R0 C3-08) forbids the Ore; on OK the ledger `Build.spent_ore` grows.
func try_pay(player: int, ore: int, ice: int) -> Pay:
	var team: int = _players.team[player]
	if team < 0 or team >= PlayerTable.TEAMS or ore > _players.team_ore[team] or ice > _players.team_ice[team]:
		return Pay.SHORT
	if _build.lock_blocks(player, ore):
		return Pay.LOCKED
	var _ok: bool = try_spend(team, ore, ice)
	_build.spent_ore[player] += ore
	return Pay.OK


## Gives back part of a payment (cancel rules, S12): the pool is credited and the ledger lowered by the Ore refunded.
func refund(player: int, ore: int, ice: int) -> void:
	credit(_players.team[player], ore, ice)
	_build.spent_ore[player] = maxi(_build.spent_ore[player] - ore, 0)


## The structure set or a structure's finished state changed: caps, power and Core counts refresh at the next read.
func mark_dirty() -> void:
	_dirty = true


## Step 10: cached values refresh, then the Core trickle (`core_trickle_ore_per_s` per finished Core, to its owner).
func step() -> void:
	if _hz <= 0:
		return
	if _dirty or _store.structures.size() != _n_struct:
		_refresh()
	for p: int in PlayerTable.SLOTS:
		if _cores[p] == 0 or _players.active[p] == 0:
			continue
		_acc[p] += _econ.core_trickle_ore_per_s * float(_cores[p])   # Ore-ticks: exact for whole rates, no per-tick rounding
		var whole: int = floori(_acc[p] / float(_hz))
		if whole > 0:
			_acc[p] -= float(whole * _hz)
			credit(_players.team[p], whole, 0, p)


func write_state(buf: StreamPeerBuffer) -> void:
	StateIO.put_props(buf, self, _STATE)


func read_state(buf: StreamPeerBuffer) -> bool:
	if not StateIO.get_props(buf, self, _STATE):
		return false
	return StateIO.sizes_ok(self, ["_power", "_cap_ore", "_cap_ice", "_low", "_full"], PlayerTable.TEAMS) \
			and StateIO.sizes_ok(self, ["_cores", "_acc"], PlayerTable.SLOTS)


func _ensure() -> void:
	if _dirty or _store.structures.size() != _n_struct:
		_refresh()


func _report_full(team: int, overflow: bool, bit: int) -> void:
	if overflow and (_full[team] & bit) == 0:
		var _e: SimEvent = _events.emit(SimEvent.Kind.ALERT, AlertKind.Kind.STORAGE_FULL, bit, Vector3.ZERO, 0.0, team)
		_full[team] |= bit
	elif not overflow:
		_full[team] &= ~bit


func _refresh() -> void:
	_dirty = false
	_n_struct = _store.structures.size()
	_cap_ore.fill(0)
	_cap_ice.fill(0)
	_cores.fill(0)
	var supply: PackedFloat32Array = PackedFloat32Array()
	var demand: PackedFloat32Array = PackedFloat32Array()
	var _r: int = supply.resize(PlayerTable.TEAMS) | demand.resize(PlayerTable.TEAMS)
	supply.fill(0.0)
	demand.fill(0.0)
	for s: int in _store.structures:
		var o: int = _store.owner[s]
		var tm: int = _store.team[s]
		if tm >= PlayerTable.TEAMS or (_store.flags[s] & EntityStore.F_BUILDING) != 0:
			continue
		var sd: StructureDef = _defs.resolved(o).structure(_store.def_id[s])
		if sd == null:
			continue
		_cap_ore[tm] += sd.storage_ore
		_cap_ice[tm] += sd.storage_ice
		var pw: float = sd.power
		if sd.solar:
			pw *= solar_factor(_store.up[s], Vector3.BACK, false, _econ.solar_band_deg, _econ.solar_plateau_mult)
		supply[tm] += maxf(pw, 0.0)
		demand[tm] += maxf(-pw, 0.0)
		if _store.def_id[s] == _core_def and o < PlayerTable.SLOTS:
			_cores[o] += 1
	for tm: int in PlayerTable.TEAMS:
		_power[tm] = 1.0 if demand[tm] <= 0.0 else minf(supply[tm] / demand[tm], 1.0)
		_report_power(tm)


func _report_power(tm: int) -> void:
	var low: bool = _power[tm] < 1.0
	if low and _low[tm] == 0:
		var _a: SimEvent = _events.emit(SimEvent.Kind.LOW_POWER, tm, 0, Vector3.ZERO, _power[tm], tm)
		var _b: SimEvent = _events.emit(SimEvent.Kind.ALERT, AlertKind.Kind.LOW_POWER, tm, Vector3.ZERO, _power[tm], tm)
	_low[tm] = 1 if low else 0
