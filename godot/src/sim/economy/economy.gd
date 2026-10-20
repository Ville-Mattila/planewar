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
var _supply: PackedFloat32Array = PackedFloat32Array()   ## refresh scratch per team
var _demand: PackedFloat32Array = PackedFloat32Array()
var _n_struct: int = -1
var _dirty: bool = true
var _core_def: int = -1
var sun_period_s: float = 0.0                            ## 0 = fixed sun +Z; > 0 = moving sun (MatchRules.sun_period_s, set by EconomyHub)
var _clock: int = 0                                      ## sim tick set by `set_clock`; derived, not state
var _plateaus: PackedVector3Array = PackedVector3Array() ## unit centres of the solar Plateau(s), set at map load (planned: no map data yet)
var _tower_rate: PackedFloat32Array = PackedFloat32Array()


func _init(store: EntityStore, players: PlayerTable, defs: WorldDefs, hz: int, events: SimEvents, build: Build) -> void:
	_store = store
	_players = players
	_defs = defs
	_events = events
	_build = build
	_hz = hz
	_econ = defs.economy if defs.economy != null else EconomyDef.new()
	var e: int = _power.resize(PlayerTable.TEAMS) | _cap_ore.resize(PlayerTable.TEAMS) | _cap_ice.resize(PlayerTable.TEAMS)
	e |= _supply.resize(PlayerTable.TEAMS) | _demand.resize(PlayerTable.TEAMS) | _cores.resize(PlayerTable.SLOTS) | _acc.resize(PlayerTable.SLOTS) | _low.resize(PlayerTable.TEAMS) | _full.resize(PlayerTable.TEAMS)
	assert(e == OK)
	_power.fill(1.0)
	assert(_tower_rate.resize(PlayerTable.TEAMS) == OK)
	_tower_rate.fill(1.0)
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


## Plateau centres (unit vectors) for the 02 s8.4 `solar_plateau_mult`; empty until the map loader feeds them.
func set_plateaus(centres: PackedVector3Array) -> void:
	_plateaus = centres
	_dirty = true


## Tick clock of the moving sun: the solar factor refreshes once a second of sim time while `sun_period_s` > 0.
func set_clock(tick: int) -> void:
	_clock = tick


## 02 s8.4 production speed: `max(production_min_speed, ratio)`.
func production_speed(team: int) -> float:
	return maxf(_econ.production_min_speed, power_ratio(team))


## 02 s8.4 tower rate of fire multiplier per team: the ratio, 0 (offline) below `tower_offline_ratio`. Reads the cache only
## (no refresh), so it is safe to call from step 9.
func tower_rates() -> PackedFloat32Array:
	for tm: int in PlayerTable.TEAMS:
		_tower_rate[tm] = _power[tm] if _power[tm] >= _econ.tower_offline_ratio else 0.0
	return _tower_rate


## 02 s8.4 Shield Projector: recharge multiplier (the ratio), 0 with the dome down (ratio below `tower_offline_ratio`).
func shield_recharge_mult(team: int) -> float:
	var r: float = power_ratio(team)
	return r if r >= _econ.tower_offline_ratio else 0.0


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
	_report_full(team, ore > ore_in, _players.team_ore[team] < _cap_ore[team], 1)
	_report_full(team, ice > ice_in, _players.team_ice[team] < _cap_ice[team], 2)


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


## True while the early share lock forbids `player` to spend `ore` more (GD-17: auto-replenish does not queue into it).
func spend_locked(player: int, ore: int) -> bool:
	return _build.lock_blocks(player, ore)


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
	var moving: bool = sun_period_s > 0.0 and _clock % _hz == 0
	if _dirty or moving or _store.structures.size() != _n_struct:
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


## One alert per crossing: raised on the first overflow, re-armed only once the pool is back below the cap (a zero credit
## into a full pool neither alerts nor re-arms).
func _report_full(team: int, overflow: bool, below_cap: bool, bit: int) -> void:
	if overflow and (_full[team] & bit) == 0:
		var _e: SimEvent = _events.emit(SimEvent.Kind.ALERT, AlertKind.Kind.STORAGE_FULL, bit, Vector3.ZERO, 0.0, team)
		_full[team] |= bit
	elif below_cap:
		_full[team] &= ~bit


func _refresh() -> void:
	_dirty = false
	_n_struct = _store.structures.size()
	_cap_ore.fill(0)
	_cap_ice.fill(0)
	_cores.fill(0)
	_supply.fill(0.0)
	_demand.fill(0.0)
	var sun: Vector3 = SunPath.dir_at(sun_period_s, float(_clock) / float(maxi(_hz, 1)))
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
			var plat: bool = not _plateaus.is_empty() and SunPath.on_plateau(_store.up[s], _plateaus, _econ.solar_plateau_radius_m)
			pw *= solar_factor(_store.up[s], sun, plat, _econ.solar_band_deg, _econ.solar_plateau_mult)
		_supply[tm] += maxf(pw, 0.0)
		_demand[tm] += maxf(-pw, 0.0)
		if _store.def_id[s] == _core_def and o < PlayerTable.SLOTS:
			_cores[o] += 1
	for tm: int in PlayerTable.TEAMS:
		_power[tm] = 1.0 if _demand[tm] <= 0.0 else minf(_supply[tm] / _demand[tm], 1.0)
		_report_power(tm)


func _report_power(tm: int) -> void:
	var low: bool = _power[tm] < 1.0
	if low and _low[tm] == 0:
		var _a: SimEvent = _events.emit(SimEvent.Kind.LOW_POWER, tm, 0, Vector3.ZERO, _power[tm], tm)
		var _b: SimEvent = _events.emit(SimEvent.Kind.ALERT, AlertKind.Kind.LOW_POWER, tm, Vector3.ZERO, _power[tm], tm)
	_low[tm] = 1 if low else 0
